import logging
import subprocess
from pathlib import Path

log = logging.getLogger("quickdex.sources")

POKEAPI_URL = "https://github.com/PokeAPI/pokeapi.git"
SPRITES_URL = "https://github.com/PokeAPI/sprites.git"
CSV_PATH = "data/v2/csv"
ART_PATH = "sprites/pokemon/other/official-artwork"
TYPE_ICON_PATH = "sprites/types/generation-ix/scarlet-violet/small"


def _git(*args: str) -> None:
    subprocess.run(["git", *args], check=True)


def ensure_sources(cache: Path) -> tuple[Path, Path, Path]:
    """Clone (or update) the two PokéAPI repos into `cache`.

    Returns (csv_dir, art_dir, type_icon_dir).
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

    csv_dir, art_dir = pokeapi / CSV_PATH, sprites / ART_PATH
    icon_dir = sprites / TYPE_ICON_PATH
    assert csv_dir.is_dir(), csv_dir
    assert art_dir.is_dir(), art_dir
    assert icon_dir.is_dir(), icon_dir
    return csv_dir, art_dir, icon_dir
