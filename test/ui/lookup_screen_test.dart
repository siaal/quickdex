import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/search/search_index.dart';
import 'package:quickdex/ui/lookup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  late SearchIndex index;
  setUpAll(() async {
    dex = await loadPokedex(rootBundle);
    index = SearchIndex(dex.entries);
  });

  Future<FrecencyStore> pump(
    WidgetTester tester, {
    List<int> visited = const [],
  }) async {
    final f = FrecencyStore(clock: () => DateTime.utc(2026, 10, 7));
    for (final id in visited) {
      f.visit(id);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: LookupScreen(dex: dex, frecency: f, index: index),
      ),
    );
    await tester.pumpAndSettle();
    return f;
  }

  testWidgets('typing filters live', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('search-field')), 'mrmime');
    await tester.pump();
    expect(find.byKey(const Key('row-122')), findsOneWidget);
    expect(find.byKey(const Key('row-1')), findsNothing);
  });

  testWidgets('swiping a frecent row removes it from recents; undo restores', (
    tester,
  ) async {
    final f = await pump(tester, visited: [25, 25]);
    expect(find.byKey(const Key('dismiss-25')), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('dismiss-25')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(f.isFrecent(25), isFalse);
    expect(find.byKey(const Key('dismiss-25')), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(f.score(25), 2);
    expect(find.byKey(const Key('dismiss-25')), findsOneWidget);
  });

  testWidgets('non-frecent rows cannot be swiped', (tester) async {
    await pump(tester, visited: [25]);
    expect(find.byKey(const Key('row-1')), findsOneWidget);
    expect(find.byKey(const Key('dismiss-1')), findsNothing);
  });

  testWidgets('back from a Pokémon page clears and refocuses search', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('search-field')), 'pikachu');
    await tester.pump();
    await tester.tap(find.byKey(const Key('row-25')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const Key('search-field')),
    );
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isTrue);
  });
}
