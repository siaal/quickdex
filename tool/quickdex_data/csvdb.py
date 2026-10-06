import csv
import logging
from pathlib import Path

log = logging.getLogger("quickdex.csvdb")

ENGLISH = "9"


class SchemaError(Exception):
    """The PokéAPI CSVs don't have the shape this pipeline expects."""


class CsvDb:
    def __init__(self, csv_dir: Path):
        assert csv_dir.is_dir(), f"missing CSV dir {csv_dir}; run `make data` to fetch sources"
        self._dir = csv_dir
        self._cache: dict[str, list[dict[str, str]]] = {}

    def rows(self, name: str, required: tuple[str, ...] = ()) -> list[dict[str, str]]:
        if name not in self._cache:
            path = self._dir / f"{name}.csv"
            if not path.is_file():
                raise SchemaError(f"missing {path.name}")
            with open(path, newline="", encoding="utf-8") as f:
                self._cache[name] = list(csv.DictReader(f))
            log.debug("csvdb.rows.loaded %s %d", name, len(self._cache[name]))
        rows = self._cache[name]
        missing = [c for c in required if not rows or c not in rows[0]]
        if missing:
            raise SchemaError(f"{name}.csv missing columns {missing}")
        return rows

    def english_names(self, name: str, key_col: str, value_col: str = "name") -> dict[str, str]:
        rows = self.rows(name, (key_col, value_col, "local_language_id"))
        return {r[key_col]: r[value_col] for r in rows if r["local_language_id"] == ENGLISH}
