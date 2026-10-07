import 'dart:convert';

class PokemonEntry {
  const PokemonEntry({
    required this.id,
    required this.dex,
    required this.name,
    required this.species,
    required this.form,
    required this.types,
    required this.stats,
    required this.forms,
    required this.chain,
    required this.defense,
  });

  /// `defenseFor` maps a type list to its defensive multipliers (derived from the chart
  /// at load, not stored in the JSON, to keep startup parsing small).
  factory PokemonEntry.fromJson(
    Map<String, dynamic> j,
    Map<String, double> Function(List<String> types) defenseFor,
  ) {
    final types = (j['types'] as List).cast<String>();
    return PokemonEntry(
      id: j['id'] as int,
      dex: j['dex'] as int,
      name: j['name'] as String,
      species: j['species'] as String,
      form: j['form'] as String?,
      types: types,
      stats: (j['stats'] as List).cast<int>(),
      forms: (j['forms'] as List).cast<int>(),
      chain: j['chain'] as int,
      defense: defenseFor(types),
    );
  }

  final int id;
  final int dex;
  final String name;
  final String species;
  final String? form;
  final List<String> types;
  final List<int> stats;
  final List<int> forms;
  final int chain;
  final Map<String, double> defense;

  String get chipLabel => form ?? species;
  String get dexLabel => '#${dex.toString().padLeft(3, '0')}';
  int get total => stats.fold(0, (a, b) => a + b);
}

class EvoEdge {
  const EvoEdge(this.from, this.to, this.method);
  final int from;
  final int to;
  final String method;
}

class EvoChain {
  const EvoChain(this.roots, this.edges);

  factory EvoChain.fromJson(Map<String, dynamic> j) =>
      EvoChain((j['roots'] as List).cast<int>(), [
        for (final e in (j['edges'] as List).cast<Map<String, dynamic>>())
          EvoEdge(e['from'] as int, e['to'] as int, e['method'] as String),
      ]);

  final List<int> roots;
  final List<EvoEdge> edges;

  List<EvoEdge> from(int id) => [
    for (final e in edges)
      if (e.from == id) e,
  ];
}

class TypeChart {
  const TypeChart(this.order, this.chart);

  factory TypeChart.fromJson(Map<String, dynamic> j) => TypeChart(
    (j['order'] as List).cast<String>(),
    (j['chart'] as Map<String, dynamic>).map(
      (atk, row) => MapEntry(
        atk,
        (row as Map<String, dynamic>).map(
          (def, m) => MapEntry(def, (m as num).toDouble()),
        ),
      ),
    ),
  );

  final List<String> order;
  final Map<String, Map<String, double>> chart;

  double multiplier(String attacker, String defender) =>
      chart[attacker]![defender]!;

  Map<String, double> defenseFor(List<String> types) {
    assert(
      types.isNotEmpty && types.length <= 2,
      'defenseFor expects 1-2 types: $types',
    );
    return {
      for (final a in order) a: types.fold(1.0, (m, d) => m * multiplier(a, d)),
    };
  }
}

class Pokedex {
  Pokedex({required this.entries, required this.chains, required this.types})
    : byId = {for (final e in entries) e.id: e};

  factory Pokedex.parse(String pokedexJson, String typesJson) {
    final dex = jsonDecode(pokedexJson) as Map<String, dynamic>;
    final types = TypeChart.fromJson(
      jsonDecode(typesJson) as Map<String, dynamic>,
    );
    // Entries sharing a typing share one (read-only) defence map.
    final defenseCache = <String, Map<String, double>>{};
    Map<String, double> defenseFor(List<String> t) =>
        defenseCache.putIfAbsent(t.join('/'), () => types.defenseFor(t));
    return Pokedex(
      entries: [
        for (final e in (dex['entries'] as List).cast<Map<String, dynamic>>())
          PokemonEntry.fromJson(e, defenseFor),
      ],
      chains: (dex['chains'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(
          int.parse(k),
          EvoChain.fromJson(v as Map<String, dynamic>),
        ),
      ),
      types: types,
    );
  }

  final List<PokemonEntry> entries;
  final Map<int, PokemonEntry> byId;
  final Map<int, EvoChain> chains;
  final TypeChart types;

  PokemonEntry operator [](int id) => byId[id]!;

  EvoChain? chainFor(PokemonEntry e) => chains[e.chain];

  /// Bundled data is build-generated; a violation here is a pipeline bug.
  void assertInvariants() {
    assert(() {
      assert(byId.length == entries.length, 'duplicate entry ids');
      assert(types.order.length == 18, 'expected 18 types');
      for (final e in entries) {
        assert(e.forms.contains(e.id), '${e.name}: forms must include itself');
        assert(e.forms.every(byId.containsKey), '${e.name}: unknown form id');
        assert(e.defense.length == 18, '${e.name}: defense must have 18 keys');
        assert(e.stats.length == 6, '${e.name}: expected 6 stats');
      }
      for (final c in chains.values) {
        for (final edge in c.edges) {
          assert(
            byId.containsKey(edge.from) && byId.containsKey(edge.to),
            'unknown chain node',
          );
        }
      }
      return true;
    }());
  }
}
