import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/ui/stat_bars.dart';

void main() {
  testWidgets('rows read HP, Atk, SpA, Def, SpD, Spe with matching values', (
    tester,
  ) async {
    // Data order is PokéAPI's: hp, atk, def, spa, spd, spe.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StatBars(stats: [1, 2, 3, 4, 5, 6])),
      ),
    );
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    expect(texts, [
      'HP', '1', //
      'Atk', '2',
      'SpA', '4',
      'Def', '3',
      'SpD', '5',
      'Spe', '6',
      'Total', '21',
    ]);
  });
}
