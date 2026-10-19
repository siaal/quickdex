---
title: Sidedeck temporary squad overflow
summary: Persist extra squad selections while blocking Sidedeck back navigation until at most six remain.
tags: [sidedeck, team, persistence, navigation]
verified: true
---

# Sidedeck squad legality

Sidedeck uses `Team.toggle(..., allowOverflow: true)` to allow selecting replacements before benching existing members. A legal squad has at most six members; zero is legal. Other toggle callers still refuse an addition to a full squad, and `Team.add` still benches new deck members when full.

The existing `d`/`q` JSON format is retained. `q` has at least six positions and can temporarily contain extra selected deck indices. Every change, including an overfull selection, is persisted through the existing callback. Loading must preserve all valid, unique indices, including extras; unknown or duplicate indices are still dropped. Bare legacy slot lists and `s` objects still migrate to six positions with their empty slots intact.

`Team.slots` and `Lineup.slots` always expose six planner positions. This is a view, not truncation of the stored selection. Removing a selected member promotes extras into vacant positions, then removes unused overflow positions. Once the selection is legal, all selected members fit in the planner view.

`SidedeckPage` rebuilds its `PopScope` from `Team.isLegal`. System back and the app back button (`maybePop`) cannot leave while overfull. The page explains the six-member limit both inline and on blocked back attempts. Nested picker/editor routes may still return to Sidedeck.

## Integration notes

- Member editors must bench by deck membership (`team.toggle(member)`), not assign through a squad slot index: an overflow member's `slotOf` result can exceed five, while the planner setter deliberately remains limited to six positions.
- If the app restarts during an overfull edit, the selection survives. `SidedeckPage` guards it when reopened; automatically reopening Sidedeck on restoration would require a host/planner navigation change.
- The dedicated widget regression suite is `test/ui/sidedeck_legality_test.dart`; model persistence/migration coverage lives in `test/team/team_test.dart`.
