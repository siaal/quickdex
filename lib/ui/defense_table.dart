import 'package:flutter/material.dart';

import '../data/ability_guard.dart';
import '../data/defense.dart';
import 'matchup_section.dart';
import 'type_badge.dart';

/// Two columns: what hits this Pokémon (defenses, keys `def-<m>-<type>` /
/// `def-guard-<type>`) and how well it hits (strengths, keys `off-<type>`):
/// super effective, then (with [neutral]) 1× (`off-section-neutral`), then
/// the types it is resisted by (`off-section-weak`) or can't touch
/// (`off-section-none`), shown only when non-empty. Each multiplier is a
/// tinted [MatchupSection].
class DefenseTable extends StatelessWidget {
  const DefenseTable({
    super.key,
    required this.defense,
    required this.coverage,
    required this.order,
    this.guard,
    this.onOpenType,
    this.neutral = false,
  });
  final Map<String, double> defense;

  /// Best multiplier per defending type of what it attacks with (e.g. its own
  /// types). Null when it has no damaging attack (`off-no-damage`).
  final Map<String, double>? coverage;

  /// Also list 1× types, in both columns (`def-section-Neutral`).
  final bool neutral;
  final List<String> order;
  final AbilityGuard? guard;

  /// Called with a tapped pill's type; pills aren't tappable when null.
  final ValueChanged<String>? onOpenType;

  VoidCallback? _open(String t) =>
      onOpenType == null ? null : () => onOpenType!(t);

  List<Widget> _defenses(BuildContext context) => [
    for (final g in defenseGroups(
      defense,
      order,
      guard: guard,
      neutral: neutral,
    ))
      MatchupSection(
        key: Key('def-section-${g.label}'),
        label: g.label,
        tint: _tint(
          context,
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

  /// [matchupTint], except 1× (transparent there) gets a faint neutral fill
  /// so its section still reads as one.
  static Color _tint(
    BuildContext context,
    double m, {
    required bool defending,
  }) => m == 1
      ? Theme.of(context).colorScheme.surfaceContainerHighest
      : matchupTint(m, defending: defending);

  List<String> _hitAt(Map<String, double> coverage, double m) => [
    for (final t in order)
      if (coverage[t] == m) t,
  ];

  /// Strength sections; super effective is always shown, the rest only when
  /// non-empty. 4× and ¼× only arise from multi-type attacks such as Flying
  /// Press.
  List<Widget> _strengths(BuildContext context, Map<String, double> coverage) {
    assert(coverage.length == order.length, 'coverage must cover every type');
    return [
      for (final (key, label, mults) in [
        ('off-section', 'Super effective', const [4.0, 2.0]),
        if (neutral) ('off-section-neutral', 'Neutral', const [1.0]),
        ('off-section-weak', 'Not very effective', const [0.5, 0.25]),
        ('off-section-none', 'No effect', const [0.0]),
      ])
        if (key == 'off-section' ||
            mults.any((m) => _hitAt(coverage, m).isNotEmpty))
          MatchupSection(
            key: Key(key),
            label: label,
            tint: _tint(
              context,
              extremeMultiplier([
                for (final m in mults)
                  if (_hitAt(coverage, m).isNotEmpty) m,
                if (key == 'off-section') 2.0,
              ]),
              defending: false,
            ),
            rows: [
              for (final m in mults)
                if (_hitAt(coverage, m) case final types when types.isNotEmpty)
                  (
                    multLabel(m),
                    [
                      for (final t in types)
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
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverage = this.coverage;
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
                  if (coverage == null)
                    const Text('No damaging moves', key: Key('off-no-damage'))
                  else
                    ..._strengths(context, coverage),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
