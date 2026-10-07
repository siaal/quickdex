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
}
