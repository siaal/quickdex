# QuickDex

Offline, low-latency Pokédex for Android (Gen 9 / Scarlet data):

- **Search:** one search for Pokémon and moves, with a Pokémon | All | Moves toggle
  above the field (the last mode is remembered). Pokémon show their Scarlet in-game dex
  number (Paldea, Kitakami or Blueberry) next to the National one, and either finds them. Live results are ranked by frecency (your team and the current zone float to
  the top). Swipe a recent away to forget it. Each Pokémon page shows artwork, types,
  base stats, type defences (Bulbapedia layout), form switching, level-up moves, and an Evo sheet (or drag from Evo and release on an evolution to
  jump straight to it).
- **Moves** (in Search): every move; each page shows type, category,
  power/accuracy/PP/priority/effect chance, target, whether it makes contact, the in-game
  text and a longer description. Moves not in Scarlet are tagged.
- **Type Chart:** a Focus tab (pick a type, toggle Attacker/Defender) and a full 18×18
  grid with frozen headers, pinch-zoom and row/column highlight.

Everything is bundled. The app has no network permission.

## Commands

| Command | What it does |
|---|---|
| `make data` | Rebuild `assets/` from PokéAPI dumps and Showdown's move flags (cached in `.cache/`) |
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

- `assets/data/pokedex.json`: entries (types, stats, forms, chain id, abilities,
  catch rate, weight), evolution chains, and ability descriptions
- `assets/data/types.json`: the 18×18 chart
- `assets/art/full/<id>.webp` (256px) and `assets/art/thumb/<id>.webp` (128px)
- `assets/art/types/<type>.png`: Scarlet/Violet type icons (60px)

Each entry's defence multipliers are derived from `types.json` when the app loads.
If every ability a Pokémon can have grants an immunity (Gastly's Levitate,
Shedinja's Wonder Guard), the defence table shows it under "Immune to".

If `make data` reports gaps (missing artwork or an evolution method it can't render),
fix them in `tool/overrides.json`.
