import 'ability_guard.dart';

class DefenseGroup {
  const DefenseGroup(this.label, this.buckets, {this.guard});
  final String label;
  final List<(double, List<String>)> buckets;

  /// Only on 'Immune to': types blocked by a guaranteed ability.
  final AbilityGuard? guard;
}

/// Bulbapedia-style grouping of a defensive multiplier map. Empty groups are omitted.
/// Types in [guard] leave their chart bucket and are listed under 'Immune to'.
List<DefenseGroup> defenseGroups(
  Map<String, double> defense,
  List<String> order, {
  AbilityGuard? guard,
}) {
  assert(defense.length == order.length, 'defense map must cover every type');
  final guarded = guard?.types.toSet() ?? const <String>{};
  List<String> at(double m) => [
    for (final t in order)
      if (defense[t] == m && !guarded.contains(t)) t,
  ];
  final groups = <DefenseGroup>[];
  void add(String label, List<double> mults, {AbilityGuard? guard}) {
    final buckets = [
      for (final m in mults)
        if (at(m).isNotEmpty) (m, at(m)),
    ];
    if (buckets.isNotEmpty || guard != null) {
      groups.add(DefenseGroup(label, buckets, guard: guard));
    }
  }

  add('Weak to', [4.0, 2.0]);
  add('Resistant to', [0.5, 0.25]);
  add('Immune to', [0.0], guard: guard);
  return groups;
}

String multLabel(double m) => switch (m) {
  4.0 => '4×',
  2.0 => '2×',
  1.0 => '1×',
  0.5 => '½×',
  0.25 => '¼×',
  0.0 => '0×',
  _ => '$m×',
};
