"""Scrambled Scarlet's item changes from the Doozdex: when Delibird Presents starts
selling each battle item (Item Locations tab) and the held-item buffs (Held Item
Buffs/Changes tab). The sheet is free text, so every name must match a Scarlet item;
anything that doesn't is a gap, fixed in overrides.json "scrambled"."""
import logging
import re
from collections.abc import Callable
from pathlib import Path

from .doozdex import ITEM_CHANGES_TAB, ITEM_SHOP_TAB, Cell, read_grid
from .items import norm

log = logging.getLogger("quickdex.scrambled_items")

_BADGE_HEADING = re.compile(r"^(\d+)\s+BADGES?\b", re.IGNORECASE)
# A cell this wide is a sentence across the sheet, not an item.
_FULL_WIDTH = 20
_PARENS = re.compile(r"\s*\(([^)]*)\)")
_CHANGE = re.compile(r"([A-Z][A-Za-z' ]+?)\s+(\d+%?)\s*>\s*(\d+%?)(?:\s*\(([^)]*)\))?")
_UNOBTAINABLE = re.compile(r"\b(\w+) Berries are not obtainable", re.IGNORECASE)
UNOBTAINABLE_NOTE = "Not obtainable in Scrambled Scarlet."


def shop_cells(grid: list[list[Cell]]) -> list[tuple[str, int | None]]:
    """Each item cell under the badge headings, with the badge count of the heading
    above it (None when it sits under no single heading)."""
    headings: list[tuple[int, int, int]] = []  # first column, last column, badges
    out: list[tuple[str, int | None]] = []
    for row in grid:
        found = [(c, c + cell.span - 1, int(m[1])) for c, cell in enumerate(row)
                 if (m := _BADGE_HEADING.match(cell.flat))]
        if found:
            headings = found
            continue
        for c, cell in enumerate(row):
            text = cell.flat
            if not text or not headings:
                continue
            if cell.span >= _FULL_WIDTH or text.startswith("<"):
                log.debug("scrambled_items.shop.prose %r", text[:40])
                continue
            under = {n for first, last, n in headings
                     if first <= c + cell.span - 1 and c <= last}
            out.append((text, under.pop() if len(under) == 1 else None))
    return out


def read_changes(grid: list[list[Cell]], is_item: Callable[[str], bool]
                 ) -> tuple[list[tuple[str, str]], list[str]]:
    """(item name as written, note) for each buffed item, and the berries the sheet
    says can't be obtained. Headings ("Healing Percentage Increased") say what
    changed; lines under them name the items, with "old > new" values. Lines with
    a sentence are commentary."""
    heading = ""
    notes: list[tuple[str, str]] = []
    unobtainable: list[str] = []
    for row in grid:
        text = row[0].flat if row else ""
        if not text:
            continue
        unobtainable += [f"{m} Berry" for m in _UNOBTAINABLE.findall(text)]
        changes = list(_CHANGE.finditer(text))
        rest = _CHANGE.sub("", text) if changes else text
        if changes and not re.sub(r"[\s-]", "", rest):
            for m in changes:
                detail = f" ({m[4]})" if m[4] else ""
                notes.append((m[1].strip(), f"{heading}: {m[2]} \u2192 {m[3]}{detail}"))
            continue
        line = text.lstrip("- ").strip()
        detail = _PARENS.search(line)
        name = _PARENS.sub("", line).strip()
        if heading and is_item(name):
            notes.append((name, heading + (f" ({detail[1]})" if detail else "")))
        elif "." not in text and len(text) < 100:
            heading = text
            log.debug("scrambled_items.changes.heading %r", text)
        else:
            log.debug("scrambled_items.changes.prose %r", text[:40])
    return notes, unobtainable


def apply_scrambled_items(items: list[dict], doozdex: Path, fix: dict) -> list[str]:
    """Adds `badges` (Delibird Presents unlock) and `note` (the hack's change) to
    Scarlet's `items` in place; returns gaps.

    `fix` is overrides.json "scrambled": `item_groups` maps a sheet phrase to item
    keys or "cat:<category>"; `item_comments` lists prefixes of non-item cells;
    `item_badges` gives the badge count for items under no single heading."""
    gaps: list[str] = []
    by_name = {norm(i["name"]): i for i in items}
    groups: dict = fix.get("item_groups", {})
    comments: list[str] = fix.get("item_comments", [])
    badge_fixes: dict = fix.get("item_badges", {})
    used: set[str] = set()

    def resolve(phrase: str, where: str) -> list[dict]:
        if phrase in groups:
            used.add(f"item_groups:{phrase}")
            spec = groups[phrase]
            if isinstance(spec, str) and spec.startswith("cat:"):
                found = [i for i in items if i["cat"] == spec[4:]]
            else:
                found = [by_name.get(norm(k)) or {"key": k} for k in spec]
            missing = [i["key"] for i in found if "id" not in i]
            if not found or missing:
                gaps.append(f"item group {phrase!r} has unknown items {missing or spec}")
            return [i for i in found if "id" in i]
        if norm(phrase) in by_name:
            return [by_name[norm(phrase)]]
        gaps.append(f"{where} {phrase!r} matches no Scarlet item")
        return []

    for text, badges in shop_cells(read_grid(doozdex / f"{ITEM_SHOP_TAB}.html")):
        comment = next((p for p in comments if text.startswith(p)), None)
        if comment is not None:
            used.add(f"item_comments:{comment}")
            log.debug("scrambled_items.shop.comment %r", text[:40])
            continue
        bare = _PARENS.sub("", text).strip()
        parts = [bare] if bare in groups else re.split(r"\s*[&+]\s*", bare)
        last_word = parts[-1].split()[-1]
        for part in parts:
            # "Kee & Maranga Berry": Kee shares the trailing "Berry".
            if (part not in groups and norm(part) not in by_name
                    and norm(f"{part} {last_word}") in by_name):
                part = f"{part} {last_word}"
            n = badges
            if n is None:
                if part not in badge_fixes:
                    gaps.append(f"shop item {part!r} sits under no single badge heading; "
                                f"add scrambled.item_badges")
                    continue
                used.add(f"item_badges:{part}")
                n = badge_fixes[part]
            for item in resolve(part, "shop item"):
                if "badges" in item and item["badges"] != n:
                    log.debug("scrambled_items.shop.repeat %s %d %d", item["key"],
                              item["badges"], n)
                item["badges"] = min(item.get("badges", n), n)

    notes, unobtainable = read_changes(read_grid(doozdex / f"{ITEM_CHANGES_TAB}.html"),
                                       lambda name: norm(name) in by_name)
    for name in unobtainable:
        notes.append((name, UNOBTAINABLE_NOTE))
    for name, note in notes:
        for item in resolve(name, "changed item"):
            if note not in item.get("note", ""):
                item["note"] = f"{item['note']}\n{note}" if "note" in item else note
    for kind, table in (("item_groups", groups), ("item_comments", comments),
                        ("item_badges", badge_fixes)):
        gaps += [f"unused override scrambled.{kind}: {k!r}" for k in table
                 if f"{kind}:{k}" not in used]
    log.debug("scrambled_items.done shop=%d notes=%d gaps=%d",
              sum("badges" in i for i in items), sum("note" in i for i in items), len(gaps))
    return gaps
