import 'dart:convert';

import '../search/searchable.dart';
import 'ability_guard.dart';

class Ability {
  const Ability(this.key, this.name, this.effect, [this.description = '']);

  factory Ability.fromJson(Map<String, dynamic> j) => Ability(
    j['key'] as String,
    j['name'] as String,
    j['effect'] as String,
    j['description'] as String,
  );

  /// PokéAPI identifier, e.g. `levitate`.
  final String key;
  final String name;

  /// One-line summary.
  final String effect;

  /// PokéAPI's long effect text; paragraphs separated by blank lines. Written
  /// around Gen 5–6, so may miss later mechanics changes.
  final String description;
}

class PokemonEntry implements Searchable {
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
    this.abilities = const [],
    this.hidden,
    this.catchRate = 0,
    this.weight = 0,
    this.guard,
    this.region,
  });

  /// `defenseFor` maps a type list to its defensive multipliers (derived from the chart
  /// at load, not stored in the JSON, to keep startup parsing small).
  /// `guardFor` derives the guaranteed ability immunity (see ability_guard.dart).
  factory PokemonEntry.fromJson(
    Map<String, dynamic> j,
    Map<String, double> Function(List<String> types) defenseFor,
    AbilityGuard? Function(List<int> abilityIds, Map<String, double> defense)
    guardFor,
  ) {
    final types = (j['types'] as List).cast<String>();
    final abilities = (j['abilities'] as List).cast<int>();
    final hidden = j['hidden'] as int?;
    final defense = defenseFor(types);
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
      defense: defense,
      abilities: abilities,
      hidden: hidden,
      catchRate: j['catch'] as int,
      weight: j['weight'] as int,
      guard: guardFor([...abilities, ?hidden], defense),
      region: switch (j['region']) {
        [final String name, final int number] => (name: name, number: number),
        _ => null,
      },
    );
  }

  @override
  final int id;
  final int dex;
  @override
  final String name;
  final String species;
  final String? form;
  final List<String> types;
  final List<int> stats;
  final List<int> forms;
  final int chain;
  final Map<String, double> defense;

  /// Non-hidden ability ids in slot order.
  final List<int> abilities;
  final int? hidden;
  final int catchRate;

  /// Hectograms, as PokéAPI stores it.
  final int weight;

  /// Immunity granted by every ability this entry can have, if any.
  final AbilityGuard? guard;

  /// Scarlet's in-game dex (Paldea, then Kitakami, then Blueberry); null if the
  /// species is in none of them.
  final ({String name, int number})? region;

  double get weightKg => weight / 10;
  String get chipLabel => form ?? species;
  @override
  List<int> get numbers => [dex, ?region?.number];

  /// e.g. "Paldea #074 · #025"; just the national "#063" if not in Scarlet.
  String get dexLabel {
    String pad(int n) => '#${n.toString().padLeft(3, '0')}';
    final r = region;
    return r == null ? pad(dex) : '${r.name} ${pad(r.number)} · ${pad(dex)}';
  }

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
  Pokedex({
    required this.entries,
    required this.chains,
    required this.types,
    this.abilities = const {},
  }) : byId = {for (final e in entries) e.id: e};

  factory Pokedex.parse(String pokedexJson, String typesJson) {
    final dex = jsonDecode(pokedexJson) as Map<String, dynamic>;
    final types = TypeChart.fromJson(
      jsonDecode(typesJson) as Map<String, dynamic>,
    );
    final abilities = (dex['abilities'] as Map<String, dynamic>).map(
      (k, v) =>
          MapEntry(int.parse(k), Ability.fromJson(v as Map<String, dynamic>)),
    );
    AbilityGuard? guardFor(List<int> ids, Map<String, double> defense) =>
        guaranteedGuard([for (final a in ids) abilities[a]!], defense);
    // Entries sharing a typing share one (read-only) defence map.
    final defenseCache = <String, Map<String, double>>{};
    Map<String, double> defenseFor(List<String> t) =>
        defenseCache.putIfAbsent(t.join('/'), () => types.defenseFor(t));
    return Pokedex(
      entries: [
        for (final e in (dex['entries'] as List).cast<Map<String, dynamic>>())
          PokemonEntry.fromJson(e, defenseFor, guardFor),
      ],
      abilities: abilities,
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
  final Map<int, Ability> abilities;

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
        assert(e.abilities.isNotEmpty, '${e.name}: no abilities');
        assert(
          [...e.abilities, ?e.hidden].every(abilities.containsKey),
          '${e.name}: unknown ability id',
        );
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
