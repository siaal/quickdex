# QuickDex — Design

**Status:** approved design, pending spec review
**Date:** 2026-10-07

## Purpose

An Android app (Pixel 7, pushed via adb) for **low-latency** Pokémon lookups while
playing Pokémon Scarlet. It is fully offline: all data and artwork are bundled in the APK.
It has two screens: a Pokémon lookup with frecency-ranked live search, and a type matchup chart.

Speed is the main design goal. The user could get this information by hand; the app exists
because it is faster.

## Scope decisions

| Decision | Choice |
|---|---|
| Stack | Flutter, pinned via fvm to 3.41.8, Android only |
| App id / name | `app.quickdex` / QuickDex |
| Data generation | Gen 9 (Scarlet): current values, 18-type chart |
| Pokémon set | Whole National Dex with Gen 9 data |
| Forms | Type/stat-relevant alternate forms included as their own entries; **Mega, Gigantamax, and cosmetic-only forms excluded** |
| Data source | PokéAPI CSV dump + PokéAPI sprites repo only. Gaps are fixed by a committed overrides file. Bulbapedia is never contacted (see "Bulbapedia dropped") |
| Portrait | Official (Sugimori) artwork |
| Runtime data | Bundled JSON parsed once into in-memory lookup tables (no SQLite) |

**Out of scope:** abilities (Levitate, Flash Fire etc. alter matchups), Tera types, moves,
locations/encounters, typo-tolerant fuzzy search, iOS.

## Verified sources

Checked against the live repos on 2026-10-07:

- `PokeAPI/pokeapi` → `data/v2/csv/` (187 files), including `pokemon.csv`,
  `pokemon_forms.csv`, `pokemon_types.csv`, `pokemon_stats.csv`,
  `pokemon_species.csv`, `pokemon_species_names.csv`, `pokemon_form_names.csv`,
  `pokemon_evolution.csv`, `evolution_chains.csv`, `evolution_triggers.csv`,
  `items.csv`, `item_names.csv`, `type_efficacy.csv`, `types.csv`. Current values
  live in the base files; `*_past.csv` hold older-generation values and are ignored.
- `PokeAPI/sprites` (default branch `master`, ~10 GB) →
  `sprites/pokemon/other/official-artwork/<pokemon_id>.png`. Alternate forms use
  ids ≥ 10001.
- Tooling present: `uv`, `cwebp` (`/opt/homebrew/bin`). Pixel 7 density is 420 dpi
  (2.625×).

## Architecture

```
tool/build_data.py ──► assets/data/pokedex.json ─┐
  (PokéAPI CSV +        assets/data/types.json   ├─► Flutter app (bundled assets)
   sprites, cwebp)      assets/art/full/*.webp    │     └─ parsed once at startup
                        assets/art/thumb/*.webp  ─┘        into in-memory LUTs
tool/overrides.json ───► hand-curated fixes for anything the gaps check reports
```

### 1. Data pipeline (`tool/`, Python via uv)

`make data` runs `tool/build_data.py`, which:

1. **Fetches sources into `.cache/` (gitignored).** Shallow clone of `PokeAPI/pokeapi`.
   Blobless partial clone + sparse checkout of only
   `sprites/pokemon/other/official-artwork/` from `PokeAPI/sprites`. If the clones
   already exist it pulls instead.
2. **Joins CSVs** into one entry per kept `pokemon.csv` row. Cosmetic-only forms
   (Vivillon, Unown, …) exist only in `pokemon_forms.csv`, not as `pokemon.csv` rows, so
   they never appear. The rule for a non-default `pokemon.csv` row is:
   - **Drop** it if its form has `is_mega=1`, or if its identifier contains `-mega`, `-gmax`,
     `-primal`, `-totem` or `-eternamax`, or ends with `-starter`.
   - **Drop** it if its types *and* base stats both equal the species' default row. This
     removes Pikachu caps, ride modes, Rockruff Own Tempo, and similar.
   - **Keep** everything else. That includes battle-only forms that change type/stats
     (Zen Mode, Aegislash Blade); the user reviews the printed kept/dropped list once.
   Each entry holds:
   - `id` (PokéAPI pokemon id), `dex` (species national dex #)
   - `name` (display, e.g. `Raichu`, `Raichu (Alolan)`), `form` label (e.g. `Alolan`, or null)
   - `types` (1–2), `stats` (hp, atk, def, spa, spd, spe; total derived)
   - `forms`: sibling entry ids (same species, including itself), in display order
   - `chain`: evolution chain id
   - `abilities` (slot order), `hidden` ability id, `catch` (capture rate), `weight`
     (hectograms); plus a top-level `abilities` table: id → key, name, English short
     effect, long description. (Added 2026-10-07.)
   - (`defense` is *not* stored. The app derives each entry's 18-type multiplier map
     from `types.json` at load time, cached per typing. Storing it doubled the JSON
     and pushed startup past 150 ms on the Pixel 7. Changed 2026-10-07.)
3. **Builds evolution trees** keyed by chain id. Each edge carries a short method string
   rendered from `pokemon_evolution.csv`: `Lv. 16`, `Thunder Stone`,
   `Trade w/ Metal Coat`, `High friendship, day`, etc. Regional evolution variants
   point at the correct form entry where the data allows.
4. **Converts artwork** with `cwebp` into two sizes per entry:
   - `assets/art/full/<id>.webp`, 256 px (Pokémon page)
   - `assets/art/thumb/<id>.webp`, 128 px (search rows and the evolution sheet; a 48 dp
     avatar at 2.625× is about 126 px)
5. **Writes** `assets/data/pokedex.json` (entries + chains) and `assets/data/types.json`
   (18×18 chart).
6. **Checks for gaps**: entries without artwork, and evolution edges whose method
   couldn't be rendered. It first applies `tool/overrides.json`, which has two maps: `art`
   (entry id → id whose artwork to reuse) and `methods` (`"<from_id>-><to_id>"` →
   method string). Any gap left after that makes `make data` **exit non-zero and print
   the list**. On success it prints the kept/dropped form list and the total asset sizes.

**Bulbapedia dropped (recon, 2026-10-07).** One request to Bulbapedia's MediaWiki API
with a descriptive User-Agent returned HTTP 403 with an HTML body. My guess is bot
protection, but that's unconfirmed. Getting past it would mean impersonating a browser,
which goes against the "polite scraper" requirement. Official artwork exists for every
candidate row except four Koraidon/Miraidon ride modes, and the form rule drops those
anyway. So gaps are resolved by hand in `tool/overrides.json`, and nothing scrapes
Bulbapedia.

The generated `assets/` are committed, so app builds never need the network.

### 2. App structure (Flutter)

**Startup:** load `pokedex.json` and `types.json` once and build the LUTs:
`Map<int, Entry> byId`, the ordered entry list, the precomputed normalised search keys,
the chains map, and each entry's defence map (derived from the chart, shared per typing).
Load time is measured and logged. Nothing is computed at page-render time.

**Moves tab** (added 2026-10-07), between Lookup and Type Chart: the same live search
(`SearchScreen<T>`, shared with Lookup) over `assets/data/moves.json`, with its own
frecency store (`frecency.moves.v1`, credited when a move page opens). Covers every
move a player can see (incl. Struggle, Celebrate, Starmobile torques); excludes Z-Moves,
Max Moves and Shadow moves. Moves no Pokémon learns in Scarlet are tagged "Not in
Scarlet". Move page: name; type, category and Not-in-Scarlet badges; Power ·
Accuracy · PP · Priority (if non-zero) · Effect chance; target and flags
(Contact, Punch, Sound, …; "contact unknown" where PokéAPI has no flag data,
i.e. all Gen 9 moves); in-game text (Scarlet's, else latest); PokéAPI long
description (hand-written via `tool/overrides.json` `move_descriptions` where missing).
No learnset (user decision). moves.json loads in the background and the tab is built on
first visit, so neither startup nor Lookup's autofocus is affected.

**Shell:** a bottom nav with **Lookup** (default), **Moves** and **Type Chart**. The theme follows
system light/dark, and type badges use the standard type colours. Each tab has its own
nested Navigator inside the IndexedStack, so pages open above the tab but below the
bottom bar, and an open page survives switching tabs; system back pops the current
tab's navigator (exits at a tab root); re-tapping the current tab pops it to its root. Enter in a search field opens the top result.

**Lookup tab:** the search field sits at the top, autofocused, with the keyboard up on
launch. Live suggestions are listed below it, each row showing a thumbnail, name, #dex
and type badges. Tapping a row opens the Pokémon page. Back returns to search with the
query cleared and the field refocused.

**Pokémon page,** top to bottom (ordered by how often each part is checked):
1. **Header:** portrait, then `Row(Expanded(name + #dex, wraps), EvoButton)`. The Evo
   button is pinned to the right edge of the page and takes no extra vertical space;
   long names wrap instead of pushing it. Type badges follow, then **one ability line**
   (`Overgrow · Chlorophyll (H)`, scaled down rather than wrapped). Tapping an
   ability opens a scrollable dialog: the one-liner in bold, then PokéAPI's long
   description (written around Gen 5–6, so it may predate later changes; correct wrong
   ones by hand if found).
2. **Form chips,** only when the entry has sibling forms (e.g. `[Raichu] [Alolan]`).
   Tapping one swaps the displayed entry **in place** (no new route), so back still
   returns to search.
3. **Base stats:** six labelled bars with values, plus the total. Display order is
   HP, Atk, SpA, Def, SpD, Spe (offence above defence); the data keeps PokéAPI order.
4. **Type defences,** in the Bulbapedia layout:
   - Weak to: 4×, 2×
   - Damaged normally by: 1×
   - Resistant to: ½×, ¼×
   - Immune to: 0×
   Each row is a wrap of type badges, read directly from the entry's `defense` map (built at load).
   **Guaranteed ability immunities:** when *every* ability an entry can have blocks a
   type (Levitate, Volt/Water Absorb, Flash Fire, …; Wonder Guard blocks everything
   not super effective), those types move to Immune to with a `(Levitate)` tag.
   E.g. Gastly, Shedinja; not Koffing (Levitate is only one of its abilities).
6. **Level-up moves** (above the footer): Lv ("Evo" for level 0), category symbol
   (drawn: Physical starburst, Special rings, Status half circle), type icon, move,
   power, accuracy, under a small header row; tapping opens the move page in the same tab and credits move
   frecency. Data: `learnsets` in moves.json (loaded in the background; the table appears
   once loaded). PokéAPI's Scarlet data includes the DLCs; entries not in Scarlet at all
   (325, e.g. Abra) fall back to Sword/Shield, then BDSP, USUM, SM, Let's Go, labelled
   "From <game>" (Legends games and Champions excluded). Cross-checked against Pokémon
   Showdown's learnsets: same coverage. Bulbapedia blocks automated access (403).
7. **Footer:** `Catch rate 45 · Weight 6.9 kg`, small and grey.
5. **Evo button** opens a bottom sheet with the chain tree (branches supported, e.g.
   Eevee). Each node shows a thumbnail + name, and each edge shows its method. Tapping
   a node swaps the page to that entry in place. Pressing and dragging from the Evo
   button instead pops up a compact list of the line (tree order) with the current
   entry under the thumb; releasing on another entry swaps to it, releasing off the
   list cancels. Its pan recognizer uses half the touch slop so it beats page scroll.

**Type order** everywhere (Focus tiles, Grid axes, defence table) is alphabetical, from
`TYPE_ORDER` via `types.json` (user choice; the conventional Normal, Fire, Water… order
can't be scanned without memorising it).

**Type Chart tab,** with two sub-tabs:
- **Focus:** an **Attacker / Defender toggle** at the top, then 18 type tiles; select
  exactly one type. Tiles sit in their own fixed 3-column grid, all the same size,
  each showing the Scarlet/Violet type icon (`assets/art/types/<type>.png`) and name.
  - Attacker mode: what type X hits, grouped as Super effective (2×),
    Not very effective (½×), No effect (0×).
  - Defender mode: how type X takes hits, grouped as Weak to (2×), Resistant to (½×),
    Immune to (0×).
  - No dual-type selection. Dual-type defence is what the Pokémon page is for.
- **Grid:** the full 18×18 chart. The attacker column and defender header row are
  frozen. Pinch to zoom and pan. Tapping a cell highlights its row and column.

### 3. Search & frecency

**Normalisation** (applied to both names and the query): lowercase, accents stripped
(`é→e`), and **all punctuation and spaces removed**. So `Mr. Mime`, `mr mime` and
`mrmime` all normalise to `mrmime`, `Farfetch'd` to `farfetchd`, and `Nidoran♀` to
`nidoranf`.

**Matching:** a query matches the normalised name, the form label (`alolan`), or the dex
number (`25`, `025`). Match tiers, best first:
1. name prefix
2. word prefix (e.g. `mime` → Mr. Mime; word boundaries come from the un-normalised name)
3. substring

**Ranking:**
1. Frecent matches (score > 0), by score descending.
2. Non-frecent matches, by match tier, then dex order.

An empty query matches everything, so it shows the frecent list followed by the full dex
in order. The same rule covers both cases.

**Frecency model:** a per-entry `(score, lastUpdated)`. When read, the score is
`score × 0.5^(age / halfLife)` with `halfLife = 3 days` (a constant). A visit decays the
stored score to now and adds 1. Storage is O(1) per entry, persisted as a small map in
`shared_preferences`. The clock is injected for tests.

**Visit attribution:** a visit is credited to the entry **opened from search**, when its
page opens (changed 2026-10-07 at the user's request; previously the entry on screen at
leave). So Raichu → [Alolan] → back credits Raichu only.

**Swipe to dismiss:** only frecent rows can be swiped. Swiping deletes that entry's
frecency record, and an Undo snackbar restores the previous `(score, lastUpdated)`.

**Image latency:** row thumbnails are 128 px. Thumbnails for the top frecent results are
precached at startup so suggestions never pop in.

### 4. Error handling

- The pipeline fails loudly (non-zero exit) on schema surprises: missing CSV columns,
  an entry with no types, or a chain referencing an unknown id. Gaps left after
  overrides (missing artwork, unrenderable method) also fail the run, with the list printed.
- The app asserts LUT invariants after load: every `forms` id and every chain node
  resolves in `byId`, and every `defense` map has 18 keys. Bundled data is
  build-generated, so a violation is a build bug, not a runtime condition to recover from.
- If the frecency store is corrupt, it is reset to empty, with a trace log.
- Tracing goes through one `trace(id, data)` helper, with stable trace IDs (e.g.
  `search.rank.frecent_hit`, `frecency.visit.credit`, `startup.load.done`) at branch
  points. By default it calls `dart:developer` `log()`. When built with
  `--dart-define=QUICKDEX_TRACE=true`, it uses `debugPrint` instead, so the lines reach
  `adb logcat` in release builds, where `log()` output isn't visible. There is no
  user-facing logging.

### 5. Project & tooling

- `git init` in this directory. `.cache/` is gitignored. `assets/` (generated) is committed.
- `.fvmrc` pins Flutter 3.41.8.
- Makefile targets:
  - `data`: run the pipeline
  - `perf`: release build with `QUICKDEX_TRACE=true`, install, and print the
    `startup.load.done` / `search.query.done` timings from logcat
  - `test`: pytest + flutter test
  - `analyze`: flutter analyze (+ ruff for tool/)
  - `run`: debug on device in a terminalcp session (hot reload)
  - `install`: release APK + `adb install -r` (daily use; release is much faster than debug)

### 6. Testing

- **Pipeline (pytest, real CSVs):**
  - Alolan Raichu is Electric/Psychic.
  - There are no Mega/G-Max entries.
  - Eevee has 8 branches, each with a method.
  - Gyarados takes Electric 4×.
  - Shedinja's defence profile is correct.
  - Every entry has both art sizes at the right dimensions.
- **Dart unit:**
  - normalisation cases (`Mr. Mime`, `mrmime`, `Farfetch'd`, `Flabébé`, `Nidoran♀`)
  - match tiers
  - ranking order
  - frecency decay and visit add (injected clock)
  - grouping of defence rows
- **Widget:**
  - swipe-dismiss + Undo
  - non-frecent rows aren't swipeable
  - a form chip swaps the page in place
  - the visit is credited to the final entry
  - evo sheet navigation
  - the Evo button stays pinned while a long name wraps
- **On-device perf:** `make perf` reports the startup load time and per-keystroke
  search time from a traced release build on the Pixel 7. Keystrokes are driven by
  `adb shell input text`. The measured numbers are reported.

## Ideal State Criteria

Pipeline
1. `make data` exits 0 starting from an empty `.cache/`.
2. `pokedex.json` contains no Mega entries.
3. `pokedex.json` contains no Gigantamax entries.
4. Raichu (Alolan) has types Electric/Psychic.
5. Raichu and Raichu (Alolan) list each other as sibling forms.
6. Eevee's chain has 8 evolutions.
7. Each of Eevee's 8 evolution edges has a non-empty method string.
8. Gyarados's defence map has Electric = 4.
9. Every entry has `assets/art/full/<id>.webp` at 256 px.
10. Every entry has `assets/art/thumb/<id>.webp` at 128 px.
11. With an artwork gap and no override, `make data` exits non-zero and prints the missing id.
12. No pipeline code contacts Bulbapedia.

App: search
13. On launch, the Lookup tab is shown.
14. On launch, the search field is focused.
15. Query `mrmime` returns Mr. Mime.
16. Query `mr mime` returns Mr. Mime.
17. Query `Mr. Mime` returns Mr. Mime.
18. Query `025` returns Pikachu.
19. A frecent match ranks above a non-frecent match that has a better match tier.
20. Swiping a frecent row removes it from the frecent section.
21. Undo after a swipe restores the entry's previous score.
22. Non-frecent rows cannot be swiped.
23. Opening Raichu, tapping [Alolan], then pressing back credits a visit to Alolan Raichu.
24. The same sequence credits no visit to Raichu.
25. Frecency persists across an app restart.

App: Pokémon page
26. The header shows the portrait.
27. The header shows the name.
28. The header shows the #dex.
29. The header shows the type badges.
30. The Evo button is pinned to the right edge of the name line.
31. A long name wraps rather than moving the Evo button.
32. Form chips appear for entries with sibling forms.
33. Form chips do not appear for entries without sibling forms.
34. Tapping a form chip swaps the page in place.
35. Back after a form-chip swap returns to search.
36. Gyarados's defence rows match Bulbapedia's groupings.
37. Shedinja's defence rows match Bulbapedia's groupings.
38. Tapping an evolution in the sheet opens that Pokémon.

App: Type chart
39. Focus in Attacker mode with a type selected shows its 2× / ½× / 0× offensive groups.
40. Focus in Defender mode with a type selected shows its 2× / ½× / 0× defensive groups.
41. Focus allows at most one selected type.
42. The grid's attacker headers stay visible while panning.
43. The grid's defender headers stay visible while panning.
44. The grid's headers stay visible while zoomed in.
45. Tapping a grid cell highlights its row.
46. Tapping a grid cell highlights its column.

Offline / perf
47. The release APK works with airplane mode on.
48. Data load is < 150 ms, measured on the Pixel 7 release build.
49. Per-keystroke search is < 2 ms, measured on the Pixel 7 release build.
50. `make test` passes.
51. `make analyze` passes.

## Documentation impact

- Feature / user-facing docs introduced: `README.md` (what QuickDex is, make targets,
  how to regenerate data); `AGENTS.md` (pipeline layout, data contract, conventions)
- Materially amended existing docs: none (new project)
- Derived / memory docs invalidated: none
