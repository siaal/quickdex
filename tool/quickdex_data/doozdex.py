"""Read the Doozdex (Scrambled Scarlet's Google Sheet) htmlview pages into cell grids.

The sheet is hand-written, so everything read from it is matched against known names
and anything unrecognised is reported as a gap rather than guessed at.
"""
import hashlib
import logging
import re
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path

from .sources import download

log = logging.getLogger("quickdex.doozdex")

# Its htmlview pages keep the cell layout and images that the CSV export loses.
SHEET = "https://docs.google.com/spreadsheets/d/1aSg996CVQ6RZwi9LPXVST73kV5lkznPd50rvDNqndqs"

# Tab gids. Only the first five feed the app today; the rest are downloaded so the
# boss/item data is at hand later (.todo/active/scrambled_boss_and_item_data).
MOVES_TAB = "1342442952"
POKEMON_TABS = ("209909734", "1842376258", "1610264723")  # Gens 9-7, 6-4, 3-1
ABILITIES_TAB = "911772807"
TMS_TAB = "1857980463"
VANILLA_BOSSES_TAB = "366088713"
REVERSE_BOSSES_TAB = "748281054"
ITEM_SHOP_TAB = "1348877308"  # Item Locations (Shop Guide)
ITEM_CHANGES_TAB = "1324157418"  # Held Item Buffs/Changes
OTHER_TABS = (
    "1333102210",  # Table of Contents
    VANILLA_BOSSES_TAB,
    REVERSE_BOSSES_TAB,
    "1014285145",  # Egg/Encounter Guide
    ITEM_SHOP_TAB,
    ITEM_CHANGES_TAB,
    "1531307935",  # Type Change Cheat Sheet
    "832607334",  # Level Caps + Boss Locations/Paths
)
ALL_TABS = (MOVES_TAB, *POKEMON_TABS, ABILITIES_TAB, TMS_TAB, *OTHER_TABS)
# Tabs whose images we read: category icons, stat bars.
IMAGE_TABS = (MOVES_TAB, TMS_TAB, *POKEMON_TABS)


def ensure_doozdex(cache: Path) -> Path:
    """Download every tab's htmlview page into `cache/doozdex/<gid>.html` once, with
    the images of IMAGE_TABS (their URLs expire, so they're fetched with the page).
    Delete the directory to refresh."""
    out = cache / "doozdex"
    for gid in ALL_TABS:
        path = out / f"{gid}.html"
        if path.is_file():
            log.debug("doozdex.ensure.cached %s", gid)
            continue
        log.debug("doozdex.ensure.download %s", gid)
        tmp = path.with_suffix(".tmp")
        download(f"{SHEET}/htmlview/sheet?headers=false&gid={gid}", tmp)
        if gid in IMAGE_TABS:
            urls = {image_key(u): u for u in _read_images(read_grid(tmp), gid)}
            todo = [(url, image_path(out, key)) for key, url in sorted(urls.items())
                    if not image_path(out, key).is_file()]
            log.debug("doozdex.ensure.images %s %d new=%d", gid, len(urls), len(todo))
            # In parallel: the signed URLs expire a few minutes after the page loads.
            with ThreadPoolExecutor(16) as pool:
                list(pool.map(lambda t: download(*t), todo))
        tmp.rename(path)
    return out


def _read_images(grid: "list[list[Cell]]", gid: str) -> list[str]:
    """Category icons (column 1 of move rows) or stat bars (beside each HP row)."""
    if gid in POKEMON_TABS:
        return [u for r, row in enumerate(grid)
                if cell(grid, r, 2).flat.startswith("HP") for u in cell(grid, r, 3).imgs]
    return [u for row in grid for u in cell([row], 0, 1).imgs]


def bar_lengths(path: Path) -> tuple[int, list[int]]:
    """(image width, the pixel length of each bar, top to bottom) of a stat bar image.
    A row belongs to a bar if it has coloured pixels; the digits drawn on a bar are
    black, so a row's extent (first to last coloured pixel) is its length."""
    from PIL import Image
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    extents = []
    for y in range(h):
        xs = [x for x in range(w) if (p := px[x, y]) and sum(p) > 120 and max(p) - min(p) > 40]
        extents.append(max(xs) - min(xs) + 1 if xs else 0)
    bars, run = [], []
    for length in [*extents, 0]:
        if length:
            run.append(length)
        elif run:
            if len(run) >= 4:  # thinner runs are anti-aliasing specks
                bars.append(sorted(run)[len(run) // 2])
            run = []
    return w, bars


def image_path(doozdex: Path, url: str) -> Path:
    return doozdex / "img" / (hashlib.sha1(image_key(url).encode()).hexdigest()[:16] + ".png")


@dataclass
class Cell:
    text: str = ""
    imgs: list[str] = field(default_factory=list)
    span: int = 1  # columns the merged cell covers

    @property
    def flat(self) -> str:
        """Text with all whitespace runs collapsed to single spaces."""
        return re.sub(r"\s+", " ", self.text).strip()


class _TableParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.rows: list[list[tuple[Cell, int, int]]] = []
        self.cell: Cell | None = None
        self.parts: list[str] = []
        self.span = (1, 1)
        self.in_body = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        a = dict(attrs)
        if tag == "tbody":
            self.in_body = True
        elif not self.in_body:
            return
        elif tag == "tr":
            self.rows.append([])
        elif tag == "td":
            self.cell, self.parts = Cell(), []
            self.span = (int(a.get("rowspan") or 1), int(a.get("colspan") or 1))
        elif self.cell is not None and tag == "br":
            self.parts.append("\n")
        elif self.cell is not None and tag == "img" and a.get("src"):
            self.cell.imgs.append(a["src"] or "")

    def handle_endtag(self, tag: str) -> None:
        if tag == "td" and self.cell is not None:
            self.cell.text = "".join(self.parts).strip()
            self.rows[-1].append((self.cell, *self.span))
            self.cell = None

    def handle_data(self, data: str) -> None:
        if self.cell is not None:
            self.parts.append(data)


def read_grid(path: Path) -> list[list[Cell]]:
    """The tab's cells by (row, column). A merged cell sits at its top-left position;
    the positions it covers are empty cells."""
    p = _TableParser()
    p.feed(path.read_text(encoding="utf-8"))
    grid: list[list[Cell]] = []
    covered: set[tuple[int, int]] = set()
    for r, row in enumerate(p.rows):
        out: list[Cell] = []
        c = 0
        for cell, rowspan, colspan in row:
            while (r, c) in covered:
                out.append(Cell())
                c += 1
            cell.span = colspan
            out.append(cell)
            covered.update((r + dr, c + dc) for dr in range(rowspan) for dc in range(colspan)
                           if dr or dc)
            c += 1
        grid.append(out)
    log.debug("doozdex.read_grid %s rows=%d", path.name, len(grid))
    return grid


def cell(grid: list[list[Cell]], r: int, c: int) -> Cell:
    row = grid[r]
    return row[c] if c < len(row) else Cell()


def image_key(url: str) -> str:
    """Sheet image URLs differ only in their size suffix between uses."""
    return re.sub(r"=w\d+-h\d+.*$", "", url)
