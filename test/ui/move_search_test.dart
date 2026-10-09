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
  setUpAll(() async {
    dex = await loadPokedex(rootBundle);
    moves = await loadMoves(rootBundle);
  });

  int idOf(String n) => moves.moves.firstWhere((m) => m.name == n).id;

  Future<FrecencyStore> pump(WidgetTester tester) async {
    final f = FrecencyStore(clock: () => DateTime.utc(2026, 10, 7));
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          dex: dex,
          frecency: FrecencyStore(),
          index: SearchIndex(dex.entries),
          moves: Future.value(moves),
          moveFrecency: f,
          initialMode: SearchMode.moves,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return f;
  }

  Future<void> open(WidgetTester tester, String query, String name) async {
    await tester.enterText(find.byKey(const Key('search-field')), query);
    await tester.pump();
    await tester.tap(find.byKey(Key('move-row-${idOf(name)}')));
    await tester.pumpAndSettle();
  }

  testWidgets('typing filters moves live', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('search-field')), 'uturn');
    await tester.pump();
    expect(find.byKey(Key('move-row-${idOf('U-turn')}')), findsOneWidget);
    expect(find.text('Thunderbolt'), findsNothing);
  });

  testWidgets('result row: category symbol only, right of the name', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('search-field')), 'uturn');
    await tester.pump();
    final row = find.byKey(Key('move-row-${idOf('U-turn')}'));
    Finder inRow(Finder f) => find.descendant(of: row, matching: f);
    expect(inRow(find.text('Physical')), findsNothing);
    final icon = tester.getRect(inRow(find.byKey(const Key('cat-physical'))));
    final name = tester.getRect(inRow(find.text('U-turn')));
    expect(icon.left, greaterThan(name.right));
    expect(icon.center.dy, closeTo(name.center.dy, 4));
    final stats = tester.widget<Text>(inRow(find.text('70 · 100%')));
    expect(stats.style?.fontSize, 14);
  });

  testWidgets('move page shows the numbers, target, text and description', (
    tester,
  ) async {
    await pump(tester);
    await open(tester, 'thunderbolt', 'Thunderbolt');
    expect(find.byKey(const Key('move-name')), findsOneWidget);
    expect(find.text('Special'), findsOneWidget);
    expect(find.byKey(const Key('move-stat-Power')), findsOneWidget);
    expect(find.text('90'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget); // effect chance
    expect(find.byKey(const Key('move-stat-Priority')), findsNothing);
    expect(find.textContaining('Selected Pokémon'), findsOneWidget);
    expect(find.textContaining('strong electric blast'), findsOneWidget);
    expect(find.textContaining('Inflicts regular damage.'), findsOneWidget);
    expect(find.byKey(const Key('move-not-sv')), findsNothing);
  });

  testWidgets('priority shown when non-zero; flags listed', (tester) async {
    await pump(tester);
    await open(tester, 'mach punch', 'Mach Punch');
    expect(find.byKey(const Key('move-stat-Priority')), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(
      find.text('Selected Pokémon · Makes contact · Punch'),
      findsOneWidget,
    );
  });

  testWidgets('category pill right-aligned on the type row; type has icon', (
    tester,
  ) async {
    await pump(tester);
    await open(tester, 'quick attack', 'Quick Attack');
    final badge = find.byKey(const Key('move-category'));
    final type = find.byKey(const Key('move-type'));
    final rect = tester.getRect(badge);
    expect(
      rect.center.dy,
      closeTo(tester.getRect(type).center.dy, 2),
      reason: 'same row as the type pill',
    );
    expect(
      find.descendant(
        of: type,
        matching: find.byKey(const Key('type-icon-normal')),
      ),
      findsOneWidget,
    );
    expect(
      rect.right,
      closeTo(
        tester.view.physicalSize.width / tester.view.devicePixelRatio - 16,
        1,
      ),
    );
    expect(
      find.descendant(
        of: badge,
        matching: find.byKey(const Key('cat-physical')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: badge, matching: find.text('Physical')),
      findsOneWidget,
    );
  });

  testWidgets('non-contact moves say so', (tester) async {
    await pump(tester);
    await open(tester, 'thunderbolt', 'Thunderbolt');
    expect(find.text('Selected Pokémon · No contact'), findsOneWidget);
  });

  testWidgets('Gen 9 move has contact; missing description omitted', (
    tester,
  ) async {
    await pump(tester);
    await open(tester, 'glaive rush', 'Glaive Rush');
    expect(find.text('Selected Pokémon · Makes contact'), findsOneWidget);
    expect(find.textContaining('unknown'), findsNothing);
    expect(find.byKey(const Key('move-desc')), findsNothing);
  });

  testWidgets('Not in Scarlet tag', (tester) async {
    await pump(tester);
    await open(tester, 'return', 'Return');
    expect(find.byKey(const Key('move-not-sv')), findsOneWidget);
  });

  testWidgets('visiting makes a move frecent and swipeable', (tester) async {
    final f = await pump(tester);
    await open(tester, 'thunderbolt', 'Thunderbolt');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(f.isFrecent(idOf('Thunderbolt')), isTrue);
    final dismiss = find.byKey(Key('move-dismiss-${idOf('Thunderbolt')}'));
    expect(dismiss, findsOneWidget);
    await tester.drag(dismiss, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(f.isFrecent(idOf('Thunderbolt')), isFalse);
  });
}
