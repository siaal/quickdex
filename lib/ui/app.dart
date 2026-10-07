import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/moves.dart';
import '../frecency/frecency.dart';
import '../search/search_index.dart';
import '../trace.dart';
import 'lookup_screen.dart';
import 'moves_screen.dart';
import 'type_chart_screen.dart';

class QuickDexApp extends StatelessWidget {
  const QuickDexApp({
    super.key,
    required this.dex,
    required this.frecency,
    required this.moves,
    required this.moveFrecency,
  });
  final Pokedex dex;
  final FrecencyStore frecency;

  /// Loaded in the background so it doesn't delay startup.
  final Future<MoveDex> moves;
  final FrecencyStore moveFrecency;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'QuickDex',
    theme: ThemeData(colorSchemeSeed: Colors.red, brightness: Brightness.light),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.red,
      brightness: Brightness.dark,
    ),
    themeMode: ThemeMode.system,
    home: HomeShell(
      dex: dex,
      frecency: frecency,
      moves: moves,
      moveFrecency: moveFrecency,
    ),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.dex,
    required this.frecency,
    required this.moves,
    required this.moveFrecency,
  });
  final Pokedex dex;
  final FrecencyStore frecency;
  final Future<MoveDex> moves;
  final FrecencyStore moveFrecency;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _movesTab = 1;
  late final _index = SearchIndex(widget.dex.entries);
  int _tab = 0;

  /// The Moves tab is built on first visit, so its autofocusing search field
  /// doesn't steal focus from Lookup at launch.
  bool _movesVisited = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _tab,
      children: [
        LookupScreen(dex: widget.dex, frecency: widget.frecency, index: _index),
        if (_movesVisited)
          FutureBuilder<MoveDex>(
            future: widget.moves,
            builder: (context, snap) {
              if (snap.hasError) {
                trace('shell.moves.load_failed', {
                  'error': snap.error.runtimeType.toString(),
                });
                return const Center(child: Text('Could not load moves'));
              }
              final moves = snap.data;
              if (moves == null) {
                trace('shell.moves.waiting');
                return const Center(child: CircularProgressIndicator());
              }
              return MovesScreen(moves: moves, frecency: widget.moveFrecency);
            },
          )
        else
          const SizedBox.shrink(),
        TypeChartScreen(chart: widget.dex.types),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) {
        trace('shell.tab.select', {'tab': i});
        setState(() {
          _tab = i;
          _movesVisited |= i == _movesTab;
        });
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.search), label: 'Lookup'),
        NavigationDestination(icon: Icon(Icons.flash_on), label: 'Moves'),
        NavigationDestination(icon: Icon(Icons.grid_on), label: 'Type Chart'),
      ],
    ),
  );
}
