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
import 'package:quickdex/ui/move_learners.dart';
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

  final learnerList = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Scrollable),
  );

  testWidgets('search -> move -> learners -> Pokemon -> move', (tester) async {
    await open(tester, scarlet, 'Thunderbolt');
    expect(find.text('TM126'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('move-learners')));
    await tester.tap(find.byKey(const Key('move-learners')));
    await tester.pumpAndSettle();
    final learner = find.byKey(const Key('move-learner-25'));
    await tester.scrollUntilVisible(learner, 400, scrollable: learnerList);
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
      await tester.scrollUntilVisible(learner, 400, scrollable: learnerList);
      await tester.tap(learner);
      await tester.pumpAndSettle();
      final page = tester.widget<PokemonPage>(find.byType(PokemonPage));
      expect(page.dex.game, game);
      expect(page.initialId, 25);
      expect(find.byKey(const Key('portrait-25')), findsOneWidget);
    },
  );

  Future<void> openLearners(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('move-learners')));
    await tester.tap(find.byKey(const Key('move-learners')));
    await tester.pumpAndSettle();
  }

  Set<int> listed(WidgetTester tester) => {
    for (final w in tester.widgetList<ListTile>(find.byType(ListTile)))
      if (w.key case ValueKey<String>(
        value: final k,
      ) when k.startsWith('move-learner-'))
        int.parse(k.substring('move-learner-'.length)),
  };

  group('learners page', () {
    setUp(MoveLearners.resetFilters);
    tearDown(MoveLearners.resetFilters);

    // Thunderbolt in Scarlet: some learn it by level only, some by TM only.
    ({Set<int> level, Set<int> tm}) sources() {
      final level = <int>{};
      final tm = <int>{};
      for (final MapEntry(key: id, value: l) in scarlet.learnsets.entries) {
        if (!dex.byId.containsKey(id)) continue;
        if (l.moves.any((m) => m.move == 85)) level.add(id);
        if (l.machines.any((m) => m.move == 85)) tm.add(id);
      }
      return (level: level, tm: tm);
    }

    Future<void> tall(WidgetTester tester) async {
      tester.view.physicalSize = const Size(480, 40000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('search field is present but not focused; All to start', (
      tester,
    ) async {
      await tall(tester);
      await open(tester, scarlet, 'Thunderbolt');
      await openLearners(tester);
      final search = tester.widget<TextField>(
        find.byKey(const Key('learners-search')),
      );
      expect(search.autofocus, isFalse);
      expect(search.focusNode?.hasFocus ?? false, isFalse);
      expect(
        tester
            .widget<SegmentedButton<LearnFilter>>(
              find.byKey(const Key('learn-filter')),
            )
            .selected,
        {LearnFilter.all},
      );
      final s = sources();
      expect(listed(tester), s.level.union(s.tm));
    });

    testWidgets('Level up and TM narrow the list to that source', (
      tester,
    ) async {
      await tall(tester);
      final s = sources();
      expect(s.level.difference(s.tm), isNotEmpty);
      expect(s.tm.difference(s.level), isNotEmpty);
      await open(tester, scarlet, 'Thunderbolt');
      await openLearners(tester);
      await tester.tap(find.byKey(const Key('learn-filter-levelUp')));
      await tester.pumpAndSettle();
      expect(listed(tester), s.level);
      await tester.tap(find.byKey(const Key('learn-filter-tm')));
      await tester.pumpAndSettle();
      expect(listed(tester), s.tm);
    });

    testWidgets('typing filters by name within the chosen source', (
      tester,
    ) async {
      await tall(tester);
      await open(tester, scarlet, 'Thunderbolt');
      await openLearners(tester);
      await tester.enterText(find.byKey(const Key('learners-search')), 'pika');
      await tester.pump();
      expect(listed(tester), contains(25));
      expect(
        listed(
          tester,
        ).every((id) => dex[id].name.toLowerCase().contains('pika')),
        isTrue,
      );
      await tester.enterText(
        find.byKey(const Key('learners-search')),
        'no-such-pokemon',
      );
      await tester.pump();
      expect(listed(tester), isEmpty);
      expect(find.byKey(const Key('learners-none')), findsOneWidget);
    });

    testWidgets('changing the filter hides the keyboard, keeps the query', (
      tester,
    ) async {
      await tall(tester);
      await open(tester, scarlet, 'Thunderbolt');
      await openLearners(tester);
      final search = find.byKey(const Key('learners-search'));
      await tester.showKeyboard(search);
      await tester.enterText(search, 'pika');
      await tester.tap(find.byKey(const Key('learn-filter-tm')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(search);
      expect(field.focusNode!.hasFocus, isFalse);
      expect(field.controller!.text, 'pika');
    });

    testWidgets('Enter opens the first listed learner', (tester) async {
      await tall(tester);
      await open(tester, scarlet, 'Thunderbolt');
      await openLearners(tester);
      await tester.enterText(
        find.byKey(const Key('learners-search')),
        'pikachu',
      );
      await tester.pump();
      final first = listed(tester).first;
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(Key('portrait-$first')), findsOneWidget);
    });

    testWidgets('the filter is remembered when reopened', (tester) async {
      await tall(tester);
      await open(tester, scarlet, 'Thunderbolt');
      await openLearners(tester);
      await tester.tap(find.byKey(const Key('learn-filter-tm')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openLearners(tester);
      expect(
        tester
            .widget<SegmentedButton<LearnFilter>>(
              find.byKey(const Key('learn-filter')),
            )
            .selected,
        {LearnFilter.tm},
      );
      expect(listed(tester), sources().tm);
    });
  });

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
