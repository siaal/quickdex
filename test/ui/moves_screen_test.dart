import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/ui/moves_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MoveDex moves;
  setUpAll(() async => moves = await loadMoves(rootBundle));

  int idOf(String n) => moves.moves.firstWhere((m) => m.name == n).id;

  Future<FrecencyStore> pump(WidgetTester tester) async {
    final f = FrecencyStore(clock: () => DateTime.utc(2026, 10, 7));
    await tester.pumpWidget(
      MaterialApp(
        home: MovesScreen(moves: moves, frecency: f),
      ),
    );
    await tester.pumpAndSettle();
    return f;
  }

  Future<void> open(WidgetTester tester, String query, String name) async {
    await tester.enterText(find.byKey(const Key('move-search-field')), query);
    await tester.pump();
    await tester.tap(find.byKey(Key('move-row-${idOf(name)}')));
    await tester.pumpAndSettle();
  }

  testWidgets('typing filters moves live', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('move-search-field')), 'uturn');
    await tester.pump();
    expect(find.byKey(Key('move-row-${idOf('U-turn')}')), findsOneWidget);
    expect(find.text('Thunderbolt'), findsNothing);
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
    expect(find.text('Selected Pokémon'), findsOneWidget);
    expect(find.textContaining('strong electric blast'), findsOneWidget);
    expect(find.textContaining('Inflicts regular damage.'), findsOneWidget);
    expect(find.byKey(const Key('move-not-sv')), findsNothing);
  });

  testWidgets('priority shown when non-zero; flags listed', (tester) async {
    await pump(tester);
    await open(tester, 'mach punch', 'Mach Punch');
    expect(find.byKey(const Key('move-stat-Priority')), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('Selected Pokémon · Contact · Punch'), findsOneWidget);
  });

  testWidgets('missing flag data and description are explicit', (tester) async {
    await pump(tester);
    await open(tester, 'glaive rush', 'Glaive Rush');
    expect(find.textContaining('contact unknown'), findsOneWidget);
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
