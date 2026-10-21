"""Items per game: the game's bag (PKHeX's lists), described by PokéAPI, falling back
to Showdown for battle items PokéAPI has no prose for. Items with no description at
all are left out."""
import json
import logging
import re
import subprocess
import unicodedata
from pathlib import Path

from .abilities import clean_paragraphs
from .csvdb import ENGLISH, CsvDb, SchemaError
from .games import Eras, Game
from .moves import game_text

log = logging.getLogger("quickdex.items")


def norm(name: str) -> str:
    """Lowercase letters and digits only, accents dropped: "Poké Ball" -> "pokeball"."""
    plain = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]", "", plain.lower())


_ARRAY = re.compile(r"ReadOnlySpan<ushort>\s+(\w+)\s*=>\s*\[(.*?)\];", re.DOTALL)


def parse_storage(text: str) -> dict[str, list[int]]:
    """PKHeX ItemStorage C#: array name -> item indices."""
    text = re.sub(r"//[^\n]*", "", text)
    out = {name: [int(n) for n in re.findall(r"\d+", body)]
           for name, body in _ARRAY.findall(text)}
    if not out:
        raise SchemaError("no item arrays found in a PKHeX ItemStorage file")
    return out


def read_names(path: Path) -> list[str]:
    """PKHeX item names, one per line by index (UTF-16 for Gen 3, UTF-8 otherwise)."""
    raw = path.read_bytes()
    text = raw.decode("utf-16") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else \
        raw.decode("utf-8-sig")
    return text.splitlines()


_SD_BLOCK = re.compile(r"^\t(\w+): \{\n(.*?)^\t\},", re.DOTALL | re.MULTILINE)
_SD_FIELD = re.compile(r'^\t\t(name|desc|shortDesc): ("(?:[^"\\]|\\.)*"),',
                       re.MULTILINE)


def load_showdown_item_text(path: Path) -> dict[str, str]:
    """Showdown's items.ts as norm(name) -> its current description (desc, else
    shortDesc). Per-generation overrides (nested blocks) are ignored."""
    out: dict[str, str] = {}
    for _, body in _SD_BLOCK.findall(path.read_text(encoding="utf-8")):
        fields = {k: json.loads(v) for k, v in _SD_FIELD.findall(body)}
        text = fields.get("desc") or fields.get("shortDesc")
        if "name" in fields and text:
            out[norm(fields["name"])] = text
    if len(out) < 300:
        raise SchemaError(f"only {len(out)} items read from Showdown's {path.name}")
    return out


def clean_effect(text: str) -> str:
    """PokéAPI prose writes "Held in battle\\n:   Does X." as a definition list."""
    return clean_paragraphs(re.sub(r"\n:\s+", ": ", text))


def bag(game: Game, pkhex: Path) -> list[int]:
    """The game's in-game item indices, in PKHeX list order, without repeats."""
    files: dict[str, dict[str, list[int]]] = {}

    def array(file: str, name: str) -> list[int]:
        if file not in files:
            files[file] = parse_storage((pkhex / file).read_text(encoding="utf-8-sig"))
        if name not in files[file]:
            raise SchemaError(f"{file} has no {name} array")
        return files[file][name]

    excluded = {i for f, a in game.item_exclusions for i in array(f, a)}
    return list(dict.fromkeys(i for f, a in game.item_lists for i in array(f, a)
                              if i not in excluded))


def build_items(db: CsvDb, game: Game, pkhex: Path, showdown: dict[str, str],
                sprites: Path) -> list[dict]:
    """Every item in the game's bag with a description, sorted by name:
    `{id, key, name, cat, effect, text, sprite}`. `id` is PokéAPI's; `cat` its
    category (None for items it files as "Unused"); `effect` is
    PokéAPI's prose (else Showdown's); `text` the in-game text (see `game_text`);
    `sprite` whether `sprites/<key>.png` exists."""
    assert game.item_lists, f"{game.key} has no item lists"
    eras = Eras(db, game)
    rows = {r["id"]: r for r in db.rows("items", ("id", "identifier", "category_id"))}
    names = db.english_names("item_names", "item_id")
    by_name = {norm(n): i for i, n in names.items()}
    by_index = {int(r["game_index"]): r["item_id"]
                for r in db.rows("item_game_indices", ("item_id", "generation_id",
                                                       "game_index"))
                if r["generation_id"] == str(game.generation)}
    categories = db.english_names("item_category_prose", "item_category_id")
    # Some real items (Kee Berry, Gracidea) are filed as "Unused", in the "Other"
    # pocket: no category beats a wrong one.
    unused = {r["id"] for r in db.rows("item_categories", ("id", "identifier"))
              if r["identifier"] == "unused"}

    prose = {r["item_id"]: r for r in db.rows("item_prose", ("item_id", "local_language_id",
                                                             "short_effect", "effect"))
             if r["local_language_id"] == ENGLISH}
    texts = game_text(db, eras, "item_flavor_text", "item_id")
    pk_names = read_names(pkhex / game.item_names)
    out: dict[str, dict] = {}
    for index in bag(game, pkhex):
        pk_name = pk_names[index] if index < len(pk_names) else ""
        # Game indices first: Gen 3 names are old spellings ("TwistedSpoon").
        iid = by_index.get(index) or by_name.get(norm(pk_name))
        if iid is None:
            log.debug("items.build.unmatched %s %d %r", game.key, index, pk_name)
            continue
        if iid in out or any(i["name"] == names[iid] for i in out.values()):
            # Fusion items come in pairs (DNA Splicers merge/split): show one.
            log.debug("items.build.repeat %s %s", game.key, iid)
            continue
        key = rows[iid]["identifier"]
        p = prose.get(iid, {})
        effect = (clean_effect(p["effect"]) if p.get("effect", "").strip()
                  else " ".join(p["short_effect"].split()) if p.get("short_effect", "").strip()
                  else showdown.get(norm(names[iid])))
        text = " ".join(texts[iid].split()) if iid in texts else None
        if effect is None and text is None:
            log.debug("items.build.no_text %s %s", game.key, key)
            continue
        if not p:
            log.debug("items.build.showdown_effect %s %s", game.key, key)
        sprite = (sprites / f"{key}.png").is_file()
        if not sprite:
            log.debug("items.build.no_sprite %s %s", game.key, key)
        out[iid] = {"id": int(iid), "key": key, "name": names[iid],
                    "cat": None if rows[iid]["category_id"] in unused
                    else categories[rows[iid]["category_id"]],
                    "effect": effect,
                    "text": text, "sprite": sprite}
    items = sorted(out.values(), key=lambda i: i["name"])
    log.debug("items.build.done %s %d", game.key, len(items))
    return items


def convert_item_sprites(items: list[dict], src_dir: Path, out_dir: Path) -> None:
    """Lossless WebP of each item's sprite as `out_dir/<id>.webp`; drops stale ones."""
    out_dir.mkdir(parents=True, exist_ok=True)
    wanted: set[str] = set()
    for item in items:
        if not item["sprite"]:
            continue
        src = src_dir / f"{item['key']}.png"
        dst = out_dir / f"{item['id']}.webp"
        wanted.add(dst.name)
        if dst.is_file() and dst.stat().st_mtime >= src.stat().st_mtime:
            continue
        subprocess.run(["cwebp", "-quiet", "-lossless", "-z", "9", str(src), "-o", str(dst)],
                       check=True)
    for stale in out_dir.glob("*.webp"):
        if stale.name not in wanted:
            log.debug("items.sprites.remove_stale %s", stale)
            stale.unlink()
