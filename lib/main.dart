import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/loader.dart';
import 'data/moves.dart';
import 'frecency/frecency.dart';
import 'ui/app.dart';
import 'ui/search_screen.dart';

const _modeKey = 'search.mode';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Not awaited: move results and learnsets appear once loaded.
  final moves = loadMoves(rootBundle);
  final dex = await loadPokedex(rootBundle);
  final prefs = await SharedPreferences.getInstance();
  FrecencyStore store(String key) => FrecencyStore.fromJson(
    prefs.getString(key),
    onChanged: (json) => prefs.setString(key, json),
  );
  runApp(
    QuickDexApp(
      dex: dex,
      frecency: store(FrecencyStore.prefsKey),
      moves: moves,
      moveFrecency: store(FrecencyStore.movesPrefsKey),
      initialSearchMode:
          SearchMode.values.asNameMap()[prefs.getString(_modeKey)] ??
          SearchMode.all,
      onSearchModeChanged: (m) => prefs.setString(_modeKey, m.name),
    ),
  );
}
