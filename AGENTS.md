# QuickDex: agent notes

- Flutter is pinned with fvm (`.fvmrc`, 3.41.8). Always run `fvm flutter …`. CI
  (`.github/workflows/release.yml`) reads the same version from `.fvmrc`.
- Platforms: Android (primary), plus Linux and Windows builds for CI releases (desktop
  windows open phone-sized, 480×900). Never commit `android/key.properties` or any
  keystore; the release key lives in `~/.config/quickdex/` (see README).
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
  an empty query lists visited entries by last visit (`FrecencyScores.lastVisit`);
  a typed one puts frecent first by score. Then match tier (prefix > word prefix >
  substring), then dex
  order. `SearchIndex<T extends Searchable>` runs per kind; the single
  `lib/ui/search_screen.dart` (Pokémon | All | Moves toggle, mode persisted under
  `search.mode`) merges kinds with `mergeHits` (Pokémon win ties; pass `byRecency` for empty queries). One `search-field`;
  move rows are keyed `move-row-<id>` / `move-dismiss-<id>`, Pokémon rows `row-<id>`.
- Moves (`assets/data/moves.json`, `lib/data/moves.dart`) load in the background at
  launch; move results and learnset tables appear once loaded. Move flags and `contact` come
  from Showdown's moves.json (`.cache/showdown/`, downloaded once; delete to refresh), since
  PokéAPI lacks Gen 9 flags; the build cross-checks the two and fails on disagreement.
- Team Planner (`lib/team/`, `lib/ui/team_screen.dart`): `Team` holds six nullable
  `TeamSlot`s (entry id, ability id, ≤4 move ids), saved in shared_preferences under
  `team.v1`; unknown ids are dropped on load. `resolveMember` applies the chosen
  ability's immunity (`abilityImmunities`, shared with `guaranteedGuard`; no ability →
  guaranteed guard only) and takes attack types from damaging moves, falling back to
  STAB. `analyseTeam` gives one `TypeMatchup` row per type.
- Frecency (`lib/frecency/`) stores a decayed `(score, updated)` per id, with a 3-day
  half-life, in shared_preferences under `frecency.v1`. A visit is credited to the
  entry opened from search (on page open), not to forms/evolutions swapped to after.

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
