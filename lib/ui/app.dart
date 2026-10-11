import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/moves.dart';
import '../frecency/frecency.dart';
import '../search/search_index.dart';
import '../team/team.dart';
import '../trace.dart';
import 'pokemon_page.dart';
import 'search_screen.dart';
import 'team_screen.dart';
import 'type_chart_screen.dart';
import 'type_focus.dart';

class QuickDexApp extends StatelessWidget {
  const QuickDexApp({
    super.key,
    required this.dex,
    required this.frecency,
    required this.moves,
    required this.moveFrecency,
    required this.team,
    this.initialSearchMode = SearchMode.all,
    this.onSearchModeChanged,
  });
  final Pokedex dex;
  final FrecencyStore frecency;
  final Team team;

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
      team: team,
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
    required this.team,
    this.initialSearchMode = SearchMode.all,
    this.onSearchModeChanged,
  });
  final Pokedex dex;
  final FrecencyStore frecency;
  final Team team;
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
  final _navigators = List.generate(3, (_) => GlobalKey<NavigatorState>());
  int _tab = 0;

  /// Bumped to make the search screen focus its field and show the keyboard.
  final _searchFocusRequests = ValueNotifier(0);

  final _typeFocus = TypeFocusController();

  /// From a Pokémon page: show [type] as a defender on the Type Chart tab.
  void _openType(String type) {
    trace('shell.open_type', {'type': type, 'from_tab': _tab});
    _navigators[1].currentState?.popUntil((r) => r.isFirst);
    _typeFocus.show(type, FocusMode.defender);
    setState(() => _tab = 1);
  }

  /// From the Type Chart's Finder: open the page within the Type Chart tab.
  void _openFromFinder(PokemonEntry e) {
    trace('shell.finder_open', {'id': e.id});
    _navigators[1].currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => PokemonPage(
          dex: widget.dex,
          frecency: widget.frecency,
          initialId: e.id,
          moves: widget.moves,
          moveFrecency: widget.moveFrecency,
          onOpenType: _openType,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchFocusRequests.dispose();
    _typeFocus.dispose();
    super.dispose();
  }

  Widget _tabNavigator(int tab, Widget root) => Navigator(
    key: _navigators[tab],
    onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => root),
  );

  /// The root navigator only sees the shell, so system back is routed to the
  /// current tab's navigator; at a tab's root it leaves the app as before.
  /// [exit]: leave the app at a tab's root (system back). The mouse back
  /// button passes false so it can't close the desktop window.
  void _back({bool exit = true}) {
    final nav = _navigators[_tab].currentState;
    if (nav != null && nav.canPop()) {
      trace('shell.back.pop_tab', {'tab': _tab});
      nav.pop();
      return;
    }
    if (!exit) {
      trace('shell.back.root_ignored', {'tab': _tab});
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
    // Mouse button 4 (back) acts like system back / a back swipe.
    child: Listener(
      onPointerDown: (e) {
        if (e.buttons & kBackMouseButton != 0) {
          trace('shell.back.mouse', {'tab': _tab});
          _back(exit: false);
        }
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
                focusRequests: _searchFocusRequests,
                onOpenType: _openType,
              ),
            ),
            _tabNavigator(
              1,
              TypeChartScreen(
                dex: widget.dex,
                focus: _typeFocus,
                onOpenPokemon: _openFromFinder,
              ),
            ),
            _tabNavigator(
              2,
              TeamScreen(
                dex: widget.dex,
                team: widget.team,
                index: _index,
                frecency: widget.frecency,
                moves: widget.moves,
                moveFrecency: widget.moveFrecency,
                onOpenType: _openType,
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            trace(i == _tab ? 'shell.tab.reselect' : 'shell.tab.select', {
              'tab': i,
            });
            // Search always lands on its search screen (open pages are dropped),
            // whether re-tapped or returned to; other tabs keep their page unless
            // re-tapped.
            if (i == 0 || i == _tab) {
              _navigators[i].currentState?.popUntil((r) => r.isFirst);
            }
            if (i != _tab) setState(() => _tab = i);
            if (i == 0) {
              // After the frame: the tab must be visible before it can take focus.
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _searchFocusRequests.value++,
              );
            }
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            NavigationDestination(
              icon: Icon(Icons.grid_on),
              label: 'Type Chart',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups),
              label: 'Team Planner',
            ),
          ],
        ),
      ),
    ),
  );
}
