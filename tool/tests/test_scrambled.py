"""Scrambled Scarlet: the Doozdex parsers on hand-made input, then the real build."""
import json

import pytest
from conftest import ROOT

from quickdex_data.doozdex import Cell
from quickdex_data.moves import load_showdown
from quickdex_data.scrambled import (
    Member,
    _boss_stats,
    _boss_title,
    _looks_like_move,
    _move_row,
    _number,
    build_scrambled,
    evolution_method,
    parse_learnset,
    reconcile_stats,
    split_ability,
)
from quickdex_data.scrambled_items import resolve_boss_items
from quickdex_data.typechart import TYPE_ORDER

DOOZDEX = ROOT / ".cache" / "doozdex"


def row(name, power="40 > 45", acc="Can't Miss", desc="Hits. Contact.", pp="20 PP"):
    return [Cell(name), Cell("", ["https://x/img=w60-h40"]), Cell("Normal"), Cell(power),
            Cell(acc), Cell(desc), Cell(pp), Cell("One Foe")]


def test_move_names_renames_and_tags():
    m = _move_row(row("Poison Sting > Poison Dart      (Mega Launcher)"), "t")
    assert (m.old, m.name, m.tags) == ("Poison Sting", "Poison Dart", ["Mega Launcher"])
    m = _move_row(row("Axe Kick >     High Jump Kick   (Negated by Gravity)"), "t")
    assert (m.old, m.name, m.tags) == ("Axe Kick", "High Jump Kick", ["Gravity"])
    m = _move_row(row("Lunge (Still Exists) > Bug Bomber (Rapid Fire, Bulletproof)"), "t")
    assert (m.old, m.name) == (None, "Bug Bomber"), "a new move beside Lunge"
    m = _move_row(row("Protect (AI Only)        Doubles are few and far between"), "t")
    assert (m.name, m.tags) == ("Protect", ["AI Only"])
    assert _move_row([Cell("Header")], "t") is None


def test_sheet_numbers():
    assert _number("40 > 45", "power") == 45
    assert _number("25*", "power") == 25
    assert _number("90 > 100%", "accuracy") == 100
    assert _number("Can't Miss", "accuracy") is None
    assert _number("---", "power") is None
    assert _number("60-120*", "power") is None
    assert _number("5 PP", "PP") == 5


def test_ability_names():
    known = sorted(["Protean", "Shadow Shield", "Versatility", "Technician", "Brazen"],
                   key=len, reverse=True)
    assert split_ability("Versatility (Protean)", known) == ("Versatility", "Protean")
    assert split_ability("Technician   (Underlined = Boosted)", known) == ("Technician", None)
    assert split_ability("Brazen Drops Stats = Boosted (Bolded)", known) == ("Brazen", None)


def test_evolution_methods():
    assert evolution_method("Now evolves at level 16, not 17.") == "Lv. 16"
    assert (evolution_method('OPTIONALLY evolves at level 30+ ONLY if taught "Draco Energy."')
            == "Lv. 30+, knows Draco Energy (optional)")
    assert evolution_method('Evolves when taught "Fire Energy."') == "knows Fire Energy"
    assert (evolution_method("Evolves if Rage Fist is used 10 times.")
            == "Evolves if Rage Fist is used 10 times.")


def test_stats_follow_bars_only_when_the_total_agrees():
    comp = [75, 55, 75, 45, 75, 35]  # Lechonk: the changes say Sp. Atk 45
    w = 254
    bars = (w, [round(v * w / 156.9) for v in (75, 55, 75, 55, 75, 35)])
    assert reconcile_stats(comp, bars, 370) == ([75, 55, 75, 55, 75, 35], "bars")
    assert reconcile_stats(comp, bars, 999)[0] == comp, "the total disagrees: keep"
    assert reconcile_stats(comp, None, 370)[0] == comp
    agree = (w, [round(v * w / 156.9) for v in comp])
    assert reconcile_stats(comp, agree, 330) == (comp, "changes (bars agree, total stale)")


def test_learnset_cells():
    names = {"tackle": 1, "growl": 2, "slash": 3, "swift": 4, "lowkick": 5, "rest": 6,
             "sleeptalk": 7, "facade": 8}
    members = [Member(10, ["sprig"]), Member(11, ["flora"]), Member(12, ["meow"])]
    cells = ["01. Tackle\n05. Growl\n05. Slash (meow only)\nEv. Swift\n2 Evolution Energy Moves",
             "", "0 BADGES:\nRest & Sleep Talk\nLow Kick**\n**No Sprig\n1 BADGE:\nFacad", "",
             ""]
    out, gaps = parse_learnset(cells, members, names, {"Facad": "Facade"}, "t")
    assert gaps == []
    assert out[10]["moves"] == [[1, 1], [5, 2]], "no Ev. move on the first stage"
    assert out[12]["moves"] == [[0, 4], [1, 1], [5, 2], [5, 3]]
    assert out[11]["moves"] == [[0, 4], [1, 1], [5, 2]]
    assert out[10]["tms"] == [[0, 6], [0, 7], [1, 8]]
    assert out[11]["tms"] == [[0, 5], [0, 6], [0, 7], [1, 8]]
    _, gaps = parse_learnset(["01. Tackle\n03. Nonsense Move"], members, names, {}, "t")
    assert len(gaps) == 1 and "Nonsense Move" in gaps[0]


def test_boss_sheet_text():
    assert _boss_title("3rd Gym Leader Iono - Level 27  (Vanilla Path)") == (
        "3rd Gym Leader Iono", 27)
    assert _boss_title("AI Sada (Level 100, Vanilla Path)") == ("AI Sada", 100)
    assert _boss_title("Titan Loyal 3 - ALL 3 HAVE 4X NORMAL AMOUNT OF HP (Lv 43.") == (
        "Titan Loyal 3", 43)
    assert _boss_stats("150 HP | 100 Atk | 120 Def | 100 Sp. A | 100 Sp. D | -1 Priority") == [
        150, 100, 120, 100, 100, None]
    assert _looks_like_move("Slack Off")
    for desc in ("85 BP | 30% Flinch", "ALWAYS Crits", "Unchanged", "Heals 50%"):
        assert not _looks_like_move(desc), desc


@pytest.fixture(scope="session")
def scrambled(db):
    if not (DOOZDEX / "1342442952.html").is_file():
        pytest.fail("Doozdex missing: run `make data` once to fetch .cache/doozdex")
    overrides = json.loads((ROOT / "tool" / "overrides.json").read_text())
    showdown = load_showdown(ROOT / ".cache" / "showdown" / "moves.json")
    return build_scrambled(db, showdown, DOOZDEX, overrides)


def test_the_sheet_builds_without_gaps(scrambled):
    assert scrambled.gaps == []
    assert len(scrambled.entries) > 700
    assert len({e["id"] for e in scrambled.entries}) == len(scrambled.entries)
    ids = {m["id"] for m in scrambled.moves}
    for ls in scrambled.learnsets.values():
        assert {m for _, m in ls["moves"]} | {m for _, m in ls["tms"]} <= ids


def test_scrambled_entries(scrambled):
    by_name = {e["name"]: e for e in scrambled.entries}
    names = {int(k): a["name"] for k, a in scrambled.abilities.items()}
    meow = by_name["Meowscarada"]
    assert [names[a] for a in meow["abilities"]] == ["Dazzling", "Technician", "Versatility"]
    assert meow["hidden"] is None
    assert by_name["Slakoth (Doozian)"]["id"] >= 20_000
    assert scrambled.art[by_name["Slakoth (Doozian)"]["id"]] == 287
    assert by_name["Palafin (Hero)"]["stats"] != [100, 160, 97, 106, 87, 100]


def test_scrambled_moves(scrambled):
    by_name = {m["name"]: m for m in scrambled.moves}
    assert by_name["Poison Dart"]["id"] == 40, "Poison Sting's slot"
    assert by_name["Divebomb"]["key"] == "high-jump-kick"
    assert by_name["High Jump Kick"]["key"] == "axe-kick"
    assert by_name["Fake Out"]["prio"] == 5
    assert by_name["Fake Out"]["cat"] == "physical"
    assert by_name["Endure"]["cat"] == "status"
    assert "Bug Bomber" in by_name and by_name["Bug Bomber"]["id"] >= 100_000
    assert "Tackle" not in by_name, "not in the hack"


def test_scrambled_bosses(scrambled):
    by_id = {e["id"]: e for e in scrambled.entries}
    moves = {m["id"]: m["name"] for m in scrambled.moves}
    bosses = {(b["name"], b["path"]): b for b in scrambled.bosses}
    assert len({b["id"] for b in scrambled.bosses}) == len(scrambled.bosses)
    assert all(1 <= len(b["team"]) <= 6 for b in scrambled.bosses)
    assert all(m in moves for b in scrambled.bosses for t in b["team"] for m in t["m"])

    def names(key):
        return [by_id[t["p"]]["name"] for t in bosses[key]["team"]]

    assert ("Arven", None) in bosses, "the same on both paths"
    assert "Rotom (Wash)" in names(("6th Gym Leader Iono", "Reverse"))
    assert names(("Titan Klawf", "Vanilla")) == ["Klawf"], "Arven's Shellder is an ally"
    assert not any("Ally" in n for n, _ in bosses)
    magneton = next(e for e in scrambled.entries if e["name"] == "Magneton")
    assert "Scarlet's data" in magneton["notes"], "not in the Doozdex, added for Iono"
    segin = next(e for e in scrambled.entries if e["name"] == "Revavroom (Segin Starmobile)")
    assert segin["types"] == ["dark", "steel"]
    assert scrambled.art[segin["id"]] == 966
    giacomo = bosses[("Star Boss Giacomo", "Vanilla")]["team"][-1]
    assert "Wicked Torque" in [moves[m] for m in giacomo["m"]], "a Scarlet move kept"
    carmine = bosses[("Carmine (Entering Kitakami)", None)]["team"]
    assert [t.get("item") for t in carmine[:3]] == ["Leftovers", "Damp Rock", "Mystic Water"]
    assert len(carmine[0]["m"]) == 3, "the sheet lists only three moves"
    assert all(t["t"] in TYPE_ORDER for b in scrambled.bosses for t in b["team"] if "t" in t)
    geeta = bosses[("Champion Geeta", None)]["team"]
    assert {by_id[t["p"]]["name"]: t.get("t") for t in geeta}["Glimmora"] == "grass"


def test_scrambled_evolutions(scrambled):
    by_name = {e["name"]: e for e in scrambled.entries}
    tusk = by_name["Great Tusk"]
    chain = scrambled.chains[str(tusk["chain"])]
    edge = next(e for e in chain["edges"] if e["to"] == tusk["id"])
    assert edge["from"] == by_name["Donphan"]["id"]
    assert edge["method"] == "Lv. 45+, knows Primal Energy (optional)"


def test_resolve_boss_items():
    items = [{"id": 1, "key": "quick-claw", "name": "Quick Claw"},
             {"id": 2, "key": "leftovers", "name": "Leftovers"}]
    bosses = [{"name": "Boss", "team": [
        {"p": 1, "item": "Quick Claw (Buffed)"}, {"p": 2, "item": "Not an item"},
        {"p": 3}, {"p": 4, "item": "Odd name"}, {"p": 5, "item": "Mystery"}]}]
    gaps = resolve_boss_items(bosses, items, {"Not an item": None, "Odd name": "leftovers",
                                              "Unused": None})
    assert bosses[0]["team"] == [{"p": 1, "i": 1}, {"p": 2}, {"p": 3}, {"p": 4, "i": 2},
                                 {"p": 5}]
    assert len(gaps) == 2
    assert "'Mystery'" in gaps[0] and "unused" in gaps[1]
