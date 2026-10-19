import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/game.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/search/search_index.dart';
import 'package:quickdex/ui/pokemon_page.dart';
import 'package:quickdex/ui/move_page.dart';
import 'package:quickdex/ui/search_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  late MoveDex scarlet;
  setUpAll(() async {
    dex = await loadPokedex(PlatformAssetBundle());
    scarlet = await loadMoves(PlatformAssetBundle());
  });

  Future<void> open(
    WidgetTester tester,
    MoveDex moves,
    String name, {
    Pokedex? gameDex,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          dex: gameDex ?? dex,
          frecency: FrecencyStore(),
          index: SearchIndex((gameDex ?? dex).entries),
          moves: Future.value(moves),
          moveFrecency: FrecencyStore(),
          initialMode: SearchMode.moves,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), name);
    await tester.pump();
    final move = moves.moves.firstWhere((m) => m.name == name);
    await tester.tap(find.byKey(Key('move-row-${move.id}')));
    await tester.pumpAndSettle();
  }

  testWidgets('search -> move -> learners -> Pokemon -> move', (tester) async {
    await open(tester, scarlet, 'Thunderbolt');
    expect(find.text('TM126'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('move-learners')));
    await tester.tap(find.byKey(const Key('move-learners')));
    await tester.pumpAndSettle();
    final learner = find.byKey(const Key('move-learner-25'));
    await tester.scrollUntilVisible(learner, 400);
    await tester.tap(learner);
    await tester.pumpAndSettle();
    expect(find.byType(PokemonPage), findsOneWidget);
    expect(find.byKey(const Key('portrait-25')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('learn-36-85')));
    await tester.tap(find.byKey(const Key('learn-36-85')));
    await tester.pumpAndSettle();
    expect(find.text('TM126'), findsOneWidget);
    expect(find.byKey(const Key('move-learners')), findsOneWidget);
  });

  testWidgets('machine labels come from the selected game', (tester) async {
    const game = GameInfo('emerald', 'Emerald', 3);
    final moves = await tester.runAsync(
      () => loadMoves(PlatformAssetBundle(), game),
    );
    final gameDex = await tester.runAsync(
      () => loadPokedex(PlatformAssetBundle(), game),
    );
    await open(tester, moves!, 'Surf', gameDex: gameDex!);
    expect(find.text('HM03'), findsOneWidget);
    expect(find.text('TM123'), findsNothing);
  });

  testWidgets('badge TMs and fallback sources appear on learner rows', (
    tester,
  ) async {
    final move = scarlet.byId[85]!;
    final moves = MoveDex(
      [move],
      {
        25: const Learnset(
          null,
          [(level: 1, move: 85), (level: 9, move: 85)],
          [(badges: 3, move: 85)],
        ),
        1: const Learnset('Emerald', [(level: 7, move: 85)]),
      },
      const GameInfo('scrambled', 'Scrambled Scarlet', 9),
    );
    await open(tester, moves, 'Thunderbolt');
    expect(find.text('TM: 3 badges'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('move-learners')));
    await tester.tap(find.byKey(const Key('move-learners')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('move-learner-25')), findsOneWidget);
    expect(find.textContaining('Lv 1, 9'), findsOneWidget);
    expect(find.textContaining('TM: 3 badges'), findsOneWidget);
    expect(find.textContaining('From Emerald'), findsOneWidget);
  });

  testWidgets(
    'bundled Scrambled badge-only learner opens its actual game page',
    (tester) async {
      const game = GameInfo('scrambled', 'Scrambled Scarlet', 9);
      final moves = await tester.runAsync(
        () => loadMoves(PlatformAssetBundle(), game),
      );
      final gameDex = await tester.runAsync(
        () => loadPokedex(PlatformAssetBundle(), game),
      );
      expect(moves!.learnsets[25]!.moves, isEmpty);
      await open(tester, moves, 'Thunderbolt', gameDex: gameDex!);
      expect(find.text('TM: 3 badges'), findsOneWidget);
      expect(find.text('TM126'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('move-learners')));
      await tester.tap(find.byKey(const Key('move-learners')));
      await tester.pumpAndSettle();
      final learner = find.byKey(const Key('move-learner-25'));
      await tester.scrollUntilVisible(learner, 400);
      await tester.tap(learner);
      await tester.pumpAndSettle();
      final page = tester.widget<PokemonPage>(find.byType(PokemonPage));
      expect(page.dex.game, game);
      expect(page.initialId, 25);
      expect(find.byKey(const Key('portrait-25')), findsOneWidget);
    },
  );

  testWidgets('pending and failed move loading is visible', (tester) async {
    final pending = Completer<MoveDex>();
    await tester.pumpWidget(
      MaterialApp(
        home: MovePage(
          move: scarlet.byId[85]!,
          frecency: FrecencyStore(),
          dex: dex,
          moves: pending.future,
          pokemonFrecency: FrecencyStore(),
        ),
      ),
    );
    expect(find.text('Loading learners...'), findsOneWidget);
    pending.completeError(StateError('test load failure'));
    await tester.pump();
    expect(find.text('Unable to load learners'), findsOneWidget);
    expect(find.byKey(const Key('move-learners')), findsNothing);
  });

  testWidgets('moves without learners have an explicit empty state', (
    tester,
  ) async {
    await open(tester, MoveDex([scarlet.byId[85]!]), 'Thunderbolt');
    expect(find.text('No TM/HM in Scarlet'), findsOneWidget);
    expect(find.text('No known learners'), findsOneWidget);
  });
}
