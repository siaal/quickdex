import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/models.dart';
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
