import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/game.dart';
import 'package:quickdex/data/items.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/search/search_index.dart';
import 'package:quickdex/ui/game_host.dart';
import 'package:quickdex/ui/game_scope.dart';
import 'package:quickdex/ui/item_page.dart';
import 'package:quickdex/ui/search_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  late MoveDex moves;
  late ItemDex scarlet;
  setUpAll(() async {
    dex = await loadPokedex(PlatformAssetBundle());
    moves = await loadMoves(PlatformAssetBundle());
    scarlet = await loadItems(PlatformAssetBundle());
  });

  Item named(ItemDex items, String name) =>
      items.items.firstWhere((i) => i.name == name);

  Future<FrecencyStore> pump(
    WidgetTester tester, {
    ItemDex? items,
    GameInfo game = GameInfo.scarlet,
    SearchMode mode = SearchMode.other,
  }) async {
    final itemFrecency = FrecencyStore();
    await tester.pumpWidget(
      GameScope(
        game: game,
        child: MaterialApp(
          home: SearchScreen(
            dex: dex,
            frecency: FrecencyStore(),
            index: SearchIndex(dex.entries),
            moves: Future.value(moves),
            moveFrecency: FrecencyStore(),
            items: Future.value(items ?? scarlet),
            itemFrecency: itemFrecency,
            initialMode: mode,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return itemFrecency;
  }

  Future<void> type(WidgetTester tester, String q) async {
    await tester.enterText(find.byKey(const Key('search-field')), q);
    await tester.pump();
  }

  test('Scarlet has its real items, each with some text', () {
    expect(scarlet.game, GameInfo.scarlet);
    final names = scarlet.items.map((i) => i.name).toSet();
    expect(names, containsAll(['Leftovers', 'Booster Energy', 'Choice Band']));
    expect(names, isNot(contains('Galactic Key')));
    expect(scarlet.items.where((i) => i.badges != null), isEmpty);
  });

  test('a saved "moves" mode is now Other', () {
    expect(savedSearchMode('moves'), SearchMode.other);
    expect(savedSearchMode('other'), SearchMode.other);
    expect(savedSearchMode('pokemon'), SearchMode.pokemon);
    expect(savedSearchMode(null), SearchMode.all);
    expect(savedSearchMode('nonsense'), SearchMode.all);
  });

  testWidgets('Other lists moves and items together', (tester) async {
    await pump(tester);
    expect(
      tester
          .widget<SegmentedButton<SearchMode>>(
            find.byKey(const Key('search-mode')),
          )
          .selected,
      {SearchMode.other},
    );
    expect(find.text('Other'), findsOneWidget);
    await type(tester, 'leftov');
    final leftovers = named(scarlet, 'Leftovers');
    expect(find.byKey(Key('item-row-${leftovers.id}')), findsOneWidget);
    await type(tester, 'surf');
    expect(
      find.byKey(
        Key('move-row-${moves.moves.firstWhere((m) => m.name == 'Surf').id}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an item opens its page, becomes recent and swipes away', (
    tester,
  ) async {
    final frecency = await pump(tester);
    final band = named(scarlet, 'Choice Band');
    await type(tester, 'choice band');
    await tester.tap(find.byKey(Key('item-row-${band.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(ItemPage), findsOneWidget);
    expect(find.byKey(const Key('item-name')), findsOneWidget);
    expect(find.byKey(const Key('item-sprite')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('item-category'))).data,
      'Choice',
    );
    expect(find.byKey(const Key('item-text')), findsOneWidget);
    expect(find.byKey(const Key('item-effect')), findsOneWidget);
    expect(find.byKey(const Key('item-shop')), findsNothing);
    expect(find.byKey(const Key('item-note')), findsNothing);
    expect(frecency.score(band.id), greaterThan(0));

    await tester.pageBack();
    await tester.pumpAndSettle();
    final dismiss = find.byKey(Key('item-dismiss-${band.id}'));
    expect(dismiss, findsOneWidget, reason: 'recent items swipe away');
    await tester.drag(dismiss, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(frecency.score(band.id), 0);
  });

  testWidgets('Enter opens the top item', (tester) async {
    await pump(tester);
    await type(tester, 'leftovers');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('item-name'))).data,
      'Leftovers',
    );
  });

  testWidgets('Scrambled items show their shop unlock and changes', (
    tester,
  ) async {
    const game = GameInfo('scrambled', 'Scrambled Scarlet', 9);
    final items = (await tester.runAsync(
      () => loadItems(PlatformAssetBundle(), game),
    ))!;
    final zoom = named(items, 'Zoom Lens');
    expect(zoom.badges, 0);
    expect(named(items, 'Choice Band').badges, 4);
    expect(named(items, 'Leppa Berry').note, contains('Not obtainable'));
    await pump(tester, items: items, game: game);
    await type(tester, 'zoom lens');
    expect(find.text('Shop: 0 badges'), findsOneWidget, reason: 'on the row');
    await tester.tap(find.byKey(Key('item-row-${zoom.id}')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('item-shop'))).data,
      'Shop: 0 badges',
    );
    final note = find.byKey(const Key('item-note'));
    expect(
      find.descendant(of: note, matching: find.text('In Scrambled Scarlet')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: note,
        matching: find.textContaining('20% \u2192 100%', findRichText: true),
      ),
      findsOneWidget,
    );
    final name = tester.getRect(find.byKey(const Key('item-name')));
    final shop = tester.getRect(find.byKey(const Key('item-shop')));
    expect(shop.left, greaterThan(name.left), reason: 'right of the name');
  });

  testWidgets('Emerald has its own items and text', (tester) async {
    const game = GameInfo('emerald', 'Emerald', 3);
    final items = (await tester.runAsync(
      () => loadItems(PlatformAssetBundle(), game),
    ))!;
    final names = items.items.map((i) => i.name).toSet();
    expect(names, containsAll(['Mach Bike', 'Leftovers']));
    expect(names, isNot(contains('Booster Energy')));
    expect(
      named(items, 'Leftovers').text,
      'A hold item that gradually restores HP in battle.',
    );
  });
}
