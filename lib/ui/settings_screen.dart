import 'package:flutter/material.dart';

import '../data/game.dart';
import '../trace.dart';
import 'game_scope.dart';

/// Opened from the cog on the Search screen. The game: picking a different
/// one reloads the app with that game's data (keys `game-<key>`). And, given
/// [themeMode], the theme: Day | Auto | Night (`theme-<light|system|dark>`).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.games,
    required this.onGameChanged,
    this.themeMode,
  });
  final List<GameInfo> games;
  final ValueChanged<GameInfo> onGameChanged;
  final ValueNotifier<ThemeMode>? themeMode;

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
          if (themeMode case final mode?) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Theme',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ValueListenableBuilder(
                valueListenable: mode,
                builder: (_, m, _) => SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Day', key: Key('theme-light')),
                      icon: Icon(Icons.light_mode),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('Auto', key: Key('theme-system')),
                      icon: Icon(Icons.brightness_auto),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Night', key: Key('theme-dark')),
                      icon: Icon(Icons.dark_mode),
                    ),
                  ],
                  selected: {m},
                  onSelectionChanged: (s) {
                    trace('settings.theme.pick', {'mode': s.single.name});
                    mode.value = s.single;
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
