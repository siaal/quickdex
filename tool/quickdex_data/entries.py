import logging
import re
from collections import defaultdict
from dataclasses import dataclass, field

from .csvdb import ENGLISH, CsvDb, SchemaError
from .games import Eras, Game

log = logging.getLogger("quickdex.entries")

DROP_SUBSTRINGS = ("-mega", "-gmax", "-primal", "-totem", "-eternamax")
STAT_IDS = ("1", "2", "3", "4", "5", "6")  # hp, atk, def, spa, spd, spe
# Labels PokéAPI's English names render awkwardly once the other forms are dropped.
LABEL_OVERRIDES = {"darmanitan-galar-standard": "Galarian", "minior-red": "Core"}
HIDDEN_ABILITIES_FROM = 5


@dataclass
class Entry:
    id: int
    dex: int
    name: str
    species: str
    form: str | None
    types: list[str]
    stats: list[int]
    chain: int
    abilities: list[int]  # non-hidden ability ids, slot order
    hidden: int | None  # hidden ability id
    catch_rate: int
    weight: int  # hectograms, as PokéAPI stores it
    region: tuple[str, int] | None = None  # the game's regional dex (label, number)
    forms: list[int] = field(default_factory=list)

    def to_json(self) -> dict:
        assert self.forms and self.id in self.forms, self
        assert self.abilities, self
        return {
            "id": self.id, "dex": self.dex, "name": self.name, "species": self.species,
            "form": self.form, "types": self.types, "stats": self.stats,
            "forms": self.forms, "chain": self.chain, "abilities": self.abilities,
            "hidden": self.hidden, "catch": self.catch_rate, "weight": self.weight,
            "region": list(self.region) if self.region else None,
        }


@dataclass
class EntryBuild:
    entries: list[Entry]
    dropped: list[tuple[str, str]]  # (identifier, reason)


def form_label(pokemon_name: str, form_name: str, species: str) -> str | None:
    raw = pokemon_name or form_name
    if not raw:
        return None
    label = raw.replace(species, "")
    label = re.sub(r"\bForme?\b", "", label)
    label = re.sub(r"[()]", "", label)
    label = re.sub(r"\s+", " ", label).strip()
    return label or None


def _name_drop_reason(identifier: str, form: dict[str, str]) -> str | None:
    if form["is_mega"] == "1":
        return "mega"
    for marker in DROP_SUBSTRINGS:
        if marker in identifier:
            return marker.strip("-")
    if identifier.endswith("-starter"):
        return "starter"
    return None


def _nearest_past(rows: list[dict[str, str]], eras: Eras, key: tuple[str, ...]
                  ) -> dict[tuple[str, ...], list[dict[str, str]]]:
    """`*_past` rows grouped by `key`, keeping only the nearest generation at or after
    the game's (a past row holds until and including its generation)."""
    best: dict[tuple[str, ...], int] = {}
    for r in rows:
        gen = int(r["generation_id"])
        k = tuple(r[c] for c in key)
        if eras.past_applies(gen) and gen < best.get(k, 99):
            best[k] = gen
    out: dict[tuple[str, ...], list[dict[str, str]]] = defaultdict(list)
    for r in rows:
        k = tuple(r[c] for c in key)
        if best.get(k) == int(r["generation_id"]):
            out[k].append(r)
    return out


def build_entries(db: CsvDb, game: Game) -> EntryBuild:
    eras = Eras(db, game)
    species_gen = {r["id"]: int(r["generation_id"])
                   for r in db.rows("pokemon_species", ("id", "generation_id"))}
    pokemon = [p for p in db.rows("pokemon", ("id", "identifier", "species_id",
                                              "is_default", "weight"))
               if species_gen[p["species_id"]] <= game.generation]
    default_form: dict[str, dict[str, str]] = {}
    for f in db.rows("pokemon_forms",
                     ("id", "pokemon_id", "is_default", "is_mega", "form_order",
                      "introduced_in_version_group_id")):
        # Some pokemon (Koraidon/Miraidon ride modes) have no is_default=1 form row;
        # their first form row stands in.
        if f["is_default"] == "1" or f["pokemon_id"] not in default_form:
            default_form[f["pokemon_id"]] = f
    type_ident = {t["id"]: t["identifier"] for t in db.rows("types", ("id", "identifier"))}
    types: dict[str, list[str]] = defaultdict(list)
    for r in sorted(db.rows("pokemon_types", ("pokemon_id", "type_id", "slot")),
                    key=lambda r: int(r["slot"])):
        types[r["pokemon_id"]].append(type_ident[r["type_id"]])
    for (pid,), rows in _nearest_past(
            db.rows("pokemon_types_past", ("pokemon_id", "generation_id", "type_id", "slot")),
            eras, ("pokemon_id",)).items():
        types[pid] = [type_ident[r["type_id"]] for r in sorted(rows, key=lambda r: r["slot"])]
        log.debug("entries.build.past_types %s %s", pid, types[pid])
    stats: dict[str, dict[str, int]] = defaultdict(dict)
    for r in db.rows("pokemon_stats", ("pokemon_id", "stat_id", "base_stat")):
        stats[r["pokemon_id"]][r["stat_id"]] = int(r["base_stat"])
    for (pid, stat), (r, *_) in _nearest_past(
            db.rows("pokemon_stats_past", ("pokemon_id", "generation_id", "stat_id",
                                           "base_stat")),
            eras, ("pokemon_id", "stat_id")).items():
        if stat in STAT_IDS:  # Gen 1's Special (9) never reaches here
            log.debug("entries.build.past_stat %s stat=%s %s", pid, stat, r["base_stat"])
            stats[pid][stat] = int(r["base_stat"])
    # slot -> (hidden, ability id or "" for "no ability in this slot")
    slots: dict[str, dict[str, tuple[bool, str]]] = defaultdict(dict)
    for r in db.rows("pokemon_abilities", ("pokemon_id", "ability_id", "is_hidden", "slot")):
        slots[r["pokemon_id"]][r["slot"]] = (r["is_hidden"] == "1", r["ability_id"])
    for (pid, slot), (r, *_) in _nearest_past(
            db.rows("pokemon_abilities_past", ("pokemon_id", "generation_id", "ability_id",
                                               "is_hidden", "slot")),
            eras, ("pokemon_id", "slot")).items():
        log.debug("entries.build.past_ability %s slot=%s %r", pid, slot, r["ability_id"])
        slots[pid][slot] = (r["is_hidden"] == "1", r["ability_id"])
    ability_gen = {r["id"]: int(r["generation_id"])
                   for r in db.rows("abilities", ("id", "generation_id"))}
    abilities: dict[str, list[int]] = defaultdict(list)
    hidden: dict[str, int] = {}
    for pid, by_slot in slots.items():
        for slot in sorted(by_slot, key=int):
            is_hidden, a = by_slot[slot]
            if not a or (is_hidden and game.generation < HIDDEN_ABILITIES_FROM):
                continue
            if is_hidden:
                hidden[pid] = int(a)
            else:
                abilities[pid].append(int(a))
    species_names = db.english_names("pokemon_species_names", "pokemon_species_id")
    form_names = {r["pokemon_form_id"]: r
                  for r in db.rows("pokemon_form_names",
                                   ("pokemon_form_id", "form_name", "pokemon_name"))
                  if r["local_language_id"] == ENGLISH}
    species_rows = {r["id"]: r for r in db.rows(
        "pokemon_species", ("id", "identifier", "evolution_chain_id", "capture_rate"))}
    sv_numbers: dict[str, dict[str, int]] = defaultdict(dict)  # species -> dex id -> no.
    for r in db.rows("pokemon_dex_numbers", ("species_id", "pokedex_id", "pokedex_number")):
        sv_numbers[r["species_id"]][r["pokedex_id"]] = int(r["pokedex_number"])

    def region_for(sid: str) -> tuple[str, int] | None:
        for dex_id, label in game.dexes:
            if dex_id in sv_numbers[sid]:
                return label, sv_numbers[sid][dex_id]
        log.debug("entries.region.none species=%s", sid)
        return None

    def signature(pid: str) -> tuple[tuple[str, ...], tuple[int, ...]]:
        t, s = types.get(pid), stats.get(pid, {})
        if not t:
            raise SchemaError(f"pokemon {pid} has no types")
        if set(s) != set(STAT_IDS):
            raise SchemaError(f"pokemon {pid} is missing base stats")
        return tuple(t), tuple(s[i] for i in STAT_IDS)

    keyed: list[tuple[tuple[int, int, int], Entry, str]] = []
    dropped: list[tuple[str, str]] = []
    for p in pokemon:
        if p["id"] not in default_form:
            raise SchemaError(f"pokemon {p['id']} ({p['identifier']}) has no form row")
    # Defaults first, then forms in game order, so that a form identical to an earlier
    # kept one (e.g. Zygarde 10% Power Construct vs Zygarde 10%) is the one dropped.
    ordered = sorted(pokemon, key=lambda p: (int(p["species_id"]), p["is_default"] != "1",
                                             int(default_form[p["id"]]["form_order"])))
    kept_signatures: dict[str, set] = defaultdict(set)
    for p in ordered:
        pid, ident, sid = p["id"], p["identifier"], p["species_id"]
        is_default = p["is_default"] == "1"
        form = default_form[pid]
        introduced = eras.vg_generation[form["introduced_in_version_group_id"]]
        if is_default:
            assert introduced <= game.generation, (ident, game.key)
        else:
            reason = _name_drop_reason(ident, form)
            if reason is None and introduced > game.generation:
                reason = f"introduced in Gen {introduced}"
            if reason is None and signature(pid) in kept_signatures[sid]:
                reason = "same types+stats as default or an earlier form"
            if reason:
                log.debug("entries.build.drop %s reason=%s", ident, reason)
                dropped.append((ident, reason))
                continue
        log.debug("entries.build.keep %s", ident)
        t, s = signature(pid)
        kept_signatures[sid].add((t, s))
        species = species_names[sid]
        fn = form_names.get(form["id"], {})
        label = form_label(fn.get("pokemon_name", ""), fn.get("form_name", ""), species)
        if ident in LABEL_OVERRIDES:
            label = LABEL_OVERRIDES[ident]
            log.debug("entries.build.label_override %s -> %s", ident, label)
        elif not is_default and label is None:
            suffix = ident.removeprefix(species_rows[sid]["identifier"] + "-")
            label = suffix.replace("-", " ").title()
            log.debug("entries.build.label_from_identifier %s -> %s", ident, label)
        name = species if is_default else f"{species} ({label})"
        if not abilities.get(pid):
            raise SchemaError(f"pokemon {pid} ({ident}) has no non-hidden ability")
        late = [a for a in [*abilities[pid], hidden.get(pid)]
                if a is not None and ability_gen[str(a)] > game.generation]
        if late:
            raise SchemaError(f"pokemon {pid} ({ident}) has abilities {late} from after "
                              f"Gen {game.generation}; pokemon_abilities_past lacks a row")
        entry = Entry(id=int(pid), dex=int(sid), name=name, species=species, form=label,
                      types=list(t), stats=list(s),
                      chain=int(species_rows[sid]["evolution_chain_id"]),
                      abilities=abilities[pid], hidden=hidden.get(pid),
                      catch_rate=int(species_rows[sid]["capture_rate"]),
                      weight=int(p["weight"]), region=region_for(sid))
        keyed.append(((int(sid), 0 if is_default else 1, int(pid)), entry, sid))

    keyed.sort(key=lambda k: k[0])
    entries = [e for _, e, _ in keyed]
    by_species: dict[int, list[int]] = defaultdict(list)
    for e in entries:
        by_species[e.dex].append(e.id)
    for e in entries:
        e.forms = by_species[e.dex]
    assert len({e.id for e in entries}) == len(entries)
    return EntryBuild(entries=entries, dropped=dropped)
