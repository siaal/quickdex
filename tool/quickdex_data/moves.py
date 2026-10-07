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
