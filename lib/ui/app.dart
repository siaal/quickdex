import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/moves.dart';
import '../frecency/frecency.dart';
import '../search/search_index.dart';
import '../trace.dart';
import 'search_screen.dart';
import 'type_chart_screen.dart';

class QuickDexApp extends StatelessWidget {
  const QuickDexApp({
    super.key,
    required this.dex,
    required this.frecency,
    required this.moves,
    required this.moveFrecency,
    this.initialSearchMode = SearchMode.all,
    this.onSearchModeChanged,
  });
  final Pokedex dex;
  final FrecencyStore frecency;

  /// Loaded in the background so it doesn't delay startup.
  final Future<MoveDex> moves;
  final FrecencyStore moveFrecency;
  final SearchMode initialSearchMode;
  final ValueChanged<SearchMode>? onSearchModeChanged;

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
      initialSearchMode: initialSearchMode,
      onSearchModeChanged: onSearchModeChanged,
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
    this.initialSearchMode = SearchMode.all,
    this.onSearchModeChanged,
  });
  final Pokedex dex;
  final FrecencyStore frecency;
  final Future<MoveDex> moves;
  final FrecencyStore moveFrecency;
  final SearchMode initialSearchMode;
  final ValueChanged<SearchMode>? onSearchModeChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final _index = SearchIndex(widget.dex.entries);

  /// Each tab has its own navigator, so pages open above the tab's content but
  /// below the bottom bar, and stay open while another tab is shown.
  final _navigators = List.generate(2, (_) => GlobalKey<NavigatorState>());
  int _tab = 0;

  Widget _tabNavigator(int tab, Widget root) => Navigator(
    key: _navigators[tab],
    onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => root),
  );

  /// The root navigator only sees the shell, so system back is routed to the
  /// current tab's navigator; at a tab's root it leaves the app as before.
  void _back() {
    final nav = _navigators[_tab].currentState;
    if (nav != null && nav.canPop()) {
      trace('shell.back.pop_tab', {'tab': _tab});
      nav.pop();
      return;
    }
    trace('shell.back.exit', {'tab': _tab});
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          _tabNavigator(
            0,
            SearchScreen(
              dex: widget.dex,
              frecency: widget.frecency,
              index: _index,
              moves: widget.moves,
              moveFrecency: widget.moveFrecency,
              initialMode: widget.initialSearchMode,
              onModeChanged: widget.onSearchModeChanged,
            ),
          ),
          _tabNavigator(1, TypeChartScreen(chart: widget.dex.types)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          if (i == _tab) {
            // Re-tapping the current tab goes back to its root (search) screen.
            trace('shell.tab.reselect', {'tab': i});
            _navigators[i].currentState?.popUntil((r) => r.isFirst);
            return;
          }
          trace('shell.tab.select', {'tab': i});
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.grid_on), label: 'Type Chart'),
        ],
      ),
    ),
  );
}
