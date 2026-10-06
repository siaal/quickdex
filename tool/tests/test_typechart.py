from quickdex_data.typechart import TYPE_ORDER, build_chart, defense_for


def _group(defense):
    out = {}
    for t, m in defense.items():
        out.setdefault(m, set()).add(t)
    return out


def test_chart_is_18_by_18(db):
    chart = build_chart(db)
    assert set(chart) == set(TYPE_ORDER)
    assert all(set(row) == set(TYPE_ORDER) for row in chart.values())


def test_gyarados_takes_4x_electric(db, by_name):
    d = defense_for(by_name["Gyarados"].types, build_chart(db))
    assert d["electric"] == 4
    g = _group(d)
    assert g[2] == {"rock"}
    assert g[0.5] == {"fire", "water", "fighting", "bug", "steel"}
    assert g[0] == {"ground"}


def test_shedinja_profile(db, by_name):
    g = _group(defense_for(by_name["Shedinja"].types, build_chart(db)))
    assert g[2] == {"fire", "flying", "rock", "ghost", "dark"}
    assert g[0] == {"normal", "fighting"}
    assert g[0.5] == {"grass", "ground", "poison", "bug"}
    assert g[1] == {"water", "electric", "ice", "psychic", "dragon", "steel", "fairy"}


def test_defense_keys_follow_type_order(db, by_name):
    assert list(defense_for(["fire"], build_chart(db))) == TYPE_ORDER
