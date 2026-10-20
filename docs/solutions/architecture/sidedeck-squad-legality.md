---
title: Sidedeck temporary squad overflow
summary: Persist temporary squad overflow, guard navigation, and freeze party-first sidedeck sorting until entry or an explicit sort selection.
tags: [sidedeck, team, persistence, navigation, sorting]
verified: true
---

# Sidedeck squad legality

Sidedeck uses `Team.toggle(..., allowOverflow: true)` to allow selecting replacements before benching existing members. A legal squad has at most six members; zero is legal. Other toggle callers still refuse an addition to a full squad, and `Team.add` still benches new deck members when full.

The existing `d`/`q` JSON format is retained. `q` has at least six positions and can temporarily contain extra selected deck indices. Every change, including an overfull selection, is persisted through the existing callback. Loading must preserve all valid, unique indices, including extras; unknown or duplicate indices are still dropped. Bare legacy slot lists and `s` objects still migrate to six positions with their empty slots intact.

`Team.slots` and `Lineup.slots` always expose six planner positions. This is a view, not truncation of the stored selection. Removing a selected member promotes extras into vacant positions, then removes unused overflow positions. Once the selection is legal, all selected members fit in the planner view.

`SidedeckPage` rebuilds its `PopScope` from `Team.isLegal`. The shell routes system and mouse back through the nested navigator's `maybePop`, not `pop`, so the guard is respected. The app back button also uses `maybePop`. `TeamScreen.onDeckChanged` tells the shell which team's sidedeck is open (including nested pickers/editors), so tab switching and tab re-selection cannot bypass the guard while it is overfull. The page explains the six-member limit both inline and on blocked back attempts. Nested picker/editor routes may still return to Sidedeck.

Team Planner also displays error-coloured text for an overfull squad, including its selected count and an explanation that only the first six are displayed and analysed. This covers restored or otherwise unexpected overflow without relying on navigation guards to enforce data validity. Opening Sidedeck and benching extras clears the warning.

## Sidedeck ordering

The header's rightmost + replaces the old Add Pokémon row. Sort offers Recency (default) and Name, with party members first in either mode. Recency keeps party members in squad order, then sorts benched members by their last removal (newest first). Legacy or never-benched members have no removal history and retain deck order as a tie-breaker.

`Team.sidedeckSort` is saved per team as optional `sort` (`name`; absent means Recency). `TeamSlot.lastBenched` is an optional `b` in member JSON. Both removal paths (`team[i] = null` and `toggle`) record the next counter above the deck's maximum; editing preserves it, and saved builds carry it. This needs no wall-clock timestamps.

`SidedeckPage` snapshots the sorted row order only when opened or when a sort mode is chosen. Membership highlighting still updates immediately. Adds append; deletion drops just that row. Sorting never mutates deck/squad order. Transient `Team.memberId` values identify deck members independently of their Pokémon species, immutable slot objects and compacted deck indices, so edits and duplicate Pokémon do not move the wrong row.

`test/ui/sidedeck_sort_test.dart` covers the header actions, frozen row order, sorting on re-entry, deletion remapping, and persistence. The model tests cover removal history and stable member identities.

## Integration notes

- Member editors must bench by deck membership (`team.toggle(member)`), not assign through a squad slot index: an overflow member's `slotOf` result can exceed five, while the planner setter deliberately remains limited to six positions.
- If the app restarts during an overfull edit, the selection survives. The planner warns, and `SidedeckPage` guards it when reopened; the app does not force navigation back to Sidedeck on restoration.
- Standalone page coverage is in `test/ui/sidedeck_legality_test.dart`; real-shell back/tab navigation, overflow editor benching and restored warnings on both team sides are covered by `test/ui/team_legality_navigation_test.dart`. Model persistence/migration coverage lives in `test/team/team_test.dart`.
