import 'package:flutter/material.dart';

import '../data/game.dart';
import '../trace.dart';
import 'game_scope.dart';

/// Opened from the cog on the Search screen. Only the game for now; picking a
/// different one reloads the app with that game's data (keys `game-<key>`).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.games,
    required this.onGameChanged,
  });
  final List<GameInfo> games;
  final ValueChanged<GameInfo> onGameChanged;

  @override
  Widget build(BuildContext context) {
    final current = GameScope.of(context);
    assert(games.contains(current), '$current is not among $games');
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Game', style: Theme.of(context).textTheme.titleSmall),
          ),
          RadioGroup<GameInfo>(
            groupValue: current,
            onChanged: (g) {
              if (g == null) return;
              trace('settings.game.pick', {'key': g.key});
              onGameChanged(g);
            },
            child: Column(
              children: [
                for (final g in games)
                  RadioListTile<GameInfo>(
                    key: Key('game-${g.key}'),
                    value: g,
                    title: Text(g.name),
                    subtitle: Text('Gen ${g.gen}'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
