import 'package:flutter/material.dart';

import '../data/defense.dart';
import '../data/models.dart';
import '../data/moves.dart';
import '../search/search_index.dart';
import '../search/searchable.dart';
import '../team/team.dart';
import '../team/team_analysis.dart';
import '../trace.dart';
import 'art.dart';
import 'matchup_section.dart';
import 'move_page.dart';
import 'move_tile.dart';
import 'pokemon_tile.dart';
import 'type_badge.dart';
import 'type_style.dart';

/// Six slots (`team-slot-<i>`) and the team's matchups: per attacking type,
/// how many members are weak / resist / immune, and how many hit it
/// super-effectively (`team-row-<type>`; tap for per-member detail,
/// `team-detail-<type>`).
class TeamScreen extends StatefulWidget {
  const TeamScreen({
    super.key,
    required this.dex,
    required this.team,
    required this.index,
    required this.frecency,
    required this.moves,
    required this.moveFrecency,
    this.onOpenType,
  });
  final Pokedex dex;
  final Team team;
  final SearchIndex<PokemonEntry> index;
  final FrecencyScores frecency;
  final Future<MoveDex> moves;
  final FrecencyScores moveFrecency;

  /// Long-press/right-click on a type pill: open it in the Type Chart (as a
  /// defender). Pills do nothing when null.
  final ValueChanged<String>? onOpenType;

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

enum _SortColumn { type, weak, resist, immune, hitters }

class _TeamScreenState extends State<TeamScreen> {
  String? _expanded;

  /// Null keeps chart order.
  _SortColumn? _sort;

  /// Type sorts A–Z first; counts sort highest first. Re-tapping reverses.
  bool _reversed = false;

  void _tapSort(_SortColumn c) {
    if (_sort == c) {
      trace('team.sort.reverse', {'column': c.name, 'reversed': !_reversed});
      setState(() => _reversed = !_reversed);
    } else {
      trace('team.sort.column', {'column': c.name});
      setState(() {
        _sort = c;
        _reversed = false;
      });
    }
  }

  List<TypeMatchup> _sorted(List<TypeMatchup> rows) {
    final c = _sort;
    if (c == null) return rows;
    final order = {for (var i = 0; i < rows.length; i++) rows[i].type: i};
    int key(TypeMatchup r) => switch (c) {
      _SortColumn.weak => r.weak,
      _SortColumn.resist => r.resist,
      _SortColumn.immune => r.immune,
      _SortColumn.hitters => r.hitters,
      _SortColumn.type => throw StateError('type sorts by label'),
    };
    int compare(TypeMatchup a, TypeMatchup b) {
      final v = c == _SortColumn.type
          ? typeLabel(a.type).compareTo(typeLabel(b.type))
          : key(b).compareTo(key(a));
      return v != 0 ? v : order[a.type]!.compareTo(order[b.type]!);
    }

    final out = [...rows]..sort(compare);
    return _reversed ? out.reversed.toList() : out;
  }

  /// Pick a Pokémon for slot [i] (resetting its ability and moves); returns
  /// false if cancelled.
  Future<bool> _choose(int i) async {
    final e = await Navigator.of(context).push(
      MaterialPageRoute<PokemonEntry>(
        builder: (_) =>
            PokemonPicker(index: widget.index, frecency: widget.frecency),
      ),
    );
    if (e == null) {
      trace('team.choose.cancelled', {'slot': i});
      return false;
    }
    widget.team[i] = TeamSlot(e.id, ability: e.abilities.first);
    return true;
  }

  Future<void> _tapSlot(int i) async {
    final nav = Navigator.of(context);
    if (widget.team[i] == null) {
      trace('team.tap.empty', {'slot': i});
      if (!await _choose(i)) return;
    } else {
      trace('team.tap.filled', {'slot': i});
    }
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => TeamSlotPage(
          dex: widget.dex,
          team: widget.team,
          slot: i,
          index: widget.index,
          frecency: widget.frecency,
          moves: widget.moves,
          moveFrecency: widget.moveFrecency,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Team Planner')),
    body: ListenableBuilder(
      listenable: widget.team,
      builder: (context, _) => FutureBuilder(
        future: widget.moves,
        builder: (context, snap) => _body(context, snap.data),
      ),
    ),
  );

  Widget _body(BuildContext context, MoveDex? moves) {
    final members = [
      for (var i = 0; i < Team.size; i++)
        if (widget.team[i] case final s?)
          resolveMember(i, s, widget.dex, moves),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.9,
          children: [
            for (var i = 0; i < Team.size; i++)
              _SlotCard(
                key: Key('team-slot-$i'),
                entry: switch (widget.team[i]) {
                  final s? => widget.dex[s.pokemon],
                  null => null,
                },
                onTap: () => _tapSlot(i),
                onChoose: () {
                  trace('team.slot.choose', {'slot': i});
                  _choose(i);
                },
                onOpenType: _openType,
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (members.isEmpty)
          const Text('Add Pokémon to see team matchups', key: Key('team-empty'))
        else
          ..._matchups(context, members),
      ],
    );
  }

  List<Widget> _matchups(BuildContext context, List<TeamMember> members) {
    final theme = Theme.of(context);
    final rows = _sorted(analyseTeam(members, widget.dex.types));
    Widget header(String text, _SortColumn c, {double? width}) {
      final active = _sort == c;
      // Arrow shows the direction of the list: up = ascending.
      final ascending = (c == _SortColumn.type) != _reversed;
      final label = InkWell(
        key: Key('team-sort-${c.name}'),
        onTap: () => _tapSort(c),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: width == null
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Flexible(child: Text(text)),
              if (active)
                Icon(
                  ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14,
                ),
            ],
          ),
        ),
      );
      return width == null
          ? Expanded(child: label)
          : SizedBox(width: width, child: label);
    }

    Widget cell(String text, {Color? tint, Key? key}) => Expanded(
      child: Container(
        key: key,
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
    return [
      Text('Team matchups', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
        'Tap a type for each member’s multipliers.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      DefaultTextStyle.merge(
        style: theme.textTheme.labelMedium,
        child: Row(
          children: [
            header('Attacking', _SortColumn.type, width: _typeColumn),
            header('Weak', _SortColumn.weak),
            header('Resist', _SortColumn.resist),
            header('Immune', _SortColumn.immune),
            header('Hit SE', _SortColumn.hitters),
          ],
        ),
      ),
      for (final r in rows) ...[
        InkWell(
          key: Key('team-row-${r.type}'),
          onTap: () {
            trace('team.row.toggle', {'type': r.type});
            setState(() => _expanded = _expanded == r.type ? null : r.type);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: _typeColumn,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TypeBadge(
                      r.type,
                      compact: true,
                      key: Key('team-type-${r.type}'),
                      onAdd: _openType(r.type, 'attacking'),
                    ),
                  ),
                ),
                // More weak than not is a hole in the team's defence.
                cell(
                  '${r.weak}',
                  key: Key('team-weak-${r.type}'),
                  tint: r.weak > r.resist + r.immune
                      ? matchupTint(r.weak >= 3 ? 4 : 2, defending: true)
                      : null,
                ),
                cell('${r.resist}'),
                cell('${r.immune}'),
                // No one hitting it super-effectively is a coverage gap.
                cell(
                  '${r.hitters}',
                  key: Key('team-hitters-${r.type}'),
                  tint: r.hitters == 0
                      ? matchupTint(0.5, defending: false)
                      : matchupTint(2, defending: false),
                ),
              ],
            ),
          ),
        ),
        if (_expanded == r.type) _detail(context, r, members),
      ],
    ];
  }

  static const _typeColumn = 84.0;

  VoidCallback? _openType(String t, String from) {
    final open = widget.onOpenType;
    if (open == null) return null;
    return () {
      trace('team.type.open', {'type': t, 'from': from});
      open(t);
    };
  }

  Widget _detail(BuildContext context, TypeMatchup r, List<TeamMember> m) {
    assert(r.defense.length == m.length && r.offense.length == m.length);
    Widget mult(double x, {required bool defending}) => Container(
      width: 44,
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: matchupTint(x, defending: defending),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(multLabel(x), textAlign: TextAlign.center),
    );
    final small = Theme.of(context).textTheme.labelSmall;
    return Container(
      key: Key('team-detail-${r.type}'),
      margin: const EdgeInsets.fromLTRB(8, 2, 0, 8),
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(),
              SizedBox(
                width: 48,
                child: Text('Takes', style: small, textAlign: TextAlign.end),
              ),
              SizedBox(
                width: 48,
                child: Text('Deals', style: small, textAlign: TextAlign.end),
              ),
            ],
          ),
          for (var i = 0; i < m.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Image.asset(thumbPath(m[i].entry.id), width: 28, height: 28),
                  const SizedBox(width: 6),
                  Expanded(child: Text(m[i].entry.name)),
                  mult(r.defense[i], defending: true),
                  mult(r.offense[i], defending: false),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onChoose,
    required this.onOpenType,
  });
  final PokemonEntry? entry;
  final VoidCallback onTap;

  /// Long-press/right-click: straight to the Pokémon chooser.
  final VoidCallback onChoose;
  final VoidCallback? Function(String type, String from) onOpenType;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onChoose,
        onSecondaryTap: onChoose,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: e == null
              ? const Center(child: Icon(Icons.add, size: 32))
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(child: Image.asset(thumbPath(e.id))),
                    Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 2,
                      children: [
                        for (final t in e.types)
                          TypeBadge(
                            t,
                            compact: true,
                            key: Key('team-slot-type-$t'),
                            onAdd: onOpenType(t, 'slot'),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Edit one slot: change the Pokémon, pick its ability and up to four moves
/// (`team-move-<k>`, cleared with `team-move-clear-<k>`), or remove it.
class TeamSlotPage extends StatelessWidget {
  const TeamSlotPage({
    super.key,
    required this.dex,
    required this.team,
    required this.slot,
    required this.index,
    required this.frecency,
    required this.moves,
    required this.moveFrecency,
  });
  final Pokedex dex;
  final Team team;
  final int slot;
  final SearchIndex<PokemonEntry> index;
  final FrecencyScores frecency;
  final Future<MoveDex> moves;
  final FrecencyScores moveFrecency;

  Future<void> _changePokemon(BuildContext context) async {
    final e = await Navigator.of(context).push(
      MaterialPageRoute<PokemonEntry>(
        builder: (_) => PokemonPicker(index: index, frecency: frecency),
      ),
    );
    if (e == null) {
      trace('team.slot.change.cancelled', {'slot': slot});
      return;
    }
    // Abilities and moves belong to the old Pokémon.
    team[slot] = TeamSlot(e.id, ability: e.abilities.first);
  }

  Future<void> _pickMove(BuildContext context, TeamSlot s, int k) async {
    final dexMoves = await moves;
    if (!context.mounted) return;
    final m = await Navigator.of(context).push(
      MaterialPageRoute<Move>(
        builder: (_) => MovePicker(
          moves: dexMoves,
          frecency: moveFrecency,
          pokemon: s.pokemon,
          exclude: s.moves.toSet(),
        ),
      ),
    );
    if (m == null) {
      trace('team.move.cancelled', {'slot': slot, 'k': k});
      return;
    }
    final current = team[slot];
    if (current == null) return; // removed meanwhile
    final next = [...current.moves];
    if (k < next.length) {
      trace('team.move.replace', {'slot': slot, 'k': k, 'move': m.id});
      next[k] = m.id;
    } else {
      trace('team.move.append', {'slot': slot, 'move': m.id});
      next.add(m.id);
    }
    team[slot] = current.copyWith(moves: next);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: team,
    builder: (context, _) {
      final s = team[slot];
      if (s == null) return const SizedBox.shrink(); // popping after remove
      final e = dex[s.pokemon];
      return Scaffold(
        appBar: AppBar(
          title: Text('Slot ${slot + 1}'),
          actions: [
            IconButton(
              key: const Key('team-remove'),
              tooltip: 'Remove from team',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                Navigator.of(context).pop();
                team[slot] = null;
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            PokemonTile(
              e,
              key: const Key('team-pokemon'),
              onTap: () => _changePokemon(context),
            ),
            _heading(context, 'Ability'),
            _abilities(context, s, e),
            _heading(context, 'Moves'),
            FutureBuilder(
              future: moves,
              builder: (context, snap) => _moves(context, s, snap.data),
            ),
          ],
        ),
      );
    },
  );

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _abilities(BuildContext context, TeamSlot s, PokemonEntry e) {
    final chosen = s.ability == null ? null : dex.abilities[s.ability!];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final id in [...e.abilities, ?e.hidden])
                ChoiceChip(
                  key: Key('team-ability-$id'),
                  label: Text(
                    '${dex.abilities[id]!.name}${id == e.hidden ? ' (H)' : ''}',
                  ),
                  selected: s.ability == id,
                  onSelected: (_) {
                    trace('team.ability', {'slot': slot, 'ability': id});
                    team[slot] = s.copyWith(ability: id);
                  },
                ),
            ],
          ),
          if (chosen != null)
            Text(chosen.effect, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _moves(BuildContext context, TeamSlot s, MoveDex? dexMoves) {
    if (dexMoves == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }
    return Column(
      children: [
        for (var k = 0; k < TeamSlot.maxMoves; k++)
          if (k < s.moves.length && dexMoves.byId[s.moves[k]] != null)
            Row(
              children: [
                Expanded(
                  child: MoveTile(
                    dexMoves.byId[s.moves[k]]!,
                    key: Key('team-move-$k'),
                    onTap: () => _pickMove(context, s, k),
                    onDetails: () =>
                        showMoveDetails(context, dexMoves.byId[s.moves[k]]!),
                  ),
                ),
                IconButton(
                  key: Key('team-move-clear-$k'),
                  tooltip: 'Clear move',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    trace('team.move.clear', {'slot': slot, 'k': k});
                    team[slot] = s.copyWith(moves: [...s.moves]..removeAt(k));
                  },
                ),
              ],
            )
          else if (k == s.moves.length)
            ListTile(
              key: Key('team-move-$k'),
              leading: const SizedBox(width: 48, child: Icon(Icons.add)),
              title: const Text('Add move'),
              onTap: () => _pickMove(context, s, k),
            ),
      ],
    );
  }
}

/// Search field over a list; pops with the tapped item.
class _Picker<T extends Searchable> extends StatefulWidget {
  const _Picker({
    required this.title,
    required this.results,
    required this.tile,
    this.header,
  });
  final String title;
  final List<T> Function(String query) results;
  final Widget Function(T item, VoidCallback onTap) tile;

  /// Shown above the results when nothing is typed.
  final String? header;

  @override
  State<_Picker<T>> createState() => _PickerState<T>();
}

class _PickerState<T extends Searchable> extends State<_Picker<T>> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.results(_query.text);
    final header = _query.text.isEmpty ? widget.header : null;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const Key('team-pick-search'),
          controller: _query,
          autofocus: true,
          decoration: InputDecoration(
            hintText: widget.title,
            border: InputBorder.none,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
      body: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: results.length + (header == null ? 0 : 1),
        itemBuilder: (context, i) {
          if (header != null) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  header,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              );
            }
            i--;
          }
          final item = results[i];
          return KeyedSubtree(
            key: Key('team-pick-row-${item.id}'),
            child: widget.tile(item, () {
              trace('team.pick', {'type': '$T', 'id': item.id});
              Navigator.of(context).pop(item);
            }),
          );
        },
      ),
    );
  }
}

/// Pick a Pokémon; ranked like search (recent first, then frecency).
class PokemonPicker extends StatelessWidget {
  const PokemonPicker({super.key, required this.index, required this.frecency});
  final SearchIndex<PokemonEntry> index;
  final FrecencyScores frecency;

  @override
  Widget build(BuildContext context) => _Picker<PokemonEntry>(
    title: 'Search Pokémon',
    results: (q) => [for (final h in index.search(q, frecency)) h.entry],
    tile: (e, onTap) => PokemonTile(e, onTap: onTap),
  );
}

/// Pick a move. With nothing typed, lists [pokemon]'s level-up moves; typing
/// searches every move. Moves in [exclude] (already chosen) are left out.
class MovePicker extends StatefulWidget {
  const MovePicker({
    super.key,
    required this.moves,
    required this.frecency,
    required this.pokemon,
    this.exclude = const {},
  });
  final MoveDex moves;
  final FrecencyScores frecency;
  final int pokemon;
  final Set<int> exclude;

  @override
  State<MovePicker> createState() => _MovePickerState();
}

class _MovePickerState extends State<MovePicker> {
  late final _index = SearchIndex(widget.moves.moves);

  late final List<Move> _learnset = [
    ...{
      for (final l in widget.moves.learnsets[widget.pokemon]?.moves ?? const [])
        if (!widget.exclude.contains(l.move)) l.move,
    }.map((id) => widget.moves.byId[id]!),
  ];

  List<Move> _results(String q) {
    if (isRecencyQuery(q)) {
      trace('team.move_picker.learnset', {'count': _learnset.length});
      return _learnset;
    }
    return [
      for (final h in _index.search(q, widget.frecency))
        if (!widget.exclude.contains(h.entry.id)) h.entry,
    ];
  }

  @override
  Widget build(BuildContext context) => _Picker<Move>(
    title: 'Search moves',
    results: _results,
    tile: (m, onTap) => Builder(
      builder: (context) => MoveTile(
        m,
        onTap: onTap,
        onDetails: () => showMoveDetails(context, m),
      ),
    ),
    header: _learnset.isEmpty ? 'Type to search moves' : 'Level-up moves',
  );
}
