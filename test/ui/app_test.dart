import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/team/team.dart';
import 'package:quickdex/ui/app.dart';
import 'package:quickdex/ui/search_screen.dart';
import 'package:quickdex/ui/type_focus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  late MoveDex moves;
  setUpAll(() async {
    dex = await loadPokedex(rootBundle);
    moves = await loadMoves(rootBundle);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      QuickDexApp(
        dex: dex,
        frecency: FrecencyStore(),
        moves: Future.value(moves),
        moveFrecency: FrecencyStore(),
        team: Team(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('launches on Search with the search field focused', (
    tester,
  ) async {
    await pumpApp(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);
    final field = tester.widget<TextField>(
      find.byKey(const Key('search-field')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets(
    'three tabs: Search (starting in All), Type Chart, Team Planner',
    (tester) async {
      await pumpApp(tester);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations.length, 3);
      expect(find.text('Team Planner'), findsOneWidget);
      expect(find.text('Type Chart'), findsOneWidget);
      final mode = tester.widget<SegmentedButton<SearchMode>>(
        find.byKey(const Key('search-mode')),
      );
      expect(mode.selected, {SearchMode.all});
    },
  );

  Future<void> openPikachu(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('search-field')), 'pikachu');
    await tester.pump();
    await tester.tap(find.byKey(const Key('row-25')));
    await tester.pumpAndSettle();
  }

  testWidgets('bottom bar stays visible on a Pokémon page', (tester) async {
    await pumpApp(tester);
    await openPikachu(tester);
    expect(find.byKey(const Key('portrait-25')), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  TextField searchField(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const Key('search-field')));

  testWidgets('returning to Search lands on the focused search screen', (
    tester,
  ) async {
    await pumpApp(tester);
    await openPikachu(tester);
    await tester.tap(find.text('Type Chart'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portrait-25')), findsNothing);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portrait-25')), findsNothing);
    expect(searchField(tester).focusNode!.hasFocus, isTrue);
  });

  testWidgets('tapping Search on the search screen re-shows the keyboard', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(searchField(tester).focusNode!.hasFocus, isTrue);
    tester.testTextInput.log.clear();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(searchField(tester).focusNode!.hasFocus, isTrue);
    expect(
      tester.testTextInput.log.map((c) => c.method),
      contains('TextInput.show'),
    );
  });

  testWidgets('tapping the current tab returns to its search screen', (
    tester,
  ) async {
    await pumpApp(tester);
    await openPikachu(tester);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portrait-25')), findsNothing);
    expect(find.byKey(const Key('search-field')), findsOneWidget);
  });

  testWidgets('system back pops the page inside the tab', (tester) async {
    await pumpApp(tester);
    await openPikachu(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portrait-25')), findsNothing);
    expect(find.byKey(const Key('search-field')), findsOneWidget);
  });

  testWidgets('Enter in search opens the top result', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byKey(const Key('search-field')), 'pikachu');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portrait-25')), findsOneWidget);
  });

  testWidgets('Enter with no results does nothing', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byKey(const Key('search-field')), 'zzzzzz');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-field')), findsOneWidget);
  });

  FocusMode focusMode(WidgetTester tester) => tester
      .widget<SegmentedButton<FocusMode>>(find.byKey(const Key('focus-mode')))
      .selected
      .single;

  testWidgets('tapping a type pill opens it as a defender in the Type Chart', (
    tester,
  ) async {
    await pumpApp(tester);
    await openPikachu(tester);
    await tester.tap(find.byKey(const Key('type-electric')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('focus-selection'))).data,
      'Electric',
    );
    expect(focusMode(tester), FocusMode.defender);
  });

  testWidgets('a weakness pill opens that type, even from the Grid tab', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Type Chart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grid'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await openPikachu(tester);
    await tester.ensureVisible(find.byKey(const Key('def-2.0-ground')));
    await tester.tap(find.byKey(const Key('def-2.0-ground')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('focus-selection'))).data,
      'Ground',
    );
    expect(focusMode(tester), FocusMode.defender);
  });

  testWidgets('Finder rows open the Pokémon page inside the Type Chart tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    await tester.tap(find.text('Type Chart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finder'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finder-type-electric')));
    await tester.enterText(find.byKey(const Key('finder-search')), 'pikachu');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finder-row-25')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portrait-25')), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
  });

  testWidgets('mouse back button pops a page but never leaves the app', (
    tester,
  ) async {
    await pumpApp(tester);
    await openPikachu(tester);
    Future<void> mouseBack() async {
      final g = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      );
      await g.down(tester.getCenter(find.byType(NavigationBar)));
      await g.up();
      await tester.pumpAndSettle();
    }

    await mouseBack();
    expect(find.byKey(const Key('portrait-25')), findsNothing);
    expect(find.byKey(const Key('search-field')), findsOneWidget);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (c) async {
        calls.add(c);
        return null;
      },
    );
    await mouseBack();
    expect(calls.where((c) => c.method == 'SystemNavigator.pop'), isEmpty);
    expect(find.byKey(const Key('search-field')), findsOneWidget);
  });

  testWidgets('a team type pill opens the Type Chart as a defender', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final golem = dex.entries.firstWhere((e) => e.name == 'Golem');
    await tester.pumpWidget(
      QuickDexApp(
        dex: dex,
        frecency: FrecencyStore(),
        moves: Future.value(moves),
        moveFrecency: FrecencyStore(),
        team: Team(slots: [TeamSlot(golem.id), null, null, null, null, null]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team Planner'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('team-type-fire')));
    await tester.longPress(find.byKey(const Key('team-type-fire')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('focus-selection'))).data,
      'Fire',
    );
    expect(focusMode(tester), FocusMode.defender);
  });
}
