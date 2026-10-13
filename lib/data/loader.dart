import 'package:flutter/services.dart';

import '../trace.dart';
import 'game.dart';
import 'models.dart';

Future<Pokedex> loadPokedex(
  AssetBundle bundle, [
  GameInfo game = GameInfo.scarlet,
]) async {
  final sw = Stopwatch()..start();
  final dexJson = await bundle.loadString('${game.dataDir}/pokedex.json');
  final typesJson = await bundle.loadString('${game.dataDir}/types.json');
  final dex = Pokedex.parse(dexJson, typesJson);
  dex.assertInvariants();
  assert(dex.game == game, 'loaded ${dex.game} for $game');
  trace('startup.load.done', {
    'game': game.key,
    'ms': sw.elapsedMilliseconds,
    'entries': dex.entries.length,
  });
  return dex;
}
