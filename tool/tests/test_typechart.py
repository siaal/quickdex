from quickdex_data.games import EMERALD, SCARLET
from quickdex_data.typechart import TYPE_ORDER, build_chart


def test_chart_is_18_by_18(db):
    order, chart = build_chart(db, SCARLET)
    assert order == TYPE_ORDER
    assert list(chart) == TYPE_ORDER
    assert sorted(TYPE_ORDER) == TYPE_ORDER  # alphabetical, by user choice
    assert all(list(row) == TYPE_ORDER for row in chart.values())


def test_gen9_matchups(db):
    _, chart = build_chart(db, SCARLET)
    assert chart["electric"]["ground"] == 0
    assert chart["electric"]["water"] == 2
    assert chart["fire"]["water"] == 0.5
    assert chart["dragon"]["fairy"] == 0
    assert chart["steel"]["fairy"] == 2
    assert chart["ghost"]["steel"] == 1


def test_gen3_chart_has_no_fairy_and_steel_resists_ghost_and_dark(db):
    order, chart = build_chart(db, EMERALD)
    assert order == [t for t in TYPE_ORDER if t != "fairy"]
    assert all(list(row) == order for row in chart.values())
    assert chart["ghost"]["steel"] == 0.5
    assert chart["dark"]["steel"] == 0.5
    # Gen 1-only rows (Ghost 0x Psychic, Bug 2x Poison) don't reach Gen 3.
    assert chart["ghost"]["psychic"] == 2
    assert chart["bug"]["poison"] == 0.5
