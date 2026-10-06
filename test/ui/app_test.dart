import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/ui/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  setUpAll(() async => dex = await loadPokedex(rootBundle));

  testWidgets('launches on Lookup with the search field focused', (
    tester,
  ) async {
    await tester.pumpWidget(QuickDexApp(dex: dex, frecency: FrecencyStore()));
    await tester.pumpAndSettle();
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);
    final field = tester.widget<TextField>(
      find.byKey(const Key('search-field')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
  });
}
