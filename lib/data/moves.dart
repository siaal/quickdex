import 'dart:convert';

import 'package:flutter/services.dart';

import '../search/searchable.dart';
import '../trace.dart';
import 'game.dart';

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
    required this.contact,
    required this.flags,
    required this.inGame,
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
    contact: j['contact'] as bool,
    flags: (j['flags'] as List).cast<String>(),
    inGame: j['in_game'] as bool,
    text: j['text'] as String?,
    description: j['desc'] as String?,
  );

  @override
  final int id;

  /// PokéAPI identifier, e.g. `thunderbolt`.
  final String key;
  @override
  final String name;

  /// `unknown` is the ??? type (Curse before Gen 5).
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

  final bool contact;

  /// Punch, Sound, Dance, …; contact is [contact].
  final List<String> flags;

  /// Whether any Pokémon learns it in the loaded game (else tagged "Not in …").
  final bool inGame;

  /// In-game text (the loaded game's when it has one).
  final String? text;

  /// PokéAPI's long description; may predate later mechanics changes. For an
  /// old game it starts with an "In Emerald:"-style paragraph of differences.
  final String? description;

  @override
  List<int> get numbers => const [];
}

/// Level-up moves of one Pokémon entry, in level order; level 0 = on evolution.
/// Games whose TMs unlock by badge (Scrambled Scarlet) also list [tms].
/// Which of a learnset's moves to show.
enum LearnFilter { levelUp, all, tm }

class Learnset {
  const Learnset(
    this.game,
    this.moves, [
    this.tms = const [],
    this.machines = const [],
  ]);

  factory Learnset.fromJson(Map<String, dynamic> j) => Learnset(
    j['game'] as String?,
    [
      for (final m in (j['moves'] as List).cast<List<dynamic>>())
        (level: m[0] as int, move: m[1] as int),
    ],
    [
      for (final m in ((j['tms'] as List?) ?? const []).cast<List<dynamic>>())
        (badges: m[0] as int, move: m[1] as int),
    ],
    [
      for (final m
          in ((j['machines'] as List?) ?? const []).cast<List<dynamic>>())
        (label: m[0] as String, move: m[1] as int),
    ],
  );

  /// Null for the loaded game; otherwise the older game the data comes from.
  final String? game;
  final List<({int level, int move})> moves;

  /// TM moves by the badge count that unlocks them, fewest badges first.
  final List<({int badges, int move})> tms;

  /// Vanilla TMs/HMs in number order, labelled e.g. 'TM034' or 'HM05'.
  final List<({String label, int move})> machines;

  /// Move ids under [filter]: level-up in level order, then TMs; no repeats.
  List<int> moveIds(LearnFilter filter) => {
    if (filter != LearnFilter.tm) ...[for (final m in moves) m.move],
    if (filter != LearnFilter.levelUp) ...[
      for (final m in tms) m.move,
      for (final m in machines) m.move,
    ],
  }.toList();
}

class MoveDex {
  MoveDex(this.moves, [this.learnsets = const {}, this.game = GameInfo.scarlet])
    : byId = {for (final m in moves) m.id: m};

  factory MoveDex.parse(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return MoveDex(
      [
        for (final m in j['moves'] as List)
          Move.fromJson(m as Map<String, dynamic>),
      ],
      {
        for (final e in (j['learnsets'] as Map<String, dynamic>).entries)
          int.parse(e.key): Learnset.fromJson(e.value as Map<String, dynamic>),
      },
      GameInfo.fromJson(j['game'] as Map<String, dynamic>),
    );
  }

  final GameInfo game;

  /// Sorted by name.
  final List<Move> moves;
  final Map<int, Move> byId;

  /// Keyed by Pokémon entry id.
  final Map<int, Learnset> learnsets;

  void assertInvariants() {
    assert(byId.length == moves.length, 'duplicate move ids');
    assert(
      moves.every((m) => m.name.isNotEmpty && (m.pp == null || m.pp! > 0)),
      'move without a name or with 0 PP',
    );
    assert(
      learnsets.values.every(
        (l) => l.moves.every((m) => byId.containsKey(m.move)),
      ),
      'learnset refers to an unknown move',
    );
  }
}

Future<MoveDex> loadMoves(
  AssetBundle bundle, [
  GameInfo game = GameInfo.scarlet,
]) async {
  final sw = Stopwatch()..start();
  final moves = MoveDex.parse(
    await bundle.loadString('${game.dataDir}/moves.json'),
  );
  moves.assertInvariants();
  assert(moves.game == game, 'loaded ${moves.game} for $game');
  trace('startup.moves.done', {
    'game': game.key,
    'ms': sw.elapsedMilliseconds,
    'moves': moves.moves.length,
  });
  return moves;
}
