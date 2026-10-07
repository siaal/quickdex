import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/ui/app.dart';

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
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('launches on Lookup with the search field focused', (
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

  testWidgets('Moves is the middle tab, built only once opened', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(
      find.byKey(const Key('move-search-field'), skipOffstage: false),
      findsNothing,
    );
    await tester.tap(find.text('Moves'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const Key('move-search-field')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
    expect(find.text('Absorb'), findsOneWidget);
  });

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

  testWidgets('switching tabs keeps the open page', (tester) async {
    await pumpApp(tester);
    await openPikachu(tester);
    await tester.tap(find.text('Type Chart'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portrait-25')), findsNothing);
    await tester.tap(find.text('Lookup'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portrait-25')), findsOneWidget);
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
}
