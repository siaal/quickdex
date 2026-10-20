import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/moves.dart';
import '../team/team.dart';
import '../trace.dart';
import 'art.dart';
import 'category_badge.dart';
import 'type_badge.dart';

/// Every Pokémon in a team's sidedeck: tap one (`deck-row-<deck index>`) to put
/// it in or take it out of the squad, long-press to edit it, swipe it away to
/// delete it (after `deck-delete-confirm`). Header actions sort (`deck-sort`)
/// or add (`deck-add`). Row order is frozen until entry or a sort selection.
/// The squad count shows top right (`deck-count`). Extra selections are allowed,
/// but back navigation stays blocked until at most six remain.
class SidedeckPage extends StatefulWidget {
  const SidedeckPage({
    super.key,
    required this.team,
    required this.dex,
    required this.moves,
    required this.onEdit,
    required this.onAdd,
  });
  final Team team;
  final Pokedex dex;
  final Future<MoveDex> moves;
  final void Function(BuildContext context, int member) onEdit;
  final void Function(BuildContext context) onAdd;

  @override
  State<SidedeckPage> createState() => _SidedeckPageState();
}

class _SidedeckPageState extends State<SidedeckPage> {
  final _order = <int>[];
  Map<int, int> _members = {};
  Team get team => widget.team;

  @override
  void initState() {
    super.initState();
    _sort();
    team.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant SidedeckPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.team != team) {
      oldWidget.team.removeListener(_changed);
      _order.clear();
      _sort();
      team.addListener(_changed);
    }
  }

  @override
  void dispose() {
    team.removeListener(_changed);
    super.dispose();
  }

  void _sync() {
    final length = team.deck.length;
    _members = {for (var d = 0; d < length; d++) team.memberId(d): d};
    _order.removeWhere((id) => !_members.containsKey(id));
    final existing = _order.toSet();
    _order.addAll(_members.keys.where((id) => !existing.contains(id)));
    assert(_order.length == _members.length);
    assert(_order.toSet().length == _order.length);
  }

  void _changed() => setState(_sync);

  void _sort() {
    _sync();
    final deck = team.deck;
    _order.sort((a, b) {
      final i = _members[a]!;
      final j = _members[b]!;
      final left = team.slotOf(i);
      final right = team.slotOf(j);
      if ((left != null) != (right != null)) return left != null ? -1 : 1;
      final int compared;
      if (team.sidedeckSort == SidedeckSort.name) {
        compared = widget.dex[deck[i].pokemon].name.toLowerCase().compareTo(
          widget.dex[deck[j].pokemon].name.toLowerCase(),
        );
      } else if (left != null && right != null) {
        compared = left.compareTo(right);
      } else {
        compared = deck[j].lastBenched.compareTo(deck[i].lastBenched);
      }
      return compared != 0 ? compared : i.compareTo(j);
    });
    trace('deck.sort', {
      'sort': team.sidedeckSort.name,
      'count': _order.length,
    });
  }

  void _explainLegality(BuildContext context) {
    assert(!team.isLegal);
    trace('deck.leave.blocked', {'count': team.squadCount});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Choose at most 6 Pokémon before leaving Sidedeck.'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final deck = team.deck;
    return PopScope<void>(
      canPop: team.isLegal,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          trace('deck.leave.allowed', {'count': team.squadCount});
        } else if (!team.isLegal) {
          _explainLegality(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: const Text('Sidedeck'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${team.squadCount}/${Team.size}',
                key: const Key('deck-count'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            PopupMenuButton<SidedeckSort>(
              key: const Key('deck-sort'),
              tooltip: 'Sort sidedeck',
              icon: const Icon(Icons.sort),
              onSelected: (sort) {
                team.sidedeckSort = sort;
                setState(_sort);
              },
              itemBuilder: (_) => [
                for (final sort in SidedeckSort.values)
                  CheckedPopupMenuItem(
                    key: Key('deck-sort-${sort.name}'),
                    value: sort,
                    checked: team.sidedeckSort == sort,
                    child: Text(
                      sort == SidedeckSort.recency ? 'Recency' : 'Name',
                    ),
                  ),
              ],
            ),
            IconButton(
              key: const Key('deck-add'),
              tooltip: 'Add Pokémon',
              icon: const Icon(Icons.add),
              onPressed: () {
                trace('deck.add');
                widget.onAdd(context);
              },
            ),
          ],
        ),
        body: FutureBuilder(
          future: widget.moves,
          builder: (context, snap) => ListView(
            children: [
              if (!team.isLegal)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Choose at most 6 Pokémon before leaving Sidedeck.',
                    key: Key('deck-legality'),
                  ),
                ),
              for (final id in _order)
                _row(context, _members[id]!, deck[_members[id]!], snap.data),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int d, TeamSlot s, MoveDex? dexMoves) {
    final theme = Theme.of(context);
    final e = widget.dex[s.pokemon];
    final inSquad = team.slotOf(d) != null;
    return Dismissible(
      key: ValueKey(team.memberId(d)),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Delete ${e.name} from the sidedeck?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('deck-delete-confirm'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
      onDismissed: (_) {
        trace('deck.delete', {'member': d, 'pokemon': s.pokemon});
        team.remove(d);
      },
      child: Material(
        color: inSquad ? theme.colorScheme.secondaryContainer : null,
        child: InkWell(
          key: Key('deck-row-$d'),
          onTap: () {
            trace('deck.toggle', {'member': d, 'in_squad': inSquad});
            final changed = team.toggle(d, allowOverflow: true);
            assert(changed);
          },
          onLongPress: () {
            trace('deck.edit', {'member': d});
            widget.onEdit(context, d);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  thumbPath(e.id),
                  width: 56,
                  height: 56,
                  semanticLabel: e.name,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 4,
                        children: [
                          for (final t in e.types) TypeBadge(t, compact: true),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (dexMoves != null) _moves(context, s, dexMoves),
                    ],
                  ),
                ),
                Icon(
                  inSquad ? Icons.check_circle : Icons.radio_button_unchecked,
                  key: Key('deck-in-$d-$inSquad'),
                  color: inSquad ? theme.colorScheme.primary : theme.hintColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Two columns of moves: category, type icon and name; hidden ones faded;
  /// unchosen slots as "? Unknown".
  Widget _moves(BuildContext context, TeamSlot s, MoveDex dexMoves) {
    final small = Theme.of(context).textTheme.bodySmall;
    return LayoutBuilder(
      builder: (context, box) => Wrap(
        runSpacing: 2,
        children: [
          for (final id in s.moves)
            if (dexMoves.byId[id] case final m?)
              SizedBox(
                width: box.maxWidth / 2,
                child: Opacity(
                  opacity: s.hidden.contains(id) ? 0.4 : 1,
                  child: Row(
                    key: Key('deck-move-${s.pokemon}-$id'),
                    children: [
                      CategoryIcon(m.category, size: 16),
                      const SizedBox(width: 2),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Image.asset(
                          typeIconPath(m.type),
                          width: 16,
                          height: 16,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          m.name,
                          style: small,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          for (var k = s.moves.length; k < TeamSlot.maxMoves; k++)
            SizedBox(
              key: Key('deck-unknown-${s.pokemon}-$k'),
              width: box.maxWidth / 2,
              child: Row(
                children: [
                  const Icon(Icons.question_mark, size: 16),
                  const SizedBox(width: 22),
                  Text('Unknown', style: small),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
