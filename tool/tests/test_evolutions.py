import json

import pytest
from conftest import ROOT

from quickdex_data.evolutions import build_chains
from quickdex_data.games import EMERALD, SCARLET


@pytest.fixture(scope="session")
def chains(db, built):
    chains, gaps = build_chains(db, built.entries, {}, SCARLET)
    return chains, gaps


def _edges(chains, by_name, name):
    chain = chains[0][str(by_name[name].chain)]
    return {(e["from"], e["to"]): e["method"] for e in chain["edges"]}


def test_eevee_has_eight_evolutions_with_methods(chains, by_name):
    edges = {k: v for k, v in _edges(chains, by_name, "Eevee").items() if k[0] == 133}
    assert len(edges) == 8
    assert all(edges.values())


def test_level_method(chains, by_name):
    assert _edges(chains, by_name, "Bulbasaur")[(1, 2)] == "Lv. 16"


def test_item_and_regional_methods(chains, by_name):
    edges = _edges(chains, by_name, "Pikachu")
    assert edges[(25, 26)] == "Thunder Stone"
    assert "Thunder Stone" in edges[(25, 10100)]
    assert "(in Alola)" in edges[(25, 10100)]


def test_trade_held_item(chains, by_name):
    assert _edges(chains, by_name, "Onix")[(95, 208)] == "Trade w/ Metal Coat"


def test_friendship_time_method(chains, by_name):
    assert _edges(chains, by_name, "Eevee")[(133, 196)] == "Level up, friendship 160+, day"


def test_friendship_is_scarlets_160_even_where_data_says_220(chains, by_name):
    # PokéAPI has 220 (the Gen 2-7 threshold) on Pichu's rows; Gen 8+ uses 160.
    assert _edges(chains, by_name, "Pichu")[(172, 25)] == "Level up, friendship 160+"
    assert "high friendship" not in json.dumps(chains[0])


def test_sylveon_needs_fairy_move_and_friendship(chains, by_name):
    assert (_edges(chains, by_name, "Eevee")[(133, 700)]
            == "Level up, knows a Fairy move, friendship 160+")


def test_toxtricity_lists_natures_per_form(chains, by_name):
    method = _edges(chains, by_name, "Toxel")[(848, 849)]
    amped, low_key = method.split(" / ")
    assert amped.startswith("Lv. 30, Amped Form if Adamant, Brave, Docile, Hardy, ")
    assert amped.endswith("Rash, Sassy")
    assert low_key.startswith("Lv. 30, Low Key Form if Bashful, Bold, Calm, ")
    assert low_key.endswith("Serious, Timid")
    assert "nature-dependent" not in method


def test_time_of_day_has_no_hyphen(chains, by_name):
    assert _edges(chains, by_name, "Ursaring")[(217, 901)] == "Peat Block, full moon"


def test_roots_are_chain_starts(chains, by_name):
    chain = chains[0][str(by_name["Pikachu"].chain)]
    assert chain["roots"] == [172]


def test_non_evolving_species_has_no_chain(chains, by_name):
    assert str(by_name["Tauros"].chain) not in chains[0]


@pytest.fixture(scope="session")
def em_chains(db, emerald):
    return build_chains(db, emerald.entries, {}, EMERALD)


def test_emerald_evolutions_are_gen_3s(em_chains, em_name):
    chains, gaps = em_chains
    assert gaps == []
    eevee = {k: v for k, v in _edges(em_chains, em_name, "Eevee").items() if k[0] == 133}
    assert eevee == {(133, 134): "Water Stone", (133, 135): "Thunder Stone",
                     (133, 136): "Fire Stone",
                     (133, 196): "Level up, friendship 220+, day",
                     (133, 197): "Level up, friendship 220+, night"}
    # No Alolan Raichu (Thunder Stone in Alola) merged into the plain edge.
    assert _edges(em_chains, em_name, "Pikachu")[(25, 26)] == "Thunder Stone"
    assert _edges(em_chains, em_name, "Feebas")[(349, 350)] == "Level up, Beauty 170+"
    # Magneton -> Magnezone is Gen 4: Magneton ends its chain.
    assert {e["to"] for e in chains[str(em_name["Magnemite"].chain)]["edges"]} == {82}


def test_every_method_override_matches_an_edge(chains):
    overrides = json.loads((ROOT / "tool" / "overrides.json").read_text())
    edges = {f"{e['from']}->{e['to']}" for c in chains[0].values() for e in c["edges"]}
    assert set(overrides["methods"]) <= edges


def test_no_unrenderable_methods_after_overrides(db, built):
    overrides = json.loads((ROOT / "tool" / "overrides.json").read_text())
    _, gaps = build_chains(db, built.entries, overrides["methods"], SCARLET)
    assert gaps == []
