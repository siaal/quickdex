import 'package:flutter/material.dart';

import '../data/defense.dart';
import 'type_badge.dart';

class DefenseTable extends StatelessWidget {
  const DefenseTable({super.key, required this.defense, required this.order});
  final Map<String, double> defense;
  final List<String> order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Type defenses', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final g in defenseGroups(defense, order))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 104,
                  child: Text(g.label, style: theme.textTheme.labelLarge),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (m, types) in g.buckets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 32, child: Text(multLabel(m))),
                              Expanded(
                                child: Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    for (final t in types)
                                      TypeBadge(
                                        t,
                                        compact: true,
                                        key: Key('def-$m-$t'),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
