import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/team/builds.dart';
import 'package:quickdex/team/team.dart';
import 'package:quickdex/ui/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  late MoveDex moves;
  setUpAll(() async {
    dex = await loadPokedex(PlatformAssetBundle());
    moves = await loadMoves(PlatformAssetBundle());
  });

  Future<Team> openPlanner(
    WidgetTester tester, {
    bool restored = false,
    bool theirs = false,
  }) async {
    tester.view.physicalSize = const Size(480, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final team = Team();
    for (var i = 0; i < 7; i++) {
      team.add(TeamSlot(dex.entries[i].id));
    }
    if (restored) team.toggle(6, allowOverflow: true);
    await tester.pumpWidget(
      QuickDexApp(
        dex: dex,
        frecency: FrecencyStore(),
        moves: Future.value(moves),
        moveFrecency: FrecencyStore(),
        planner: TeamPlanner(
          mine: TeamSide(team: theirs ? Team() : team),
          theirs: TeamSide(team: theirs ? team : Team()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team Planner'));
    await tester.pumpAndSettle();
    if (theirs) {
      await tester.tap(find.text('Theirs'));
      await tester.pumpAndSettle();
    }
    return team;
  }

  for (final path in [
    'Android back',
    'app back',
    'reselect',
    'switch',
    'mouse back',
  ]) {
    testWidgets('overfull sidedeck blocks $path in the real app shell', (
      tester,
    ) async {
      final team = await openPlanner(tester);
      await tester.tap(find.byKey(const Key('team-deck')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-row-6')));
      await tester.pumpAndSettle();
      expect(team.squadCount, 7);
      switch (path) {
        case 'Android back':
          await tester.binding.handlePopRoute();
        case 'app back':
          await tester.tap(find.byType(BackButton));
        case 'reselect':
          await tester.tap(find.text('Team Planner'));
        case 'switch':
          await tester.tap(find.text('Search'));
        case 'mouse back':
          final gesture = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
            buttons: kBackMouseButton,
          );
          await gesture.down(tester.getCenter(find.byType(NavigationBar)));
          await gesture.up();
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deck-count')), findsOneWidget);
      expect(
        team.squadCount,
        7,
        reason: 'blocked navigation must not drop anyone',
      );
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.tap(find.byKey(const Key('deck-row-0')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deck-count')), findsNothing);
      expect(find.byKey(const Key('team-save')), findsOneWidget);
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('search-field')), findsOneWidget);
    });
  }

  testWidgets(
    'nested editor can return but cannot bypass the sidedeck tab guard',
    (tester) async {
      await openPlanner(tester);
      await tester.tap(find.byKey(const Key('team-deck')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-row-6')));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('deck-row-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-pokemon')), findsOneWidget);
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-pokemon')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deck-count')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deck-count')), findsOneWidget);
    },
  );

  testWidgets('the editor can bench a member beyond the first six slots', (
    tester,
  ) async {
    final team = await openPlanner(tester);
    await tester.tap(find.byKey(const Key('team-deck')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deck-row-6')));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const Key('deck-row-6')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-remove')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(team.squadCount, 6);
    expect(team.slotOf(6), isNull);
    expect(team.deck, hasLength(7));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-save')), findsOneWidget);
  });

  for (final theirs in [false, true]) {
    testWidgets(
      'restored overflow on ${theirs ? 'Theirs' : 'Mine'} has a visible warning and is repairable',
      (tester) async {
        final team = await openPlanner(tester, restored: true, theirs: theirs);
        final warning = find.byKey(const Key('team-legality'));
        expect(warning, findsOneWidget);
        expect(tester.widget<Text>(warning).data, contains('7'));
        expect(tester.widget<Text>(warning).data, contains('first 6'));
        expect(
          tester.widget<Text>(warning).style!.color,
          Theme.of(tester.element(warning)).colorScheme.error,
        );
        // Unexpected overflow warns at the planner root; it does not trap the app.
        await tester.tap(find.text('Search'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('search-field')), findsOneWidget);
        await tester.tap(find.text('Team Planner'));
        await tester.pumpAndSettle();
        expect(warning, findsOneWidget);
        await tester.tap(find.byKey(const Key('team-deck')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('deck-row-0')));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(team.squadCount, 6);
        expect(warning, findsNothing);
      },
    );
  }
}
