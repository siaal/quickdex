import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/ui/learnset_table.dart';
import 'package:quickdex/ui/pokemon_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  late MoveDex moves;
  setUpAll(() async {
    dex = await loadPokedex(rootBundle);
    moves = await loadMoves(rootBundle);
  });
  tearDown(LearnsetTable.resetFilters);

  int moveId(String n) => moves.moves.firstWhere((m) => m.name == n).id;

  Future<FrecencyStore> pump(WidgetTester tester, int id) async {
    final moveFrecency = FrecencyStore();
    await tester.pumpWidget(
      MaterialApp(
        home: PokemonPage(
          dex: dex,
          frecency: FrecencyStore(),
          initialId: id,
          moves: Future.value(moves),
          moveFrecency: moveFrecency,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return moveFrecency;
  }

  testWidgets('level-up table sits above the catch rate line', (tester) async {
    await pump(tester, 25);
    final table = find.byKey(const Key('learnset'));
    expect(table, findsOneWidget);
    expect(
      tester.getTopLeft(table).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('misc-line'))).dy),
    );
    final row = find.byKey(Key('learn-36-${moveId('Thunderbolt')}'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Thunderbolt')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('learnset-game')), findsNothing);
  });

  testWidgets('rows show category symbol left of type, power and accuracy', (
    tester,
  ) async {
    await pump(tester, 25);
    final row = find.byKey(Key('learn-36-${moveId('Thunderbolt')}'));
    Finder inRow(Finder f) => find.descendant(of: row, matching: f);
    final cat = inRow(find.byKey(const Key('cat-special')));
    expect(cat, findsOneWidget);
    expect(inRow(find.text('Special')), findsNothing);
    expect(
      tester.getTopLeft(cat).dx,
      lessThan(tester.getTopLeft(inRow(find.byType(Image))).dx),
    );
    expect(inRow(find.text('90')), findsOneWidget);
    expect(inRow(find.text('100%')), findsOneWidget);
    // Never-miss / status moves show a dash for accuracy.
    final growl = find.byKey(Key('learn-1-${moveId('Growl')}'));
    expect(
      find.descendant(of: growl, matching: find.byKey(const Key('cat-status'))),
      findsOneWidget,
    );
  });

  testWidgets('evolution moves show as Evo', (tester) async {
    await pump(tester, 700);
    final row = find.byKey(Key('learn-0-${moveId('Disarming Voice')}'));
    expect(
      find.descendant(of: row, matching: find.text('Evo')),
      findsOneWidget,
    );
  });

  testWidgets('Pokémon not in Scarlet say which game the table is from', (
    tester,
  ) async {
    await pump(tester, 63); // Abra
    expect(find.text('From Sword/Shield'), findsOneWidget);
  });

  testWidgets('tapping a move opens its page and credits it', (tester) async {
    final f = await pump(tester, 25);
    final row = find.byKey(Key('learn-36-${moveId('Thunderbolt')}'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('move-name')), findsOneWidget);
    expect(f.isFrecent(moveId('Thunderbolt')), isTrue);
  });

  testWidgets('Scarlet starts on Level up; TM and All add numbered TMs', (
    tester,
  ) async {
    expect(LearnsetTable.defaultFilter(moves.game), LearnFilter.levelUp);
    await pump(tester, 25);
    final levelRow = find.byKey(Key('learn-36-${moveId('Thunderbolt')}'));
    final tmRow = find.byKey(const Key('machine-TM126'));
    expect(levelRow, findsOneWidget);
    expect(tmRow, findsNothing);

    await tester.ensureVisible(find.byKey(const Key('learn-filter')));
    await tester.tap(find.byKey(const Key('learn-filter-tm')));
    await tester.pumpAndSettle();
    expect(levelRow, findsNothing);
    await tester.scrollUntilVisible(
      tmRow,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(of: tmRow, matching: find.text('Thunderbolt')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tmRow, matching: find.text('TM126')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const Key('learn-filter')));
    await tester.tap(find.byKey(const Key('learn-filter-all')));
    await tester.pumpAndSettle();
    expect(levelRow, findsOneWidget);
    expect(find.byKey(const Key('tms')), findsOneWidget);
  });

  testWidgets('the picked filter sticks for the next page', (tester) async {
    await pump(tester, 25);
    await tester.ensureVisible(find.byKey(const Key('learn-filter')));
    await tester.tap(find.byKey(const Key('learn-filter-tm')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await pump(tester, 26);
    expect(find.byKey(const Key('tms')), findsOneWidget);
    expect(find.byKey(const Key('learnset-game')), findsNothing);
    expect(find.text('Level-up moves'), findsNothing);
  });

  testWidgets('a Pokémon from an older game learns no TMs here', (
    tester,
  ) async {
    await pump(tester, 63); // Abra: Sword/Shield learnset
    await tester.ensureVisible(find.byKey(const Key('learn-filter')));
    await tester.tap(find.byKey(const Key('learn-filter-tm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('no-tms')), findsOneWidget);
  });

  testWidgets('table follows a form swap', (tester) async {
    await pump(tester, 26);
    await tester.tap(find.byKey(const Key('form-chip-10100')));
    await tester.pumpAndSettle();
    // Alolan Raichu learns Psychic on evolution; Kantonian Raichu doesn't.
    expect(find.byKey(Key('learn-0-${moveId('Psychic')}')), findsOneWidget);
  });
}
