import logging
from collections import defaultdict

from .csvdb import CsvDb, SchemaError
from .entries import Entry

log = logging.getLogger("quickdex.evolutions")

SV_VERSION_GROUP = "25"

TRIGGER_LABELS = {
    "spin": "Spin around holding a Sweet",
    "tower-of-darkness": "Train in the Tower of Darkness",
    "tower-of-waters": "Train in the Tower of Waters",
    "three-critical-hits": "Land 3 critical hits in one battle",
    "three-defeated-bisharp": "Defeat 3 Bisharp holding Leader's Crest",
    "gimmighoul-coins": "Collect 999 Gimmighoul Coins",
    "meltan-candies": "400 Meltan Candies (GO)",
    "shed": "Spare party slot + Poké Ball",
}
STYLE = {"agile-style-move": " in Agile Style", "strong-style-move": " in Strong Style"}
RELATIVE_STATS = {"1": "Atk > Def", "0": "Atk = Def", "-1": "Atk < Def"}
GENDERS = {"1": "female", "2": "male"}


class Names:
    def __init__(self, db: CsvDb):
        self.items = db.english_names("item_names", "item_id")
        self.moves = db.english_names("move_names", "move_id")
        self.locations = db.english_names("location_names", "location_id")
        self.species = db.english_names("pokemon_species_names", "pokemon_species_id")
        self.types = {t["id"]: t["identifier"].capitalize() for t in db.rows("types")}
        self.regions = {r["id"]: r["identifier"].capitalize() for r in db.rows("regions")}
        self.triggers = {r["id"]: r["identifier"] for r in db.rows("evolution_triggers")}


def render_method(r: dict[str, str], n: Names) -> str | None:
    def has(col: str) -> bool:
        return r.get(col, "") != ""

    def flag(col: str) -> bool:
        return r.get(col, "0") == "1"

    trig = n.triggers.get(r["evolution_trigger_id"])
    held = n.items.get(r["held_item_id"]) if has("held_item_id") else None
    if trig == "level-up":
        head = f"Lv. {r['minimum_level']}" if has("minimum_level") else "Level up"
    elif trig == "in-battle-level-up":
        head = (f"Lv. {r['minimum_level']} in battle" if has("minimum_level")
                else "Level up in battle")
    elif trig == "trade":
        head = f"Trade w/ {held}" if held else "Trade"
        held = None
    elif trig == "use-item":
        if not has("trigger_item_id"):
            log.debug("evolutions.render.use_item_missing_item %s", r["id"])
            return None
        head = n.items[r["trigger_item_id"]]
    elif trig in ("use-move", "agile-style-move", "strong-style-move"):
        if not has("used_move_id"):
            log.debug("evolutions.render.use_move_missing_move %s", r["id"])
            return None
        count = f" ×{r['minimum_move_count']}" if has("minimum_move_count") else ""
        head = f"Use {n.moves[r['used_move_id']]}{STYLE.get(trig, '')}{count}"
    elif trig == "take-damage":
        head = (f"Take {r['minimum_damage_taken']}+ damage" if has("minimum_damage_taken")
                else "Take damage")
    elif trig == "recoil-damage":
        head = (f"Lose {r['minimum_damage_taken']}+ HP to recoil" if has("minimum_damage_taken")
                else "Lose HP to recoil")
    elif trig in TRIGGER_LABELS:
        head = TRIGGER_LABELS[trig]
    else:
        log.debug("evolutions.render.unknown_trigger %s trigger=%s", r["id"], trig)
        return None

    cond: list[str] = []
    if has("gender_id"):
        cond.append(GENDERS[r["gender_id"]])
    if held:
        cond.append(f"holding {held}")
    if has("known_move_id"):
        cond.append(f"knows {n.moves[r['known_move_id']]}")
    if has("known_move_type_id"):
        cond.append(f"knows a {n.types[r['known_move_type_id']]} move")
    if has("minimum_happiness"):
        cond.append("high friendship")
    if has("minimum_affection"):
        cond.append("high affection")
    if has("minimum_beauty"):
        cond.append("high Beauty")
    if has("time_of_day"):
        cond.append(r["time_of_day"].replace("-", " "))
    if has("location_id"):
        cond.append(f"at {n.locations.get(r['location_id'], 'a special location')}")
    if flag("near_special_rock"):
        cond.append("near a special rock")
    if has("relative_physical_stats"):
        cond.append(RELATIVE_STATS[r["relative_physical_stats"]])
    if has("party_species_id"):
        cond.append(f"with {n.species[r['party_species_id']]} in party")
    if has("party_type_id"):
        cond.append(f"with a {n.types[r['party_type_id']]} type in party")
    if has("trade_species_id"):
        cond.append(f"for {n.species[r['trade_species_id']]}")
    if flag("needs_overworld_rain"):
        cond.append("in rain")
    if flag("turn_upside_down"):
        cond.append("console upside down")
    if flag("needs_multiplayer"):
        cond.append("in Union Circle")
    if has("minimum_steps"):
        cond.append(f"after {r['minimum_steps']} Let's Go steps")
    if has("nature_bitmask"):
        cond.append("nature-dependent")
    if has("percentage_chance"):
        cond.append(f"{r['percentage_chance']}% chance")
    text = ", ".join([head, *cond])
    if has("region_id"):
        text += f" (in {n.regions[r['region_id']]})"
    return text


def _select_rows(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    sv = [r for r in rows if r["version_group_id"] == SV_VERSION_GROUP]
    if sv:
        return sv
    default = [r for r in rows if r["is_default"] == "1"]
    return default or rows


def build_chains(db: CsvDb, entries: list[Entry],
                 method_overrides: dict[str, str]) -> tuple[dict[str, dict], list[str]]:
    kept = {e.id for e in entries}
    order = {e.id: i for i, e in enumerate(entries)}
    entry_chain = {e.id: e.chain for e in entries}
    species = {r["id"]: r for r in db.rows("pokemon_species", ("id", "evolves_from_species_id"))}
    form_to_pokemon = {f["id"]: f["pokemon_id"] for f in db.rows("pokemon_forms")}
    default_pokemon = {p["species_id"]: p["id"] for p in db.rows("pokemon")
                       if p["is_default"] == "1"}
    names = Names(db)

    def resolve(form_id: str, species_id: str) -> int:
        pid = form_to_pokemon.get(form_id) if form_id else None
        if pid is None or int(pid) not in kept:
            if pid is not None:
                log.debug("evolutions.resolve.fallback_default form=%s pokemon=%s", form_id, pid)
            pid = default_pokemon[species_id]
        return int(pid)

    grouped: dict[tuple[int, int], list[dict[str, str]]] = defaultdict(list)
    seen_species: set[str] = set()
    cols = ("evolved_species_id", "evolution_trigger_id", "version_group_id", "is_default",
            "required_pokemon_form_id", "evolved_pokemon_form_id")
    for r in db.rows("pokemon_evolution", cols):
        to_sid = r["evolved_species_id"]
        from_sid = species[to_sid]["evolves_from_species_id"]
        if not from_sid:
            raise SchemaError(f"evolution row {r['id']} targets species {to_sid} with no parent")
        seen_species.add(to_sid)
        key = (resolve(r["required_pokemon_form_id"], from_sid),
               resolve(r["evolved_pokemon_form_id"], to_sid))
        grouped[key].append(r)

    gaps: list[str] = []
    for sid, s in species.items():
        if s["evolves_from_species_id"] and sid not in seen_species:
            key = (int(default_pokemon[s["evolves_from_species_id"]]), int(default_pokemon[sid]))
            log.debug("evolutions.build.species_without_rows %s", sid)
            grouped.setdefault(key, [])

    chains: dict[int, dict] = defaultdict(lambda: {"roots": [], "edges": []})
    for (frm, to), rows in sorted(grouped.items()):
        override = method_overrides.get(f"{frm}->{to}")
        if override:
            log.debug("evolutions.build.override %s->%s", frm, to)
            method: str | None = override
        else:
            rendered = [render_method(r, names) for r in _select_rows(rows)] if rows else [None]
            method = None if None in rendered else " / ".join(dict.fromkeys(rendered))
        if method is None:
            gaps.append(f"evolution {frm}->{to}: no renderable method "
                        f"(add tool/overrides.json methods[\"{frm}->{to}\"])")
            method = ""
        if entry_chain[frm] != entry_chain[to]:
            raise SchemaError(f"evolution {frm}->{to} crosses chains")
        chains[entry_chain[frm]]["edges"].append({"from": frm, "to": to, "method": method})

    for chain in chains.values():
        targets = {e["to"] for e in chain["edges"]}
        sources = {e["from"] for e in chain["edges"]}
        chain["roots"] = sorted(sources - targets, key=order.__getitem__)
        chain["edges"].sort(key=lambda e: (order[e["from"]], order[e["to"]]))
        assert chain["roots"], chain
    return {str(k): v for k, v in sorted(chains.items())}, gaps
