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
        Row(
          children: [
            SizedBox(width: 36, child: Text('Lv', style: hint)),
            const SizedBox(width: 52),
            Expanded(child: Text('Move', style: hint)),
            SizedBox(
              width: 36,
              child: Text('Pow', style: hint, textAlign: TextAlign.end),
            ),
            SizedBox(
              width: 48,
              child: Text('Acc', style: hint, textAlign: TextAlign.end),
            ),
          ],
        ),
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
            CategoryIcon(m.category),
            const SizedBox(width: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(typeIconPath(m.type), width: 20, height: 20),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(m.name)),
            SizedBox(
              width: 36,
              child: Text('${m.power ?? '—'}', textAlign: TextAlign.end),
            ),
            SizedBox(
              width: 48,
              child: Text(
                m.accuracy == null ? '—' : '${m.accuracy}%',
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
