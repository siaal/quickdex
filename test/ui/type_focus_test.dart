import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/ui/matchup_section.dart';
import 'package:quickdex/ui/type_focus.dart';
import 'package:quickdex/ui/type_tile.dart';

TypeChart realChart() => Pokedex.parse(
  File('assets/data/pokedex.json').readAsStringSync(),
  File('assets/data/types.json').readAsStringSync(),
).types;

void main() {
  final chart = realChart();

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: TypeFocus(chart: chart)),
    ),
  );

  testWidgets('attacker mode shows offensive groups', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('focus-type-electric')));
    await tester.pump();
    expect(
      find.byKey(const Key('focus-result-Super effective (2×)-water')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('focus-result-Super effective (2×)-flying')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('focus-result-No effect (0×)-ground')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('focus-result-Not very effective (½×)-grass')),
      findsOneWidget,
    );
  });

  testWidgets('defender mode shows defensive groups', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Defender'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('focus-type-electric')));
    await tester.pump();
    expect(
      find.byKey(const Key('focus-result-Weak to (2×)-ground')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('focus-result-Resistant to (½×)-steel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('focus-result-Resistant to (½×)-flying')),
      findsOneWidget,
    );
  });

  testWidgets('only one type can be selected', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('focus-type-fire')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('focus-type-water')));
    await tester.pump();
    final selected = tester
        .widgetList<TypeTile>(find.byType(TypeTile))
        .where((c) => c.selected)
        .map((c) => c.key)
        .toList();
    expect(selected, [const Key('focus-type-water')]);
  });

  List<Key?> selectedTiles(WidgetTester tester) => tester
      .widgetList<TypeTile>(find.byType(TypeTile))
      .where((c) => c.selected)
      .map((c) => c.key)
      .toList();

  testWidgets('long-press adds a second type: dual defender', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);
    await tester.tap(find.text('Defender'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('focus-type-fighting')));
    await tester.pump();
    await tester.longPress(find.byKey(const Key('focus-type-fairy')));
    await tester.pump();
    expect(
      selectedTiles(tester),
      unorderedEquals([
        const Key('focus-type-fighting'),
        const Key('focus-type-fairy'),
      ]),
    );
    expect(find.text('Fighting + Fairy'), findsOneWidget);
    // Fighting/Fairy: Flying, Psychic, Poison 2×; Bug, Dark ¼×; Dragon 0×.
    for (final t in ['flying', 'psychic', 'poison']) {
      expect(
        find.byKey(Key('focus-result-Weak to (2×)-$t')),
        findsOneWidget,
        reason: t,
      );
    }
    expect(
      find.byKey(const Key('focus-result-Resistant to (¼×)-dark')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('focus-result-Immune to (0×)-dragon')),
      findsOneWidget,
    );
    expect(find.text('4×'), findsNothing, reason: 'empty 4× row hidden');
    expect(find.text('¼×'), findsOneWidget);
  });

  testWidgets('4× weakness is a row inside Weak to', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Defender'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('focus-type-grass')));
    await tester.longPress(find.byKey(const Key('focus-type-bug')));
    await tester.pump();
    expect(find.text('Weak to'), findsOneWidget);
    expect(find.text('4×'), findsOneWidget);
    expect(find.text('Weak to (4×)'), findsNothing);
    final weak = find.ancestor(
      of: find.text('Weak to'),
      matching: find.byType(MatchupSection),
    );
    for (final t in ['fire', 'flying']) {
      expect(
        find.descendant(
          of: weak,
          matching: find.byKey(Key('focus-result-Weak to (4×)-$t')),
        ),
        findsOneWidget,
        reason: t,
      );
    }
  });

  testWidgets('right-click adds; attacker shows combined STAB coverage', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('focus-type-electric')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('focus-type-ice')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    // Ice covers Electric's Ground immunity and Grass/Dragon resists.
    for (final t in ['water', 'flying', 'ground', 'grass', 'dragon']) {
      expect(
        find.byKey(Key('focus-result-Super effective (2×)-$t')),
        findsOneWidget,
        reason: t,
      );
    }
    expect(
      find.byKey(const Key('focus-result-No effect (0×)-ground')),
      findsNothing,
    );
  });

  testWidgets('adding a third replaces the second; tap resets to one', (
    tester,
  ) async {
    await pump(tester);
    await tester.longPress(find.byKey(const Key('focus-type-fire')));
    await tester.pump();
    expect(selectedTiles(tester), [const Key('focus-type-fire')]);
    await tester.longPress(find.byKey(const Key('focus-type-water')));
    await tester.pump();
    await tester.longPress(find.byKey(const Key('focus-type-grass')));
    await tester.pump();
    expect(find.text('Fire + Grass'), findsOneWidget);
    await tester.longPress(find.byKey(const Key('focus-type-fire')));
    await tester.pump();
    expect(
      find.text('Fire + Grass'),
      findsNothing,
      reason: 'long-press removes',
    );
    expect(selectedTiles(tester), [const Key('focus-type-grass')]);
    await tester.longPress(find.byKey(const Key('focus-type-water')));
    await tester.tap(find.byKey(const Key('focus-type-dark')));
    await tester.pump();
    expect(selectedTiles(tester), [const Key('focus-type-dark')]);
  });

  testWidgets('result pills: tap picks, long-press adds; mode is kept', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);
    await tester.tap(find.text('Defender'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('focus-type-fighting')));
    await tester.pump();
    await tester.longPress(
      find.byKey(const Key('focus-result-Weak to (2×)-fairy')),
    );
    await tester.pump();
    expect(find.text('Fighting + Fairy'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('focus-result-Weak to (2×)-psychic')),
    );
    await tester.pump();
    expect(selectedTiles(tester), [const Key('focus-type-psychic')]);
    final mode = tester.widget<SegmentedButton<FocusMode>>(
      find.byKey(const Key('focus-mode')),
    );
    expect(mode.selected, {FocusMode.defender});
  });

  testWidgets('no type name is truncated at Pixel 7 width', (tester) async {
    // The default test font draws every glyph as a square; measure with the
    // Roboto Bold the device uses (worst case for the w600 labels).
    final engine = Platform.resolvedExecutable;
    final cache = engine.substring(0, engine.indexOf('/bin/cache/') + 11);
    final roboto = File('${cache}artifacts/material_fonts/Roboto-Bold.ttf');
    await tester.runAsync(
      () =>
          (FontLoader('Roboto')..addFont(
                Future.value(ByteData.sublistView(roboto.readAsBytesSync())),
              ))
              .load(),
    );
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await pump(tester);
    for (final t in chart.order) {
      final p = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(Key('focus-type-$t')),
          matching: find.byType(RichText),
        ),
      );
      expect(p.didExceedMaxLines, isFalse, reason: t);
    }
  });

  testWidgets('type tiles form a 3-column grid of equal size with icons', (
    tester,
  ) async {
    await pump(tester);
    final tiles = find.byType(TypeTile);
    expect(tiles, findsNWidgets(18));
    final sizes = {
      for (final e in tiles.evaluate()) tester.getSize(find.byWidget(e.widget)),
    };
    expect(sizes, hasLength(1));
    final lefts = {
      for (final e in tiles.evaluate())
        tester.getTopLeft(find.byWidget(e.widget)).dx,
    };
    expect(lefts, hasLength(3));
    expect(
      find.descendant(
        of: find.byKey(const Key('focus-type-fire')),
        matching: find.image(const AssetImage('assets/art/types/fire.png')),
      ),
      findsOneWidget,
    );
  });
}
