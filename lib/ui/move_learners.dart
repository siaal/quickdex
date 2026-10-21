import 'package:flutter/material.dart';

import '../data/game.dart';
import '../data/models.dart';
import '../data/moves.dart';
import '../search/normalise.dart';
import '../trace.dart';
import 'art.dart';
import 'learnset_table.dart';

typedef _Learner = ({
  PokemonEntry entry,
  String method,
  bool byLevel,
  bool byTm,
});

/// The move's TM/HM in the loaded game ("TM220", Scrambled's "TM: 3 badges"),
/// or null when it has none.
String? machineLabel(Move move, MoveDex moves) {
  final labels = <String>{};
  final badges = <int>{};
  for (final l in moves.learnsets.values) {
    for (final m in l.machines) {
      if (m.move == move.id) labels.add(m.label);
    }
    for (final m in l.tms) {
      if (m.move == move.id) badges.add(m.badges);
    }
  }
  // Scrambled's sheet can list one TM at different badge counts per Pokémon.
  final sorted = badges.toList()..sort();
  final parts = [
    ...labels.toList()..sort(),
    if (sorted.isNotEmpty)
      sorted.length == 1
          ? 'TM: ${sorted.single} ${sorted.single == 1 ? 'badge' : 'badges'}'
          : 'TM: ${sorted.first}\u2013${sorted.last} badges',
  ];
  trace('move.machine_label', {'move': move.id, 'count': parts.length});
  return parts.isEmpty ? null : parts.join(', ');
}

/// Reverse lookup over the loaded game's level-up and TM/HM learnsets.
/// Fallback level-up sources stay labelled; no breeding/tutor data is bundled.
class MoveLearners extends StatelessWidget {
  const MoveLearners({
    super.key,
    required this.move,
    required this.moves,
    required this.dex,
    required this.onOpen,
  });

  final Move move;
  final MoveDex moves;
  final Pokedex dex;
  final ValueChanged<PokemonEntry> onOpen;

  /// The learners page's Level up | All | TM choice per game, until restart.
  static final _chosen = <String, LearnFilter>{};

  @visibleForTesting
  static void resetFilters() => _chosen.clear();

  @override
  Widget build(BuildContext context) {
    assert(moves.byId.containsKey(move.id), 'unknown move ${move.id}');
    final learners = <_Learner>[];
    // Dex order, including the retained alternate forms, one row per entry.
    for (final entry in dex.entries) {
      final learnset = moves.learnsets[entry.id];
      if (learnset == null) continue;
      final levels = {
        for (final m in learnset.moves)
          if (m.move == move.id) m.level,
      }.toList()..sort();
      final labels = {
        for (final m in learnset.machines)
          if (m.move == move.id) m.label,
      }.toList()..sort();
      final unlocks = {
        for (final m in learnset.tms)
          if (m.move == move.id) m.badges,
      }.toList()..sort();
      if (levels.isEmpty && labels.isEmpty && unlocks.isEmpty) continue;
      learners.add((
        entry: entry,
        method: [
          if (levels.contains(0)) 'On evolution',
          if (levels.any((l) => l > 0))
            'Lv ${levels.where((l) => l > 0).join(', ')}',
          ...labels,
          for (final n in unlocks) 'TM: $n ${n == 1 ? 'badge' : 'badges'}',
          if (learnset.game case final source?) 'From $source',
        ].join(' · '),
        byLevel: levels.isNotEmpty,
        byTm: labels.isNotEmpty || unlocks.isNotEmpty,
      ));
    }
    trace('move.learners.lookup', {
      'move': move.id,
      'game': moves.game.key,
      'learners': learners.length,
      'empty': learners.isEmpty,
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        if (learners.isEmpty)
          const Text('No known learners')
        else
          OutlinedButton(
            key: const Key('move-learners'),
            onPressed: () {
              trace('move.learners.open', {
                'move': move.id,
                'count': learners.length,
              });
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _LearnersPage(
                    move: move,
                    game: moves.game,
                    learners: learners,
                    onOpen: onOpen,
                  ),
                ),
              );
            },
            child: Text('Who can learn it? (${learners.length})'),
          ),
      ],
    );
  }
}

/// Learners with a name search (`learners-search`, unfocused on open) and a
/// Level up | All | TM toggle remembered per game.
class _LearnersPage extends StatefulWidget {
  const _LearnersPage({
    required this.move,
    required this.game,
    required this.learners,
    required this.onOpen,
  });
  final Move move;
  final GameInfo game;
  final List<_Learner> learners;
  final ValueChanged<PokemonEntry> onOpen;

  @override
  State<_LearnersPage> createState() => _LearnersPageState();
}

class _LearnersPageState extends State<_LearnersPage> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  late LearnFilter _filter =
      MoveLearners._chosen[widget.game.key] ?? LearnFilter.all;

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<_Learner> _shown() {
    final q = normalise(_query.text);
    return [
      for (final l in widget.learners)
        if (switch (_filter) {
              LearnFilter.levelUp => l.byLevel,
              LearnFilter.tm => l.byTm,
              LearnFilter.all => true,
            } &&
            (q.isEmpty || normalise(l.entry.name).contains(q)))
          l,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown();
    trace('move.learners.shown', {
      'move': widget.move.id,
      'filter': _filter.name,
      'query_len': _query.text.length,
      'count': shown.length,
    });
    return Scaffold(
      appBar: AppBar(title: Text('${widget.move.name}: learners')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              key: const Key('learners-search'),
              controller: _query,
              focusNode: _focus,
              decoration: const InputDecoration(
                hintText: 'Filter by name',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (shown.isEmpty) {
                  trace('move.learners.submit.empty');
                  return;
                }
                _open(shown.first);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Center(
              child: LearnFilterToggle(
                value: _filter,
                onChanged: (f) {
                  trace('move.learners.filter', {'filter': f.name});
                  _focus.unfocus();
                  setState(() {
                    _filter = f;
                    MoveLearners._chosen[widget.game.key] = f;
                  });
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${widget.game.name}: level-up and TM/HM learners. Older level-up '
              'sources are labelled; egg and tutor moves are not included.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No matching Pokémon',
                      key: Key('learners-none'),
                    ),
                  )
                : ListView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final learner = shown[i];
                      return ListTile(
                        key: Key('move-learner-${learner.entry.id}'),
                        leading: Image.asset(
                          thumbPath(learner.entry.id),
                          width: 48,
                          height: 48,
                        ),
                        title: Text(learner.entry.name),
                        subtitle: Text(learner.method),
                        trailing: Text(learner.entry.dexLabel),
                        onTap: () => _open(learner),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _open(_Learner learner) {
    trace('move.learners.select', {
      'move': widget.move.id,
      'entry': learner.entry.id,
    });
    widget.onOpen(learner.entry);
  }
}
