import 'package:flutter/material.dart';

import '../data/models.dart';
import '../frecency/frecency.dart';
import '../search/search_index.dart';
import '../trace.dart';
import 'lookup_screen.dart';
import 'type_chart_screen.dart';

class QuickDexApp extends StatelessWidget {
  const QuickDexApp({super.key, required this.dex, required this.frecency});
  final Pokedex dex;
  final FrecencyStore frecency;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'QuickDex',
    theme: ThemeData(colorSchemeSeed: Colors.red, brightness: Brightness.light),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.red,
      brightness: Brightness.dark,
    ),
    themeMode: ThemeMode.system,
    home: HomeShell(dex: dex, frecency: frecency),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.dex, required this.frecency});
  final Pokedex dex;
  final FrecencyStore frecency;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final _index = SearchIndex(widget.dex.entries);
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _tab,
      children: [
        LookupScreen(dex: widget.dex, frecency: widget.frecency, index: _index),
        TypeChartScreen(chart: widget.dex.types),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) {
        trace('shell.tab.select', {'tab': i});
        setState(() => _tab = i);
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.search), label: 'Lookup'),
        NavigationDestination(icon: Icon(Icons.grid_on), label: 'Type Chart'),
      ],
    ),
  );
}
