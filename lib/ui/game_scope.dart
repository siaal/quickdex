import 'package:flutter/widgets.dart';

import '../data/game.dart';

/// The loaded game, for UI that names it ("Not in Emerald").
class GameScope extends InheritedWidget {
  const GameScope({super.key, required this.game, required super.child});
  final GameInfo game;

  /// Scarlet when there's no scope (widget tests that pump a lone widget).
  static GameInfo of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GameScope>()?.game ??
      GameInfo.scarlet;

  @override
  bool updateShouldNotify(GameScope old) => old.game != game;
}
