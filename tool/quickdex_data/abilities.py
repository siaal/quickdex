import logging
import re
from collections import defaultdict

from .csvdb import ENGLISH, CsvDb, SchemaError
from .entries import Entry
from .games import Eras, Game

log = logging.getLogger("quickdex.abilities")


# A Markdown table's header rule, e.g. "--------------- | ----:".
_TABLE_RULE = re.compile(r":?-+:?(\s*\|\s*:?-+:?)+")


def _clean_cell(cell: str) -> str:
    # Ranges are padded for alignment ("0\u2013 1"); the app aligns them itself.
    return re.sub(r"\s*\u2013\s*", "\u2013", " ".join(cell.split()))


def _clean_table(lines: list[str]) -> str:
    """Markdown table rows as "a | b", rule kept (it carries the alignment)."""
    rows = [[_clean_cell(c) for c in line.strip().strip("|").split("|")] for line in lines]
    assert all(len(r) == len(rows[0]) for r in rows), lines
    return "\n".join(" | ".join(r) for r in rows)


def clean_paragraphs(text: str) -> str:
    """Collapse runs of spaces (prose sometimes double-spaces); keep paragraph breaks.
    A paragraph that is a Markdown table keeps one row per line (the app draws it)."""
    out = []
    for p in text.split("\n\n"):
        lines = p.strip().split("\n")
        if len(lines) > 2 and _TABLE_RULE.fullmatch(lines[1].strip()):
            log.debug("abilities.clean_paragraphs.table rows=%d", len(lines) - 2)
            out.append(_clean_table(lines))
        elif p.strip():
            out.append(" ".join(p.split()))
    return "\n\n".join(out)


def era_notes(game: Game, changes: list[tuple[int, str]]) -> str | None:
    """`changes` are (version-group order, "how it was before then") for changes after
    the game, any order. Returns an "In <game>:" paragraph, earliest change first."""
    if not changes:
        return None
    notes = [f"• {' '.join(text.split())}" for _, text in sorted(changes)]
    return "\n".join([f"In {game.name}:", *notes])


def build_abilities(db: CsvDb, entries: list[Entry], game: Game) -> dict[str, dict[str, str]]:
    """Ability id -> {key, name, effect, description} for every ability an entry can have.

    `effect` is PokéAPI's one-line short_effect, or the game's in-game text when the
    ability has changed since; `description` its long effect text, led by notes on how
    it differed in the game (`ability_changelog_prose`).
    """
    eras = Eras(db, game)
    used = sorted({a for e in entries for a in [*e.abilities, e.hidden] if a is not None})
    keys = {r["id"]: r["identifier"] for r in db.rows("abilities", ("id", "identifier"))}
    names = db.english_names("ability_names", "ability_id")
    effects = db.english_names("ability_prose", "ability_id", "short_effect")
    long_effects = db.english_names("ability_prose", "ability_id", "effect")
    game_text = {r["ability_id"]: r["flavor_text"]
                 for r in db.rows("ability_flavor_text", ("ability_id", "version_group_id",
                                                          "language_id", "flavor_text"))
                 if r["language_id"] == ENGLISH and r["version_group_id"] == game.version_group}
    change_prose = db.english_names("ability_changelog_prose", "ability_changelog_id", "effect")
    changes: dict[str, list[tuple[int, str]]] = defaultdict(list)
    for r in db.rows("ability_changelog", ("id", "ability_id", "changed_in_version_group_id")):
        vg = r["changed_in_version_group_id"]
        if eras.after_game(vg) and r["id"] in change_prose:
            changes[r["ability_id"]].append((eras.order[vg], change_prose[r["id"]]))
    table: dict[str, dict[str, str]] = {}
    for a in map(str, used):
        if (a not in keys or not names.get(a) or not effects.get(a)
                or not long_effects.get(a)):
            raise SchemaError(f"ability {a} lacks identifier, English name or effect text")
        effect = " ".join(effects[a].split())
        description = clean_paragraphs(long_effects[a])
        notes = era_notes(game, changes[a])
        if notes:
            if a not in game_text:
                raise SchemaError(f"ability {a} changed since {game.name} but has no "
                                  f"{game.name} in-game text")
            log.debug("abilities.build.era_notes %s %s", game.key, keys[a])
            effect = " ".join(game_text[a].split())
            description = f"{notes}\n\n{description}"
        table[a] = {"key": keys[a], "name": names[a], "effect": effect,
                    "description": description}
    log.debug("abilities.build.done %s %d", game.key, len(table))
    return table
