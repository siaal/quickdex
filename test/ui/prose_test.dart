import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/ui/ability_line.dart';
import 'package:quickdex/ui/move_page.dart';
import 'package:quickdex/ui/prose.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  late MoveDex moves;
  setUpAll(() async {
    dex = await loadPokedex(rootBundle);
    moves = await loadMoves(rootBundle);
  });

  Move move(String key) => moves.moves.firstWhere((m) => m.key == key);

  /// Pixel 7 width, so long cells have to wrap.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  // The test font (Ahem) is far wider than Roboto, so a not-in-game move's
  // header row needs more than a phone's width; the default 800px surface it is.
  Future<void> details(WidgetTester tester, String key) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: MoveDetails(move(key))),
        ),
      ),
    );
  }

  /// The table's cell texts, row by row.
  List<List<String>> cells(WidgetTester tester, Finder table) => [
    for (final row in tester.widget<Table>(table).children)
      [
        for (final c in row.children)
          tester
              .widget<Text>(
                find.descendant(
                  of: find.byWidget(c),
                  matching: find.byType(Text),
                ),
              )
              .data!,
      ],
  ];

  testWidgets('Low Kick draws its weight table as a table', (tester) async {
    await details(tester, 'low-kick');
    final desc = find.byKey(const Key('move-desc'));
    final table = find.descendant(of: desc, matching: find.byType(Table));
    expect(table, findsOneWidget);
    expect(cells(tester, table), [
      ['Target\u2019s weight', 'Power'],
      ['Up to 10kg', '20'],
      ['Up to 25kg', '40'],
      ['Up to 50kg', '60'],
      ['Up to 100kg', '80'],
      ['Up to 200kg', '100'],
      ['Above 200kg', '120'],
    ]);
    expect(find.textContaining('----'), findsNothing, reason: 'no rule shown');
    expect(find.textContaining('|'), findsNothing);
    // "----:" right-aligns the power column.
    expect(tester.widget<Text>(find.text('120')).textAlign, TextAlign.right);
    expect(
      tester.widget<Text>(find.text('Above 200kg')).textAlign,
      TextAlign.left,
    );
    expect(
      tester.getTopLeft(find.text('Up to 10kg')).dy,
      greaterThan(
        tester.getBottomLeft(find.textContaining('to a maximum of 120')).dy,
      ),
      reason: 'below the prose',
    );
  });

  testWidgets('every move with a power table draws one', (tester) async {
    for (final key in [
      'grass-knot',
      'heavy-slam',
      'heat-crash',
      'electro-ball',
      'flail',
      'reversal',
      'present',
    ]) {
      await details(tester, key);
      expect(find.byType(Table), findsOneWidget, reason: key);
      expect(tester.takeException(), isNull, reason: key);
    }
    await details(tester, 'flail');
    expect(find.text('0\u20131'), findsOneWidget, reason: 'range tidied');
    await details(tester, 'magnitude');
    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining('double power against'), findsOneWidget);
  });

  testWidgets('formulas lose their backticks', (tester) async {
    await details(tester, 'eruption');
    expect(find.textContaining('`'), findsNothing);
    expect(
      find.textContaining('150 * HP / max HP', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('Hard Press has a description', (tester) async {
    await details(tester, 'hard-press');
    expect(
      find.textContaining('100 \u00d7 the target\u2019s current HP'),
      findsOneWidget,
    );
  });

  testWidgets('ability tables fit the dialog at phone width', (tester) async {
    phone(tester);
    final forewarn = dex.abilities.entries
        .firstWhere((a) => a.value.key == 'forewarn')
        .key;
    final entry = dex.entries.firstWhere((e) => e.abilities.contains(forewarn));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AbilityLine(entry: entry, abilities: dex.abilities),
        ),
      ),
    );
    await tester.tap(find.byKey(Key('ability-$forewarn')));
    await tester.pumpAndSettle();
    final table = find.descendant(
      of: find.byKey(const Key('ability-description')),
      matching: find.byType(Table),
    );
    expect(table, findsOneWidget);
    expect(cells(tester, table).first, ['Power', 'Moves']);
    expect(tester.takeException(), isNull);
  });

  test('only a paragraph led by a header and rule is a table', () {
    expect(ProseText.tableOf('a | b\n--- | ---:\nc | d'), [
      ['a', 'b'],
      ['---', '---:'],
      ['c', 'd'],
    ]);
    expect(ProseText.tableOf('Head Smash | Headlong Rush'), isNull);
    expect(ProseText.tableOf('a | b\nc | d\ne | f'), isNull);
  });
}
