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
/// delete it (after `deck-delete-confirm`). The last row (`deck-add`) adds one.
/// The squad count shows top right (`deck-count`). Extra selections are allowed,
/// but back navigation stays blocked until at most six remain.
class SidedeckPage extends StatelessWidget {
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: team,
    builder: (context, _) => PopScope<void>(
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
          ],
        ),
        body: FutureBuilder(
          future: moves,
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
              for (final (d, s) in team.deck.indexed)
                _row(context, d, s, snap.data),
              ListTile(
                key: const Key('deck-add'),
                leading: const SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(Icons.add, size: 32),
                ),
                title: const Text('Add Pokémon'),
                onTap: () {
                  trace('deck.add');
                  onAdd(context);
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _row(BuildContext context, int d, TeamSlot s, MoveDex? dexMoves) {
    final theme = Theme.of(context);
    final e = dex[s.pokemon];
    final inSquad = team.slotOf(d) != null;
    return Dismissible(
      key: ObjectKey(s),
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
            onEdit(context, d);
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
