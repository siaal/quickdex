import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/search/search_index.dart';
import 'package:quickdex/ui/search_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  late MoveDex moves;
  late SearchIndex<PokemonEntry> index;
  setUpAll(() async {
    dex = await loadPokedex(rootBundle);
    moves = await loadMoves(rootBundle);
    index = SearchIndex(dex.entries);
  });

  int moveId(String n) => moves.moves.firstWhere((m) => m.name == n).id;
  late FrecencyStore moveFrecency;
  final modeChanges = <SearchMode>[];

  Future<FrecencyStore> pump(
    WidgetTester tester, {
    List<int> visited = const [],
    SearchMode mode = SearchMode.pokemon,
    FrecencyStore? store,
  }) async {
    final f = store ?? FrecencyStore(clock: () => DateTime.utc(2026, 10, 7));
    moveFrecency = FrecencyStore(clock: () => DateTime.utc(2026, 10, 7));
    modeChanges.clear();
    for (final id in visited) {
      f.visit(id);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          dex: dex,
          frecency: f,
          index: index,
          moves: Future.value(moves),
          moveFrecency: moveFrecency,
          initialMode: mode,
          onModeChanged: modeChanges.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return f;
  }

  Future<void> type(WidgetTester tester, String q) async {
    await tester.enterText(find.byKey(const Key('search-field')), q);
    await tester.pump();
  }

  double rowY(WidgetTester tester, int id) =>
      tester.getTopLeft(find.byKey(Key('row-$id'))).dy;

  testWidgets('empty field lists by recency; typing switches to frecency', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 7);
    final f = FrecencyStore(clock: () => now)
      ..visit(25)
      ..visit(25)
      ..visit(25);
    now = now.add(const Duration(minutes: 1));
    f.visit(1);
    await pump(tester, store: f);
    expect(rowY(tester, 1), lessThan(rowY(tester, 25)), reason: 'recency');

    await type(tester, 'a'); // matches both Bulbasaur and Pikachu
    expect(rowY(tester, 25), lessThan(rowY(tester, 1)), reason: 'frecency');
  });

  testWidgets('mode toggle sits above the search field', (tester) async {
    await pump(tester);
    for (final m in ['Pokémon', 'All', 'Moves']) {
      expect(find.text(m), findsOneWidget);
    }
    expect(
      tester.getBottomLeft(find.byKey(const Key('search-mode'))).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const Key('search-field'))).dy,
      ),
    );
  });

  testWidgets('All finds Pokémon and moves; each mode filters', (tester) async {
    final thunder = Key('move-row-${moveId('Thunder')}');
    await pump(tester, mode: SearchMode.all);
    await type(tester, 'thund');
    expect(find.byKey(const Key('row-642')), findsOneWidget);
    expect(find.byKey(thunder), findsOneWidget);

    await tester.tap(find.byKey(const Key('mode-pokemon')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('row-642')), findsOneWidget);
    expect(find.byKey(thunder), findsNothing);

    await tester.tap(find.byKey(const Key('mode-moves')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('row-642')), findsNothing);
    expect(find.byKey(thunder), findsOneWidget);

    expect(modeChanges, [SearchMode.pokemon, SearchMode.moves]);
    final field = tester.widget<TextField>(
      find.byKey(const Key('search-field')),
    );
    expect(field.controller!.text, 'thund', reason: 'query kept');
    expect(field.focusNode!.hasFocus, isTrue, reason: 'keyboard stays up');
  });

  testWidgets('in All, a move opens its page and becomes frecent', (
    tester,
  ) async {
    await pump(tester, mode: SearchMode.all);
    await type(tester, 'thunderbolt');
    await tester.tap(find.byKey(Key('move-row-${moveId('Thunderbolt')}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('move-name')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(moveFrecency.isFrecent(moveId('Thunderbolt')), isTrue);
    expect(
      find.byKey(Key('move-dismiss-${moveId('Thunderbolt')}')),
      findsOneWidget,
    );
  });

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
