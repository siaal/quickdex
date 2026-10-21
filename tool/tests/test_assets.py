import json

import pytest
from conftest import ROOT
from PIL import Image

from quickdex_data.games import GAMES

DATA = ROOT / "assets" / "data"
ART = ROOT / "assets" / "art"


def _entries(game: str):
    return json.loads((DATA / game / "pokedex.json").read_text())["entries"]


def _all_ids() -> set[int]:
    return {e["id"] for g in GAMES for e in _entries(g.key)}


def test_games_json_lists_every_bundle():
    games = json.loads((DATA / "games.json").read_text())
    assert games == [{"key": g.key, "name": g.name, "gen": g.generation} for g in GAMES]
    assert {p.name for p in DATA.iterdir() if p.is_dir()} == {g.key for g in GAMES}
    for g in GAMES:
        for f in ("pokedex.json", "moves.json", "items.json"):
            meta = json.loads((DATA / g.key / f).read_text())["game"]
            assert meta == {"key": g.key, "name": g.name, "gen": g.generation}


def test_every_entry_has_full_art_at_256():
    for i in _all_ids():
        with Image.open(ART / "full" / f"{i}.webp") as im:
            assert im.size == (256, 256), i


def test_every_entry_has_thumb_at_128():
    for i in _all_ids():
        with Image.open(ART / "thumb" / f"{i}.webp") as im:
            assert im.size == (128, 128), i


def test_no_orphan_art_files():
    ids = {f"{i}.webp" for i in _all_ids()}
    for sub in ("full", "thumb"):
        assert {p.name for p in (ART / sub).glob("*.webp")} == ids


def test_item_sprites_match_items():
    items = [i for g in GAMES
             for i in json.loads((DATA / g.key / "items.json").read_text())["items"]]
    with_sprite = {f"{i['id']}.webp" for i in items if i["sprite"]}
    assert {p.name for p in (ART / "items").glob("*.webp")} == with_sprite
    assert len(with_sprite) > 300


@pytest.mark.parametrize("game,count", [("scarlet", 18), ("emerald", 17)])
def test_types_json_shape(game, count):
    types = json.loads((DATA / game / "types.json").read_text())
    assert len(types["order"]) == count
    assert types["chart"]["electric"]["ground"] == 0


def test_every_type_has_a_scarlet_violet_icon():
    order = json.loads((DATA / "scarlet" / "types.json").read_text())["order"]
    # Plus a drawn one for ??? (Curse's type before Gen 5).
    assert {p.stem for p in (ART / "types").glob("*.png")} == {*order, "unknown"}
    for t in [*order, "unknown"]:
        with Image.open(ART / "types" / f"{t}.png") as im:
            assert im.size == (60, 60), t
