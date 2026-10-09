import pytest
from conftest import ROOT

from quickdex_data.csvdb import SchemaError
from quickdex_data.moves import build_learnsets, build_moves, load_showdown

SHOWDOWN = ROOT / ".cache" / "showdown" / "moves.json"


@pytest.fixture(scope="module")
def showdown():
    if not SHOWDOWN.is_file():
        pytest.fail("Showdown moves missing: run `make data` once to fetch .cache/")
    return load_showdown(SHOWDOWN)


@pytest.fixture(scope="module")
def moves(db, showdown):
    return {m["key"]: m for m in build_moves(db, {}, showdown)}


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
    assert t["contact"] is False
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
    assert (moves["tackle"]["contact"], moves["tackle"]["flags"]) == (True, [])
    tp = moves["thunder-punch"]
    assert (tp["contact"], tp["flags"]) == (True, ["Punch"])


def test_gen9_moves_have_flags_from_showdown(moves):
    # PokéAPI has no flag rows for Gen 9 moves; Showdown fills them.
    assert moves["glaive-rush"]["contact"] is True
    assert moves["tera-blast"]["contact"] is False
    assert moves["torch-song"]["flags"] == ["Sound"]


def test_every_move_has_contact_and_flags(moves):
    for m in moves.values():
        assert isinstance(m["contact"], bool), m["key"]
        assert isinstance(m["flags"], list), m["key"]


def test_move_missing_from_showdown_fails(db, showdown):
    partial = {n: f for n, f in showdown.items() if n != 33}  # Tackle
    with pytest.raises(SchemaError, match="tackle"):
        build_moves(db, {}, partial)


def test_showdown_disagreeing_with_pokeapi_fails(db, showdown):
    lying = {**showdown, 33: set()}  # Tackle without contact
    with pytest.raises(SchemaError, match="tackle"):
        build_moves(db, {}, lying)


def test_not_in_scarlet(moves):
    assert moves["return"]["sv"] is False
    assert moves["pursuit"]["sv"] is False
    assert moves["tera-blast"]["sv"] is True
    for key in ("struggle", "behemoth-blade", "blazing-torque"):
        assert moves[key]["sv"] is True, key


def test_text_falls_back_to_latest_game(moves):
    assert moves["return"]["text"]  # not in Scarlet, text from an older game
    assert "\n" not in moves["return"]["text"]


def test_missing_long_description_is_null_unless_overridden(db, moves, showdown):
    assert moves["glaive-rush"]["desc"] is None
    fixed = {m["key"]: m
             for m in build_moves(db, {"glaive-rush": "Hand written."}, showdown)}
    assert fixed["glaive-rush"]["desc"] == "Hand written."


def test_starmobile_torque_moves_have_no_in_game_text(moves):
    assert moves["blazing-torque"]["text"] is None


def test_revival_blessing_is_not_mistaken_for_a_z_move(moves):
    assert moves["revival-blessing"]["pp"] == 1


def test_target_without_prose_gets_a_label(moves):
    assert moves["revival-blessing"]["target"] == "Fainted party Pokémon"


def test_sorted_by_name_with_unique_ids(moves):
    ms = sorted(moves.values(), key=lambda m: m["name"])
    assert [m["name"] for m in ms] == sorted(m["name"] for m in ms)
    assert len({m["id"] for m in ms}) == len(ms)
    assert 840 < len(ms) < 860


@pytest.fixture(scope="module")
def learnsets(db, built, moves):
    return build_learnsets(db, [e.id for e in built.entries],
                           {m["id"] for m in moves.values()})


def test_every_entry_has_a_learnset(learnsets, built):
    assert set(learnsets) == {str(e.id) for e in built.entries}
    assert all(ls["moves"] for ls in learnsets.values())


def test_scarlet_learnset_is_unlabelled_and_in_level_order(learnsets, moves):
    pika = learnsets["25"]
    assert pika["game"] is None
    levels = [lv for lv, _ in pika["moves"]]
    assert levels == sorted(levels)
    thunderbolt = moves["thunderbolt"]["id"]
    assert [36, thunderbolt] in pika["moves"]


def test_evolution_moves_are_level_zero_first(learnsets, moves):
    sylveon = learnsets["700"]["moves"]
    kiss = moves["disarming-voice"]["id"]
    assert sylveon[0] == [0, kiss]


def test_not_in_scarlet_falls_back_to_latest_classic_game(learnsets):
    assert learnsets["63"]["game"] == "Sword/Shield"  # Abra
    assert learnsets["10"]["game"] == "Sword/Shield"  # Caterpie
    games = {ls["game"] for ls in learnsets.values()}
    assert "Legends: Arceus" not in games
