"""Build QuickDex's bundled data from PokéAPI dumps. Usage: make data"""
import argparse
import json
import logging
import sys
from pathlib import Path

from quickdex_data.abilities import build_abilities
from quickdex_data.art import convert_art, copy_type_icons
from quickdex_data.csvdb import CsvDb
from quickdex_data.entries import build_entries
from quickdex_data.evolutions import build_chains
from quickdex_data.moves import build_learnsets, build_moves, load_showdown
from quickdex_data.sources import ensure_showdown_moves, ensure_sources
from quickdex_data.typechart import TYPE_ORDER, build_chart

ROOT = Path(__file__).resolve().parent.parent
log = logging.getLogger("quickdex.build")


def check_gaps(gaps: list[str]) -> int:
    if not gaps:
        return 0
    print(f"\n{len(gaps)} gap(s); fix via tool/overrides.json:")
    for g in gaps:
        print(f"  - {g}")
    return 1


def _write_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")),
                    encoding="utf-8")


def _dir_size(path: Path) -> int:
    return sum(p.stat().st_size for p in path.rglob("*") if p.is_file())


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", type=Path, default=ROOT / ".cache")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.WARNING,
                        format="%(name)s %(message)s")

    csv_dir, art_dir, icon_dir = ensure_sources(args.cache)
    db = CsvDb(csv_dir)
    overrides = json.loads((ROOT / "tool" / "overrides.json").read_text())
    build = build_entries(db)
    chart = build_chart(db)
    abilities = build_abilities(db, build.entries)
    showdown = load_showdown(ensure_showdown_moves(args.cache))
    moves = build_moves(db, overrides["move_descriptions"], showdown)
    learnsets = build_learnsets(db, [e.id for e in build.entries], {m["id"] for m in moves})
    chains, evo_gaps = build_chains(db, build.entries, overrides["methods"])
    art_gaps = convert_art(build.entries, art_dir, ROOT / "assets" / "art", overrides["art"])
    type_idents = {r["id"]: r["identifier"] for r in db.rows("types", ("id", "identifier"))
                   if r["identifier"] in TYPE_ORDER}
    art_gaps += copy_type_icons(type_idents, icon_dir, ROOT / "assets" / "art" / "types")

    print("Kept alternate forms:")
    for e in build.entries:
        if e.id != e.dex:
            print(f"  {e.id:>6}  {e.name}  [{'/'.join(e.types)}]")
    print("Dropped forms:")
    for ident, reason in build.dropped:
        print(f"  {ident}  ({reason})")

    code = check_gaps(evo_gaps + art_gaps)
    if code:
        return code
    _write_json(ROOT / "assets" / "data" / "pokedex.json",
                {"entries": [e.to_json() for e in build.entries], "chains": chains,
                 "abilities": abilities})
    _write_json(ROOT / "assets" / "data" / "types.json", {"order": TYPE_ORDER, "chart": chart})
    _write_json(ROOT / "assets" / "data" / "moves.json", {"moves": moves, "learnsets": learnsets})
    print(f"\n{len(build.entries)} entries, {len(chains)} chains, {len(moves)} moves")
    print(f"data {_dir_size(ROOT / 'assets' / 'data') / 1e6:.2f} MB, "
          f"full art {_dir_size(ROOT / 'assets' / 'art' / 'full') / 1e6:.2f} MB, "
          f"thumbs {_dir_size(ROOT / 'assets' / 'art' / 'thumb') / 1e6:.2f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
