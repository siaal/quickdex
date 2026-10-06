import json

from conftest import ROOT
from PIL import Image

DATA = ROOT / "assets" / "data"
ART = ROOT / "assets" / "art"


def _entries():
    return json.loads((DATA / "pokedex.json").read_text())["entries"]


def test_every_entry_has_full_art_at_256():
    for e in _entries():
        with Image.open(ART / "full" / f"{e['id']}.webp") as im:
            assert im.size == (256, 256), e["id"]


def test_every_entry_has_thumb_at_128():
    for e in _entries():
        with Image.open(ART / "thumb" / f"{e['id']}.webp") as im:
            assert im.size == (128, 128), e["id"]


def test_no_orphan_art_files():
    ids = {f"{e['id']}.webp" for e in _entries()}
    for sub in ("full", "thumb"):
        assert {p.name for p in (ART / sub).glob("*.webp")} == ids


def test_types_json_shape():
    types = json.loads((DATA / "types.json").read_text())
    assert len(types["order"]) == 18
    assert types["chart"]["electric"]["ground"] == 0
