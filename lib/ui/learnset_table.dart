import 'package:flutter/material.dart';

import '../data/moves.dart';
import '../trace.dart';
import 'art.dart';
import 'category_badge.dart';

/// Level-up moves; tapping one calls [onOpen]. Row keys: `learn-<level>-<move id>`.
class LearnsetTable extends StatelessWidget {
  const LearnsetTable({
    super.key,
    required this.learnset,
    required this.moves,
    required this.onOpen,
  });
  final Learnset learnset;
  final MoveDex moves;
  final ValueChanged<Move> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);
    return Column(
      key: const Key('learnset'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Level-up moves', style: theme.textTheme.titleMedium),
        if (learnset.game case final game?)
          Text('From $game', key: const Key('learnset-game'), style: hint),
        const SizedBox(height: 4),
        for (final (:level, :move) in learnset.moves)
          _row(context, level, move),
      ],
    );
  }

  Widget _row(BuildContext context, int level, int moveId) {
    final m = moves.byId[moveId]!;
    return InkWell(
      key: Key('learn-$level-$moveId'),
      onTap: () {
        trace('learnset.open', {'move': moveId, 'level': level});
        onOpen(m);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 36, child: Text(level == 0 ? 'Evo' : '$level')),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(typeIconPath(m.type), width: 20, height: 20),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(m.name)),
            CategoryBadge(m.category, compact: true),
            SizedBox(
              width: 40,
              child: Text('${m.power ?? '—'}', textAlign: TextAlign.end),
            ),
          ],
        ),
      ),
    );
  }
}
