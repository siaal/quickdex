import logging

from .csvdb import CsvDb, SchemaError
from .entries import Entry

log = logging.getLogger("quickdex.abilities")


def build_abilities(db: CsvDb, entries: list[Entry]) -> dict[str, dict[str, str]]:
    """Ability id -> {key, name, effect, description} for every ability an entry can have.

    `effect` is PokéAPI's one-line short_effect; `description` its long effect text.
    """
    used = sorted({a for e in entries for a in [*e.abilities, e.hidden] if a is not None})
    keys = {r["id"]: r["identifier"] for r in db.rows("abilities", ("id", "identifier"))}
    names = db.english_names("ability_names", "ability_id")
    effects = db.english_names("ability_prose", "ability_id", "short_effect")
    long_effects = db.english_names("ability_prose", "ability_id", "effect")
    table: dict[str, dict[str, str]] = {}
    for a in map(str, used):
        if (a not in keys or not names.get(a) or not effects.get(a)
                or not long_effects.get(a)):
            raise SchemaError(f"ability {a} lacks identifier, English name or effect text")
        # Prose sometimes double-spaces between sentences; keep paragraph breaks.
        effect = " ".join(effects[a].split())
        description = "\n\n".join(" ".join(p.split())
                                   for p in long_effects[a].split("\n\n") if p.strip())
        table[a] = {"key": keys[a], "name": names[a], "effect": effect,
                    "description": description}
    log.debug("abilities.build.done %d", len(table))
    return table
