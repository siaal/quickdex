import 'package:flutter/material.dart';

import '../data/moves.dart';
import '../frecency/frecency.dart';
import '../trace.dart';
import 'category_badge.dart';
import 'type_badge.dart';

class MovePage extends StatefulWidget {
  const MovePage({super.key, required this.move, required this.frecency});
  final Move move;
  final FrecencyStore frecency;

  @override
  State<MovePage> createState() => _MovePageState();
}

class _MovePageState extends State<MovePage> {
  @override
  void initState() {
    super.initState();
    // Unlike Pokémon pages there are no forms to switch, so credit on open.
    widget.frecency.visit(widget.move.id);
    trace('move.page.open', {'id': widget.move.id});
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.move;
    final theme = Theme.of(context);
    final stats = [
      ('Power', m.power?.toString() ?? '—'),
      ('Accuracy', m.accuracy == null ? '—' : '${m.accuracy}%'),
      ('PP', m.pp?.toString() ?? '—'),
      if (m.priority != 0)
        ('Priority', m.priority > 0 ? '+${m.priority}' : '${m.priority}'),
      if (m.chance != null) ('Effect', '${m.chance}%'),
    ];
    final properties = [
      m.target,
      ...?m.flags,
      if (m.flags == null) 'contact unknown',
    ].join(' · ');
    return Scaffold(
      appBar: AppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              m.name,
              key: const Key('move-name'),
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                TypeBadge(m.type),
                CategoryBadge(m.category),
                if (!m.inScarlet)
                  Container(
                    key: const Key('move-not-sv'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.hintColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Not in Scarlet',
                      style: TextStyle(color: theme.hintColor),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final (label, value) in stats)
                  Expanded(
                    key: Key('move-stat-$label'),
                    child: Column(
                      children: [
                        Text(label, style: theme.textTheme.labelSmall),
                        Text(value, style: theme.textTheme.titleLarge),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              properties,
              key: const Key('move-properties'),
              style: theme.textTheme.bodyMedium,
            ),
            if (m.text case final text?) ...[
              const SizedBox(height: 16),
              Text(
                text,
                key: const Key('move-text'),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (m.description case final desc?) ...[
              const SizedBox(height: 16),
              Text(desc, key: const Key('move-desc')),
            ],
          ],
        ),
      ),
    );
  }
}
