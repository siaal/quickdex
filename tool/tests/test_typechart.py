from quickdex_data.typechart import TYPE_ORDER, build_chart


def test_chart_is_18_by_18(db):
    chart = build_chart(db)
    assert list(chart) == TYPE_ORDER
    assert all(list(row) == TYPE_ORDER for row in chart.values())


def test_gen9_matchups(db):
    chart = build_chart(db)
    assert chart["electric"]["ground"] == 0
    assert chart["electric"]["water"] == 2
    assert chart["fire"]["water"] == 0.5
    assert chart["dragon"]["fairy"] == 0
    assert chart["steel"]["fairy"] == 2
