import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/moves.dart';
import '../trace.dart';
import 'art.dart';

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

  @override
  Widget build(BuildContext context) {
    assert(moves.byId.containsKey(move.id), 'unknown move ${move.id}');
    final machines = <String>{};
    final badges = <int>{};
    final learners = <({PokemonEntry entry, String method})>[];
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
      machines.addAll(labels);
      badges.addAll(unlocks);
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
      ));
    }
    final sortedMachines = machines.toList()..sort();
    final sortedBadges = badges.toList()..sort();
    trace('move.learners.lookup', {
      'move': move.id,
      'game': moves.game.key,
      'learners': learners.length,
      'machines': machines.length,
      'badges': badges.length,
      'empty': learners.isEmpty,
      'has_machine': machines.isNotEmpty || badges.isNotEmpty,
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          'TM/HM in ${moves.game.name}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (machines.isEmpty && badges.isEmpty)
          Text('No TM/HM in ${moves.game.name}')
        else ...[
          for (final label in sortedMachines) Text(label),
          for (final n in sortedBadges)
            Text('TM: $n ${n == 1 ? 'badge' : 'badges'}'),
        ],
        const SizedBox(height: 8),
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
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text('${move.name}: learners')),
                    body: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '${moves.game.name}: level-up and TM/HM learners. Older level-up sources are labelled; egg and tutor moves are not included.',
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: learners.length,
                            itemBuilder: (context, i) {
                              final learner = learners[i];
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
                                onTap: () {
                                  trace('move.learners.select', {
                                    'move': move.id,
                                    'entry': learner.entry.id,
                                  });
                                  onOpen(learner.entry);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
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
