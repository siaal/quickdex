"""Scrambled Scarlet: Scarlet's data with the Doozdex's changes laid over it.

Renamed moves and abilities keep the id and key of the vanilla one they replace
(only the name changes), so ability immunities and saved teams follow them. Moves the
hack adds get ids above NEW_MOVE_BASE, derived from their name so they're stable.
"""
import logging
import re
import zlib
from dataclasses import dataclass, field
from pathlib import Path
from types import SimpleNamespace

from PIL import Image

from .abilities import build_abilities, clean_paragraphs
from .csvdb import CsvDb, SchemaError
from .doozdex import (
    ABILITIES_TAB,
    MOVES_TAB,
    POKEMON_TABS,
    REVERSE_BOSSES_TAB,
    TMS_TAB,
    VANILLA_BOSSES_TAB,
    Cell,
    bar_lengths,
    cell,
    image_key,
    image_path,
    read_grid,
)
from .entries import Entry, build_entries
from .evolutions import build_chains
from .games import SCARLET
from .moves import build_moves
from .typechart import TYPE_ORDER

log = logging.getLogger("quickdex.scrambled")

NEW_MOVE_BASE = 100_000
# Bracketed tags on a move's name that say which abilities boost or block it. Anything
# else in brackets there is a note on who learns it.
MOVE_TAGS = {"mega launcher": "Mega Launcher", "bulletproof": "Bulletproof",
             "sharpness": "Sharpness", "sound": "Sound", "wind rider": "Wind Rider",
             "rapid fire": "Rapid Fire", "ai only": "AI Only",
             "negated by gravity": "Gravity", "gravity": "Gravity"}
# Showdown flags still meaningful in the hack (Pulse/Bullet became the sheet's Mega
# Launcher/Bulletproof lists). Only for moves the hack didn't rename.
KEPT_SHOWDOWN_FLAGS = {"punch": "Punch", "bite": "Bite", "powder": "Powder",
                       "dance": "Dance"}


def norm(name: str) -> str:
    """Match key for names: case, spacing, hyphens and accents ignored."""
    name = name.replace("é", "e").replace("’", "'")
    return re.sub(r"[^a-z0-9]", "", name.lower())


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower().replace("é", "e")).strip("-")


def _category(path: Path) -> str:
    """The sheet's category icons: grey status, red physical, blue special."""
    im = Image.open(path).convert("RGBA")
    px = [p for p in im.get_flattened_data() if p[3] > 200]
    assert px, path
    r, g, b = (sum(p[i] for p in px) / len(px) for i in range(3))
    if max(r, g, b) - min(r, g, b) < 20:
        return "status"
    return "physical" if r > b else "special"


@dataclass
class MoveRow:
    """One listing of a move in the sheet (moves appear in several sections)."""
    where: str
    old: str | None  # the vanilla move it replaces, for "Old > New" names
    name: str
    tags: list[str]
    cat_img: str | None
    type: str
    power: str
    acc: str
    desc: str
    pp: str
    target: str
    notes: list[str] = field(default_factory=list)


_TM_PREFIX = re.compile(r"^TM\s*\d+\s+")


def _move_row(row: list[Cell], where: str) -> MoveRow | None:
    if len(row) < 8 or row[2].flat.lower() not in TYPE_ORDER:
        return None
    raw = re.sub(r">\s+", "> ", _TM_PREFIX.sub("", row[0].text.strip()))
    tags, notes = [], []
    for inner in re.findall(r"\(([^)]*)\)", raw):
        for part in re.split(r",|-", inner):
            t = MOVE_TAGS.get(part.strip().lower())
            if t:
                tags.append(t)
            elif part.strip():
                notes.append(part.strip())
    # "Lunge (Still Exists) > Bug Bomber": a new move, not a replacement.
    still = re.search(r"\(still exists\)", raw, re.IGNORECASE) is not None
    raw = re.sub(r"\((still exists)\)", "", raw, flags=re.IGNORECASE)
    # The name ends at its first bracket or wide gap; a note may follow (Protect).
    raw = re.split(r"\(|\s{3,}|\n", raw)[0].replace("*", "").strip()
    old, _, new = raw.rpartition(">")
    if still:
        log.debug("scrambled.moves.new_beside %s %s", old.strip(), new.strip())
        old = ""
    return MoveRow(where, old.strip() or None, new.strip(), sorted(set(tags)),
                   image_key(row[1].imgs[0]) if row[1].imgs else None,
                   row[2].flat.lower(), row[3].flat, row[4].flat, row[5].flat,
                   row[6].flat, row[7].flat, notes)


def _number(text: str, what: str) -> int | None:
    """The sheet's numbers: "40 > 45" is the new value, "25*" footnoted, "---" none."""
    text = text.rpartition(">")[2].replace("*", "").replace("%", "").strip()
    text = re.sub(r"\s*PP$", "", text)
    if text in ("", "---", "----", "Can't Miss", "TBD", "PP"):
        return None
    if re.fullmatch(r"\d+", text):
        return int(text)
    if re.fullmatch(r"\d+-\d+", text):  # variable power, explained in the text
        return None
    raise SchemaError(f"unreadable {what}: {text!r}")


_PRIORITY = re.compile(r"([+-]\d)\s*priority", re.IGNORECASE)


@dataclass
class VanillaMoves:
    """Every PokéAPI move by id, with name lookups."""
    names: dict[int, str]
    keys: dict[int, str]
    by_norm: dict[str, int]

    @classmethod
    def load(cls, db: CsvDb) -> "VanillaMoves":
        names = {int(k): v for k, v in db.english_names("move_names", "move_id").items()
                 if int(k) < 10000}
        keys = {int(r["id"]): r["identifier"] for r in db.rows("moves", ("id", "identifier"))}
        by_norm: dict[str, int] = {}
        for mid, name in sorted(names.items()):
            by_norm.setdefault(norm(name), mid)
        return cls(names, keys, by_norm)


def read_move_rows(doozdex: Path) -> list[MoveRow]:
    rows = []
    for tab in (MOVES_TAB, TMS_TAB):
        for i, row in enumerate(read_grid(doozdex / f"{tab}.html")):
            if row and row[0].flat.upper().startswith("*UNUSED MOVES"):
                log.debug("scrambled.moves.unused_from %s:%d", tab, i)
                break  # the rest are scrapped
            m = _move_row(row, f"{tab}:{i}")
            if m:
                rows.append(m)
    return rows


STAT_LABELS = ("HP", "Attack", "Defense", "Sp. Atk", "Sp. Def", "Speed")


@dataclass
class Block:
    """One Pokémon's section on a Gens tab."""
    where: str
    name: str
    types: list[str]
    stat_diffs: list[int]
    total: int | None  # the sheet's new base stat total, a checksum
    abilities: list[str]  # as written, e.g. "Energy Shield (Shadow Shield)"
    notes: str
    # Learnset cells as written (level-up, then TMs by badge); only on the first
    # Pokémon of a family, the rest share them.
    learnset: list[str]
    family: str = ""  # the heading above, e.g. "Tadbulb - Bellibolt"
    total_diff: int | None = None  # the sheet's "Total (+n)"
    # The stat bar image: (width, bar lengths in px). Its bars are the real stats.
    bars: tuple[int, list[int]] | None = None


def read_blocks(doozdex: Path) -> tuple[list[Block], list[str]]:
    blocks, gaps = [], []
    for tab in POKEMON_TABS:
        grid = read_grid(doozdex / f"{tab}.html")
        family = ""
        for i, row in enumerate(grid):
            filled = [c for c in row if c.flat and c.flat != "[img]" and not c.imgs]
            if len(filled) == 1 and 0 < len(row[0].flat) < 80 and not row[0].flat.lower(
                    ).startswith(("click", "shortcut")):
                family = row[0].text.split("\n")[0]
                family = re.split(r"\s{3,}|CLICK", family)[0].strip()
            if len(row) < 3 or not row[2].flat.startswith("(Difference From Vanilla"):
                continue
            where = f"{tab}:{i}"
            if row[0].flat == "POKEMON NAME":  # the sheet's template
                continue
            diffs, total, total_row, prev, total_diff = [], None, i + 7, i, None
            for label in (*STAT_LABELS, "Total"):
                # By label, not offset: a few blocks are a row out.
                # Tolerates the sheet's dropped brackets, e.g. "Attack (+15".
                pattern = re.compile(rf"{re.escape(label)}\s*\(?\s*([+-]?\s*\d+)\s*\)?")
                found = [(r, m) for r in range(i + 1, i + 10)
                         if (m := pattern.fullmatch(cell(grid, r, 2).flat))]
                if not found and label != "Total":
                    # Mislabelled (e.g. a second "Sp. Atk"): take the next row.
                    m = re.search(r"\(([+-]?\d+)\)", cell(grid, prev + 1, 2).flat)
                    if m:
                        log.debug("scrambled.blocks.stat_by_position %s %s", where, label)
                        found = [(prev + 1, m)]
                if not found:
                    if label != "Total":
                        gaps.append(f"{where} {row[0].flat}: no {label} (+n)")
                    diffs.append(0)
                    continue
                r, m = found[0]
                prev = r
                if label == "Total":
                    total_row = r
                    total_diff = int(m[1].replace(" ", ""))
                    t = cell(grid, r, 3).flat.lstrip("&")
                    total = int(t) if t.isdigit() else None
                else:
                    diffs.append(int(m[1].replace(" ", "")))
            diffs = diffs[:6]
            hp_row = next(r for r in range(i + 1, i + 10)
                          if cell(grid, r, 2).flat.startswith("HP"))
            types = [c.flat.lower() for c in grid[hp_row][:2] if c.flat]
            bars = None
            for url in cell(grid, hp_row, 3).imgs:
                if image_path(doozdex, url).is_file():
                    bars = bar_lengths(image_path(doozdex, url))
            abilities = [cell(grid, hp_row + k, 5).text for k in (0, 2, 4)]
            learnset = [cell(grid, i + 1, c).text for c in range(6, 11)]
            blocks.append(Block(where, row[0].flat, types, diffs, total,
                                [a.strip() for a in abilities if a.strip()],
                                cell(grid, total_row, 4).text.strip(),
                                learnset if any(learnset) else [], family, total_diff,
                                bars))
    return blocks, gaps


BAR_AXIS = 156.9  # stat points across a stat bar image's width (unless stretched)


def reconcile_stats(comp: list[int], bars: tuple[int, list[int]] | None,
                    total: int | None) -> tuple[list[int], str]:
    """The sheet's stats: vanilla + its per-stat changes (`comp`), unless the stat bar
    image and the sheet's total both say otherwise. The changes column is sometimes
    stale; the bars are drawn from the real numbers but only read to about ±2, so a
    stat changes only when a bar disagrees by 3+ and the new values sum to the total."""
    import statistics
    if bars is None or len(bars[1]) != 6 or total is None or sum(comp) == total:
        return comp, "changes"
    w, lengths = bars
    scale = statistics.median(n / c for n, c in zip(lengths, comp, strict=True) if c)
    if all(abs(n / scale - c) < 2 for n, c in zip(lengths, comp, strict=True)):
        return comp, "changes (bars agree, total stale)"
    if sum(abs(n / scale - c) < 2 for n, c in zip(lengths, comp, strict=True)) < 4:
        scale = w / BAR_AXIS  # most bars disagree: assume the usual axis
    read = [round(n / scale) for n in lengths]
    off = [i for i, (b, c) in enumerate(zip(read, comp, strict=True)) if abs(b - c) >= 3]
    fixed = [read[i] if i in off else c for i, c in enumerate(comp)]
    if off and sum(fixed) == total:
        return fixed, "bars"
    if len(off) == 1:  # the bar is close; the total pins the exact value
        i = off[0]
        exact = comp[i] + total - sum(comp)
        if abs(exact - read[i]) <= 2:
            return [exact if k == i else c for k, c in enumerate(comp)], "bars+total"
    return comp, "changes (total disagrees)"


REGIONS = {"alolan": "Alolan", "galarian": "Galarian", "hisuian": "Hisuian",
           "hiusian": "Hisuian", "paldean": "Paldean"}
# The hack's own regional forms: new entries, drawn with the base species' artwork.
DOOZIAN = "Doozian"
DOOZIAN_ID_BASE = 20_000


class EntryMatcher:
    """Sheet names -> Scarlet entries (dicts in pokedex.json shape).

    Plain species names, "<Region> <Species>", and bare form names ("Combat Breed",
    "Midday Form") read in the context of the species named last.
    """

    def __init__(self, entries: list[dict], name_overrides: dict[str, int]):
        self.by_id = {e["id"]: e for e in entries}
        self.overrides = name_overrides
        self.species: dict[str, list[dict]] = {}
        for e in entries:
            self.species.setdefault(norm(e["species"]), []).append(e)

    def contexts(self, family: str) -> list[str]:
        """Species named in a family heading, e.g. "Paldean Tauros Combat Breed"."""
        words = re.split(r"[\s\-]+", family)
        return [norm(w) for w in words if norm(w) in self.species]

    def match(self, name: str, contexts: list[str]) -> dict | None:
        if name in self.overrides:
            return self.by_id[self.overrides[name]]
        words = name.split()
        region = REGIONS.get(words[0].lower()) if len(words) > 1 else None
        if region:
            for e in self.species.get(norm(" ".join(words[1:])), []):
                if (e["form"] or "").startswith(region):
                    return e
            return None
        forms = self.species.get(norm(name))
        if forms:
            return min(forms, key=lambda e: e["id"])  # the default form
        # "<Species> <Form>", "<Form> <Species>" or a bare form of a context species.
        for i in range(len(words) - 1, 0, -1):
            if norm(" ".join(words[:i])) in self.species:
                contexts, words = [norm(" ".join(words[:i]))], words[i:]
                break
            if norm(" ".join(words[i:])) in self.species:
                contexts, words = [norm(" ".join(words[i:]))], words[:i]
                break
        want = norm(re.sub(r"\b(Form|Mode)\b", "", " ".join(words)))
        for context in contexts:
            for e in self.species.get(context, []):
                if want and want in norm(e["form"] or ""):
                    return e
        return None


@dataclass
class AbilityGuide:
    """The Ability Guide tab: hack name -> vanilla name it replaced, and the guide's
    text per ability (hack name, or vanilla name for buffed ones)."""
    renames: dict[str, str]
    text: dict[str, str]


def read_ability_guide(doozdex: Path, vanilla: set[str]) -> AbilityGuide:
    grid = read_grid(doozdex / f"{ABILITIES_TAB}.html")
    renames: dict[str, str] = {}
    text: dict[str, list[str]] = {}
    current: list[str] = []
    started = False
    for row in grid:
        line = row[0].flat if row else ""
        if not started:  # skip the contents table at the top
            started = bool(re.fullmatch(r"[\w' -]+ -> [\w' -]+", line))
            if not started:
                continue
        if not line:
            current = []
            continue
        m = re.fullmatch(r"([\w' -]+?) -> ([\w' -]+)", line)
        heads = [h.strip() for h in re.split(r" & |/", line)]
        if m:
            renames[m[2].strip()] = m[1].strip()
            current.append(m[2].strip())
            text.setdefault(m[2].strip(), [])
        elif not current and all(norm(h) in vanilla for h in heads):
            current = heads  # a buffed vanilla ability, e.g. "Mega Launcher & Bulletproof"
            for h in heads:
                text.setdefault(h, [])
        elif current:
            for h in current:
                text[h].append(" ".join(c.flat for c in row if c.flat))
    return AbilityGuide(renames, {k: "\n".join(v) for k, v in text.items() if v})


def split_ability(raw: str, known: list[str]) -> tuple[str, str | None]:
    """"Energy Shield (Shadow Shield)" -> ("Energy Shield", "Shadow Shield"): the name and
    the vanilla ability it replaced, if the brackets name one. Other brackets are notes.
    `known` is every ability name (vanilla and hack), longest first, for names the sheet
    runs into a note ("Brazen Drops Stats = Boosted")."""
    flat = re.sub(r"\s+", " ", raw).strip()
    name = flat.split("(")[0].strip()
    if norm(name) not in {norm(k) for k in known}:
        name = next((k for k in known if norm(flat).startswith(norm(k))), name)
    old = None
    for inner in re.findall(r"\(([^)]*)\)?", flat):
        if inner.strip() and norm(inner) in {norm(k) for k in known}:
            old = inner.strip()
    return name, old


def build_scrambled_moves(db: CsvDb, scarlet_moves: list[dict], showdown: dict[int, set[str]],
                          doozdex: Path, overrides: dict) -> tuple[list[dict], dict[str, int],
                                                                     list[str]]:
    """The hack's moves in the app's move shape, sorted by name; the norm(name) -> id
    lookup that learnsets resolve against; and gaps."""
    vanilla = VanillaMoves.load(db)
    scarlet = {m["id"]: m for m in scarlet_moves}
    rows = read_move_rows(doozdex)
    cats = {url: _category(image_path(doozdex, url))
            for url in sorted({r.cat_img for r in rows if r.cat_img})
            if image_path(doozdex, url).is_file()}
    gaps: list[str] = []

    # Renames first: "Old > New" gives New the id of Old, wherever it's listed.
    renamed: dict[str, int] = {}
    for r in rows:
        if r.old:
            old_id = vanilla.by_norm.get(norm(r.old))
            if old_id is None:
                gaps.append(f"move {r.name!r} replaces unknown move {r.old!r} ({r.where})")
                continue
            if renamed.setdefault(norm(r.name), old_id) != old_id:
                gaps.append(f"move {r.name!r} replaces two moves ({r.where})")
    replaced = set(renamed.values())

    by_id: dict[int, MoveRow] = {}
    for r in rows:
        key = norm(r.name)
        mid = renamed.get(key)
        if mid is None:
            mid = vanilla.by_norm.get(key)
            if mid in replaced:  # e.g. High Jump Kick now names Axe Kick's slot
                mid = None
        if mid is None:
            mid = NEW_MOVE_BASE + zlib.crc32(key.encode()) % NEW_MOVE_BASE
        first = by_id.setdefault(mid, r)
        if first is not r and (first.type, first.power, first.acc, first.pp) != (
                r.type, r.power, r.acc, r.pp):
            log.debug("scrambled.moves.listing_differs %s %s vs %s", r.name, first.where,
                      r.where)
    names = {norm(r.name): mid for mid, r in by_id.items()}
    if len(names) != len(by_id):
        gaps.append("two moves share a name")

    out = []
    for mid, r in by_id.items():
        if r.cat_img not in cats:
            gaps.append(f"move {r.name!r} has no category icon ({r.where})")
            continue
        try:
            power, acc, pp = (_number(r.power, "power"), _number(r.acc, "accuracy"),
                              _number(r.pp, "PP"))
        except SchemaError as e:
            gaps.append(f"move {r.name!r}: {e} ({r.where})")
            continue
        base = scarlet.get(mid)
        same_move = base is not None and norm(base["name"]) == norm(r.name)
        prio = _PRIORITY.search(r.desc)
        flags = list(r.tags)
        if same_move:
            flags += [label for f, label in KEPT_SHOWDOWN_FLAGS.items()
                      if f in showdown.get(mid, set())]
        out.append({
            "id": mid,
            "key": vanilla.keys[mid] if mid in vanilla.keys else slug(r.name),
            "name": r.name, "type": r.type, "cat": cats[r.cat_img],
            "power": power, "acc": acc, "pp": pp,
            "prio": int(prio[1]) if prio else (base["prio"] if same_move else 0),
            "chance": None,
            "target": r.target,
            # The sheet says "Contact." for some contact moves but not all, so the
            # game's flag for the move's slot counts too.
            "contact": bool(re.search(r"(^|\.\s*)Contact\.", r.desc))
            or "contact" in showdown.get(mid, set()),
            "flags": sorted(set(flags)),
            "in_game": True,
            "text": r.desc,
            "desc": None,
        })
    out.sort(key=lambda m: m["name"])
    return out, names, gaps


# ---------------------------------------------------------------------------
# Learnsets


@dataclass
class Member:
    """A Pokémon sharing a family learnset, with the names the sheet may call it."""
    entry_id: int
    names: list[str]  # norm()ed: block name, species


@dataclass
class _Token:
    move: int
    stars: int
    only: set[int] | None  # entry ids allowed (None: everyone)
    level: int | None  # None for TMs; 0 for "Ev."
    badges: int


_LEVEL = re.compile(r"^(\d+|Ev)\s*\.\s*(.+)$", re.IGNORECASE)
_BADGE = re.compile(r"^\+?\s*(?:BADGES\s+)?(\d+)(?:\s*-\s*\d+)?\s*BADGE", re.IGNORECASE)
_EVO_PLACEHOLDER = re.compile(r"evo(lution)?\s*(energy\s*)?moves?\b", re.IGNORECASE)


def _mentioned(text: str, members: list[Member]) -> list[Member]:
    """Members named in `text`, in the order they're named."""
    flat = norm(text)
    hits = []
    for m in members:
        pos = [flat.find(n) for n in m.names if n and n in flat]
        if pos:
            hits.append((min(pos), m))
    return [m for _, m in sorted(hits, key=lambda h: h[0])]


def _only_rule(text: str, members: list[Member]) -> set[int] | None:
    """Who a footnote like "*Means ONLY Golem can learn the move, NOT Graveler" or
    "**No Sprigatito" lets learn the marked moves; None if it can't be read."""
    ids = [m.entry_id for m in members]
    m = re.search(r"\bonly\b(.*)", text, re.IGNORECASE)
    if m and (after := _mentioned(m[1], members)):
        return {after[0].entry_id}
    if m and (before := _mentioned(text[:m.start()], members)):  # "Overqwil Only"
        return {before[-1].entry_id}
    m = re.search(r"\b(?:no|not)\s+(.*)|(.*)\bcan'?t\b", text, re.IGNORECASE)
    if m:
        named = _mentioned(m[1] or m[2] or "", members)
        if named:
            return set(ids) - {n.entry_id for n in named}
        until = re.search(r"until evolving into (.*)", text, re.IGNORECASE)
        if until and (into := _mentioned(until[1], members)):
            return set(ids[ids.index(into[0].entry_id):])
    return None


def parse_learnset(cells: list[str], members: list[Member], move_names: dict[str, int],
                   fixes: dict[str, str | None], where: str
                   ) -> tuple[dict[int, dict[str, list[list[int]]]], list[str]]:
    """A family's learnset cells -> entry id -> {"moves": [[level, id]], "tms":
    [[badges, id]]}. "Ev." moves (level 0) go to the evolved members only."""
    gaps: list[str] = []
    tokens: list[_Token] = []
    rules: dict[int, set[int] | None] = {}
    sticky: set[int] | None = None
    badges = 0
    lines = [(k, line.strip()) for k, c in enumerate(cells)
             for line in re.split(r"\n|\s{3,}", c) if line.strip()]
    for k, line in lines:
        if line in fixes:
            if fixes[line] is None:
                continue
            line = fixes[line]  # type: ignore[assignment]
        level = None
        if m := _LEVEL.match(line):
            level = 0 if m[1].lower() == "ev" else int(m[1])
            line = m[2]
        elif m := _BADGE.match(line):
            badges = int(m[1])
            continue
        if line.lower() in ("x", "v", "=", "^") or line.startswith("(Part"):
            continue
        if line.startswith("("):  # a note on the move above, or on what follows
            rule = _only_rule(line, members)
            if re.search(r"after this", line, re.IGNORECASE) and rule is not None:
                sticky = rule  # "(Trapinch can't [learn] any ... listed after this)"
            elif re.search(r"\bonly\b", line, re.IGNORECASE) and tokens and rule is not None:
                tokens[-1].only = rule  # "(Lilligant Only)"
            else:
                log.debug("scrambled.learnset.note %s %r", where, line[:60])
            continue
        if line.startswith(("*", "^")) or re.match(r"means\b", line, re.IGNORECASE):
            stars = len(line) - len(line.lstrip("*"))
            rule = _only_rule(line, members)
            if line.startswith("^"):
                if "from" in line.lower() or "level" in line.lower():
                    continue  # "^ Level-Up Moves From Donphan": a section label
                if tokens and rule is not None:
                    tokens[-1].only = rule
                continue
            if rule is None:
                log.debug("scrambled.learnset.unread_footnote %s %r", where, line)
            rules[max(stars, 1)] = rule
            continue
        if _EVO_PLACEHOLDER.search(line):
            continue  # "Optional Evolution Move": the hack's no-effect energy moves
        only = None
        for inner in re.findall(r"\(([^)]*)\)?", line):
            if re.search(r"\bonly\b", inner, re.IGNORECASE):
                only = _only_rule(inner, members)
        body = re.split(r"\(", line)[0]
        stars = body.count("*")
        body = body.replace("*", "").strip().lstrip("+").strip()
        parts = [p.strip().lstrip("+").strip() for p in re.split(r"/|\+| & ", body)]
        parts = [fixes.get(p, p) for p in parts if p]
        if parts and all(p is None for p in parts):
            continue  # moves the sheet names but never lists (overrides say so)
        parts = [p for p in parts if p]
        ids = [move_names.get(norm(p)) for p in parts]
        if only is None and level is not None:
            only = sticky
        if parts and all(ids):
            tokens += [_Token(i, stars, only, level, badges) for i in ids]  # type: ignore[misc]
        elif len(body.split()) > 4 or body.endswith((":", ".")):
            log.debug("scrambled.learnset.prose %s %r", where, line[:60])
        else:
            gaps.append(f"learnset {where}: unknown move {line!r} (add to "
                        f"overrides.json scrambled.learnset_fixes)")

    everyone = {m.entry_id for m in members}
    out: dict[int, dict[str, set[tuple[int, int]]]] = {
        m.entry_id: {"moves": set(), "tms": set()} for m in members}
    first = members[0].entry_id
    for t in tokens:
        allowed = t.only if t.only is not None else (rules.get(t.stars) if t.stars else None)
        for mid in allowed if allowed is not None else everyone:
            if t.level is not None:
                if t.level == 0 and mid == first and len(members) > 1:
                    continue
                out[mid]["moves"].add((t.level, t.move))
            else:
                out[mid]["tms"].add((t.badges, t.move))
    result = {}
    for mid, sets in out.items():
        tms: dict[int, int] = {}
        for b, move in sets["tms"]:
            tms[move] = min(b, tms.get(move, b))
        result[mid] = {"moves": [list(x) for x in sorted(sets["moves"])],
                       "tms": [[b, m] for m, b in sorted(tms.items(), key=lambda x: (x[1], x[0]))]}
    return result, gaps


# ---------------------------------------------------------------------------
# Evolutions


_SENTENCE = re.compile(r"(?<=[.!])\s+|\n")


def evolution_sentence(notes: str) -> str | None:
    """The first sentence of a block's notes that says how it evolves."""
    for s in _SENTENCE.split(notes):
        s = re.sub(r"\s+", " ", s).strip()
        if re.search(r"\bevolv", s, re.IGNORECASE) and not re.search(r"weirder|moves are", s, re.IGNORECASE):
            return s
    return None


def evolution_method(sentence: str) -> str:
    """"OPTIONALLY evolves at level 30+ ONLY if taught "Draco Energy."" ->
    "Lv. 30+, knows Draco Energy (optional)". Unrecognised sentences stay as written."""
    level = re.search(r"\blevel (\d+)(\+?)", sentence, re.IGNORECASE)
    energy = re.search(r"(?:taught|teach) (?:the evolution (?:energy )?move|one of)?\s*"
                       r"[\"\u201c\u201d']?([\w ,]*?Energy)", sentence, re.IGNORECASE)
    if not level and not energy:
        return re.sub(r"\s*\(No battle.*$|\s*Click here.*$", "", sentence).strip()
    parts = []
    if level:
        parts.append(f"Lv. {level[1]}{level[2]}")
    if energy:
        parts.append(f"knows {energy[1].strip()}")
    elif re.search(r"energy move", sentence, re.IGNORECASE):
        parts.append("knows its Energy move")
    method = ", ".join(parts)
    if re.search(r"\boptional", sentence, re.IGNORECASE):
        method += " (optional)"
    return method


def _evolution_partner(sentence: str, direction: str) -> str | None:
    m = re.search(rf"\b{direction}\s+(?:either\s+)?([A-Z][\w'\-]*(?:\s+[A-Z][\w'\-]*)?)",
                  sentence)
    return m[1] if m else None


# ---------------------------------------------------------------------------
# The whole game


class _Tracked(dict):
    """An overrides table that remembers which keys were looked up, so overrides
    the sheet no longer needs are reported."""

    def __init__(self, data: dict) -> None:
        super().__init__(data)
        self.used: set = set()

    def __contains__(self, key: object) -> bool:
        hit = super().__contains__(key)
        if hit:
            self.used.add(key)
        return hit

    def get(self, key, default=None):  # type: ignore[override]
        if super().__contains__(key):
            self.used.add(key)
        return super().get(key, default)

    def unused(self) -> list:
        return sorted(set(self) - self.used)


@dataclass
class ScrambledBuild:
    entries: list[dict]
    abilities: dict[str, dict[str, str]]
    moves: list[dict]
    learnsets: dict[str, dict]
    chains: dict[str, dict]
    art: dict[int, int]  # new entry id -> the id whose artwork it uses
    bosses: list[dict]
    gaps: list[str]


def _clean_notes(text: str) -> str | None:
    paras = [re.sub(r"[ \t]+", " ", p).strip() for p in re.split(r"\n\s*\n|\s{6,}", text)]
    paras = [p for p in paras if p and not p.lower().startswith("click here")]
    return "\n\n".join(paras) or None


BOSS_TABS = ((VANILLA_BOSSES_TAB, "Vanilla"), (REVERSE_BOSSES_TAB, "Reverse"))
_BOSS_LEVEL = re.compile(r"\b(?:Level|Lv\.?)\s*(\d+)")


def _boss_title(header: str) -> tuple[str, int]:
    """"3rd Gym Leader Iono - Level 27  (Vanilla Path)" -> ("3rd Gym Leader Iono", 27)."""
    level = int(_BOSS_LEVEL.search(header).group(1))  # type: ignore[union-attr]
    title = re.sub(r"\(\s*(?:Level|Lv\.?)\s*\d+[^)]*\)?", "", header)
    title = _BOSS_LEVEL.sub("", title)
    title = re.sub(r"\((?:Vanilla|Reverse) Path\)", "", title)
    title = re.sub(r"\s+-\s+[A-Z0-9 ]+$", "", title.strip())  # "- ALL 3 HAVE 4X ... HP"
    return re.sub(r"\s+", " ", title).strip(" -"), level


def _boss_move(text: str) -> str:
    """"Lash Out (50 BP)*" -> "Lash Out"."""
    return re.sub(r"\([^)]*\)|\*", "", text).strip()


_BOSS_STATS = ("HP", "Atk", "Def", "Sp. A", "Sp. D", "Spe")


def _boss_stats(line: str) -> list[int | None]:
    """"150 HP | 100 Atk | 120 Def | 100 Sp. A | 100 Sp. D | 1 Spe" -> six numbers,
    None where the line leaves one out (Segin Starmobile has no Speed)."""
    got = {s: int(v) for v, s in re.findall(r"(\d+) (HP|Atk|Def|Sp\. A|Sp\. D|Spe)\b", line)}
    return [got.get(s) for s in _BOSS_STATS]


def _looks_like_move(text: str) -> bool:
    """A short title-case name, not a description like "85 BP | 30% Flinch"."""
    words = text.split()
    return (bool(words) and not re.search(r"[\d|,%:]", text) and len(words) <= 3
            and text[:1].isupper() and not words[0].isupper() and text != "Unchanged")


def read_bosses(doozdex: Path, resolve, ability_id, move_id,
                fixes: dict[str, str | None]) -> tuple[list[dict], list[str]]:
    """Both boss tabs as team presets {name, level, path, team: [{p, a, m}]}. A fight
    the same on both paths has path null. Allies ("Arven's Shellder", Carmine's "Ally"
    fight) are skipped; a fight with more than six foes is split into parts.

    resolve(name, title, types, stats, ability, where) gives a foe's entry id, or None;
    move_id(name) a move's."""
    gaps: list[str] = []
    fights: list[tuple[str, str, int, list[dict]]] = []  # (path, title, level, team)
    for gid, path in BOSS_TABS:
        grid = read_grid(doozdex / f"{gid}.html")
        current: tuple[str, int, list[dict]] | None = None
        for i, row in enumerate(grid):
            filled = [(c, x.text) for c, x in enumerate(row) if x and x.text.strip()]
            if (len(filled) == 1 and filled[0][0] == 0 and len(filled[0][1]) < 120
                    and _BOSS_LEVEL.search(filled[0][1])):
                title, level = _boss_title(filled[0][1])
                if re.search(r"\bAlly$", title):
                    log.debug("scrambled.bosses.ally_fight %s", title)
                    current = None
                    continue
                current = (title, level, [])
                fights.append((path, title, level, current[2]))
                log.debug("scrambled.bosses.fight %s %s lv%d", path, title, level)
                continue
            for c, text in filled:
                if not text.startswith("Ability:") or current is None:
                    continue
                where = f"boss tab {gid} row {i + 1}"
                b = c - 21
                name_row = next((r for r in (i - 1, i - 2, i - 3)
                                 if cell(grid, r, b).text.strip()), i - 2)
                raw = cell(grid, name_row, b).text
                name = re.sub(r"^#\d+\.\s*", "", re.sub(r"\s+", " ", raw)).strip()
                if "'s " in name or "âs " in name:
                    log.debug("scrambled.bosses.ally %s %s", current[0], name)
                    continue
                name = fixes.get(name, name)
                if name is None:
                    continue
                name = re.sub(r"^Titan(?:ic)?\s+", "", name)
                types = [t for k in range(b + 21, b + 42)
                         if (t := cell(grid, name_row, k).text.strip().lower()) in TYPE_ORDER]
                stats_row = next((r for r in range(i + 1, min(i + 20, len(grid)))
                                  if re.match(r"\d+ HP\b", cell(grid, r, b).text)), None)
                if stats_row is None:
                    gaps.append(f"{where}: {current[0]} {name}: no stats line")
                    continue
                ability_raw = text.removeprefix("Ability:")
                pid = resolve(name, current[0], types,
                              _boss_stats(cell(grid, stats_row, b).text), ability_raw, where)
                if pid is None:
                    continue
                got = ability_id(ability_raw, f"{where} {current[0]}")
                # Moves sit in the rows under the stats, between their descriptions,
                # not always on the same rows.
                moves: list[int] = []
                for r in range(stats_row + 1, min(stats_row + 7, len(grid))):
                    for mc in (b, b + 21):
                        mt = re.sub(r"\s+", " ", cell(grid, r, mc).text).strip()
                        mt = fixes.get(mt, mt)
                        if not mt:
                            continue
                        mid = move_id(_boss_move(mt.split("|")[0]))
                        if mid is None:
                            if _looks_like_move(_boss_move(mt)):
                                gaps.append(f"{where}: {current[0]} {name}: unknown move "
                                            f"{mt!r} (add to overrides.json "
                                            "scrambled.boss_fixes)")
                        elif mid not in moves and len(moves) < 4:
                            moves.append(mid)
                if not moves:
                    gaps.append(f"{where}: {current[0]} {name}: no moves")
                current[2].append({"p": pid, **({"a": got[0]} if got else {}), "m": moves})
    # One preset per distinct fight; the path only where the two paths differ.
    teams: dict[str, list[tuple[str, list[dict]]]] = {}
    for path, title, level, team in fights:
        if not team:
            gaps.append(f"{path} path: {title}: no PokÃ©mon")
            continue
        teams.setdefault(f"{title}|{level}", []).append((path, team))
    out: list[dict] = []
    for path, title, level, team in fights:
        variants = teams.get(f"{title}|{level}", [])
        if (path, team) not in variants:
            continue
        same = len(variants) == len(BOSS_TABS) and all(t == team for _, t in variants)
        if same and path != BOSS_TABS[0][1]:
            continue  # already added from the first tab
        parts = [team[k:k + 6] for k in range(0, len(team), 6)]
        for n, part in enumerate(parts, 1):
            suffix = f" ({n}/{len(parts)})" if len(parts) > 1 else ""
            # The id keys the app's frecency, so it's the name's, not the position's.
            key = f"{title}{suffix}|{level}|{None if same else path}"
            out.append({"id": zlib.crc32(key.encode()) % 1_000_000_000,
                        "name": title + suffix, "level": level,
                        "path": None if same else path, "team": part})
    if len({b["id"] for b in out}) != len(out):
        gaps.append("two boss teams share an id; make their names differ")
    log.debug("scrambled.bosses.done presets=%d gaps=%d", len(out), len(gaps))
    return out, gaps


def build_scrambled(db: CsvDb, showdown: dict[int, set[str]], doozdex: Path,
                    overrides: dict) -> ScrambledBuild:
    """The whole romhack from the cached Doozdex. Nothing is guessed: anything the
    sheet says that can't be matched is a gap, fixed via overrides.json "scrambled"."""
    gaps: list[str] = []
    scarlet_moves = build_moves(db, overrides["move_descriptions"], showdown, SCARLET)
    moves, move_names, move_gaps = build_scrambled_moves(db, scarlet_moves, showdown,
                                                         doozdex, overrides)
    gaps += move_gaps
    blocks, block_gaps = read_blocks(doozdex)
    gaps += block_gaps
    fix = overrides.get("scrambled", {})

    tracked = {k: _Tracked(fix.get(k, {}))
               for k in ("entry_names", "new_forms", "ability_names", "learnset_fixes",
                         "boss_fixes", "boss_new_forms")}
    candidates = build_entries(db, SCARLET, keep_lookalikes=True).entries
    by_id: dict[int, Entry] = {e.id: e for e in candidates}
    matcher = EntryMatcher([e.to_json() for e in candidates], tracked["entry_names"])
    new_forms: dict[str, list] = tracked["new_forms"]

    # Abilities: vanilla names, the guide's renames and every "New (Old)" on the tabs.
    van_names = {int(k): v for k, v in db.english_names("ability_names", "ability_id").items()
                 if int(k) < 10000}
    van_by_norm = {norm(v): k for k, v in sorted(van_names.items())}
    guide = read_ability_guide(doozdex, set(van_by_norm))
    known = sorted({*van_names.values(), *guide.renames}, key=len, reverse=True)
    replaces = {norm(k): v for k, v in guide.renames.items()}
    for b in blocks:
        for raw in b.abilities:
            name, old = split_ability(raw, known)
            if old and norm(name) not in van_by_norm:
                replaces.setdefault(norm(name), old)
    ability_fixes: dict[str, str | None] = tracked["ability_names"]

    def ability_id(raw: str, where: str) -> tuple[int, str] | None:
        flat = re.sub(r"\s+", " ", raw).strip()
        if flat in ability_fixes:
            if ability_fixes[flat] is None:
                return None
            flat = ability_fixes[flat]  # type: ignore[assignment]
        name, old = split_ability(flat, known)
        if norm(name) in van_by_norm:
            return van_by_norm[norm(name)], name
        old = replaces.get(norm(name)) or old
        if old and norm(old) in van_by_norm:
            return van_by_norm[norm(old)], name
        gaps.append(f"{where}: unknown ability {flat!r} (add to overrides.json "
                    "scrambled.ability_names)")
        return None

    # Entries.
    entries: list[dict] = []
    art: dict[int, int] = {}
    seen: dict[int, Block] = {}
    block_entry: list[tuple[Block, int]] = []
    hack_names: dict[int, str] = {}  # ability id -> its name in the hack
    stat_sources: dict[str, int] = {}
    contexts: list[str] = []
    for b in blocks:
        new_form = None
        if b.name.startswith(DOOZIAN + " "):
            new_form = (b.name.removeprefix(DOOZIAN + " "), DOOZIAN)
        elif b.name in new_forms:
            new_form = tuple(new_forms[b.name])
        if new_form:
            base = matcher.match(new_form[0], [])
            if base is None:
                gaps.append(f"{b.where}: {b.name}: unknown species {new_form[0]!r}")
                continue
            base_entry = by_id[base["id"]]
            k = sum(1 for e in entries if e["dex"] == base_entry.dex and e["id"] >= DOOZIAN_ID_BASE)
            eid = DOOZIAN_ID_BASE + base_entry.dex * 10 + k
            art[eid] = base_entry.id
            entry = {**base_entry.to_json(), "id": eid, "form": new_form[1],
                     "name": f"{base_entry.species} ({new_form[1]})"}
            log.debug("scrambled.entries.new_form %s -> %d", b.name, eid)
        else:
            found = matcher.match(b.name, matcher.contexts(b.family) + contexts)
            if found is None:
                gaps.append(f"{b.where}: no Pokémon matches {b.name!r} (family "
                            f"{b.family!r}; add to overrides.json scrambled.entry_names)")
                continue
            entry = dict(found)
            contexts = [norm(found["species"])]
        if entry["id"] in seen:
            log.debug("scrambled.entries.listed_twice %s %s and %s", b.name,
                      seen[entry["id"]].where, b.where)
            continue
        seen[entry["id"]] = b
        comp = [v + d for v, d in zip(entry["stats"], b.stat_diffs, strict=True)]
        stats, how = reconcile_stats(comp, b.bars, b.total)
        stat_sources[how] = stat_sources.get(how, 0) + 1
        if how != "changes":
            log.debug("scrambled.entries.stats %s %s %s -> %s (total %s)", b.name, how,
                      comp, stats, b.total)
        if (how != "changes (bars agree, total stale)"
                and b.total_diff is not None and sum(b.stat_diffs) == b.total_diff
                and b.total is not None and sum(entry["stats"]) + b.total_diff != b.total):
            # The sheet is self-consistent but its vanilla isn't ours: wrong form?
            gaps.append(f"{b.where}: {b.name} matched {entry['name']}, whose stats total "
                        f"{sum(entry['stats'])}, but the sheet's vanilla total is "
                        f"{b.total - b.total_diff}")
        if not 1 <= len(b.types) <= 2 or any(t not in TYPE_ORDER for t in b.types):
            gaps.append(f"{b.where}: {b.name}: bad types {b.types}")
            continue
        ability_ids = []
        for raw in b.abilities:
            got = ability_id(raw, f"{b.where} {b.name}")
            if got:
                aid, name = got
                if hack_names.setdefault(aid, name) != name and norm(hack_names[aid]) != norm(name):
                    gaps.append(f"{b.where}: ability {van_names[aid]} is both "
                                f"{hack_names[aid]!r} and {name!r}")
                ability_ids.append(aid)
        if not ability_ids and entries and entries[-1]["dex"] == entry["dex"]:
            log.debug("scrambled.entries.abilities_from_previous_form %s", b.name)
            ability_ids = list(entries[-1]["abilities"])  # e.g. Minior's Core form
        if not ability_ids:
            gaps.append(f"{b.where}: {b.name}: no abilities")
            continue
        entry.update(types=b.types, stats=stats, abilities=list(dict.fromkeys(ability_ids)),
                     hidden=None, notes=_clean_notes(b.notes))
        entries.append(entry)
        block_entry.append((b, entry["id"]))
    kept = {e["id"] for e in entries}

    # Boss teams. A foe the Doozdex doesn't list (the hack left it alone) is added
    # with Scarlet's data; a Starmobile is a new Revavroom form with the sheet's
    # types and the stats of its first fight.
    boss_matcher = EntryMatcher(
        [*entries, *(c.to_json() for c in candidates if c.id not in kept)], {})
    boss_forms: dict[str, list] = tracked["boss_new_forms"]

    def add_entry(entry: dict, why: str) -> None:
        entries.append(entry)
        kept.add(entry["id"])
        for aid in [*entry["abilities"], *([entry["hidden"]] if entry["hidden"] else [])]:
            hack_names.setdefault(aid, van_names[aid])
        log.debug("scrambled.bosses.add_entry %s %s", entry["name"], why)

    def resolve(name: str, title: str, types: list[str], stats: list[int | None],
                ability_raw: str, where: str) -> int | None:
        if name in boss_forms:
            species, form = boss_forms[name]
            known = next((e for e in entries if e["form"] == form), None)
            if known:
                return known["id"]
            base = boss_matcher.match(species, [])
            got = ability_id(ability_raw, where)
            if (base is None or stats.count(None) > 1 or not 1 <= len(types) <= 2
                    or got is None):
                gaps.append(f"{where}: {title}: can't make {name!r} (species, types "
                            f"{types}, stats {stats})")
                return None
            # One stat left out: the species' own (Segin Starmobile's Speed).
            stats = [s if s is not None else b for s, b in zip(stats, base["stats"], strict=True)]
            k = sum(1 for e in entries if e["dex"] == base["dex"] and e["id"] >= DOOZIAN_ID_BASE)
            eid = DOOZIAN_ID_BASE + base["dex"] * 10 + k
            art[eid] = base["id"]
            hack_names.setdefault(got[0], got[1])
            add_entry({**base, "id": eid, "form": form, "name": f"{base['species']} ({form})",
                       "types": types, "stats": stats, "abilities": [got[0]], "hidden": None,
                       "notes": f"Only fought in boss battles ({title}); stats as there."},
                      "boss form")
            return eid
        bare = re.sub(r"\s*\([^)]*\)?", "", name).strip()
        contexts = boss_matcher.contexts(title)
        found = (boss_matcher.match(re.sub(r"[()]", "", name), contexts)
                 or boss_matcher.match(bare, contexts))
        if found is None:
            gaps.append(f"{where}: {title}: no PokÃ©mon matches {name!r} (add to "
                        "overrides.json scrambled.boss_fixes)")
            return None
        if types and found["types"] != types:
            # A bare species name: the form with these types ("Sunflora" with the
            # Doozian Sunflora's typing).
            same = [e for e in entries if e["dex"] == found["dex"] and e["types"] == types]
            if same:
                log.debug("scrambled.bosses.form_by_types %s -> %s", name, same[0]["name"])
                found = same[0]
        if found["id"] not in kept:
            add_entry({**found, "notes": "Not in the Doozdex, so this is Scarlet's data."},
                      "vanilla")
        return found["id"]

    def boss_ability(raw: str, where: str) -> tuple[int, str] | None:
        got = ability_id(raw, where)
        if got:
            hack_names.setdefault(*got)
        return got

    scarlet_by_name = {norm(m["name"]): m for m in scarlet_moves}
    hack_move_ids = {m["id"] for m in moves}

    def boss_move(name: str) -> int | None:
        """A hack move, else a Scarlet one the hack dropped from its guide but a
        boss still uses (Torque moves, Detect), added with Scarlet's data."""
        mid = move_names.get(norm(name))
        if mid is not None:
            return mid
        v = scarlet_by_name.get(norm(name))
        if v is None or v["id"] in hack_move_ids:
            return None  # unknown, or its slot now holds another move
        log.debug("scrambled.bosses.vanilla_move %s", name)
        moves.append({**v, "in_game": True})
        hack_move_ids.add(v["id"])
        move_names[norm(name)] = v["id"]
        return v["id"]

    bosses, boss_gaps = read_bosses(doozdex, resolve, boss_ability, boss_move,
                                    tracked["boss_fixes"])
    gaps += boss_gaps

    # Abilities table: vanilla text, led by the guide's where it has some.
    vanilla_table = build_abilities(
        db, [SimpleNamespace(abilities=sorted(hack_names), hidden=None)], SCARLET)
    abilities = {}
    for aid, name in sorted(hack_names.items()):
        v = vanilla_table[str(aid)]
        text = guide.text.get(name) or guide.text.get(v["name"])
        if norm(name) == norm(v["name"]):
            effect, desc = v["effect"], v["description"]
            if text:
                desc = f"In Scrambled Scarlet:\n{clean_paragraphs(text)}\n\n{desc}"
        elif text:
            effect = clean_paragraphs(text).split("\n")[0]
            desc = f"{clean_paragraphs(text)}\n\nReplaces {v['name']}."
        else:
            effect = f"Replaces {v['name']}: {v['effect']}"
            desc = (f"Replaces {v['name']}; the notes of the Pokémon that have it say what "
                    f"changed.\n\n{v['name']}: {v['description']}")
        abilities[str(aid)] = {"key": v["key"], "name": name, "effect": effect,
                               "description": desc}

    # Learnsets, per family (a block with learnset cells and the blocks after it).
    learnsets: dict[str, dict] = {}
    families: list[tuple[Block, list[Member]]] = []
    for b, eid in block_entry:
        e = next(x for x in entries if x["id"] == eid)
        member = Member(eid, [norm(b.name), norm(e["species"]), norm(e["name"])])
        if b.learnset or not families:
            families.append((b, [member]))
        else:
            families[-1][1].append(member)
    learnset_fixes = tracked["learnset_fixes"]
    for head, members in families:
        sets, ls_gaps = parse_learnset(head.learnset, members, move_names, learnset_fixes,
                                       f"{head.where} {head.name}")
        gaps += ls_gaps
        for eid, s in sets.items():
            learnsets[str(eid)] = {"game": None, **s}

    # Evolutions: vanilla chains among the kept Pokémon, then the sheet's changes.
    vanilla_entries = [by_id[i] for i in sorted(kept) if i in by_id]
    for ve in vanilla_entries:
        ve.forms = [i for i in ve.forms if i in kept]
    chains_v, chain_gaps = build_chains(db, vanilla_entries, overrides["methods"], SCARLET)
    gaps += chain_gaps
    chain_of = {e["id"]: e["chain"] for e in entries}
    edges: dict[tuple[int, int], str] = {}
    for c in chains_v.values():
        for ed in c["edges"]:
            edges[(ed["from"], ed["to"])] = ed["method"]
    order = {e["id"]: i for i, e in enumerate(entries)}
    by_name: dict[str, list[int]] = {}
    for e in entries:
        for n in {norm(e["species"]), norm(e["name"])}:
            by_name.setdefault(n, []).append(e["id"])

    def named(name: str, near: int) -> int | None:
        """The kept entry called `name`, preferring one listed close to `near`."""
        ids = by_name.get(norm(name)) or by_name.get(norm(name.split()[0]))
        return min(ids, key=lambda i: abs(order[i] - order[near])) if ids else None

    from_sheet: dict[tuple[int, int], str] = {}
    for idx, (b, eid) in enumerate(block_entry):
        s = evolution_sentence(b.notes)
        if not s:
            continue
        method = evolution_method(s)
        pairs: list[tuple[int, int]] = []
        if (src := _evolution_partner(s, "from")) and (sid := named(src, eid)):
            pairs = [(sid, eid)]
        elif (dst := _evolution_partner(s, "into")) and (did := named(dst, eid)):
            pairs = [(eid, did)]
        elif re.match(r"evolves when taught", s, re.IGNORECASE):
            # "Evolves when taught Fire Energy" on Vivillon's Sunny Form: into this one,
            # from the last other species listed before it in the family.
            dex = next(x["dex"] for x in entries if x["id"] == eid)
            prev = [p for p, pid in block_entry[:idx] if p.family == b.family
                    and next(x["dex"] for x in entries if x["id"] == pid) != dex]
            if prev:
                pairs = [(next(pid for p, pid in block_entry if p is prev[-1]), eid)]
        else:
            pairs = [p for p in edges if p[0] == eid]
            nxt = block_entry[idx + 1][1] if idx + 1 < len(block_entry) else None
            if not pairs and nxt is not None and b.family and block_entry[idx + 1][0].family == b.family:
                pairs = [(eid, nxt)]
        if not pairs:
            log.debug("scrambled.evolutions.no_edge %s %r", b.name, s)
            continue
        for p in pairs:
            if p in from_sheet and len(from_sheet[p]) >= len(method):
                continue  # both ends' notes describe it; keep the fuller one
            if p in edges and method == s and re.search(r"\beither\b|\bOR\b", s):
                continue  # "Can evolve into either X OR Y" adds no method
            edges[p] = from_sheet[p] = method
            a, z = chain_of[p[0]], chain_of[p[1]]
            if a != z:  # a new evolution joins two vanilla chains
                log.debug("scrambled.evolutions.join %s %s", p, s)
                for e in entries:
                    if chain_of[e["id"]] == z:
                        chain_of[e["id"]] = a
    chains: dict[int, dict] = {}
    for (frm, to), method in edges.items():
        if frm in kept and to in kept:
            chains.setdefault(chain_of[frm], {"roots": [], "edges": []})["edges"].append(
                {"from": frm, "to": to, "method": method})
    for c in chains.values():
        targets = {e["to"] for e in c["edges"]}
        c["roots"] = sorted({e["from"] for e in c["edges"]} - targets, key=order.__getitem__)
        c["edges"].sort(key=lambda e: (order[e["from"]], order[e["to"]]))
        if not c["roots"]:
            gaps.append(f"evolution cycle in chain {c['edges']}")
    for name, table in tracked.items():
        for key in table.unused():
            gaps.append(f"overrides.json scrambled.{name}[{key!r}] matches nothing; remove it")
    by_species: dict[int, list[int]] = {}
    for e in entries:
        e["chain"] = chain_of[e["id"]]
        by_species.setdefault(e["dex"], []).append(e["id"])
    for e in entries:
        e["forms"] = sorted(by_species[e["dex"]], key=lambda i: (i != e["dex"], i))
    entries.sort(key=lambda e: (e["dex"], e["id"] != e["dex"], e["id"]))
    moves.sort(key=lambda m: m["name"])  # bosses may have added Scarlet moves
    log.debug("scrambled.build.done entries=%d moves=%d chains=%d gaps=%d stats=%s",
              len(entries), len(moves), len(chains), len(gaps), stat_sources)
    print(f"Scrambled Scarlet stats from: {stat_sources}")
    return ScrambledBuild(entries, abilities, moves, learnsets,
                          {str(k): v for k, v in sorted(chains.items())}, art, bosses, gaps)
