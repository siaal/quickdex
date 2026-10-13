import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/game.dart';
import 'ui/game_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final (prefs, games) = await (
    SharedPreferences.getInstance(),
    loadGames(rootBundle),
  ).wait;
  final session = await GameSession.load(
    rootBundle,
    prefs,
    savedGame(prefs, games),
  );
  runApp(GameHost(prefs: prefs, games: games, initial: session));
}
