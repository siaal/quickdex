import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/team/team.dart';
import 'package:quickdex/ui/sidedeck_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  late MoveDex moves;
  setUpAll(() async {
    dex = await loadPokedex(PlatformAssetBundle());
    moves = await loadMoves(PlatformAssetBundle());
  });

  TeamSlot slot(String name) =>
      TeamSlot(dex.entries.firstWhere((e) => e.name == name).id);
  Team team() => Team()
    ..add(slot('Zangoose'))
    ..add(slot('Abra'))
    ..add(slot('Pikachu'))
    ..add(slot('Golem'))
    ..toggle(2)
    ..toggle(0);

  List<int> order(WidgetTester tester) => [
    for (final widget in tester.widgetList<InkWell>(find.byType(InkWell)))
      if (widget.key case ValueKey<String>(
        value: final key,
      ) when key.startsWith('deck-row-'))
        int.parse(key.substring('deck-row-'.length)),
  ];

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Open Sidedeck'));
    await tester.pumpAndSettle();
  }

  Future<void> host(WidgetTester tester, Team team) async {
    tester.view.physicalSize = const Size(480, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SidedeckPage(
                    team: team,
                    dex: dex,
                    moves: Future.value(moves),
                    onEdit: (_, member) =>
                        team.setMember(member, slot('Zubat')),
                    onAdd: (_) => team.add(slot('Bulbasaur')),
                  ),
                ),
              ),
              child: const Text('Open Sidedeck'),
            ),
          ),
        ),
      ),
    );
    await open(tester);
  }

  Future<void> sort(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const Key('deck-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('deck-sort-$name')));
    await tester.pumpAndSettle();
  }

  testWidgets('header has Sort and a rightmost +, without an Add Pokemon row', (
    tester,
  ) async {
    final t = team();
    await host(tester, t);
    final add = find.byKey(const Key('deck-add'));
    expect(tester.widget(add), isA<IconButton>());
    expect(
      find.descendant(of: find.byType(AppBar), matching: add),
      findsOneWidget,
    );
    expect(
      tester.getCenter(add).dx,
      greaterThan(tester.getCenter(find.byKey(const Key('deck-sort'))).dx),
    );
    expect(find.text('Add Pokémon'), findsNothing);
    expect(order(tester), [1, 3, 0, 2]);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(t.deck, hasLength(5));
    expect(order(tester), [
      1,
      3,
      0,
      2,
      4,
    ], reason: 'new members append even when added to the party');
  });

  testWidgets(
    'Recency defaults to party first and most recently benched first',
    (tester) async {
      final t = team();
      await host(tester, t);
      expect(order(tester), [1, 3, 0, 2]);
      final original = t.deck.map((s) => s.pokemon).toList();
      await tester.tap(find.byKey(const Key('deck-row-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-row-1')));
      await tester.pumpAndSettle();
      expect(order(tester), [
        1,
        3,
        0,
        2,
      ], reason: 'membership changes must not move rows');
      expect(find.byKey(const Key('deck-in-0-true')), findsOneWidget);
      expect(find.byKey(const Key('deck-in-1-false')), findsOneWidget);
      expect(
        t.deck.map((s) => s.pokemon),
        original,
        reason: 'sorting is only a view',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await open(tester);
      expect(order(tester), [0, 3, 1, 2]);
    },
  );

  testWidgets(
    'Name keeps party first and freezes edits until a sort selection',
    (tester) async {
      final t = team();
      await host(tester, t);
      await sort(tester, 'name');
      expect(order(tester), [1, 3, 2, 0]);
      await tester.longPress(find.byKey(const Key('deck-row-1')));
      await tester.pumpAndSettle();
      expect(order(tester), [
        1,
        3,
        2,
        0,
      ], reason: 'editing must not move a row');
      await sort(tester, 'name');
      expect(order(tester), [3, 1, 2, 0]);
      final restored = Team.fromJson(t.toJson(), dex);
      await tester.pumpWidget(const SizedBox());
      await host(tester, restored);
      expect(order(tester), [
        3,
        1,
        2,
        0,
      ], reason: 'sort choice survives restart');
      await tester.tap(find.byKey(const Key('deck-row-0')));
      await tester.pumpAndSettle();
      expect(order(tester), [
        3,
        1,
        2,
        0,
      ], reason: 'Name also freezes membership changes');
      await sort(tester, 'name');
      expect(order(tester), [3, 0, 1, 2]);
    },
  );

  testWidgets('bench recency survives restart and slot-editor removals', (
    tester,
  ) async {
    final t = team();
    t[3] = null;
    final restored = Team.fromJson(t.toJson(), dex);
    await host(tester, restored);
    expect(order(tester), [1, 3, 0, 2]);
    await tester.tap(find.byKey(const Key('deck-row-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deck-row-2')));
    await tester.pumpAndSettle();
    expect(order(tester), [1, 3, 0, 2]);
    await sort(tester, 'recency');
    expect(order(tester), [1, 2, 3, 0]);
  });

  testWidgets(
    'duplicate Pokemon remain independently editable and selectable',
    (tester) async {
      final duplicate = slot('Pikachu');
      final t = Team()
        ..add(duplicate)
        ..add(duplicate);
      await host(tester, t);
      expect(tester.takeException(), isNull);
      expect(order(tester), [0, 1]);
      await tester.longPress(find.byKey(const Key('deck-row-0')));
      await tester.pumpAndSettle();
      expect(t.deck[0].pokemon, slot('Zubat').pokemon);
      expect(t.deck[1].pokemon, duplicate.pokemon);
      await tester.tap(find.byKey(const Key('deck-row-1')));
      await tester.pumpAndSettle();
      expect(t.slotOf(0), isNotNull);
      expect(t.slotOf(1), isNull);
      expect(order(tester), [0, 1]);
    },
  );

  testWidgets('deletion preserves the frozen order and remaps deck indices', (
    tester,
  ) async {
    final t = team();
    await host(tester, t);
    t.remove(0);
    await tester.pumpAndSettle();
    expect(order(tester), [0, 2, 1]);
    await tester.tap(find.byKey(const Key('deck-row-1')));
    await tester.pumpAndSettle();
    expect(t.slotOf(1), isNotNull);
    expect(t.deck[1].pokemon, slot('Pikachu').pokemon);
  });
}
