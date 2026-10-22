import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/game.dart';
import '../data/items.dart';
import '../data/models.dart';
import '../data/moves.dart';
import '../frecency/frecency.dart';
import '../search/search_index.dart';
import '../team/builds.dart';
import '../team/team.dart';
import '../trace.dart';
import 'pokemon_page.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'team_screen.dart';
import 'type_badge.dart';
import 'type_chart_screen.dart';
import 'type_focus.dart';

class QuickDexApp extends StatelessWidget {
  const QuickDexApp({
    super.key,
    required this.dex,
    required this.frecency,
    required this.moves,
    required this.moveFrecency,
    required this.planner,
    this.items,
    this.itemFrecency,
    this.initialSearchMode = SearchMode.all,
    this.onSearchModeChanged,
    this.games = const [],
    this.onGameChanged,
  });
  final Pokedex dex;
  final FrecencyStore frecency;
  final TeamPlanner planner;

  /// Loaded in the background so it doesn't delay startup.
  final Future<MoveDex> moves;
  final FrecencyStore moveFrecency;

  /// Loaded in the background; without them Search has no items.
  final Future<ItemDex>? items;
  final FrecencyStore? itemFrecency;
  final SearchMode initialSearchMode;
  final ValueChanged<SearchMode>? onSearchModeChanged;

  /// For the settings page; without [onGameChanged] there's no settings cog.
  final List<GameInfo> games;
  final ValueChanged<GameInfo>? onGameChanged;

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
      items: items,
      itemFrecency: itemFrecency,
      planner: planner,
      initialSearchMode: initialSearchMode,
      onSearchModeChanged: onSearchModeChanged,
      games: games,
      onGameChanged: onGameChanged,
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
    required this.planner,
    this.items,
    this.itemFrecency,
    this.initialSearchMode = SearchMode.all,
    this.onSearchModeChanged,
    this.games = const [],
    this.onGameChanged,
  });
  final Pokedex dex;
  final FrecencyStore frecency;
  final TeamPlanner planner;
  final Future<MoveDex> moves;
  final FrecencyStore moveFrecency;
  final Future<ItemDex>? items;
  final FrecencyStore? itemFrecency;
  final SearchMode initialSearchMode;
  final ValueChanged<SearchMode>? onSearchModeChanged;
  final List<GameInfo> games;
  final ValueChanged<GameInfo>? onGameChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final _index = SearchIndex(widget.dex.entries);

  /// Each tab has its own navigator, so pages open above the tab's content but
  /// below the bottom bar, and stay open while another tab is shown.
  final _navigators = List.generate(3, (_) => GlobalKey<NavigatorState>());
  int _tab = 0;
  Team? _openDeck;

  /// The tab a type pill was tapped on, so back from the Type Chart's root
  /// returns there. Cleared once used or when a tab is chosen by hand.
  int? _typeReturn;

  /// Bumped to make the search screen focus its field and show the keyboard.
  final _searchFocusRequests = ValueNotifier(0);

  final _typeFocus = TypeFocusController();

  /// From a Pokémon page: show [type] as a defender on the Type Chart tab.
  void _openType(String type) {
    if (_deckBlocks('type:$type')) return;
    trace('shell.open_type', {'type': type, 'from_tab': _tab});
    _navigators[1].currentState?.popUntil((r) => r.isFirst);
    _typeFocus.show(type, FocusMode.defender);
    setState(() {
      // From the Type Chart itself, keep wherever back already led.
      if (_tab != 1) _typeReturn = _tab;
      _tab = 1;
    });
  }

  /// From the Type Chart's Finder: open the page within the Type Chart tab.
  void _openFromFinder(PokemonEntry e) {
    trace('shell.finder_open', {'id': e.id});
    _pushPokemon(1, e);
  }

  /// From a Team Planner slot: open the page within the Team tab, so back
  /// returns to the planner.
  void _openFromTeam(PokemonEntry e) {
    trace('shell.team_open', {'id': e.id});
    _pushPokemon(2, e);
  }

  void _pushPokemon(int tab, PokemonEntry e) {
    assert(tab == _tab, 'pushing onto a hidden tab');
    _navigators[tab].currentState?.push(
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

  /// From the Search screen's cog: the settings page, within the Search tab.
  void _openSettings() {
    final onGameChanged = widget.onGameChanged!;
    trace('shell.settings.open', {'game': widget.dex.game.key});
    _navigators[0].currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SettingsScreen(games: widget.games, onGameChanged: onGameChanged),
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
      // Honour the active route's PopScope, including Sidedeck legality.
      nav.maybePop();
      return;
    }
    if (_tab == 1 && _typeReturn != null) {
      trace('shell.back.type_return', {'to': _typeReturn});
      setState(() {
        _tab = _typeReturn!;
        _typeReturn = null;
      });
      return;
    }
    if (!exit) {
      trace('shell.back.root_ignored', {'tab': _tab});
      return;
    }
    trace('shell.back.exit', {'tab': _tab});
    SystemNavigator.pop();
  }

  /// An overfull open Sidedeck keeps the Team Planner tab until it's legal.
  bool _deckBlocks(String to) {
    final deck = _openDeck;
    if (_tab != 2 || deck == null || deck.isLegal) return false;
    trace('shell.tab.blocked_overfull_deck', {
      'to': to,
      'count': deck.squadCount,
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Choose at most 6 Pokémon before leaving Sidedeck.'),
          duration: Duration(seconds: 2),
        ),
      );
    return true;
  }

  @override
  Widget build(BuildContext context) =>
      TypeOpener(open: _openType, child: _shell(context));

  Widget _shell(BuildContext context) => PopScope(
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
                items: widget.items,
                itemFrecency: widget.itemFrecency,
                initialMode: widget.initialSearchMode,
                onModeChanged: widget.onSearchModeChanged,
                focusRequests: _searchFocusRequests,
                onOpenType: _openType,
                onOpenSettings: widget.onGameChanged == null
                    ? null
                    : _openSettings,
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
                planner: widget.planner,
                index: _index,
                frecency: widget.frecency,
                moves: widget.moves,
                moveFrecency: widget.moveFrecency,
                onOpenType: _openType,
                onOpenPokemon: _openFromTeam,
                onDeckChanged: (team) => _openDeck = team,
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            if (_deckBlocks('tab:$i')) return;
            _typeReturn = null;
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
