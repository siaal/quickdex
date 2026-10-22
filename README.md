# QuickDex

Offline, low-latency Pokédex for Android. It shows one game at a time: Scarlet (Gen 9),
Emerald (Gen 3) or the Scrambled Scarlet romhack, picked from the cog on the Search
screen. Each game has its own types, typings, stats, abilities, moves and evolutions as
they were in that game, and its own team and recents. Scrambled Scarlet's data comes
from its Doozdex sheet: the hack's Pokémon only, with their notes and TMs by badge.


- **Search:** one search for Pokémon, moves and items, with a Pokémon | All | Other toggle
  (Other is moves and items) above the field (the last mode is remembered), with the settings cog on its right.
  Pokémon show the game's regional dex number (Scarlet: Paldea, Kitakami or Blueberry;
  Emerald: Hoenn) next to the National one, and either finds them. With nothing typed, the list
  shows what you opened most recently first; once you type, results are ranked by
  frecency (your team and the current zone float to the top). Swipe a recent away to forget it. Each Pokémon page shows artwork, types,
  base stats, type defences (Bulbapedia grouping, each group on a red/green tint) beside what its
  own types hit super-effectively, not very effectively or not at all, form switching, moves under a Level up | All | TM toggle (All to start in Scrambled Scarlet,
  Level up elsewhere; the pick sticks until restart), and an Evo sheet (or drag from Evo and release on an evolution to
  jump straight to it). Enter selects the first displayed result in Search, the
  Pokémon/move/build/learner lists and Type Finder; with no matches, it does nothing.
  Tapping a type pill anywhere (search rows, Pokémon and move pages, sidedeck, team
  planner, pickers) opens that type in the Type Chart's Focus tab, closing any sheet
  it was in (back, by swipe, button or mouse, returns to where you tapped it, unless
  you've since picked a tab yourself); on the Focus tab itself, pills pick the type there instead.
- **Moves** (in Search): every move; each page shows type, category,
  power/accuracy/PP/priority/effect chance, target, whether it makes contact, the in-game
  text and a longer description (for Emerald, led by how the effect differed back then).
  Power tables (Low Kick, Heavy Slam, Flail, Magnitude...) and ability tables are drawn
  as real tables.
  Moves no Pokémon learns in the game are tagged "Not in <game>". The move's TM/HM
  in this game (or Scrambled's badge TM) sits right-aligned beside its name, and a "Who can learn it?"
  button opening every learner, with a name filter (not focused on open) and a
  Level up | All | TM toggle (All to start; the choice is remembered per game until
  restart and hides the keyboard).
- **Items** (in Search, under Other and All): everything in the game's bag that has a
  description, TMs aside (move pages cover them). Each page shows the sprite, category,
  the in-game text and what it does. In Scrambled Scarlet, battle items show when
  Delibird Presents starts selling them ("Shop: 3 badges", right of the name and on
  the row), and the hack's changes (buffed items, the unobtainable Leppa Berry) sit in
  an "In Scrambled Scarlet" box.
- **Type Chart:** a Focus tab (pick a type to see defence and attack side by side, like the Pokémon page;
  long-press or right-click a second type for dual-type defence and two-type STAB
  coverage; result pills work the same way), a Finder tab (pick one or two types to list every Pokémon
  with them; long-press the only picked type for just that type alone; filter by name, optionally highest evolution only) and a full 18×18 (17×17
  in Emerald)
  grid with frozen headers, pinch-zoom and row/column highlight.
- **Team Planner:** Save and Load on the left of the header, a Mine | Theirs toggle on
  the right: your team, and an opponent's, each with its own saved builds. The
  Sidedeck button between them lists every Pokémon you've added to the team (types
  and moves with type and category, an N/6 squad counter): tap one to put it in or
  take it out of the squad, long-press to edit it, swipe to delete it. The header's
  rightmost + adds a Pokémon; Sort offers Recency (default) or Name, always with
  party members first. Recency puts the most recently benched members first.
  Order is calculated only on entry or a sort selection: toggling or editing never
  moves a row, and new members append until the next sort. Sort choice and bench
  recency survive restarts, separately for each team and game. The header's trash
  icon clears the whole sidedeck (after confirming), back to a blank team. Picking a
  Pokemon that's benched in the Sidedeck (for a slot, a change, or +) brings that
  member back, ability and moves included, instead of adding a duplicate.
  You can select more than six while rearranging, but must bench the extras before
  leaving the sidedeck. If an overfull squad is restored or otherwise reaches the
  planner, an error message shows the count and explains that only the first six
  are shown and included in matchups.
  Removing a Pokémon from a squad slot only benches it, and so does
  changing a slot's Pokemon (the new one is a fresh sidedeck member in that slot; the
  old one keeps its ability and moves); only the trash icon on a benched member or a
  swipe in the Sidedeck deletes. Builds save the whole deck. Save names
  the shown team as a build (it offers the loaded build's name, so one tap overwrites
  it, and lists the side's builds, shown as thumbnails, most recent first, filtered as
  you type; tap one to
  overwrite it instead); Load lists that side's builds most recently used first, typing ranks them like
  search, and a loaded team can be undone from the snackbar; swipe a build away to
  delete it. In Scrambled Scarlet, Theirs can also load every boss team from the
  Doozdex (gyms, rivals, Team Star, Titans, Elite 4, both paths). Theirs opens with
  **Versus**: your team's sprites on the left, theirs on the right; tap one to draw a
  line to each Pokémon opposite, split in half: the half by your Pokémon is how hard
  you hit them, the half by theirs is how hard they hit you (your 2× hits green and
  4× blue, theirs red and 4× purple, neutral grey, resisted faded, immune dashed). Each team has six slots; tap one to
  pick a Pokémon, its ability and up to four
  moves (its learnable moves are suggested under a Level up | All | TM toggle, All to
  start; your choice is remembered for the next move, and changing it hides the
  keyboard; typing searches every move; long-press or
  right-click a move to read what it does; the eye button leaves a move out of the
  matchups without removing it, e.g. a U-turn that doesn't define them). Below, each
  attacking type shows how many members are weak, resist or are immune (the chosen
  ability's immunity counts, e.g. Levitate), and how many hit it super-effectively
  with their damaging moves. Move slots start as "? Unknown", and while any slot is
  unknown the Pokémon also counts its own types (it could still learn STAB); four
  known moves that are all status moves hit nothing. Flying Press counts as Fighting
  and Flying at once (multipliers multiply, whoever uses it), and Revelation Dance as
  the user's first type. A row is red
  when more members lose that matchup than win it, green when more win (each member
  compares what it deals with what it takes, so resisting counts as winning and taking
  2× while dealing 2× is even). Tap a type for
  each member's multipliers; tap a column header to sort by it (again to reverse).
  Long-press or right-click a filled slot to open that Pokemon's page (back returns to
  the planner), or an empty slot to go straight to the Pokémon chooser, or a type
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
  - `moves.json`: moves and learnsets (level-up moves plus TMs/HMs by number)
  - `items.json`: the game's items (`tool/quickdex_data/items.py`). Which items a game
    has comes from PKHeX's bag lists (`.cache/pkhex/`, downloaded once); PokéAPI's
    item table lists every old item in each generation. Text is PokéAPI's, with
    Showdown's `items.ts` (`.cache/showdown/`) for battle items PokéAPI doesn't
    describe; items with no text at all (picnic ingredients, Tera Shards, materials,
    most key items) are left out.
- `assets/art/items/<id>.webp`: item sprites (lossless), shared by all games
- `assets/art/full/<id>.webp` (256px) and `assets/art/thumb/<id>.webp` (128px)
- Scrambled Scarlet (`tool/quickdex_data/scrambled.py`): Scarlet's data with the
  Doozdex sheet's changes. The sheet is hand-written, so the build fails on anything
  it can't match; fix those in `tool/overrides.json` under `scrambled`. Its pages are
  cached in `.cache/doozdex/` (delete to refresh). Renamed moves and abilities keep the
  vanilla id/key they replace. Stats are vanilla + the sheet's per-stat changes, unless
  its stat bar picture and its total both say otherwise. Items are Scarlet's plus the
  Item Locations tab's badge unlocks and the Held Item Buffs tab's changes
  (`scrambled_items.py`); group lines ("All Arceus Plates"), commentary cells and
  items under no single badge heading are spelled out in the overrides.
- `assets/art/types/<type>.png`: Scarlet/Violet type icons (60px), plus a drawn grey
  one for ??? (Curse's type in Gen 2–4); shared by all games, like the artwork

Each entry's defence multipliers are derived from `types.json` when the app loads.
If every ability a Pokémon can have grants an immunity (Gastly's Levitate,
Shedinja's Wonder Guard), the defence table shows it under "Immune to".

If `make data` reports gaps (missing artwork or an evolution method it can't render),
fix them in `tool/overrides.json`.
