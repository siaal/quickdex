import json
import logging
from collections import defaultdict
from pathlib import Path

from .abilities import clean_paragraphs, era_notes
from .csvdb import ENGLISH, CsvDb, SchemaError
from .games import Eras, Game

log = logging.getLogger("quickdex.moves")

# Showdown flag -> label; only flags that matter when reading a move. Contact is
# emitted separately as a bool. PokéAPI's move_flag_map lacks every Gen 9 and many
# Gen 7-8 moves, so flags come from Showdown, cross-checked against PokéAPI. They're
# today's flags in every game.
FLAG_LABELS = {"punch": "Punch", "sound": "Sound", "powder": "Powder", "bite": "Bite",
               "pulse": "Pulse", "bullet": "Bullet", "dance": "Dance"}
# PokéAPI move_flags id -> Showdown flag, for the cross-check.
POKEAPI_FLAGS = {"1": "contact", "8": "punch", "9": "sound", "15": "powder", "16": "bite",
                 "17": "pulse", "18": "bullet", "21": "dance"}
TARGET_FALLBACK = {"fainting-pokemon": "Fainted party Pokémon"}
# Before the Gen 4 physical/special split a damaging move's class came from its type.
SPLIT_GENERATION = 4
PHYSICAL_TYPES = {"normal", "fighting", "flying", "poison", "ground", "rock", "bug",
                  "ghost", "steel"}
# move_changelog columns: each row holds the values from before its version group.
CHANGELOG_COLUMNS = ("type_id", "power", "pp", "accuracy", "priority", "target_id",
                     "effect_id", "effect_chance")


def _excluded(m: dict[str, str], game: Game) -> str | None:
    if int(m["id"]) > 10000:
        return "shadow"
    if int(m["generation_id"]) > game.generation:
        return f"introduced in Gen {m['generation_id']}"
    if m["identifier"].startswith("max-"):
        return "max"
    # Z-Moves are the Gen 7 1-PP moves (Struggle is Gen 1, Revival Blessing Gen 9).
    if m["pp"] == "1" and m["generation_id"] == "7":
        return "z-move"
    return None


def _clean(text: str) -> str:
    return " ".join(text.split())


def load_showdown(path: Path) -> dict[int, set[str]]:
    """Showdown's moves.json as move number -> the flags we use (incl. contact)."""
    wanted = set(POKEAPI_FLAGS.values())
    out: dict[int, set[str]] = {}
    for m in json.loads(path.read_text()).values():
        if m["num"] <= 0:  # CAP / custom moves
            continue
        # Hidden Power has one entry per type, all with the same relevant flags.
        out[m["num"]] = set(m.get("flags", {})) & wanted
    assert out, path
    return out


def _as_of_game(db: CsvDb, eras: Eras) -> dict[str, dict[str, str]]:
    """Move id -> changelog columns as they were in the game (only those that differ).
    For each column the earliest change after the game holds the game's value."""
    best: dict[tuple[str, str], tuple[int, str]] = {}
    for r in db.rows("move_changelog", ("move_id", "changed_in_version_group_id",
                                        *CHANGELOG_COLUMNS)):
        vg = r["changed_in_version_group_id"]
        if not eras.after_game(vg):
            continue
        for col in CHANGELOG_COLUMNS:
            key = (r["move_id"], col)
            if r[col] != "" and (key not in best or eras.order[vg] < best[key][0]):
                best[key] = (eras.order[vg], r[col])
    out: dict[str, dict[str, str]] = defaultdict(dict)
    for (mid, col), (_, value) in best.items():
        out[mid][col] = value
    return out


# Scarlet's placeholder for moves it lists but won't let you use.
UNUSABLE_TEXT = "This move can't be used."


def game_text(db: CsvDb, eras: Eras, table: str = "move_flavor_text",
              id_col: str = "move_id") -> dict[str, str]:
    """Move (or item) id -> English in-game text: the game's own, else the latest
    from a version group of its generation or earlier. Placeholder texts don't count."""
    best: dict[str, tuple[tuple[bool, int], str]] = {}
    gen = eras.game.generation
    for r in db.rows(table, (id_col, "version_group_id", "language_id", "flavor_text")):
        vg = r["version_group_id"]
        if r["language_id"] != ENGLISH or eras.vg_generation[vg] > gen:
            continue
        if r["flavor_text"].startswith(UNUSABLE_TEXT):
            continue
        rank = (vg == eras.game.version_group, eras.order[vg])
        if r[id_col] not in best or rank > best[r[id_col]][0]:
            best[r[id_col]] = (rank, r["flavor_text"])
    return {mid: text for mid, (_, text) in best.items()}


def build_moves(db: CsvDb, desc_overrides: dict[str, str],
                showdown: dict[int, set[str]], game: Game) -> list[dict]:
    """Every move a player can see in battle in `game`, as it was there, sorted by
    English name.

    `desc_overrides` maps move identifier -> hand-written long description;
    `showdown` is move number -> flags, from `load_showdown`.
    """
    eras = Eras(db, game)
    types = {r["id"]: r["identifier"] for r in db.rows("types", ("id", "identifier"))}
    classes = {r["id"]: r["identifier"]
               for r in db.rows("move_damage_classes", ("id", "identifier"))}
    target_ids = {r["id"]: r["identifier"] for r in db.rows("move_targets", ("id", "identifier"))}
    target_names = db.english_names("move_target_prose", "move_target_id")
    names = db.english_names("move_names", "move_id")
    long = db.english_names("move_effect_prose", "move_effect_id", "effect")
    change_prose = db.english_names("move_effect_changelog_prose",
                                    "move_effect_changelog_id", "effect")
    effect_changes: dict[str, list[tuple[int, str]]] = defaultdict(list)
    for r in db.rows("move_effect_changelog", ("id", "effect_id", "changed_in_version_group_id")):
        vg = r["changed_in_version_group_id"]
        if eras.after_game(vg) and r["id"] in change_prose:
            effect_changes[r["effect_id"]].append((eras.order[vg], change_prose[r["id"]]))
    in_game = {r["move_id"] for r in db.rows("pokemon_moves", ("move_id", "version_group_id"))
               if r["version_group_id"] == game.version_group}
    pokeapi_flags: dict[str, set[str]] = defaultdict(set)
    for r in db.rows("move_flag_map", ("move_id", "move_flag_id")):
        pokeapi_flags[r["move_id"]].add(POKEAPI_FLAGS.get(r["move_flag_id"], ""))
    text = game_text(db, eras)
    past = _as_of_game(db, eras)

    rows = db.rows("moves", ("id", "identifier", "generation_id", "type_id", "power", "pp",
                             "accuracy", "priority", "target_id", "damage_class_id",
                             "effect_id", "effect_chance"))
    unknown = set(desc_overrides) - {m["identifier"] for m in rows}
    if unknown:
        raise SchemaError(f"move description overrides match no move: {sorted(unknown)}")
    out = []
    for m in rows:
        mid, key = m["id"], m["identifier"]
        reason = _excluded(m, game)
        if reason:
            log.debug("moves.build.drop %s %s reason=%s", game.key, key, reason)
            continue
        if past.get(mid):
            log.debug("moves.build.as_of_game %s %s %s", game.key, key, past[mid])
        m = {**m, **past.get(mid, {})}
        if mid not in names:
            raise SchemaError(f"move {mid} ({key}) lacks an English name")
        if mid not in text:
            log.debug("moves.build.no_text %s %s", game.key, key)
        target_key = target_ids[m["target_id"]]
        desc = desc_overrides.get(key)
        if desc is None and m["effect_id"] in long:
            desc = clean_paragraphs(long[m["effect_id"]])
        notes = era_notes(game, effect_changes[m["effect_id"]])
        if notes:
            log.debug("moves.build.era_notes %s %s", game.key, key)
            desc = f"{notes}\n\n{desc}" if desc else notes
        if desc is None:
            log.debug("moves.build.no_description %s %s", game.key, key)
        flags = showdown.get(int(mid))
        if flags is None:
            raise SchemaError(f"move {mid} ({key}) is missing from Showdown's moves")
        if mid in pokeapi_flags and pokeapi_flags[mid] - {""} != flags:
            raise SchemaError(f"move {mid} ({key}) flags differ: PokéAPI "
                              f"{sorted(pokeapi_flags[mid] - {''})} vs Showdown {sorted(flags)}")
        if mid not in pokeapi_flags:
            log.debug("moves.build.flags_from_showdown_only %s", key)
        move_type = types[m["type_id"]]
        cat = classes[m["damage_class_id"]]
        if game.generation < SPLIT_GENERATION and cat != "status":
            cat = "physical" if move_type in PHYSICAL_TYPES else "special"
        out.append({
            "id": int(mid), "key": key, "name": names[mid], "type": move_type,
            "cat": cat,
            "power": int(m["power"]) if m["power"] else None,
            "acc": int(m["accuracy"]) if m["accuracy"] else None,
            "pp": int(m["pp"]) if m["pp"] else None,
            "prio": int(m["priority"]),
            "chance": int(m["effect_chance"]) if m["effect_chance"] else None,
            "target": target_names.get(m["target_id"]) or TARGET_FALLBACK[target_key],
            "contact": "contact" in flags,
            "flags": [label for f, label in FLAG_LABELS.items() if f in flags],
            "in_game": mid in in_game or key in game.extra_moves,
            "text": _clean(text[mid]) if mid in text else None,
            "desc": desc,
        })
    out.sort(key=lambda m: m["name"])
    return out


LEVEL_UP = "1"
MACHINE = "4"


def machine_label(number: int, generation: int) -> str:
    """PokéAPI numbers HMs from 101: 34 -> "TM034" (Gen 9) or "TM34", 101 -> "HM01"."""
    assert 0 <= number <= 108 or generation >= 8, number
    if number > 100 and generation < 8:
        return f"HM{number - 100:02d}"
    return f"TM{number:03d}" if generation >= 8 else f"TM{number:02d}"


def build_learnsets(db: CsvDb, entry_ids: list[int], move_ids: set[int],
                    game: Game) -> dict[str, dict]:
    """Learnset per entry id: `{"game": None | fallback label,
    "moves": [[level, move id], ...], "machines": [["TM034", move id], ...]}`,
    level 0 = learned on evolution, machines in TM-then-HM number order. Pokémon the
    game lacks use its first fallback game that has them, with no machines (the
    numbering is per game)."""
    fallbacks = dict(game.fallback_games)
    preference = [game.version_group, *fallbacks]
    wanted = {str(i) for i in entry_ids}
    rows: dict[str, dict[str, list[tuple[int, int, int]]]] = defaultdict(lambda: defaultdict(list))
    number = {r["move_id"]: int(r["machine_number"])
              for r in db.rows("machines", ("machine_number", "version_group_id", "move_id"))
              if r["version_group_id"] == game.version_group}
    machines: dict[str, set[tuple[int, int]]] = defaultdict(set)
    for r in db.rows("pokemon_moves", ("pokemon_id", "version_group_id", "move_id",
                                       "pokemon_move_method_id", "level", "order")):
        vg = r["version_group_id"]
        if r["pokemon_id"] not in wanted or vg not in preference:
            continue
        if r["pokemon_move_method_id"] == MACHINE and vg == game.version_group:
            if r["move_id"] not in number:
                raise SchemaError(f"pokemon {r['pokemon_id']} learns move {r['move_id']} "
                                  f"by machine, but no {game.name} machine teaches it")
            machines[r["pokemon_id"]].add((number[r["move_id"]], int(r["move_id"])))
            continue
        if r["pokemon_move_method_id"] != LEVEL_UP:
            continue
        rows[r["pokemon_id"]][vg].append(
            (int(r["level"]), int(r["order"] or 0), int(r["move_id"])))
    out = {}
    for pid in sorted(wanted, key=int):
        by_game = rows.get(pid)
        if not by_game:
            raise SchemaError(f"pokemon {pid} has no level-up learnset in {game.name} "
                              f"or its fallbacks")
        vg = min(by_game, key=preference.index)
        if vg != game.version_group:
            log.debug("moves.learnset.fallback %s %s game=%s", game.key, pid, vg)
        moves = [[lv, mid] for lv, _, mid in sorted(by_game[vg])]
        tms = [[machine_label(n, game.generation), mid]
               for n, mid in sorted(machines.get(pid, ()))] if vg == game.version_group else []
        if not tms:
            log.debug("moves.learnset.no_machines %s %s game=%s", game.key, pid, vg)
        unknown = {mid for _, mid in moves + tms} - move_ids
        if unknown:
            raise SchemaError(f"pokemon {pid} learns moves not in moves.json: {unknown}")
        out[pid] = {"game": fallbacks.get(vg), "moves": moves, "machines": tms}
    return out
