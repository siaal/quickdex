import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/ui/type_finder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  setUpAll(() async => dex = await loadPokedex(rootBundle));

  final opened = <int>[];

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    opened.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TypeFinder(dex: dex, onOpen: (e) => opened.add(e.id)),
        ),
      ),
    );
  }

  Finder row(int id) => find.byKey(Key('finder-row-$id'));

  testWidgets('nothing picked lists nothing', (tester) async {
    await pump(tester);
    expect(find.text('Pick a type'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(1), reason: 'checkbox only');
  });

  testWidgets('tap one type, long-press a second: Pokémon with both', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('finder-type-fire')));
    await tester.longPress(find.byKey(const Key('finder-type-ground')));
    await tester.pump();
    expect(row(322), findsOneWidget, reason: 'Numel');
    expect(row(323), findsOneWidget, reason: 'Camerupt');
    expect(find.text('Fire + Ground · 2 Pokémon'), findsOneWidget);
    await tester.tap(row(323));
    expect(opened, [323]);
  });

  testWidgets('highest evolution only drops pre-evolutions, per form', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('finder-type-fire')));
    await tester.enterText(find.byKey(const Key('finder-search')), 'growlithe');
    await tester.pump();
    expect(row(58), findsOneWidget);
    expect(
      row(10229),
      findsOneWidget,
      reason: 'Hisuian Growlithe is Fire/Rock',
    );
    await tester.tap(find.byKey(const Key('finder-final-only')));
    await tester.enterText(find.byKey(const Key('finder-search')), 'arcanine');
    await tester.pump();
    expect(row(59), findsOneWidget);
    expect(row(10230), findsOneWidget);
    await tester.enterText(find.byKey(const Key('finder-search')), 'growlithe');
    await tester.pump();
    expect(row(58), findsNothing);
    expect(row(10229), findsNothing);
  });
}
