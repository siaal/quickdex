import 'package:flutter/material.dart';

import '../data/models.dart';
import '../trace.dart';

/// One line of tappable ability names; the hidden ability is marked `(H)`.
class AbilityLine extends StatelessWidget {
  const AbilityLine({super.key, required this.entry, required this.abilities});
  final PokemonEntry entry;
  final Map<int, Ability> abilities;

  void _explain(BuildContext context, int id, bool hidden) {
    final a = abilities[id]!;
    final showLong = a.description.isNotEmpty && a.description != a.effect;
    trace('page.ability.open', {
      'entry': entry.id,
      'ability': a.key,
      'long': showLong,
    });
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(a.name),
        scrollable: true, // long descriptions run to ~1500 chars
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hidden) ...[
              Text(
                'Hidden ability',
                style: Theme.of(dialogContext).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
            ],
            Text(a.effect, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (showLong) ...[const SizedBox(height: 12), Text(a.description)],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = [
      for (final id in entry.abilities) (id, false),
      if (entry.hidden case final h?) (h, true),
    ];
    final link = theme.textTheme.bodyMedium?.copyWith(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
    );
    // Scales down rather than wrapping so the header never grows.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          for (final (i, (id, hidden)) in items.indexed) ...[
            if (i > 0) Text('  ·  ', style: theme.textTheme.bodyMedium),
            InkWell(
              key: Key('ability-$id'),
              onTap: () => _explain(context, id, hidden),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  hidden ? '${abilities[id]!.name} (H)' : abilities[id]!.name,
                  style: hidden
                      ? link?.copyWith(fontStyle: FontStyle.italic)
                      : link,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
