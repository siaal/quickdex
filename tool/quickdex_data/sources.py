import logging
import subprocess
import urllib.request
from pathlib import Path

log = logging.getLogger("quickdex.sources")

POKEAPI_URL = "https://github.com/PokeAPI/pokeapi.git"
SPRITES_URL = "https://github.com/PokeAPI/sprites.git"
CSV_PATH = "data/v2/csv"
ART_PATH = "sprites/pokemon/other/official-artwork"
TYPE_ICON_PATH = "sprites/types/generation-ix/scarlet-violet/small"
ITEM_SPRITE_PATH = "sprites/items"
SHOWDOWN_MOVES_URL = "https://play.pokemonshowdown.com/data/moves.json"
# Battle item descriptions, including Gen 8-9 items PokéAPI has no prose for.
SHOWDOWN_ITEM_TEXT_URL = ("https://raw.githubusercontent.com/smogon/pokemon-showdown/"
                          "master/data/text/items.ts")
# PKHeX's per-game bag contents: which items each game really has (PokéAPI's
# item_game_indices lists every item in a generation's internal table).
PKHEX_URL = "https://raw.githubusercontent.com/kwsch/PKHeX/master/PKHeX.Core"
PKHEX_FILES = {
    "ItemStorage9SV.cs": "Items/ItemStorage9SV.cs",
    "ItemStorage3RS.cs": "Items/ItemStorage3RS.cs",
    "ItemStorage3E.cs": "Items/ItemStorage3E.cs",
    "text_Items_en.txt": "Resources/text/items/text_Items_en.txt",
    "text_ItemsG3_en.txt": "Resources/text/items/gen3/text_ItemsG3_en.txt",
}


def _git(*args: str) -> None:
    subprocess.run(["git", *args], check=True)


def ensure_sources(cache: Path) -> tuple[Path, Path, Path, Path]:
    """Clone (or update) the two PokéAPI repos into `cache`.

    Returns (csv_dir, art_dir, type_icon_dir, item_sprite_dir).
    """
    cache.mkdir(parents=True, exist_ok=True)
    pokeapi = cache / "pokeapi"
    sprites = cache / "sprites"

    if (pokeapi / ".git").is_dir():
        log.debug("sources.pokeapi.pull")
        _git("-C", str(pokeapi), "pull", "--quiet", "--ff-only")
    else:
        log.debug("sources.pokeapi.clone")
        _git("clone", "--quiet", "--depth", "1", "--filter=blob:none", "--sparse",
             POKEAPI_URL, str(pokeapi))
        _git("-C", str(pokeapi), "sparse-checkout", "set", CSV_PATH)

    if not (sprites / ".git").is_dir():
        log.debug("sources.sprites.clone")
        _git("clone", "--quiet", "--depth", "1", "--filter=blob:none", "--no-checkout",
             SPRITES_URL, str(sprites))
    if (sprites / ART_PATH).is_dir():
        log.debug("sources.sprites.pull")
        _git("-C", str(sprites), "pull", "--quiet", "--ff-only")
    else:
        log.debug("sources.sprites.checkout")
        _git("-C", str(sprites), "sparse-checkout", "set", "--no-cone", f"/{ART_PATH}/*.png")
        _git("-C", str(sprites), "checkout", "--quiet", "master")
    if not (sprites / TYPE_ICON_PATH).is_dir():
        # Caches cloned before type icons were used only have the artwork path.
        log.debug("sources.sprites.add_type_icons")
        _git("-C", str(sprites), "sparse-checkout", "add", f"/{TYPE_ICON_PATH}/*.png")
    if not (sprites / ITEM_SPRITE_PATH).is_dir():
        log.debug("sources.sprites.add_item_sprites")
        _git("-C", str(sprites), "sparse-checkout", "add", f"/{ITEM_SPRITE_PATH}/*.png")

    csv_dir, art_dir = pokeapi / CSV_PATH, sprites / ART_PATH
    icon_dir, item_dir = sprites / TYPE_ICON_PATH, sprites / ITEM_SPRITE_PATH
    assert csv_dir.is_dir(), csv_dir
    assert art_dir.is_dir(), art_dir
    assert icon_dir.is_dir(), icon_dir
    assert item_dir.is_dir(), item_dir
    return csv_dir, art_dir, icon_dir, item_dir


def download(url: str, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".part")
    # Showdown 403s Python's default User-Agent.
    req = urllib.request.Request(url, headers={"User-Agent": "quickdex-data"})
    with urllib.request.urlopen(req) as resp:
        tmp.write_bytes(resp.read())
    tmp.rename(path)



def ensure_showdown_moves(cache: Path) -> Path:
    """Download Showdown's moves.json into `cache` once; delete it to refresh."""
    path = cache / "showdown" / "moves.json"
    if path.is_file():
        log.debug("sources.showdown.cached")
        return path
    log.debug("sources.showdown.download")
    download(SHOWDOWN_MOVES_URL, path)
    return path


def ensure_showdown_item_text(cache: Path) -> Path:
    """Download Showdown's item text into `cache` once; delete it to refresh."""
    path = cache / "showdown" / "items.ts"
    if path.is_file():
        log.debug("sources.showdown_items.cached")
        return path
    log.debug("sources.showdown_items.download")
    download(SHOWDOWN_ITEM_TEXT_URL, path)
    return path


def ensure_pkhex(cache: Path) -> Path:
    """Download PKHeX's item lists and names into `cache/pkhex` once; delete to refresh."""
    out = cache / "pkhex"
    for name, rel in PKHEX_FILES.items():
        if (out / name).is_file():
            continue
        log.debug("sources.pkhex.download %s", name)
        download(f"{PKHEX_URL}/{rel}", out / name)
    return out
