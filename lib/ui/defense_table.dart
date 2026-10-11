import 'package:flutter/material.dart';

import '../data/ability_guard.dart';
import '../data/defense.dart';
import 'matchup_section.dart';
import 'type_badge.dart';

/// Two columns: what hits this Pokémon (defenses, keys `def-<m>-<type>` /
/// `def-guard-<type>`) and what its own types hit super-effectively (strengths,
/// keys `off-<type>`). Each multiplier is a tinted [MatchupSection].
class DefenseTable extends StatelessWidget {
  const DefenseTable({
    super.key,
    required this.defense,
    required this.coverage,
    required this.order,
    this.guard,
    this.onOpenType,
  });
  final Map<String, double> defense;

  /// Best multiplier per defending type across this Pokémon's own types.
  final Map<String, double> coverage;
  final List<String> order;
  final AbilityGuard? guard;

  /// Called with a tapped pill's type; pills aren't tappable when null.
  final ValueChanged<String>? onOpenType;

  VoidCallback? _open(String t) =>
      onOpenType == null ? null : () => onOpenType!(t);

  List<Widget> _defenses(BuildContext context) => [
    for (final g in defenseGroups(defense, order, guard: guard))
      MatchupSection(
        key: Key('def-section-${g.label}'),
        label: g.label,
        tint: matchupTint(
          extremeMultiplier([
            for (final (m, _) in g.buckets) m,
            if (g.guard != null) 0.0,
          ]),
          defending: true,
        ),
        rows: [
          for (final (m, types) in g.buckets)
            (
              multLabel(m),
              [
                for (final t in types)
                  TypeBadge(
                    t,
                    compact: true,
                    key: Key('def-$m-$t'),
                    onTap: _open(t),
                  ),
              ],
            ),
          if (g.guard case final guard?)
            (
              multLabel(0),
              [
                for (final t in guard.types)
                  TypeBadge(
                    t,
                    compact: true,
                    key: Key('def-guard-$t'),
                    onTap: _open(t),
                  ),
                Text(
                  '(${guard.ability})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
        ],
      ),
  ];

  @override
  Widget build(BuildContext context) {
    assert(coverage.length == order.length, 'coverage must cover every type');
    final theme = Theme.of(context);
    final strong = [
      for (final t in order)
        if (coverage[t] == 2) t,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                key: const Key('defense-column'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Type defenses', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ..._defenses(context),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                key: const Key('strength-column'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Strengths', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  MatchupSection(
                    key: const Key('off-section'),
                    label: 'Super effective',
                    tint: matchupTint(2, defending: false),
                    rows: [
                      if (strong.isNotEmpty)
                        (
                          multLabel(2),
                          [
                            for (final t in strong)
                              TypeBadge(
                                t,
                                compact: true,
                                key: Key('off-$t'),
                                onTap: _open(t),
                              ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
