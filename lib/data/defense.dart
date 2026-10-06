class DefenseGroup {
  const DefenseGroup(this.label, this.buckets);
  final String label;
  final List<(double, List<String>)> buckets;
}

/// Bulbapedia-style grouping of a defensive multiplier map. Empty groups are omitted.
List<DefenseGroup> defenseGroups(
  Map<String, double> defense,
  List<String> order,
) {
  assert(defense.length == order.length, 'defense map must cover every type');
  List<String> at(double m) => [
    for (final t in order)
      if (defense[t] == m) t,
  ];
  final groups = <DefenseGroup>[];
  void add(String label, List<double> mults) {
    final buckets = [
      for (final m in mults)
        if (at(m).isNotEmpty) (m, at(m)),
    ];
    if (buckets.isNotEmpty) groups.add(DefenseGroup(label, buckets));
  }

  add('Weak to', [4.0, 2.0]);
  add('Damaged normally by', [1.0]);
  add('Resistant to', [0.5, 0.25]);
  add('Immune to', [0.0]);
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
