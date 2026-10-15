import 'package:flutter/material.dart';

import '../data/defense.dart';
import '../data/models.dart';
import '../data/moves.dart';
import '../search/search_index.dart';
import '../search/searchable.dart';
import '../team/builds.dart';
import '../team/team.dart';
import '../team/team_analysis.dart';
import '../trace.dart';
import 'art.dart';
import 'learnset_table.dart';
import 'matchup_section.dart';
import 'sidedeck_page.dart';
import 'move_page.dart';
import 'move_tile.dart';
import 'pokemon_tile.dart';
import 'type_badge.dart';
import 'type_style.dart';
import 'versus_view.dart';

/// Six slots (`team-slot-<i>`) and the team's matchups: per attacking type,
/// how many members are weak / resist / immune, and how many hit it
/// super-effectively (`team-row-<type>`; tap for per-member detail,
/// `team-detail-<type>`).
class TeamScreen extends StatefulWidget {
  const TeamScreen({
    super.key,
    required this.dex,
    required this.planner,
    required this.index,
    required this.frecency,
    required this.moves,
    required this.moveFrecency,
    this.onOpenType,
  });
  final Pokedex dex;
  final TeamPlanner planner;
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

/// Your team, or the opponent's (`team-side`).
enum _Side { mine, theirs }

class _TeamScreenState extends State<TeamScreen> {
  String? _expanded;
  _Side _side = _Side.mine;

  TeamSide get _sideData => switch (_side) {
    _Side.mine => widget.planner.mine,
    _Side.theirs => widget.planner.theirs,
  };

  Team get _team => _sideData.team;

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
    _team[i] = TeamSlot(e.id, ability: e.abilities.first);
    return true;
  }

  Future<void> _tapSlot(int i) async {
    final nav = Navigator.of(context);
    if (_team[i] == null) {
      trace('team.tap.empty', {'slot': i});
      if (!await _choose(i)) return;
    } else {
      trace('team.tap.filled', {'slot': i});
    }
    final member = _team.lineup.squad[i];
    assert(member != null, 'slot $i filled above');
    if (member == null) return;
    await nav.push(_editRoute(member));
  }

  /// The editor for deck member [member].
  Route<void> _editRoute(int member) => MaterialPageRoute<void>(
    builder: (_) => TeamSlotPage(
      dex: widget.dex,
      team: _team,
      member: member,
      index: widget.index,
      frecency: widget.frecency,
      moves: widget.moves,
      moveFrecency: widget.moveFrecency,
    ),
  );

  /// Saves the shown side's team as one of that side's builds, named as it
  /// was loaded or saved unless renamed; an existing name is overwritten.
  Future<void> _save() async {
    final side = _sideData;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _SaveDialog(
        initial: side.team.name ?? '',
        builds: side.builds,
        frecency: side.frecency,
        dex: widget.dex,
      ),
    );
    if (name == null) {
      trace('team.save.cancelled', {'side': _side.name});
      return;
    }
    final build = side.builds.save(name, side.team.lineup);
    trace('team.save', {'side': _side.name, 'id': build.id});
    side.frecency.visit(build.id);
    side.team.name = build.name;
  }

  /// Replaces the shown side's team with one of its saved builds or presets
  /// (boss teams), picked from a list ranked like search. Undoable.
  Future<void> _load() async {
    final side = _sideData;
    final frecency = side.frecency;
    final team = side.team;
    final build = await Navigator.of(context).push(
      MaterialPageRoute<TeamBuild>(
        builder: (_) => BuildPicker(
          builds: () => side.loadable,
          frecency: frecency,
          dex: widget.dex,
          changes: side.builds,
          canDelete: (b) => !side.presets.contains(b),
          onDelete: (b) {
            side.builds.delete(b.id);
            frecency.remove(b.id);
          },
        ),
      ),
    );
    if (build == null || !mounted) {
      trace('team.load.cancelled', {'side': _side.name});
      return;
    }
    trace('team.load.build', {'side': _side.name, 'id': build.id});
    frecency.visit(build.id);
    final (before, beforeName) = (team.lineup, team.name);
    team.load(build.lineup, name: build.name);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Loaded ${build.name}'),
          // An action would otherwise keep it up until dismissed.
          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              trace('team.load.undo', {'id': build.id});
              team.load(before, name: beforeName);
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _team,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        child: FutureBuilder(
          future: widget.moves,
          builder: (context, snap) => _body(context, snap.data),
        ),
      ),
    ),
  );

  /// Opens the shown side's sidedeck; + there adds a Pokémon and edits it.
  void _openDeck() {
    trace('team.deck.open', {'side': _side.name, 'deck': _team.deck.length});
    final team = _team;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SidedeckPage(
          team: team,
          dex: widget.dex,
          moves: widget.moves,
          onEdit: (context, member) =>
              Navigator.of(context).push(_editRoute(member)),
          onAdd: (context) async {
            final nav = Navigator.of(context);
            final e = await nav.push(
              MaterialPageRoute<PokemonEntry>(
                builder: (_) => PokemonPicker(
                  index: widget.index,
                  frecency: widget.frecency,
                ),
              ),
            );
            if (e == null) {
              trace('team.deck.add.cancelled');
              return;
            }
            final member = team.add(TeamSlot(e.id, ability: e.abilities.first));
            await nav.push(_editRoute(member));
          },
        ),
      ),
    );
  }

  /// Save, Load, Sidedeck and Mine | Theirs; scrolls away with the team.
  Widget _header() => SizedBox(
    height: kToolbarHeight,
    child: Row(
      children: [
        IconButton(
          key: const Key('team-save'),
          tooltip: 'Save build',
          icon: const Icon(Icons.save_outlined),
          onPressed: _team.deck.isEmpty ? null : _save,
        ),
        IconButton(
          key: const Key('team-load'),
          tooltip: 'Load build',
          icon: const Icon(Icons.folder_open_outlined),
          onPressed: _load,
        ),
        const Spacer(),
        IconButton(
          key: const Key('team-deck'),
          tooltip: 'Sidedeck',
          icon: const Icon(Icons.style_outlined),
          onPressed: _openDeck,
        ),
        const Spacer(),
        SegmentedButton<_Side>(
          key: const Key('team-side'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _Side.mine, label: Text('Mine')),
            ButtonSegment(value: _Side.theirs, label: Text('Theirs')),
          ],
          selected: {_side},
          onSelectionChanged: (s) {
            trace('team.side', {'side': s.single.name});
            setState(() => _side = s.single);
          },
        ),
      ],
    ),
  );

  Widget _body(BuildContext context, MoveDex? moves) {
    final members = [
      for (var i = 0; i < Team.size; i++)
        if (_team[i] case final s?) resolveMember(i, s, widget.dex, moves),
    ];
    return ListView(
      key: const Key('team-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        _header(),
        if (_team.name case final name?)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              name,
              key: const Key('team-name'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
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
                entry: switch (_team[i]) {
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
        if (_side == _Side.theirs && members.isNotEmpty)
          ..._versus(context, members, moves),
        if (members.isEmpty)
          const Text('Add Pokémon to see team matchups', key: Key('team-empty'))
        else
          ..._matchups(context, members),
      ],
    );
  }

  /// Your team against [theirs], above their type table.
  List<Widget> _versus(
    BuildContext context,
    List<TeamMember> theirs,
    MoveDex? moves,
  ) {
    final mineTeam = widget.planner.mine.team;
    final mine = [
      for (var i = 0; i < Team.size; i++)
        if (mineTeam[i] case final s?) resolveMember(i, s, widget.dex, moves),
    ];
    final theme = Theme.of(context);
    return [
      Text('Versus', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      if (mine.isEmpty)
        const Text('Add Pokémon on Mine to compare', key: Key('versus-empty'))
      else
        VersusView(key: const Key('versus'), mine: mine, theirs: theirs),
      const SizedBox(height: 16),
    ];
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
          // Red when more members are behind this type than ahead of it,
          // green when more are ahead (see TypeMatchup.edges).
          child: ColoredBox(
            key: Key('team-tint-${r.type}'),
            color: _rowTint(r),
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
                  cell('${r.weak}', key: Key('team-weak-${r.type}')),
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
        ),
        if (_expanded == r.type) _detail(context, r, members),
      ],
    ];
  }

  static const _typeColumn = 84.0;

  static Color _rowTint(TypeMatchup r) {
    final net = r.ahead - r.behind;
    trace('team.row.tint', {
      'type': r.type,
      'ahead': r.ahead,
      'behind': r.behind,
    });
    if (net == 0) return Colors.transparent;
    // matchupTint as an attacker: 2×/4× green, ½×/¼× red.
    return matchupTint(
      net > 0 ? (net >= 3 ? 4 : 2) : (net <= -3 ? 0.25 : 0.5),
      defending: false,
    );
  }

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
    // Null: only status moves, so it deals nothing.
    Widget mult(double? x, {required bool defending}) => Container(
      width: 44,
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: x == null ? null : matchupTint(x, defending: defending),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(x == null ? '—' : multLabel(x), textAlign: TextAlign.center),
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
/// (`team-move-<k>`, cleared with `team-move-clear-<k>`, left out of the
/// analysis with `team-move-hide-<k>`), or remove it.
class TeamSlotPage extends StatelessWidget {
  const TeamSlotPage({
    super.key,
    required this.dex,
    required this.team,
    required this.member,
    required this.index,
    required this.frecency,
    required this.moves,
    required this.moveFrecency,
  });
  final Pokedex dex;
  final Team team;
  final int member;
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
      trace('team.slot.change.cancelled', {'member': member});
      return;
    }
    // Abilities and moves belong to the old Pokémon.
    team.setMember(member, TeamSlot(e.id, ability: e.abilities.first));
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
      trace('team.move.cancelled', {'member': member, 'k': k});
      return;
    }
    if (member >= team.deck.length) return; // removed meanwhile
    final current = team.deck[member];
    final next = [...current.moves];
    if (k < next.length) {
      trace('team.move.replace', {'member': member, 'k': k, 'move': m.id});
      next[k] = m.id;
    } else {
      trace('team.move.append', {'member': member, 'move': m.id});
      next.add(m.id);
    }
    team.setMember(member, current.copyWith(moves: next));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: team,
    builder: (context, _) {
      if (member >= team.deck.length) {
        return const SizedBox.shrink(); // popping after a delete
      }
      final s = team.deck[member];
      final e = dex[s.pokemon];
      final slot = team.slotOf(member);
      return Scaffold(
        appBar: AppBar(
          title: Text(slot == null ? 'Sidedeck' : 'Slot ${slot + 1}'),
          actions: [
            // In the squad: bench it (it stays in the sidedeck). Out: delete.
            IconButton(
              key: const Key('team-remove'),
              tooltip: slot == null
                  ? 'Delete from sidedeck'
                  : 'Take out of squad',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                trace('team.member.remove_tap', {
                  'member': member,
                  'slot': slot,
                });
                Navigator.of(context).pop();
                if (slot == null) {
                  team.remove(member);
                } else {
                  team[slot] = null;
                }
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
                    trace('team.ability', {'member': member, 'ability': id});
                    team.setMember(member, s.copyWith(ability: id));
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
                  child: Opacity(
                    opacity: s.hidden.contains(s.moves[k]) ? 0.4 : 1,
                    child: MoveTile(
                      dexMoves.byId[s.moves[k]]!,
                      key: Key('team-move-$k'),
                      onTap: () => _pickMove(context, s, k),
                      onDetails: () =>
                          showMoveDetails(context, dexMoves.byId[s.moves[k]]!),
                    ),
                  ),
                ),
                // Hidden moves stay in the slot but don't count in matchups.
                IconButton(
                  key: Key('team-move-hide-$k'),
                  tooltip: s.hidden.contains(s.moves[k])
                      ? 'Count in matchups'
                      : 'Leave out of matchups',
                  icon: Icon(
                    s.hidden.contains(s.moves[k])
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () {
                    final id = s.moves[k];
                    final hide = !s.hidden.contains(id);
                    trace(hide ? 'team.move.hide' : 'team.move.show', {
                      'member': member,
                      'k': k,
                    });
                    team.setMember(
                      member,
                      s.copyWith(
                        hidden: hide
                            ? {...s.hidden, id}
                            : ({...s.hidden}..remove(id)),
                      ),
                    );
                  },
                ),
                IconButton(
                  key: Key('team-move-clear-$k'),
                  tooltip: 'Clear move',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    trace('team.move.clear', {'member': member, 'k': k});
                    team.setMember(
                      member,
                      s.copyWith(moves: [...s.moves]..removeAt(k)),
                    );
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
    this.changes,
    this.bottom,
  });
  final String title;

  /// Below the search field, e.g. a filter toggle.
  final PreferredSizeWidget? bottom;
  final List<T> Function(String query) results;
  final Widget Function(T item, VoidCallback onTap) tile;

  /// Shown above the results when nothing is typed.
  final String? header;

  /// Re-lists the results when it notifies (e.g. a build was deleted).
  final Listenable? changes;

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
    final changes = widget.changes;
    return changes == null
        ? _page(context)
        : ListenableBuilder(listenable: changes, builder: (c, _) => _page(c));
  }

  Widget _page(BuildContext context) {
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
        bottom: widget.bottom,
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

/// Pick a build: nothing typed lists the most recently loaded first, typing
/// ranks matches by frecency, as search does. With [onDelete], rows that
/// [canDelete] allows swipe away (`build-dismiss-<id>`) after a confirmation.
class BuildPicker extends StatelessWidget {
  const BuildPicker({
    super.key,
    required this.builds,
    required this.frecency,
    required this.dex,
    this.changes,
    this.onDelete,
    this.canDelete,
  });
  final List<TeamBuild> Function() builds;
  final FrecencyScores frecency;
  final Pokedex dex;
  final Listenable? changes;
  final ValueChanged<TeamBuild>? onDelete;

  /// Which rows [onDelete] applies to; all when null.
  final bool Function(TeamBuild)? canDelete;

  Widget _tile(BuildContext context, TeamBuild b, VoidCallback onTap) {
    final tile = ListTile(
      title: Text(b.name),
      subtitle: BuildThumbs(team: b, dex: dex),
      onTap: onTap,
    );
    final delete = onDelete;
    if (delete == null || !(canDelete?.call(b) ?? true)) return tile;
    return Dismissible(
      key: Key('build-dismiss-${b.id}'),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Delete ${b.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('build-delete-confirm'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
      onDismissed: (_) {
        trace('team.build.delete', {'id': b.id});
        delete(b);
      },
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) => _Picker<TeamBuild>(
    title: 'Search builds',
    changes: changes,
    results: (q) => [
      for (final h in SearchIndex(builds()).search(q, frecency)) h.entry,
    ],
    tile: (b, onTap) => Builder(builder: (c) => _tile(c, b, onTap)),
    header: builds().isEmpty ? 'No saved builds yet' : null,
  );
}

/// A build's Pokémon as thumbnails (`build-thumb-<build id>-<slot>`), wrapping
/// onto a second line when there isn't room for all six.
class BuildThumbs extends StatelessWidget {
  const BuildThumbs({super.key, required this.team, required this.dex});
  final TeamBuild team;
  final Pokedex dex;

  @override
  Widget build(BuildContext context) => Wrap(
    children: [
      for (final (i, s) in team.slots.indexed)
        if (s != null)
          Image.asset(
            thumbPath(s.pokemon),
            key: Key('build-thumb-${team.id}-$i'),
            width: 40,
            height: 40,
            semanticLabel: dex[s.pokemon].name,
          ),
    ],
  );
}

/// Name a build to save; pops with the name, or null if cancelled. Below the
/// field, the side's saved builds (recent first, filtered by the name typed);
/// tapping one (`team-save-pick-<id>`) takes its name, to overwrite it.
class _SaveDialog extends StatefulWidget {
  const _SaveDialog({
    required this.initial,
    required this.builds,
    required this.frecency,
    required this.dex,
  });
  final String initial;
  final SavedBuilds builds;
  final FrecencyScores frecency;
  final Pokedex dex;

  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> {
  late final _name = TextEditingController(text: widget.initial);

  /// The list filters by the name only once it's typed, not when pre-filled
  /// or picked.
  var _typed = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    final overwrites = widget.builds.named(name) != null;
    void submit() => Navigator.of(context).pop(name);
    final saved = [
      for (final h in SearchIndex(
        widget.builds.builds,
      ).search(_typed ? _name.text : '', widget.frecency))
        h.entry,
    ];
    return AlertDialog(
      title: const Text('Save build'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('team-save-name'),
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Name'),
              onChanged: (_) => setState(() => _typed = true),
              onSubmitted: name.isEmpty ? null : (_) => submit(),
            ),
            if (saved.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView(
                  key: const Key('team-save-list'),
                  shrinkWrap: true,
                  children: [
                    for (final b in saved)
                      ListTile(
                        key: Key('team-save-pick-${b.id}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(b.name),
                        subtitle: BuildThumbs(team: b, dex: widget.dex),
                        selected: b.name == name,
                        onTap: () {
                          trace('team.save.pick', {'id': b.id});
                          setState(() {
                            _name.text = b.name;
                            _typed = false;
                          });
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('team-save-confirm'),
          onPressed: name.isEmpty ? null : submit,
          child: Text(overwrites ? 'Overwrite' : 'Save'),
        ),
      ],
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

/// Pick a move. With nothing typed, lists [pokemon]'s moves under a Level up |
/// All | TM toggle (All to start); typing searches every move. Moves in
/// [exclude] (already chosen) are left out.
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

  var _filter = LearnFilter.all;

  List<Move> get _learnset => [
    for (final id
        in widget.moves.learnsets[widget.pokemon]?.moveIds(_filter) ??
            const <int>[])
      if (!widget.exclude.contains(id)) widget.moves.byId[id]!,
  ];

  List<Move> _results(String q) {
    if (isRecencyQuery(q)) {
      final learnset = _learnset;
      trace('team.move_picker.learnset', {
        'filter': _filter.name,
        'count': learnset.length,
      });
      return learnset;
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
    header: _learnset.isEmpty ? 'Type to search moves' : null,
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(44),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: LearnFilterToggle(
          value: _filter,
          onChanged: (f) {
            trace('team.move_picker.filter', {'filter': f.name});
            setState(() => _filter = f);
          },
        ),
      ),
    ),
  );
}
