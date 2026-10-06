import pytest

from quickdex_data.csvdb import SchemaError


def test_rows_reads_pokemon(db):
    rows = db.rows("pokemon", ("id", "identifier"))
    assert rows[0]["identifier"] == "bulbasaur"


def test_missing_required_column_raises(db):
    with pytest.raises(SchemaError):
        db.rows("pokemon", ("no_such_column",))


def test_english_names(db):
    names = db.english_names("pokemon_species_names", "pokemon_species_id")
    assert names["122"] == "Mr. Mime"
    assert names["29"] == "Nidoran♀"
