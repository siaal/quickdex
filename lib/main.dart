import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/loader.dart';
import 'frecency/frecency.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dex = await loadPokedex(rootBundle);
  final prefs = await SharedPreferences.getInstance();
  final frecency = FrecencyStore.fromJson(
    prefs.getString(FrecencyStore.prefsKey),
    onChanged: (json) => prefs.setString(FrecencyStore.prefsKey, json),
  );
  runApp(QuickDexApp(dex: dex, frecency: frecency));
}
