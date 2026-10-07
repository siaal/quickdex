import pytest

from quickdex_data.moves import build_moves


@pytest.fixture(scope="module")
def moves(db):
    return {m["key"]: m for m in build_moves(db, {})}


def test_battle_only_oddities_included(moves):
    for key in ("struggle", "celebrate", "hold-hands", "happy-hour", "hold-back",
                "blazing-torque", "behemoth-blade", "pika-papow"):
        assert key in moves, key


def test_z_max_and_shadow_moves_excluded(moves):
    for key in ("breakneck-blitz--physical", "catastropika", "10-000-000-volt-thunderbolt",
                "max-flare", "max-guard", "shadow-rush"):
        assert key not in moves, key
    assert not any(k.startswith("max-") for k in moves)


def test_thunderbolt_at_a_glance(moves):
    t = moves["thunderbolt"]
    assert (t["name"], t["type"], t["cat"]) == ("Thunderbolt", "electric", "special")
    assert (t["power"], t["acc"], t["pp"], t["prio"], t["chance"]) == (90, 100, 15, 0, 10)
    assert t["target"] == "Selected Pokémon"
    assert t["flags"] == []
    assert t["sv"] is True
    assert t["text"] == ("The user attacks the target with a strong electric blast. "
                         "This may also leave the target with paralysis.")
    assert t["desc"].startswith("Inflicts regular damage.")
    assert "  " not in t["desc"]


def test_status_move_has_no_power_or_accuracy(moves):
    sd = moves["swords-dance"]
    assert (sd["cat"], sd["power"], sd["acc"]) == ("status", None, None)
    assert sd["flags"] == ["Dance"]


def test_contact_and_other_flags(moves):
    assert moves["tackle"]["flags"] == ["Contact"]
    assert moves["thunder-punch"]["flags"] == ["Contact", "Punch"]


def test_gen9_moves_have_unknown_flags(moves):
    # PokéAPI has no flag rows for Gen 9 moves: unknown, not "no contact".
    assert moves["glaive-rush"]["flags"] is None


def test_not_in_scarlet(moves):
    assert moves["return"]["sv"] is False
    assert moves["pursuit"]["sv"] is False
    assert moves["tera-blast"]["sv"] is True
    for key in ("struggle", "behemoth-blade", "blazing-torque"):
        assert moves[key]["sv"] is True, key


def test_text_falls_back_to_latest_game(moves):
    assert moves["return"]["text"]  # not in Scarlet, text from an older game
    assert "\n" not in moves["return"]["text"]


def test_missing_long_description_is_null_unless_overridden(db):
    plain = {m["key"]: m for m in build_moves(db, {})}
    assert plain["glaive-rush"]["desc"] is None
    fixed = {m["key"]: m for m in build_moves(db, {"glaive-rush": "Hand written."})}
    assert fixed["glaive-rush"]["desc"] == "Hand written."


def test_starmobile_torque_moves_have_no_in_game_text(moves):
    assert moves["blazing-torque"]["text"] is None


def test_revival_blessing_is_not_mistaken_for_a_z_move(moves):
    assert moves["revival-blessing"]["pp"] == 1


def test_target_without_prose_gets_a_label(moves):
    assert moves["revival-blessing"]["target"] == "Fainted party Pokémon"


def test_sorted_by_name_with_unique_ids(db):
    ms = build_moves(db, {})
    assert [m["name"] for m in ms] == sorted(m["name"] for m in ms)
    assert len({m["id"] for m in ms}) == len(ms)
    assert 840 < len(ms) < 860
