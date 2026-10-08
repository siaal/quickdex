from quickdex_data.entries import form_label


def test_no_mega_entries(by_id, built):
    # venusaur-mega, charizard-mega-x, rayquaza-mega, raichu-mega-x
    for mega_id in (10033, 10034, 10079, 10304):
        assert mega_id not in by_id
    reasons = dict(built.dropped)
    assert reasons["venusaur-mega"] == "mega"


def test_no_gigantamax_entries(by_id):
    for gmax_id in (10195, 10199, 10190):  # venusaur-gmax, pikachu-gmax, eternatus-eternamax
        assert gmax_id not in by_id


def test_alolan_raichu_types(by_name):
    assert by_name["Raichu (Alolan)"].types == ["electric", "psychic"]


def test_raichu_forms_are_siblings(by_name):
    raichu, alolan = by_name["Raichu"], by_name["Raichu (Alolan)"]
    assert raichu.forms == [26, 10100]
    assert alolan.forms == [26, 10100]


def test_cosmetic_pikachu_forms_dropped(by_name, by_id):
    assert 10094 not in by_id  # pikachu-original-cap
    assert by_name["Pikachu"].forms == [25]


def test_gen9_typing(by_name):
    assert by_name["Clefairy"].types == ["fairy"]


def test_type_changing_forms_kept(by_name):
    assert by_name["Rotom (Heat)"].types == ["electric", "fire"]
    assert by_name["Tauros (Paldean Combat Breed)"].types == ["fighting"]


def test_ability_only_duplicate_form_dropped(by_name, by_id):
    assert by_name["Zygarde (10%)"].id == 10181
    assert 10118 not in by_id  # zygarde-10-power-construct: same types+stats as 10181


def test_scarlet_regional_dex_numbers(by_id, by_name):
    assert by_name["Sprigatito"].region == ("Paldea", 1)
    assert by_name["Pikachu"].region == ("Paldea", 74)  # Paldea wins over Kitakami
    assert by_name["Dipplin"].region == ("Kitakami", 36)  # DLC-only
    assert by_id[1].region == ("Blueberry", 164)  # Bulbasaur
    assert by_name["Abra"].region is None  # not in Scarlet
    assert by_name["Tauros (Paldean Combat Breed)"].region == ("Paldea", 223)
    assert by_name["Sprigatito"].to_json()["region"] == ["Paldea", 1]


def test_label_overrides(by_id):
    assert by_id[10177].name == "Darmanitan (Galarian)"
    assert by_id[10136].name == "Minior (Core)"


def test_display_names_unique(built):
    names = [e.name for e in built.entries]
    assert len(names) == len(set(names))


def test_every_national_dex_number_present(built):
    defaults = {e.dex for e in built.entries if e.id == e.dex}
    assert defaults == set(range(1, 1026))


def test_stats_shape(by_name):
    assert by_name["Pikachu"].stats == [35, 55, 40, 50, 50, 90]


def test_form_label_rules():
    assert form_label("Alolan Raichu", "Alolan Form", "Raichu") == "Alolan"
    assert form_label("Heat Rotom", "Heat Rotom", "Rotom") == "Heat"
    assert form_label("Paldean Tauros (Combat Breed)", "", "Tauros") == "Paldean Combat Breed"
    assert form_label("Hero Form Palafin", "Hero Form", "Palafin") == "Hero"
    assert form_label("", "", "Pikachu") is None
