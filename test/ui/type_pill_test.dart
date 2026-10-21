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
import 'package:quickdex/ui/pokemon_page.dart';
import 'package:quickdex/ui/type_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  late MoveDex moves;
  setUpAll(() async {
    dex = await loadPokedex(PlatformAssetBundle());
    moves = await loadMoves(PlatformAssetBundle());
  });

  PokemonEntry named(String n) => dex.entries.firstWhere((e) => e.name == n);

  Future<void> pumpApp(WidgetTester tester, {Team? team}) async {
    tester.view.physicalSize = const Size(480, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      QuickDexApp(
        dex: dex,
        frecency: FrecencyStore(),
        moves: Future.value(moves),
        moveFrecency: FrecencyStore(),
        planner: TeamPlanner(mine: TeamSide(team: team ?? Team())),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectFocused(WidgetTester tester, String label) {
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('focus-selection'))).data,
      label,
    );
  }

  Finder pill(Finder within, String type) => find.descendant(
    of: within,
    matching: find.byWidgetPredicate((w) => w is TypeBadge && w.type == type),
  );

  testWidgets('a pill on a search row opens the type, not the row', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.enterText(find.byKey(const Key('search-field')), 'pikachu');
    await tester.pump();
    await tester.tap(pill(find.byKey(const Key('row-25')), 'electric'));
    await tester.pumpAndSettle();
    expectFocused(tester, 'Electric');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.byType(PokemonPage), findsNothing);
  });

  int tab(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  List<MethodCall> recordPlatform(WidgetTester tester) {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (c) async {
        calls.add(c);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return calls;
  }

  group('back after a pill', () {
    testWidgets('returns to the Pokémon page it came from', (tester) async {
      await pumpApp(tester);
      await tester.enterText(find.byKey(const Key('search-field')), 'pikachu');
      await tester.pump();
      await tester.tap(find.byKey(const Key('row-25')));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byWidgetPredicate((w) => w is TypeBadge && w.type == 'electric')
            .hitTestable()
            .first,
      );
      await tester.pumpAndSettle();
      expectFocused(tester, 'Electric');
      final calls = recordPlatform(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tab(tester), 0);
      expect(find.byKey(const Key('portrait-25')), findsOneWidget);
      expect(calls.where((c) => c.method == 'SystemNavigator.pop'), isEmpty);
    });

    testWidgets('returns to the Team Planner, mouse back too', (tester) async {
      final team = Team(
        slots: [TeamSlot(named('Golem').id), null, null, null, null, null],
      );
      await pumpApp(tester, team: team);
      await tester.tap(find.text('Team Planner'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-slot-type-rock')));
      await tester.pumpAndSettle();
      expectFocused(tester, 'Rock');
      final g = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      );
      await g.down(tester.getCenter(find.byType(NavigationBar)));
      await g.up();
      await tester.pumpAndSettle();
      expect(tab(tester), 2);
      expect(find.byKey(const Key('team-slot-0')), findsOneWidget);
    });

    testWidgets('only once, and not after choosing a tab yourself', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.enterText(find.byKey(const Key('search-field')), 'pikachu');
      await tester.pump();
      await tester.tap(pill(find.byKey(const Key('row-25')), 'electric'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Team Planner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Type Chart'));
      await tester.pumpAndSettle();
      final calls = recordPlatform(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tab(tester), 1, reason: 'a chosen tab is a fresh start');
      expect(
        calls.where((c) => c.method == 'SystemNavigator.pop'),
        hasLength(1),
      );
    });
  });

  testWidgets('the move page type pill opens the type', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byKey(const Key('search-field')), 'surf');
    await tester.pump();
    final surf = moves.moves.firstWhere((m) => m.name == 'Surf');
    await tester.tap(find.byKey(Key('move-row-${surf.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('move-type')));
    await tester.pumpAndSettle();
    expectFocused(tester, 'Water');
  });

  testWidgets('team slot and sidedeck pills open on tap', (tester) async {
    final team = Team(
      slots: [TeamSlot(named('Golem').id), null, null, null, null, null],
    );
    await pumpApp(tester, team: team);
    await tester.tap(find.text('Team Planner'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-slot-type-rock')));
    await tester.pumpAndSettle();
    expectFocused(tester, 'Rock');

    await tester.tap(find.text('Team Planner'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-deck')));
    await tester.pumpAndSettle();
    await tester.tap(pill(find.byKey(const Key('deck-row-0')), 'ground'));
    await tester.pumpAndSettle();
    expectFocused(tester, 'Ground');
    expect(team.slotOf(0), isNotNull, reason: 'the row was not toggled');
  });

  testWidgets('an overfull sidedeck still blocks leaving via a pill', (
    tester,
  ) async {
    final team = Team();
    for (var i = 0; i < 7; i++) {
      team.add(TeamSlot(named('Golem').id));
    }
    await pumpApp(tester, team: team);
    await tester.tap(find.text('Team Planner'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-deck')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deck-row-6')));
    await tester.pumpAndSettle();
    await tester.tap(pill(find.byKey(const Key('deck-row-0')), 'rock'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deck-count')), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
  });

  testWidgets('a pill in a bottom sheet closes the sheet first', (
    tester,
  ) async {
    final opened = <String>[];
    // As in the app: the sheet opens on a navigator below the opener.
    await tester.pumpWidget(
      TypeOpener(
        open: opened.add,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const TypeBadge('fire'),
                ),
                child: const Text('Sheet'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TypeBadge));
    await tester.pumpAndSettle();
    expect(opened, ['fire']);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('without an opener a pill is not tappable', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TypeBadge('fire'))),
    );
    expect(find.byType(GestureDetector), findsNothing);
  });
}
