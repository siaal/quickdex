import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/ui/type_badge.dart';
import 'package:quickdex/ui/type_style.dart';

void main() {
  test('dark text exactly where white contrast is below 2.3:1', () {
    for (final MapEntry(key: t, value: c) in typeColors.entries) {
      // WCAG contrast of white (luminance 1) on this colour.
      final contrast = 1.05 / (c.computeLuminance() + 0.05);
      expect(darkTextTypes.contains(t), contrast < 2.3, reason: '$t $contrast');
    }
  });

  test('Normal is Scarlet\'s grey, not olive (looked like Bug)', () {
    expect(typeColors['normal'], const Color(0xFF9FA19F));
  });

  testWidgets('badges use the hard-coded text colour', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(children: [TypeBadge('electric'), TypeBadge('water')]),
      ),
    );
    Color colorOf(String label) =>
        tester.widget<Text>(find.text(label)).style!.color!;
    expect(colorOf('Electric'), Colors.black);
    expect(colorOf('Water'), Colors.white);
  });
}
