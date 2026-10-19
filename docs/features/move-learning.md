# Move machines and learners

The full move page shows the selected game's TM/HM labels (for example, Scarlet
Thunderbolt is TM126; Emerald Surf is HM03). Scrambled Scarlet shows its TM badge
unlock counts instead of inheriting Scarlet's machine numbers.

"Who can learn it?" opens a scrollable, lazily built list of matching Pokemon
entries, including retained forms. Each row shows its level-up levels, evolution
learning, machine labels or badge requirements. An entry appears once even when it
has several learning methods. Tap a row to open that game's Pokemon page; its
learnset moves can open full move pages again. Both search results and Pokemon
learnset rows provide the move page with the same game data and frecency stores.
The compact move-details bottom sheet remains unchanged.

## Data boundary

`lib/ui/move_learners.dart` reverses the existing `MoveDex.learnsets`, joining by
entry id against the loaded `Pokedex`. There are no JSON/model/pipeline changes.
The page waits for the existing background move-loading future and distinguishes
loading, failure, no machine, and no known learner states.

This is a list of **known level-up and TM/HM learners**, not a complete learnability
claim: bundled learnsets do not include egg or tutor moves. Older-game fallback
level-up learnsets are included with `From <game>` labels, matching the Pokemon
page. A fallback does not invent machine compatibility for the selected game.

## Verification

- `make test-moves`: focused navigation, game-specific machines, Scrambled badge
  learners, duplicate learning methods, fallback labels, empty/loading/failure
  states, plus existing move-search and Pokemon-learnset tests.
- `make analyze`: Python lint and Flutter static analysis.
- `make format DART_FILES='<changed Dart paths>'`: scoped Dart formatting.

Developer traces: `move.learners.lookup`, `.open`, `.select`, `.loading`, and
`.load_failed`. Reverse lookup asserts that the move belongs to the supplied
MoveDex. Opening a learner uses Pokemon frecency; opening a move uses move
frecency. Listing learners itself does not credit visits.
