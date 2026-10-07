# QuickDex

Offline, low-latency Pokédex for Android (Gen 9 / Scarlet data):

- **Lookup:** live search ranked by frecency (your team and the current zone float to
  the top). Swipe a recent away to forget it. Each Pokémon page shows artwork, types,
  base stats, type defences (Bulbapedia layout), form switching, and an Evo sheet.
- **Type Chart:** a Focus tab (pick a type, toggle Attacker/Defender) and a full 18×18
  grid with frozen headers, pinch-zoom and row/column highlight.

Everything is bundled. The app has no network permission.

## Commands

| Command | What it does |
|---|---|
| `make data` | Rebuild `assets/` from PokéAPI dumps (clones into `.cache/`) |
| `make test` | pytest (`tool/tests`) + `flutter test` |
| `make analyze` | ruff + `flutter analyze` |
| `make run` | Debug build on the connected device (hot reload) |
| `make install` | Release build + `adb install -r` |
| `make perf` | Traced release build; prints startup and per-keystroke timings from logcat |

`make perf` needs the phone awake and unlocked. It reads only QuickDex's own log lines,
and only types while QuickDex is the focused window.

## Data

`tool/build_data.py` reads the PokéAPI CSVs and official artwork and writes:

- `assets/data/pokedex.json`: entries (types, stats, forms, chain id, abilities,
  catch rate, weight), evolution chains, and ability descriptions
- `assets/data/types.json`: the 18×18 chart
- `assets/art/full/<id>.webp` (256px) and `assets/art/thumb/<id>.webp` (128px)

Each entry's defence multipliers are derived from `types.json` when the app loads.
If every ability a Pokémon can have grants an immunity (Gastly's Levitate,
Shedinja's Wonder Guard), the defence table shows it under "Immune to".

If `make data` reports gaps (missing artwork or an evolution method it can't render),
fix them in `tool/overrides.json`.
