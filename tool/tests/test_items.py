"""Items: the parsers on hand-made input, then the real Scarlet/Emerald/Scrambled builds."""
import pytest
from conftest import ROOT

from quickdex_data.csvdb import SchemaError
from quickdex_data.doozdex import Cell
from quickdex_data.games import EMERALD, SCARLET
from quickdex_data.items import (
    build_items,
    clean_effect,
    load_showdown_item_text,
    norm,
    parse_storage,
    read_names,
)
from quickdex_data.scrambled_items import (
    UNOBTAINABLE_NOTE,
    apply_scrambled_items,
    read_changes,
    shop_cells,
)

CACHE = ROOT / ".cache"
PKHEX = CACHE / "pkhex"
SPRITES = CACHE / "sprites" / "sprites" / "items"
DOOZDEX = CACHE / "doozdex"


@pytest.fixture(scope="module")
def showdown():
    path = CACHE / "showdown" / "items.ts"
    if not path.is_file() or not PKHEX.is_dir():
        pytest.fail("item sources missing: run `make data` once to fetch .cache/")
    return load_showdown_item_text(path)


@pytest.fixture(scope="module")
def scarlet(db, showdown):
    return {i["key"]: i for i in build_items(db, SCARLET, PKHEX, showdown, SPRITES)}


@pytest.fixture(scope="module")
def emerald(db, showdown):
    return {i["key"]: i for i in build_items(db, EMERALD, PKHEX, showdown, SPRITES)}


def test_parse_storage_reads_arrays_and_skips_comments():
    text = """
    public static ReadOnlySpan<ushort> Balls =>
    [
        0001, 0002, // 0003,
        0004,
    ];
    internal static ReadOnlySpan<ushort> Unreleased => [005, 044]; // Safari Ball
    """
    assert parse_storage(text) == {"Balls": [1, 2, 4], "Unreleased": [5, 44]}
    with pytest.raises(SchemaError):
        parse_storage("nothing here")


def test_read_names_handles_utf16_and_utf8(tmp_path):
    (tmp_path / "a.txt").write_text("(None)\nPoké Ball", encoding="utf-16")
    (tmp_path / "b.txt").write_bytes("\ufeff(None)\nMaster Ball\n".encode())
    assert read_names(tmp_path / "a.txt") == ["(None)", "Poké Ball"]
    assert read_names(tmp_path / "b.txt") == ["(None)", "Master Ball"]


def test_norm_and_clean_effect():
    assert norm("Poké Ball") == norm("POKé BALL") == "pokeball"
    assert norm("TwistedSpoon") == norm("Twisted Spoon")
    assert clean_effect("Held in battle\n:   Does  X.\n\n    More\nhere.") == \
        "Held in battle: Does X.\n\nMore here."


def test_scarlet_bag_is_real_items_only(scarlet):
    for key in ("leftovers", "booster-energy", "covert-cloak", "poke-ball", "kee-berry"):
        assert key in scarlet, key
    # PokéAPI's Gen 9 table has every old item; Scarlet has none of these.
    for key in ("galactic-key", "normalium-z--held", "gengarite", "mach-bike"):
        assert key not in scarlet, key
    assert not any(k.startswith("tm") and k[2:].isdigit() for k in scarlet), "no TMs"


def test_scarlet_item_text(scarlet):
    lo = scarlet["leftovers"]
    assert (lo["name"], lo["cat"], lo["sprite"]) == ("Leftovers", "Held items", True)
    assert lo["effect"].startswith("Held: Heals the holder by 1/16")
    assert lo["text"].startswith("An item to be held by a Pokémon.")
    # No PokéAPI prose: Showdown's description.
    assert scarlet["booster-energy"]["effect"].startswith("Activates the Protosynthesis")
    # PokéAPI's "Unused" category is dropped, not shown.
    reins = next(i for i in scarlet.values() if i["name"] == "Reins of Unity")
    assert reins["cat"] is None


def test_items_sorted_and_unique(db, showdown):
    items = build_items(db, SCARLET, PKHEX, showdown, SPRITES)
    names = [i["name"] for i in items]
    assert names == sorted(names)
    assert len(names) == len(set(names)), "fusion item pairs show once"
    assert all(i["effect"] or i["text"] for i in items)


def test_emerald_bag_with_emerald_text(emerald):
    for key in ("mach-bike", "safari-ball", "cheri-berry", "leftovers"):
        assert key in emerald, key
    for key in ("booster-energy", "throat-spray", "galactic-key"):
        assert key not in emerald, key
    assert emerald["leftovers"]["text"] == "A hold item that gradually restores HP in battle."


def test_shop_cells_follow_their_heading_columns():
    def at(text, span=2):
        return Cell(text, span=span)
    # As read_grid lays them out: a merged cell, then blanks for the columns it covers.
    grid = [
        [at("0 BADGES: at the start", 26)],
        [Cell(), Cell(), at("Leftovers"), Cell(), at("< a comment", 3)],
        [at("*Prose across the sheet", 26)],
        # 4 BADGES covers columns 3-10, 5 BADGES 14-19.
        [*[Cell()] * 3, at("4 BADGES: (30s)", 8), *[Cell()] * 10, at("5 BADGES: (40s)", 6)],
        # Choice Band 2-3, Focus Sash 11-12 (under neither), Weakness Policy 15-16.
        [Cell(), Cell(), at("Choice Band"), *[Cell()] * 8, at("Focus Sash"), *[Cell()] * 3,
         at("Weakness Policy")],
    ]
    assert shop_cells(grid) == [("Leftovers", 0), ("Choice Band", 4), ("Focus Sash", None),
                                ("Weakness Policy", 5)]


def test_read_changes_headings_and_values():
    rows = ["Intro. Leppa Berries are not obtainable, sadly.",
            "Healing Percentage Increased",
            "Shell Bell 12% > 25% (1/4 Damage Dealt) Big Root 30% > 100%",
            "Buffed To Always Activate",
            "Quick Claw",
            "Custap Berry still has amazing use. Not a buff."]
    notes, unobtainable = read_changes([[Cell(r)] for r in rows],
                                       lambda n: n in ("Quick Claw", "Shell Bell"))
    assert notes == [("Shell Bell", "Healing Percentage Increased: 12% \u2192 25% (1/4 Damage Dealt)"),
                     ("Big Root", "Healing Percentage Increased: 30% \u2192 100%"),
                     ("Quick Claw", "Buffed To Always Activate")]
    assert unobtainable == ["Leppa Berry"]


@pytest.fixture(scope="module")
def overrides():
    import json
    return json.loads((ROOT / "tool" / "overrides.json").read_text())["scrambled"]


def test_scrambled_shop_and_buffs(db, showdown, overrides):
    if not DOOZDEX.is_dir():
        pytest.fail("Doozdex missing: run `make data` once to fetch .cache/")
    items = build_items(db, SCARLET, PKHEX, showdown, SPRITES)
    assert apply_scrambled_items(items, DOOZDEX, overrides) == []
    by = {i["name"]: i for i in items}
    assert by["Leftovers"]["badges"] == 0
    assert by["Choice Band"]["badges"] == 4
    assert by["Throat Spray"]["badges"] == 7
    assert by["Kee Berry"]["badges"] == by["Maranga Berry"]["badges"] == 0
    assert by["Pixie Plate"]["badges"] == 1, "All Arceus Plates"
    assert by["Chilan Berry"]["badges"] == 0, "earliest of its two listings"
    assert by["Zoom Lens"]["note"].endswith("20% \u2192 100%")
    assert by["Leppa Berry"]["note"] == UNOBTAINABLE_NOTE
    assert "badges" not in by["Potion"] and "note" not in by["Potion"]


def test_scrambled_unmatched_and_unused_are_gaps(db, showdown, overrides):
    items = build_items(db, SCARLET, PKHEX, showdown, SPRITES)
    fix = {**overrides, "item_badges": {}, "item_groups": {**overrides["item_groups"],
                                                           "Nothing Like This": ["Potion"]}}
    gaps = apply_scrambled_items(items, DOOZDEX, fix)
    assert any("'Focus Sash' sits under no single badge heading" in g for g in gaps)
    assert any("unused override scrambled.item_groups: 'Nothing Like This'" in g for g in gaps)
