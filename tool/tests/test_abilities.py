from quickdex_data.abilities import build_abilities


def test_entry_abilities_in_slot_order_with_hidden(by_name):
    bulbasaur = by_name["Bulbasaur"]
    assert bulbasaur.abilities == [65]  # overgrow
    assert bulbasaur.hidden == 34  # chlorophyll


def test_single_ability_has_no_hidden(by_name):
    assert by_name["Gastly"].abilities == [26]  # levitate
    assert by_name["Gastly"].hidden is None


def test_forms_have_their_own_abilities(by_name):
    assert by_name["Ogerpon (Wellspring Mask)"].abilities == [11]  # water-absorb


def test_catch_rate_and_weight(by_name):
    assert by_name["Bulbasaur"].catch_rate == 45
    assert by_name["Bulbasaur"].weight == 69  # hectograms
    assert by_name["Gastly"].catch_rate == 190
    assert by_name["Gastly"].weight == 1


def test_ability_table_covers_every_entry_ability(db, built):
    table = build_abilities(db, built.entries)
    used = {a for e in built.entries for a in [*e.abilities, e.hidden] if a is not None}
    assert set(table) == {str(a) for a in used}
    lev = table["26"]
    assert (lev["key"], lev["name"], lev["effect"]) == ("levitate", "Levitate",
                                                         "Evades Ground moves.")
    assert lev["description"].startswith("This Pokémon is immune to Ground-type moves")
    assert all(v["effect"] and v["name"] and v["description"] for v in table.values())


def test_description_keeps_paragraphs_but_collapses_spaces(db, built):
    lev = build_abilities(db, built.entries)["26"]["description"]
    assert "\n\nThis ability is disabled during Gravity" in lev
    assert "Iron Ball. This ability is not disabled" in lev  # was double-spaced
    assert "  " not in lev
