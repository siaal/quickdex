import 'dart:convert';

import 'package:flutter/services.dart';

import '../search/searchable.dart';
import '../trace.dart';

enum MoveCategory { physical, special, status }

class Move implements Searchable {
  const Move({
    required this.id,
    required this.key,
    required this.name,
    required this.type,
    required this.category,
    required this.power,
    required this.accuracy,
    required this.pp,
    required this.priority,
    required this.chance,
    required this.target,
    required this.flags,
    required this.inScarlet,
    required this.text,
    required this.description,
  });

  factory Move.fromJson(Map<String, dynamic> j) => Move(
    id: j['id'] as int,
    key: j['key'] as String,
    name: j['name'] as String,
    type: j['type'] as String,
    category: MoveCategory.values.byName(j['cat'] as String),
    power: j['power'] as int?,
    accuracy: j['acc'] as int?,
    pp: j['pp'] as int?,
    priority: j['prio'] as int,
    chance: j['chance'] as int?,
    target: j['target'] as String,
    flags: (j['flags'] as List?)?.cast<String>(),
    inScarlet: j['sv'] as bool,
    text: j['text'] as String?,
    description: j['desc'] as String?,
  );

  @override
  final int id;

  /// PokéAPI identifier, e.g. `thunderbolt`.
  final String key;
  @override
  final String name;
  final String type;
  final MoveCategory category;

  /// Null when the move has no fixed power / never misses.
  final int? power;
  final int? accuracy;
  final int? pp;
  final int priority;

  /// Percent chance of the secondary effect, if any.
  final int? chance;
  final String target;

  /// Contact, Punch, Sound, …; null when PokéAPI has no flag data (Gen 9 moves).
  final List<String>? flags;
  final bool inScarlet;

  /// In-game text (Scarlet's when it has one).
  final String? text;

  /// PokéAPI's long description; may predate later mechanics changes.
  final String? description;

  @override
  int? get number => null;
}

class MoveDex {
  MoveDex(this.moves) : byId = {for (final m in moves) m.id: m};

  factory MoveDex.parse(String json) => MoveDex([
    for (final m in (jsonDecode(json) as Map<String, dynamic>)['moves'] as List)
      Move.fromJson(m as Map<String, dynamic>),
  ]);

  /// Sorted by name.
  final List<Move> moves;
  final Map<int, Move> byId;

  void assertInvariants() {
    assert(byId.length == moves.length, 'duplicate move ids');
    assert(
      moves.every((m) => m.name.isNotEmpty && (m.pp == null || m.pp! > 0)),
      'move without a name or with 0 PP',
    );
  }
}

Future<MoveDex> loadMoves(AssetBundle bundle) async {
  final sw = Stopwatch()..start();
  final moves = MoveDex.parse(
    await bundle.loadString('assets/data/moves.json'),
  );
  moves.assertInvariants();
  trace('startup.moves.done', {
    'ms': sw.elapsedMilliseconds,
    'moves': moves.moves.length,
  });
  return moves;
}
