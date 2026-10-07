# QuickDex: agent notes

- Flutter is pinned with fvm (`.fvmrc`, 3.41.8). Always run `fvm flutter …`.
- Python tooling lives in `tool/` as a uv project: `uv run --project tool …`.
- All commands go through the Makefile (`data`, `test`, `analyze`, `run`, `install`, `perf`).

## Architecture

- `tool/quickdex_data/` is the build-time pipeline. It runs in this order:
  `sources` (git clones in `.cache/`) → `entries` (form rule) → `typechart` →
  `evolutions` → `art`. `build_data.py` wires them together, applies
  `tool/overrides.json`, and fails on any gap.
- `assets/` is generated **and committed**. Never hand-edit it; rerun `make data`.
  The output is deterministic, so a rerun with no source changes leaves `git status`
  clean.
- The app parses the JSON once at startup (`lib/data/loader.dart`) into in-memory
  lookup tables. There's no database. Defence maps are **not** in the JSON:
  `Pokedex.parse` derives them from the chart, one shared map per typing. Bundling them
  doubled the JSON and pushed startup past 150 ms.
- Ability immunities (`lib/data/ability_guard.dart`) are game logic, so they live in
  Dart, not the pipeline: a const map of ability key → immune types, plus Wonder
  Guard. An entry gets a guard only if *all* its abilities (hidden included) share the
  immunity and the chart doesn't already make it 0× (so Rotom-Fan gets none).
- Search (`lib/search/`) is synchronous over all entries on every keystroke. Ranking:
  frecent first by score, then match tier (prefix > word prefix > substring), then dex
  order.
- Frecency (`lib/frecency/`) stores a decayed `(score, updated)` per id, with a 3-day
  half-life, in shared_preferences under `frecency.v1`. A visit is credited to the
  entry on screen when the user leaves the Pokémon page.

## Conventions

- Data contract: `pokedex.json` and `types.json` shapes are defined in
  `tool/build_data.py` and `tool/quickdex_data/entries.py` (`Entry.to_json`). The Dart
  side is `lib/data/models.dart`. Change both together.
- The form rule (`entries.py`) drops Mega/G-Max/Primal/Totem/Eternamax/`-starter` forms,
  plus any form whose types and stats match the default or an earlier kept form. For
  example, Zygarde 10% Power Construct is dropped in favour of Zygarde 10%. A few
  awkward labels are fixed in `LABEL_OVERRIDES`.
- Bulbapedia is never contacted (it returns 403 to scripts). Gaps are fixed in
  `tool/overrides.json`. A test fails if an override no longer matches a real edge.
- Tracing: Dart `trace('module.fn.branch', {...})` from `lib/trace.dart`. Release builds
  only emit traces to logcat when built with `--dart-define=QUICKDEX_TRACE=true`.
  Python uses `logging.getLogger("quickdex.*").debug`, shown with `build_data.py -v`.
- Widget tests use the real bundled data via `loadPokedex(rootBundle)`.

## The test device is the owner's personal phone

- Only interact with QuickDex. Never screenshot or screen-record.
- Read logcat by QuickDex's pid only, and never clear the device log.
- Only send `adb shell input` while QuickDex is the focused window (`tool/perf.sh`
  enforces all of this).
- The phone dozes during long release builds. If `perf.sh` reports the screen is off,
  ask the owner to unlock it.
