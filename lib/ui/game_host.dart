import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/game.dart';
import '../data/loader.dart';
import '../data/models.dart';
import '../data/moves.dart';
import '../frecency/frecency.dart';
import '../team/team.dart';
import '../trace.dart';
import 'app.dart';
import 'game_scope.dart';
import 'search_screen.dart';

/// Everything loaded for one game. Switching games builds a new one and drops
/// the old, so only one game's data is ever in memory.
class GameSession {
  GameSession._(
    this.game,
    this.dex,
    this.moves,
    this.frecency,
    this.moveFrecency,
    this.team,
  );

  /// Team and frecency are per game ([GameInfo.prefsKey]).
  static Future<GameSession> load(
    AssetBundle bundle,
    SharedPreferences prefs,
    GameInfo game,
  ) async {
    // Not awaited: move results and learnsets appear once loaded.
    final moves = loadMoves(bundle, game);
    final dex = await loadPokedex(bundle, game);
    FrecencyStore store(String base) {
      final key = game.prefsKey(base);
      return FrecencyStore.fromJson(
        prefs.getString(key),
        onChanged: (json) => prefs.setString(key, json),
      );
    }

    final teamKey = game.prefsKey(Team.prefsKey);
    return GameSession._(
      game,
      dex,
      moves,
      store(FrecencyStore.prefsKey),
      store(FrecencyStore.movesPrefsKey),
      Team.fromJson(
        prefs.getString(teamKey),
        dex,
        onChanged: (json) => prefs.setString(teamKey, json),
      ),
    );
  }

  final GameInfo game;
  final Pokedex dex;
  final Future<MoveDex> moves;
  final FrecencyStore frecency;
  final FrecencyStore moveFrecency;
  final Team team;
}

/// Prefs key of the chosen game.
const gamePrefsKey = 'game';
const _modeKey = 'search.mode';

/// The game saved in [prefs], else Scarlet (also if it's no longer bundled).
GameInfo savedGame(SharedPreferences prefs, List<GameInfo> games) {
  final key = prefs.getString(gamePrefsKey);
  final game = games.where((g) => g.key == key).firstOrNull;
  trace(game == null ? 'game.saved.default' : 'game.saved.found', {'key': key});
  return game ?? GameInfo.scarlet;
}

/// Shows the app for one [GameSession] and swaps in another when the user
/// picks a different game.
class GameHost extends StatefulWidget {
  const GameHost({
    super.key,
    required this.prefs,
    required this.games,
    required this.initial,
    this.bundle,
  });
  final SharedPreferences prefs;
  final List<GameInfo> games;
  final GameSession initial;

  /// Defaults to [rootBundle].
  final AssetBundle? bundle;

  @override
  State<GameHost> createState() => _GameHostState();
}

class _GameHostState extends State<GameHost> {
  late GameSession _session = widget.initial;

  /// The game being loaded, so a second tap doesn't start another load.
  GameInfo? _loading;

  Future<void> _switch(GameInfo game) async {
    if (game == _session.game || game == _loading) {
      trace('game.switch.ignored', {'key': game.key});
      return;
    }
    trace('game.switch.start', {'from': _session.game.key, 'to': game.key});
    _loading = game;
    final sw = Stopwatch()..start();
    final next = await GameSession.load(
      widget.bundle ?? rootBundle,
      widget.prefs,
      game,
    );
    if (!mounted || _loading != game) return;
    await widget.prefs.setString(gamePrefsKey, game.key);
    trace('game.switch.done', {'to': game.key, 'ms': sw.elapsedMilliseconds});
    setState(() {
      _session = next;
      _loading = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final prefs = widget.prefs;
    return GameScope(
      game: s.game,
      // Keyed by game: the whole shell (tabs, open pages) is rebuilt for it.
      child: QuickDexApp(
        key: ValueKey(s.game.key),
        dex: s.dex,
        frecency: s.frecency,
        moves: s.moves,
        moveFrecency: s.moveFrecency,
        team: s.team,
        games: widget.games,
        onGameChanged: _switch,
        initialSearchMode:
            SearchMode.values.asNameMap()[prefs.getString(_modeKey)] ??
            SearchMode.all,
        onSearchModeChanged: (m) => prefs.setString(_modeKey, m.name),
      ),
    );
  }
}
