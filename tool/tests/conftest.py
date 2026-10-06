from pathlib import Path

import pytest

from quickdex_data.csvdb import CsvDb
from quickdex_data.entries import build_entries

ROOT = Path(__file__).resolve().parents[2]
CSV_DIR = ROOT / ".cache" / "pokeapi" / "data" / "v2" / "csv"


@pytest.fixture(scope="session")
def db() -> CsvDb:
    if not CSV_DIR.is_dir():
        pytest.fail("PokéAPI CSVs missing: run `make data` once to fetch .cache/")
    return CsvDb(CSV_DIR)


@pytest.fixture(scope="session")
def built(db):
    return build_entries(db)


@pytest.fixture(scope="session")
def by_name(built):
    return {e.name: e for e in built.entries}


@pytest.fixture(scope="session")
def by_id(built):
    return {e.id: e for e in built.entries}
