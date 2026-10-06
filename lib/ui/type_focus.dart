import 'package:flutter/material.dart';

import '../data/models.dart';
import '../trace.dart';
import 'type_badge.dart';
import 'type_style.dart';

enum FocusMode { attacker, defender }

class TypeFocus extends StatefulWidget {
  const TypeFocus({super.key, required this.chart});
  final TypeChart chart;

  @override
  State<TypeFocus> createState() => _TypeFocusState();
}

class _TypeFocusState extends State<TypeFocus> {
  FocusMode _mode = FocusMode.attacker;
  String? _selected;

  List<(String, List<String>)> _groups(String t) {
    final order = widget.chart.order;
    if (_mode == FocusMode.attacker) {
      final row = widget.chart.chart[t]!;
      List<String> at(double m) => [
        for (final d in order)
          if (row[d] == m) d,
      ];
      return [
        ('Super effective (2×)', at(2)),
        ('Not very effective (½×)', at(0.5)),
        ('No effect (0×)', at(0)),
      ];
    }
    final def = widget.chart.defenseFor([t]);
    List<String> at(double m) => [
      for (final a in order)
        if (def[a] == m) a,
    ];
    return [
      ('Weak to (2×)', at(2)),
      ('Resistant to (½×)', at(0.5)),
      ('Immune to (0×)', at(0)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<FocusMode>(
          key: const Key('focus-mode'),
          segments: const [
            ButtonSegment(value: FocusMode.attacker, label: Text('Attacker')),
            ButtonSegment(value: FocusMode.defender, label: Text('Defender')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) {
            trace('focus.mode', {'mode': s.single.name});
            setState(() => _mode = s.single);
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in widget.chart.order)
              ChoiceChip(
                key: Key('focus-type-$t'),
                label: Text(typeLabel(t)),
                selected: _selected == t,
                selectedColor: typeColors[t],
                onSelected: (_) {
                  trace('focus.type', {'type': t});
                  setState(() => _selected = t);
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_selected == null)
          const Text('Pick a type')
        else
          for (final (label, types) in _groups(_selected!))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  if (types.isEmpty)
                    const Text('None')
                  else
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final t in types)
                          TypeBadge(t, key: Key('focus-result-$label-$t')),
                      ],
                    ),
                ],
              ),
            ),
      ],
    );
  }
}
