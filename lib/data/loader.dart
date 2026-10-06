import 'package:flutter/services.dart';

import '../trace.dart';
import 'models.dart';

Future<Pokedex> loadPokedex(AssetBundle bundle) async {
  final sw = Stopwatch()..start();
  final dexJson = await bundle.loadString('assets/data/pokedex.json');
  final typesJson = await bundle.loadString('assets/data/types.json');
  final dex = Pokedex.parse(dexJson, typesJson);
  dex.assertInvariants();
  trace('startup.load.done', {
    'ms': sw.elapsedMilliseconds,
    'entries': dex.entries.length,
  });
  return dex;
}
