# QuickDex

Offline, low-latency Pokédex for Android. It shows one game at a time: Scarlet (Gen 9),
Emerald (Gen 3) or the Scrambled Scarlet romhack, picked from the cog on the Search
screen. Each game has its own types, typings, stats, abilities, moves and evolutions as
they were in that game, and its own team and recents. Scrambled Scarlet's data comes
from its Doozdex sheet: the hack's Pokémon only, with their notes and TMs by badge.


- **Search:** one search for Pokémon and moves, with a Pokémon | All | Moves toggle
  above the field (the last mode is remembered), with the settings cog on its right.
  Pokémon show the game's regional dex number (Scarlet: Paldea, Kitakami or Blueberry;
  Emerald: Hoenn) next to the National one, and either finds them. With nothing typed, the list
  shows what you opened most recently first; once you type, results are ranked by
  frecency (your team and the current zone float to the top). Swipe a recent away to forget it. Each Pokémon page shows artwork, types,
  base stats, type defences (Bulbapedia grouping, each group on a red/green tint) beside what its
  own types hit super-effectively, not very effectively or not at all (tap any type pill to open it in the Type Chart as a
  defender), form switching, level-up moves, and an Evo sheet (or drag from Evo and release on an evolution to
  jump straight to it).
- **Moves** (in Search): every move; each page shows type, category,
  power/accuracy/PP/priority/effect chance, target, whether it makes contact, the in-game
  text and a longer description (for Emerald, led by how the effect differed back then).
  Moves no Pokémon learns in the game are tagged "Not in <game>".
- **Type Chart:** a Focus tab (pick a type, toggle Attacker/Defender;
  long-press or right-click a second type for a dual-type defender or two-type STAB
  coverage; result pills work the same way), a Finder tab (pick one or two types to list every Pokémon
  with them, filter by name, optionally highest evolution only) and a full 18×18 (17×17
  in Emerald)
  grid with frozen headers, pinch-zoom and row/column highlight.
- **Team Planner:** six slots; tap one to pick a Pokémon, its ability and up to four
  moves (level-up moves are suggested; typing searches every move; long-press or
  right-click a move to read what it does; the eye button leaves a move out of the
  matchups without removing it, e.g. a U-turn that doesn't define them). Below, each
  attacking type shows how many members are weak, resist or are immune (the chosen
  ability's immunity counts, e.g. Levitate), and how many hit it super-effectively
  with their damaging moves (or their own types if no moves are picked). A row is red
  when more members lose that matchup than win it, green when more win (each member
  compares what it deals with what it takes, so resisting counts as winning and taking
  2× while dealing 2× is even). Tap a type for
  each member's multipliers; tap a column header to sort by it (again to reverse).
  Long-press or right-click a slot to go straight to the Pokémon chooser, or a type
  pill to open it in the Type Chart as a defender. The team is saved on the device.

On desktop, the mouse back button goes back like a back swipe (but never closes the
app).

Everything is bundled. The app has no network permission.

## Commands

| Command | What it does |
|---|---|
| `make data` | Rebuild `assets/` from PokéAPI dumps, Showdown's move flags and the Doozdex sheet (cached in `.cache/`) |
| `make icon` | Regenerate Android/Windows/Linux app icons from `tool/icon/foreground.svg` (needs rsvg-convert, ImageMagick) |
| `make test` | pytest (`tool/tests`) + `flutter test` |
| `make analyze` | ruff + `flutter analyze` |
| `make run` | Debug build on the connected device (hot reload) |
| `make install` | Release build + `adb install -r` |
| `make perf` | Traced release build; prints startup and per-keystroke timings from logcat |

`make perf` needs the phone awake and unlocked. It reads only QuickDex's own log lines,
and only types while QuickDex is the focused window.

## Releases (CI)

Every push to `main` runs `.github/workflows/release.yml`: `flutter analyze` + `flutter
test`, then builds an Android APK, a Linux x64 tarball and a Windows x64 zip, and publishes
them as GitHub release `v1.0.<run number>`. The Android versionCode is the commit count,
the same as `make install`, so local and CI builds install over each other. (Python data
tests need the PokéAPI cache, so they run locally only.)

Android release signing uses one key for local and CI builds:

- Locally, `android/key.properties` (gitignored) symlinks to
  `~/.config/quickdex/key.properties`, which points at `~/.config/quickdex/release.jks`.
  **Back both up.** Lose the key and installed copies can't be updated without an
  uninstall.
- In CI, it comes from four repository secrets: `ANDROID_KEYSTORE_BASE64`,
  `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. The build fails
  if they're missing rather than shipping a debug-signed APK.

Without `key.properties` outside CI, release builds fall back to the debug key.

## Data

`tool/build_data.py` reads the PokéAPI CSVs and official artwork and writes:

- `assets/data/games.json`: the games (key, name, generation), from
  `tool/quickdex_data/games.py`
- per game, `assets/data/<game>/`:
  - `pokedex.json`: entries (types, stats, forms, chain id, abilities, catch rate,
    weight), evolution chains, and ability descriptions
  - `types.json`: the game's type chart (18×18; 17×17 before Fairy)
  - `moves.json`: moves and level-up learnsets
- `assets/art/full/<id>.webp` (256px) and `assets/art/thumb/<id>.webp` (128px)
- Scrambled Scarlet (`tool/quickdex_data/scrambled.py`): Scarlet's data with the
  Doozdex sheet's changes. The sheet is hand-written, so the build fails on anything
  it can't match; fix those in `tool/overrides.json` under `scrambled`. Its pages are
  cached in `.cache/doozdex/` (delete to refresh). Renamed moves and abilities keep the
  vanilla id/key they replace. Stats are vanilla + the sheet's per-stat changes, unless
  its stat bar picture and its total both say otherwise.
- `assets/art/types/<type>.png`: Scarlet/Violet type icons (60px), plus a drawn grey
  one for ??? (Curse's type in Gen 2–4); shared by all games, like the artwork

Each entry's defence multipliers are derived from `types.json` when the app loads.
If every ability a Pokémon can have grants an immunity (Gastly's Levitate,
Shedinja's Wonder Guard), the defence table shows it under "Immune to".

If `make data` reports gaps (missing artwork or an evolution method it can't render),
fix them in `tool/overrides.json`.
