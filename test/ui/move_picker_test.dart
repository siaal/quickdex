import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/game.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/ui/team_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MoveDex scarlet;
  late MoveDex emerald;
  late int bronzong;
  late int bulbasaur;

  setUp(MovePicker.resetFilters);
  tearDown(MovePicker.resetFilters);

  setUpAll(() async {
    final bundle = PlatformAssetBundle();
    scarlet = await loadMoves(bundle);
    emerald = await loadMoves(bundle, const GameInfo('emerald', 'Emerald', 3));
    final dex = await loadPokedex(bundle);
    bronzong = dex.entries.firstWhere((e) => e.name == 'Bronzong').id;
    bulbasaur = dex.entries.firstWhere((e) => e.name == 'Bulbasaur').id;
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => Navigator.of(context).push<Move>(
                  MaterialPageRoute(
                    builder: (_) => MovePicker(
                      moves: scarlet,
                      frecency: FrecencyStore(),
                      pokemon: bronzong,
                    ),
                  ),
                ),
                child: const Text('Pick move'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Pick move'));
    await tester.pumpAndSettle();
  }

  void expectFilter(WidgetTester tester, LearnFilter filter) {
    expect(
      tester
          .widget<SegmentedButton<LearnFilter>>(
            find.byKey(const Key('learn-filter')),
          )
          .selected,
      {filter},
    );
  }

  for (final filter in [LearnFilter.tm, LearnFilter.levelUp]) {
    testWidgets(
      'move picker retains ${filter.name} after cancel and selection',
      (tester) async {
        await pumpHost(tester);
        await open(tester);
        expectFilter(tester, LearnFilter.all);
        await tester.tap(find.byKey(Key('learn-filter-${filter.name}')));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        await open(tester);
        expectFilter(tester, filter);
        final id = filter == LearnFilter.tm
            ? scarlet.learnsets[bronzong]!.machines.first.move
            : scarlet.learnsets[bronzong]!.moves.first.move;
        await tester.tap(find.byKey(Key('team-pick-row-$id')));
        await tester.pumpAndSettle();
        await open(tester);
        expectFilter(tester, filter);
        await tester.tap(find.byKey(const Key('learn-filter-all')));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        await open(tester);
        expectFilter(tester, LearnFilter.all);
      },
    );
  }

  testWidgets('move picker filter dismisses search focus and keyboard', (
    tester,
  ) async {
    await pumpHost(tester);
    await open(tester);
    final search = find.byKey(const Key('team-pick-search'));
    for (final filter in [
      LearnFilter.tm,
      LearnFilter.levelUp,
      LearnFilter.all,
    ]) {
      await tester.showKeyboard(search);
      await tester.enterText(search, 'earthquake');
      await tester.pumpAndSettle();
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(find.byKey(Key('learn-filter-${filter.name}')));
      await tester.pumpAndSettle();
      expectFilter(tester, filter);
      expect(editable.focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(editable.controller.text, 'earthquake', reason: 'keep the query');
    }
  });

  testWidgets('move picker remembers choices independently per game', (
    tester,
  ) async {
    Future<void> show(MoveDex moves, int pokemon) async {
      // Dispose the previous picker rather than updating its state in place.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: MovePicker(
            moves: moves,
            frecency: FrecencyStore(),
            pokemon: pokemon,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(scarlet, bronzong);
    await tester.tap(find.byKey(const Key('learn-filter-tm')));
    await tester.pumpAndSettle();
    await show(emerald, bulbasaur);
    expectFilter(tester, LearnFilter.all);
    await tester.tap(find.byKey(const Key('learn-filter-levelUp')));
    await tester.pumpAndSettle();
    await show(scarlet, bulbasaur);
    expectFilter(tester, LearnFilter.tm);
    await show(emerald, bulbasaur);
    expectFilter(tester, LearnFilter.levelUp);
  });
}
