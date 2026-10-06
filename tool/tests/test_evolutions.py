import json

import pytest
from conftest import ROOT

from quickdex_data.evolutions import build_chains


@pytest.fixture(scope="session")
def chains(db, built):
    chains, gaps = build_chains(db, built.entries, {})
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
    method = _edges(chains, by_name, "Eevee")[(133, 196)]
    assert "high friendship" in method
    assert "day" in method


def test_time_of_day_has_no_hyphen(chains, by_name):
    assert _edges(chains, by_name, "Ursaring")[(217, 901)] == "Peat Block, full moon"


def test_roots_are_chain_starts(chains, by_name):
    chain = chains[0][str(by_name["Pikachu"].chain)]
    assert chain["roots"] == [172]


def test_non_evolving_species_has_no_chain(chains, by_name):
    assert str(by_name["Tauros"].chain) not in chains[0]


def test_every_method_override_matches_an_edge(chains):
    overrides = json.loads((ROOT / "tool" / "overrides.json").read_text())
    edges = {f"{e['from']}->{e['to']}" for c in chains[0].values() for e in c["edges"]}
    assert set(overrides["methods"]) <= edges


def test_no_unrenderable_methods_after_overrides(db, built):
    overrides = json.loads((ROOT / "tool" / "overrides.json").read_text())
    _, gaps = build_chains(db, built.entries, overrides["methods"])
    assert gaps == []
