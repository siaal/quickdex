import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/ui/evolution_sheet.dart';
import 'package:quickdex/ui/pokemon_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  setUpAll(() async => dex = await loadPokedex(rootBundle));

  testWidgets('Eevee sheet lists all 8 branches with methods', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EvolutionSheet(dex: dex, current: dex[133], onSelect: (_) {}),
        ),
      ),
    );
    for (final id in [134, 135, 136, 196, 197, 470, 471, 700]) {
      expect(find.byKey(Key('evo-node-$id')), findsOneWidget, reason: '$id');
    }
    expect(find.textContaining('Thunder Stone'), findsOneWidget);
  });

  testWidgets('non-evolving species says so', (tester) async {
    final tauros = dex.entries.firstWhere((e) => e.name == 'Tauros');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EvolutionSheet(dex: dex, current: tauros, onSelect: (_) {}),
        ),
      ),
    );
    expect(find.byKey(const Key('evo-none')), findsOneWidget);
  });

  testWidgets('tapping a node in the sheet opens that Pokémon in place', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PokemonPage(dex: dex, frecency: FrecencyStore(), initialId: 1),
      ),
    );
    await tester.tap(find.byKey(const Key('evo-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('evo-node-3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portrait-3')), findsOneWidget);
    expect(find.byKey(const Key('evo-node-3')), findsNothing); // sheet closed
  });
}
