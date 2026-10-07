import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/ui/pokemon_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  setUpAll(() async => dex = await loadPokedex(rootBundle));

  /// Pumps a launcher screen with an "open" button that pushes the page, like search does.
  Future<FrecencyStore> pumpLauncher(WidgetTester tester, int id) async {
    final f = FrecencyStore(clock: () => DateTime.utc(2026, 10, 7));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      PokemonPage(dex: dex, frecency: f, initialId: id),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return f;
  }

  int idOf(String name) => dex.entries.firstWhere((e) => e.name == name).id;

  testWidgets('ability line lists abilities, hidden marked', (tester) async {
    await pumpLauncher(tester, 1);
    expect(find.byKey(const Key('ability-65')), findsOneWidget);
    expect(find.text('Overgrow'), findsOneWidget);
    expect(find.text('Chlorophyll (H)'), findsOneWidget);
  });

  testWidgets('tapping an ability explains it in a dialog', (tester) async {
    await pumpLauncher(tester, idOf('Gastly'));
    await tester.tap(find.byKey(const Key('ability-26')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Evades Ground moves.'), findsOneWidget);
    expect(
      find.textContaining('disabled during Gravity or Ingrain'),
      findsOneWidget,
    );
  });

  testWidgets('description equal to the one-liner is not repeated', (
    tester,
  ) async {
    final talonflame = dex.entries.firstWhere((e) => e.name == 'Talonflame');
    await pumpLauncher(tester, talonflame.id);
    await tester.tap(find.byKey(Key('ability-${talonflame.hidden}')));
    await tester.pumpAndSettle();
    expect(
      find.text("Raises Flying moves' priority by one stage."),
      findsOneWidget,
    );
  });

  testWidgets('catch rate and weight sit at the bottom', (tester) async {
    await pumpLauncher(tester, 1);
    expect(find.text('Catch rate 45 · Weight 6.9 kg'), findsOneWidget);
  });

  testWidgets('Gastly shows Ground under Immune with a Levitate tag', (
    tester,
  ) async {
    await pumpLauncher(tester, idOf('Gastly'));
    expect(find.byKey(const Key('def-2.0-ground')), findsNothing);
    expect(find.byKey(const Key('def-guard-ground')), findsOneWidget);
    expect(find.text('(Levitate)'), findsOneWidget);
  });

  testWidgets('header shows portrait, name, dex and types', (tester) async {
    await pumpLauncher(tester, 25);
    expect(find.byKey(const Key('portrait-25')), findsOneWidget);
    expect(find.textContaining('Pikachu', findRichText: true), findsWidgets);
    expect(find.textContaining('#025', findRichText: true), findsOneWidget);
    expect(find.text('Electric'), findsWidgets);
  });

  testWidgets('form chips only when sibling forms exist', (tester) async {
    await pumpLauncher(tester, 26);
    expect(find.byKey(const Key('form-chip-10100')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await pumpLauncher(tester, 25);
    expect(find.byKey(const Key('form-chips')), findsNothing);
  });

  testWidgets(
    'form chip swaps in place; back returns to launcher; credit goes to the opened entry',
    (tester) async {
      final f = await pumpLauncher(tester, 26);
      await tester.tap(find.byKey(const Key('form-chip-10100')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('portrait-10100')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      expect(f.isFrecent(26), isTrue);
      expect(f.isFrecent(10100), isFalse);
    },
  );

  testWidgets('Gyarados defence table', (tester) async {
    await pumpLauncher(tester, idOf('Gyarados'));
    expect(find.byKey(const Key('def-4.0-electric')), findsOneWidget);
    expect(find.byKey(const Key('def-2.0-rock')), findsOneWidget);
    expect(find.byKey(const Key('def-0.0-ground')), findsOneWidget);
    expect(find.byKey(const Key('def-0.5-steel')), findsOneWidget);
  });

  testWidgets('Shedinja defence table', (tester) async {
    await pumpLauncher(tester, idOf('Shedinja'));
    for (final t in ['fire', 'flying', 'rock', 'ghost', 'dark']) {
      expect(find.byKey(Key('def-2.0-$t')), findsOneWidget, reason: t);
    }
    expect(find.byKey(const Key('def-0.0-normal')), findsOneWidget);
    expect(find.byKey(const Key('def-0.0-fighting')), findsOneWidget);
  });

  testWidgets('Evo button stays pinned right while a long name wraps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 3; // 300dp wide
    addTearDown(tester.view.reset);
    await pumpLauncher(tester, 25);
    final shortRight = tester
        .getTopRight(find.byKey(const Key('evo-button')))
        .dx;
    final shortHeight = tester
        .getSize(find.byKey(const Key('name-line')))
        .height;
    await tester.pageBack();
    await tester.pumpAndSettle();
    final longest = dex.entries.reduce(
      (a, b) => a.name.length >= b.name.length ? a : b,
    );
    await pumpLauncher(tester, longest.id);
    expect(
      tester.getTopRight(find.byKey(const Key('evo-button'))).dx,
      shortRight,
    );
    expect(
      tester.getSize(find.byKey(const Key('name-line'))).height,
      greaterThan(shortHeight),
    );
  });
}
