import re
from pathlib import Path

from conftest import ROOT

from quickdex_data.art import convert_art
from quickdex_data.entries import Entry

PIKACHU_PNG = ROOT / ".cache/sprites/sprites/pokemon/other/official-artwork/25.png"


def _entry(eid: int) -> Entry:
    return Entry(id=eid, dex=eid, name=f"E{eid}", species=f"E{eid}", form=None,
                 types=["normal"], stats=[1] * 6, chain=1, forms=[eid])


def test_missing_art_is_a_gap(tmp_path: Path):
    gaps = convert_art([_entry(1)], tmp_path / "src", tmp_path / "out", {})
    assert gaps and "1" in gaps[0]


def test_art_override_is_used(tmp_path: Path):
    src = tmp_path / "src"
    src.mkdir()
    (src / "2.png").write_bytes(PIKACHU_PNG.read_bytes())
    gaps = convert_art([_entry(1)], src, tmp_path / "out", {"1": 2})
    assert gaps == []
    assert (tmp_path / "out/full/1.webp").is_file()
    assert (tmp_path / "out/thumb/1.webp").is_file()


def test_check_gaps_exit_codes(capsys):
    import build_data
    assert build_data.check_gaps([]) == 0
    assert build_data.check_gaps(["artwork missing for 1"]) == 1
    assert "artwork missing for 1" in capsys.readouterr().out


def test_pipeline_never_contacts_bulbapedia():
    for path in (ROOT / "tool").rglob("*.py"):
        if "tests" in path.parts or ".venv" in path.parts:
            continue
        assert not re.search(r"bulbapedia|bulbagarden", path.read_text(), re.IGNORECASE), path
