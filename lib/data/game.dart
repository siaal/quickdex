import 'dart:convert';

import 'package:flutter/services.dart';

/// The game whose data bundle is loaded (`assets/data/<key>/`, one per game in
/// tool/quickdex_data/games.py).
class GameInfo {
  const GameInfo(this.key, this.name, this.gen);

  factory GameInfo.fromJson(Map<String, dynamic> j) =>
      GameInfo(j['key'] as String, j['name'] as String, j['gen'] as int);

  static const scarlet = GameInfo('scarlet', 'Scarlet', 9);

  /// Bundle directory, e.g. `emerald`.
  final String key;

  /// Display name, e.g. `Emerald` ("Not in Emerald").
  final String name;
  final int gen;

  String get dataDir => 'assets/data/$key';

  /// Prefs key for per-game state (team, frecency). Scarlet keeps the keys from
  /// before there were several games, so existing data survives.
  String prefsKey(String base) => key == scarlet.key ? base : '$base.$key';

  @override
  bool operator ==(Object other) => other is GameInfo && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'GameInfo($key)';
}

/// Every bundled game, in menu order.
Future<List<GameInfo>> loadGames(AssetBundle bundle) async => [
  for (final g
      in jsonDecode(await bundle.loadString('assets/data/games.json')) as List)
    GameInfo.fromJson(g as Map<String, dynamic>),
];
