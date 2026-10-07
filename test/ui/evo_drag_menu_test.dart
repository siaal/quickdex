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

  Future<TestGesture> pressEvo(WidgetTester tester, int id) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PokemonPage(dex: dex, frecency: FrecencyStore(), initialId: id),
      ),
    );
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('evo-button'))),
    );
    await g.moveBy(const Offset(0, 12)); // past the drag threshold
    await tester.pump();
    return g;
  }

  Future<void> dragTo(WidgetTester tester, TestGesture g, Finder f) async {
    await g.moveTo(tester.getCenter(f));
    await tester.pump();
  }

  testWidgets('drag from Evo, release on an evolution switches to it', (
    tester,
  ) async {
    final g = await pressEvo(tester, 1);
    for (final id in [1, 2, 3]) {
      expect(find.byKey(Key('evo-drag-item-$id')), findsOneWidget);
    }
    // The current Pokémon starts under the thumb.
    final evo = tester.getCenter(find.byKey(const Key('evo-button')));
    expect(
      tester.getRect(find.byKey(const Key('evo-drag-item-1'))).top,
      lessThanOrEqualTo(evo.dy + 12),
    );
    await dragTo(tester, g, find.byKey(const Key('evo-drag-item-3')));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portrait-3')), findsOneWidget);
    expect(find.byKey(const Key('evo-drag-item-3')), findsNothing);
  });

  testWidgets('works upwards to pre-evolutions too', (tester) async {
    final g = await pressEvo(tester, 3);
    await dragTo(tester, g, find.byKey(const Key('evo-drag-item-1')));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portrait-1')), findsOneWidget);
  });

  testWidgets('releasing off the list cancels', (tester) async {
    final g = await pressEvo(tester, 1);
    await g.moveTo(const Offset(5, 5));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portrait-1')), findsOneWidget);
    expect(find.byKey(const Key('evo-drag-item-1')), findsNothing);
  });

  testWidgets('Eevee lists all nine', (tester) async {
    final g = await pressEvo(tester, 133);
    for (final id in [133, 134, 135, 136, 196, 197, 470, 471, 700]) {
      expect(find.byKey(Key('evo-drag-item-$id')), findsOneWidget);
    }
    await dragTo(tester, g, find.byKey(const Key('evo-drag-item-700')));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portrait-700')), findsOneWidget);
  });

  testWidgets('non-evolving Pokémon shows no list', (tester) async {
    final tauros = dex.entries.firstWhere((e) => e.name == 'Tauros');
    final g = await pressEvo(tester, tauros.id);
    expect(find.byKey(Key('evo-drag-item-${tauros.id}')), findsNothing);
    await g.up();
    await tester.pumpAndSettle();
  });
}
