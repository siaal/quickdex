"""Build QuickDex's bundled data from PokéAPI dumps. Usage: make data"""
import argparse
import json
import logging
import sys
from pathlib import Path
from types import SimpleNamespace

from quickdex_data.abilities import build_abilities
from quickdex_data.art import convert_art, copy_type_icons, draw_unknown_type_icon
from quickdex_data.csvdb import CsvDb
from quickdex_data.doozdex import ensure_doozdex
from quickdex_data.entries import Entry, build_entries
from quickdex_data.evolutions import build_chains
from quickdex_data.games import GAMES, SCARLET, Game
from quickdex_data.items import build_items, convert_item_sprites, load_showdown_item_text
from quickdex_data.moves import build_learnsets, build_moves, load_showdown
from quickdex_data.scrambled import build_scrambled
from quickdex_data.scrambled_items import apply_scrambled_items
from quickdex_data.sources import (
    ensure_pkhex,
    ensure_showdown_item_text,
    ensure_showdown_moves,
    ensure_sources,
)
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


def game_meta(game: Game) -> dict:
    return {"key": game.key, "name": game.name, "gen": game.generation}


def build_scrambled_game(db: CsvDb, game: Game, overrides: dict,
                         showdown: dict[int, set[str]], doozdex: Path, out: Path,
                         items: list[dict]) -> tuple[list[SimpleNamespace], list[str]]:
    """Like build_game, for the Doozdex romhack. Its new forms use their base
    species' artwork; `items` are Scarlet's, which get the hack's changes."""
    s = build_scrambled(db, showdown, doozdex, overrides)
    order, chart = build_chart(db, game)
    print(f"\n== {game.name}")
    art = [SimpleNamespace(id=e["id"], name=e["name"]) for e in s.entries]
    overrides["art"].update({str(k): v for k, v in s.art.items()})
    gaps = s.gaps + apply_scrambled_items(items, doozdex, overrides.get("scrambled", {}))
    if gaps:
        return art, gaps
    meta = game_meta(game)
    _write_json(out / game.key / "pokedex.json",
                {"game": meta, "entries": s.entries, "chains": s.chains,
                 "abilities": s.abilities, "bosses": s.bosses})
    _write_json(out / game.key / "types.json", {"order": order, "chart": chart})
    _write_json(out / game.key / "moves.json",
                {"game": meta, "moves": s.moves, "learnsets": s.learnsets})
    _write_json(out / game.key / "items.json", {"game": meta, "items": items})
    print(f"{game.name}: {len(s.entries)} entries, {len(s.chains)} chains, "
          f"{len(s.moves)} moves, {len(order)} types, {len(s.bosses)} boss teams, "
          f"{len(items)} items ({sum('badges' in i for i in items)} in shops, "
          f"{sum('note' in i for i in items)} changed)")
    return art, []


def build_game(db: CsvDb, game: Game, overrides: dict, showdown: dict[int, set[str]],
               out: Path, items: list[dict]) -> tuple[list[Entry], list[str]]:
    """Write `out/<game>/{pokedex,types,moves,items}.json`; returns the entries (for
    art) and any gaps. Nothing is written if there are gaps."""
    build = build_entries(db, game)
    order, chart = build_chart(db, game)
    abilities = build_abilities(db, build.entries, game)
    moves = build_moves(db, overrides["move_descriptions"], showdown, game)
    learnsets = build_learnsets(db, [e.id for e in build.entries], {m["id"] for m in moves},
                                game)
    chains, gaps = build_chains(db, build.entries, overrides["methods"], game)
    print(f"\n== {game.name}\nKept alternate forms:")
    for e in build.entries:
        if e.id != e.dex:
            print(f"  {e.id:>6}  {e.name}  [{'/'.join(e.types)}]")
    print("Dropped forms:")
    for ident, reason in build.dropped:
        print(f"  {ident}  ({reason})")
    if gaps:
        return build.entries, gaps
    meta = game_meta(game)
    _write_json(out / game.key / "pokedex.json",
                {"game": meta, "entries": [e.to_json() for e in build.entries],
                 "chains": chains, "abilities": abilities})
    _write_json(out / game.key / "types.json", {"order": order, "chart": chart})
    _write_json(out / game.key / "moves.json",
                {"game": meta, "moves": moves, "learnsets": learnsets})
    _write_json(out / game.key / "items.json", {"game": meta, "items": items})
    print(f"{game.name}: {len(build.entries)} entries, {len(chains)} chains, "
          f"{len(moves)} moves, {len(order)} types, {len(items)} items")
    return build.entries, []


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", type=Path, default=ROOT / ".cache")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.WARNING,
                        format="%(name)s %(message)s")

    csv_dir, art_dir, icon_dir, item_sprite_dir = ensure_sources(args.cache)
    db = CsvDb(csv_dir)
    overrides = json.loads((ROOT / "tool" / "overrides.json").read_text())
    showdown = load_showdown(ensure_showdown_moves(args.cache))
    item_text = load_showdown_item_text(ensure_showdown_item_text(args.cache))
    pkhex = ensure_pkhex(args.cache)
    data = ROOT / "assets" / "data"
    gaps: list[str] = []
    art_entries: dict[int, Entry | SimpleNamespace] = {}
    all_items: dict[int, dict] = {}
    for game in GAMES:
        # The romhack's bag is Scarlet's, with its changes added.
        items = build_items(db, SCARLET if game.doozdex else game, pkhex, item_text,
                            item_sprite_dir)
        all_items.update((i["id"], i) for i in items)
        if game.doozdex:
            entries, game_gaps = build_scrambled_game(
                db, game, overrides, showdown, ensure_doozdex(args.cache), data, items)
        else:
            entries, game_gaps = build_game(db, game, overrides, showdown, data, items)
        gaps += [f"{game.name}: {g}" for g in game_gaps]
        art_entries.update((e.id, e) for e in entries)
    convert_item_sprites(sorted(all_items.values(), key=lambda i: i["id"]),
                         item_sprite_dir, ROOT / "assets" / "art" / "items")
    gaps += convert_art(sorted(art_entries.values(), key=lambda e: e.id), art_dir,
                        ROOT / "assets" / "art", overrides["art"])
    type_idents = {r["id"]: r["identifier"] for r in db.rows("types", ("id", "identifier"))
                   if r["identifier"] in TYPE_ORDER}
    gaps += copy_type_icons(type_idents, icon_dir, ROOT / "assets" / "art" / "types")
    draw_unknown_type_icon(ROOT / "assets" / "art" / "types")
    code = check_gaps(gaps)
    if code:
        return code
    _write_json(data / "games.json", [game_meta(g) for g in GAMES])
    print(f"\ndata {_dir_size(ROOT / 'assets' / 'data') / 1e6:.2f} MB, "
          f"full art {_dir_size(ROOT / 'assets' / 'art' / 'full') / 1e6:.2f} MB, "
          f"thumbs {_dir_size(ROOT / 'assets' / 'art' / 'thumb') / 1e6:.2f} MB, "
          f"items {_dir_size(ROOT / 'assets' / 'art' / 'items') / 1e6:.2f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
