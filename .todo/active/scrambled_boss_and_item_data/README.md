---
title: Use Scrambled Scarlet boss fights, level caps, items in the team planner
status: active
priority: medium
created: 2026-10-13
tags: [scrambled, team-planner, data]
blocks: []
---

The first Scrambled Scarlet build only takes Pokémon, moves and abilities from the
Doozdex sheet. The other tabs are already downloaded with it (`.cache/doozdex/`,
see `tool/quickdex_data/doozdex.py` for the gid of each tab):

- Vanilla Path Boss Fights, Reverse Path Boss Fights (enemy gym/boss teams)
- Level Caps + Boss Locations/Paths
- Egg/Encounter Guide, Item Locations (Shop Guide), Held Item Buffs/Changes

Done since: boss teams (Theirs presets), and items (shop badge unlocks and held-item
buffs, `scrambled_items.py`). Still unused: Level Caps + Boss Locations/Paths and the
Egg/Encounter Guide.

The owner plans team planner improvements next: saving and loading teams, including
the enemy gym teams from the boss fight tabs.
