import pytest
from conftest import ROOT

from quickdex_data.csvdb import SchemaError
from quickdex_data.games import EMERALD, SCARLET
from quickdex_data.moves import build_learnsets, build_moves, load_showdown, machine_label

SHOWDOWN = ROOT / ".cache" / "showdown" / "moves.json"


@pytest.fixture(scope="module")
def showdown():
    if not SHOWDOWN.is_file():
        pytest.fail("Showdown moves missing: run `make data` once to fetch .cache/")
    return load_showdown(SHOWDOWN)


@pytest.fixture(scope="module")
def moves(db, showdown):
    return {m["key"]: m for m in build_moves(db, {}, showdown, SCARLET)}


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
    assert t["in_game"] is True
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
        build_moves(db, {}, partial, SCARLET)


def test_showdown_disagreeing_with_pokeapi_fails(db, showdown):
    lying = {**showdown, 33: set()}  # Tackle without contact
    with pytest.raises(SchemaError, match="tackle"):
        build_moves(db, {}, lying, SCARLET)


def test_not_in_scarlet(moves):
    assert moves["return"]["in_game"] is False
    assert moves["pursuit"]["in_game"] is False
    assert moves["tera-blast"]["in_game"] is True
    for key in ("struggle", "behemoth-blade", "blazing-torque"):
        assert moves[key]["in_game"] is True, key


def test_text_falls_back_to_latest_game(moves):
    assert moves["return"]["text"]  # not in Scarlet, text from an older game
    assert "\n" not in moves["return"]["text"]


def test_missing_long_description_is_null_unless_overridden(db, moves, showdown):
    assert moves["glaive-rush"]["desc"] is None
    fixed = {m["key"]: m
             for m in build_moves(db, {"glaive-rush": "Hand written."}, showdown, SCARLET)}
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
def em_moves(db, showdown):
    return {m["key"]: m for m in build_moves(db, {}, showdown, EMERALD)}


def test_emerald_has_only_gen_1_to_3_moves(em_moves):
    assert len(em_moves) == 354
    assert "aura-sphere" not in em_moves and "tera-blast" not in em_moves
    # In Gen 3 but no Emerald Pokémon learns them (FRLG tutors, GSC Nightmare).
    assert {k for k, m in em_moves.items() if not m["in_game"]} == {
        "nightmare", "blast-burn", "hydro-cannon", "frenzy-plant"}
    assert em_moves["struggle"]["in_game"] is True


def test_emerald_category_follows_type(em_moves):
    assert em_moves["shadow-ball"]["cat"] == "physical"  # Ghost
    assert em_moves["bite"]["cat"] == "special"  # Dark
    assert em_moves["fire-punch"]["cat"] == "special"
    assert em_moves["hypnosis"]["cat"] == "status"


def test_emerald_moves_have_their_gen_3_values_and_text(em_moves):
    t = em_moves["thunderbolt"]
    assert (t["power"], t["acc"], t["pp"]) == (95, 100, 15)  # 90 from Gen 6
    assert t["text"] == "A strong electrical attack that may paralyze the foe."
    assert (em_moves["tackle"]["power"], em_moves["tackle"]["acc"]) == (35, 95)
    assert em_moves["knock-off"]["power"] == 20
    assert em_moves["curse"]["type"] == "unknown"  # the ??? type until Gen 5


def test_emerald_descriptions_lead_with_how_the_effect_differed(em_moves, moves):
    s = em_moves["struggle"]["desc"]
    assert s.startswith("In Emerald:\n\u2022 The user")
    assert "1/2 of the damage dealt" in s.split("\n\n")[0]
    assert not moves["struggle"]["desc"].startswith("In ")


@pytest.fixture(scope="module")
def learnsets(db, built, moves):
    return build_learnsets(db, [e.id for e in built.entries],
                           {m["id"] for m in moves.values()}, SCARLET)


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


def test_emerald_learnsets(db, emerald, em_moves):
    ls = build_learnsets(db, [e.id for e in emerald.entries],
                         {m["id"] for m in em_moves.values()}, EMERALD)
    assert set(ls) == {str(e.id) for e in emerald.entries}
    assert ls["25"]["game"] is None
    assert [26, em_moves["thunderbolt"]["id"]] in ls["25"]["moves"]  # Pikachu Lv. 26
    # FRLG-only Deoxys formes fall back to FireRed/LeafGreen.
    assert ls["10001"]["game"] == "FireRed/LeafGreen"


def test_machine_labels():
    assert machine_label(34, 9) == "TM034"
    assert machine_label(34, 3) == "TM34"
    assert machine_label(105, 3) == "HM05"


def test_scarlet_machines_in_number_order(learnsets, moves):
    pika = learnsets["25"]["machines"]
    assert ["TM126", moves["thunderbolt"]["id"]] in pika
    assert [label for label, _ in pika] == sorted(label for label, _ in pika)
    assert learnsets["63"]["machines"] == []  # Abra: Sword/Shield fallback, no machines


def test_emerald_machines_include_hms(db, emerald, em_moves):
    ls = build_learnsets(db, [e.id for e in emerald.entries],
                         {m["id"] for m in em_moves.values()}, EMERALD)
    pika = ls["25"]["machines"]
    assert ["TM24", em_moves["thunderbolt"]["id"]] in pika
    assert ["HM05", em_moves["flash"]["id"]] in pika
    assert pika[-1][0].startswith("HM")
