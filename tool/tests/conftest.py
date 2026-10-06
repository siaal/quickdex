from pathlib import Path

import pytest

from quickdex_data.csvdb import CsvDb

ROOT = Path(__file__).resolve().parents[2]
CSV_DIR = ROOT / ".cache" / "pokeapi" / "data" / "v2" / "csv"


@pytest.fixture(scope="session")
def db() -> CsvDb:
    if not CSV_DIR.is_dir():
        pytest.fail("PokéAPI CSVs missing: run `make data` once to fetch .cache/")
    return CsvDb(CSV_DIR)
