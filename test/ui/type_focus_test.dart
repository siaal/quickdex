import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/ui/type_focus.dart';

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
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((c) => c.selected)
        .map((c) => c.key)
        .toList();
    expect(selected, [const Key('focus-type-water')]);
  });
}
