import logging
from collections import defaultdict

from .csvdb import ENGLISH, CsvDb, SchemaError

log = logging.getLogger("quickdex.moves")

SV_VERSION_GROUP = "25"
# Seen in Scarlet without any Pokémon learning them.
SV_EXTRA = {"struggle", "behemoth-blade", "behemoth-bash", "blazing-torque",
            "wicked-torque", "noxious-torque", "combat-torque", "magical-torque"}
# move_flags id -> label; only flags that matter when reading a move.
FLAG_LABELS = {"1": "Contact", "8": "Punch", "9": "Sound", "15": "Powder", "16": "Bite",
               "17": "Pulse", "18": "Bullet", "21": "Dance"}
TARGET_FALLBACK = {"fainting-pokemon": "Fainted party Pokémon"}


def _excluded(m: dict[str, str]) -> str | None:
    if int(m["id"]) > 10000:
        return "shadow"
    if m["identifier"].startswith("max-"):
        return "max"
    # Z-Moves are the Gen 7 1-PP moves (Struggle is Gen 1, Revival Blessing Gen 9).
    if m["pp"] == "1" and m["generation_id"] == "7":
        return "z-move"
    return None


def _clean(text: str) -> str:
    return " ".join(text.split())


def build_moves(db: CsvDb, desc_overrides: dict[str, str]) -> list[dict]:
    """Every move a player can see in battle, sorted by English name.

    `desc_overrides` maps move identifier -> hand-written long description.
    """
    types = {r["id"]: r["identifier"] for r in db.rows("types", ("id", "identifier"))}
    classes = {r["id"]: r["identifier"]
               for r in db.rows("move_damage_classes", ("id", "identifier"))}
    target_ids = {r["id"]: r["identifier"] for r in db.rows("move_targets", ("id", "identifier"))}
    target_names = db.english_names("move_target_prose", "move_target_id")
    names = db.english_names("move_names", "move_id")
    long = db.english_names("move_effect_prose", "move_effect_id", "effect")
    sv = {r["move_id"] for r in db.rows("pokemon_moves", ("move_id", "version_group_id"))
          if r["version_group_id"] == SV_VERSION_GROUP}
    flags: dict[str, list[str]] = defaultdict(list)
    for r in db.rows("move_flag_map", ("move_id", "move_flag_id")):
        if r["move_flag_id"] in FLAG_LABELS:
            flags[r["move_id"]].append(r["move_flag_id"])
    has_flag_data = {r["move_id"] for r in db.rows("move_flag_map")}
    # Latest English in-game text per move (Scarlet/Violet when it has one).
    text: dict[str, tuple[int, str]] = {}
    for r in db.rows("move_flavor_text", ("move_id", "version_group_id", "language_id",
                                          "flavor_text")):
        vg = int(r["version_group_id"])
        if r["language_id"] == ENGLISH and vg >= text.get(r["move_id"], (-1, ""))[0]:
            text[r["move_id"]] = (vg, r["flavor_text"])

    unused = set(desc_overrides)
    out = []
    for m in db.rows("moves", ("id", "identifier", "generation_id", "type_id", "power", "pp", "accuracy",
                               "priority", "target_id", "damage_class_id", "effect_id",
                               "effect_chance")):
        mid, key = m["id"], m["identifier"]
        reason = _excluded(m)
        if reason:
            log.debug("moves.build.drop %s reason=%s", key, reason)
            continue
        if mid not in names:
            raise SchemaError(f"move {mid} ({key}) lacks an English name")
        if mid not in text:
            log.debug("moves.build.no_text %s", key)
        target_key = target_ids[m["target_id"]]
        desc = desc_overrides.get(key)
        unused.discard(key)
        if desc is None and m["effect_id"] in long:
            desc = "\n\n".join(_clean(p) for p in long[m["effect_id"]].split("\n\n") if p.strip())
        if desc is None:
            log.debug("moves.build.no_description %s", key)
        if mid not in has_flag_data:
            log.debug("moves.build.no_flag_data %s", key)
        out.append({
            "id": int(mid), "key": key, "name": names[mid], "type": types[m["type_id"]],
            "cat": classes[m["damage_class_id"]],
            "power": int(m["power"]) if m["power"] else None,
            "acc": int(m["accuracy"]) if m["accuracy"] else None,
            "pp": int(m["pp"]) if m["pp"] else None,
            "prio": int(m["priority"]),
            "chance": int(m["effect_chance"]) if m["effect_chance"] else None,
            "target": target_names.get(m["target_id"]) or TARGET_FALLBACK[target_key],
            "flags": ([FLAG_LABELS[f] for f in sorted(flags[mid], key=int)]
                      if mid in has_flag_data else None),
            "sv": mid in sv or key in SV_EXTRA,
            "text": _clean(text[mid][1]) if mid in text else None,
            "desc": desc,
        })
    if unused:
        raise SchemaError(f"move description overrides match no move: {sorted(unused)}")
    out.sort(key=lambda m: m["name"])
    return out


LEVEL_UP = "1"
# Fallback games for Pokémon not in Scarlet, labelled on the page, most preferred
# first: Sword/Shield's learnsets are what Scarlet's derive from, BDSP keeps Gen 4
# ones. Legends games and Champions are left out: their move systems differ.
FALLBACK_GAMES = {"20": "Sword/Shield", "23": "Brilliant Diamond/Shining Pearl",
                  "18": "Ultra Sun/Ultra Moon", "17": "Sun/Moon", "19": "Let's Go"}
_PREFERENCE = list(FALLBACK_GAMES)


def build_learnsets(db: CsvDb, entry_ids: list[int], move_ids: set[int]) -> dict[str, dict]:
    """Level-up learnset per entry id: `{"game": None | fallback label,
    "moves": [[level, move id], ...]}`, level 0 = learned on evolution."""
    wanted = {str(i) for i in entry_ids}
    rows: dict[str, dict[str, list[tuple[int, int, int]]]] = defaultdict(lambda: defaultdict(list))
    for r in db.rows("pokemon_moves", ("pokemon_id", "version_group_id", "move_id",
                                       "pokemon_move_method_id", "level", "order")):
        vg = r["version_group_id"]
        if (r["pokemon_move_method_id"] != LEVEL_UP or r["pokemon_id"] not in wanted
                or (vg != SV_VERSION_GROUP and vg not in FALLBACK_GAMES)):
            continue
        rows[r["pokemon_id"]][vg].append(
            (int(r["level"]), int(r["order"] or 0), int(r["move_id"])))
    out = {}
    for pid in sorted(wanted, key=int):
        by_game = rows.get(pid)
        if not by_game:
            raise SchemaError(f"pokemon {pid} has no level-up learnset in any supported game")
        vg = SV_VERSION_GROUP if SV_VERSION_GROUP in by_game else min(by_game, key=_PREFERENCE.index)
        if vg != SV_VERSION_GROUP:
            log.debug("moves.learnset.fallback %s game=%s", pid, vg)
        moves = [[lv, mid] for lv, _, mid in sorted(by_game[vg])]
        unknown = {mid for _, mid in moves} - move_ids
        if unknown:
            raise SchemaError(f"pokemon {pid} learns moves not in moves.json: {unknown}")
        out[pid] = {"game": FALLBACK_GAMES.get(vg), "moves": moves}
    return out
