import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/search/search_index.dart';
import 'package:quickdex/team/team.dart';
import 'package:quickdex/ui/team_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  late MoveDex moves;
  setUpAll(() async {
    dex = await loadPokedex(rootBundle);
    moves = await loadMoves(rootBundle);
  });

  PokemonEntry named(String n) => dex.entries.firstWhere((e) => e.name == n);
  int ability(String key) =>
      dex.abilities.entries.firstWhere((a) => a.value.key == key).key;
  int move(String key) => moves.moves.firstWhere((m) => m.key == key).id;

  final openedTypes = <String>[];

  Future<Team> pump(WidgetTester tester, [Team? team]) async {
    openedTypes.clear();
    tester.view.physicalSize = const Size(480, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final t = team ?? Team();
    await tester.pumpWidget(
      MaterialApp(
        home: TeamScreen(
          dex: dex,
          team: t,
          index: SearchIndex(dex.entries),
          frecency: FrecencyStore(),
          moves: Future.value(moves),
          moveFrecency: FrecencyStore(),
          onOpenType: openedTypes.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return t;
  }

  Finder pickRow(int id) => find.byKey(Key('team-pick-row-$id'));
  String cellText(WidgetTester tester, String key) => tester
      .widget<Text>(
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
      )
      .data!;

  testWidgets('empty team shows six add slots and no matchups', (tester) async {
    await pump(tester);
    for (var i = 0; i < Team.size; i++) {
      expect(find.byKey(Key('team-slot-$i')), findsOneWidget);
    }
    expect(find.byIcon(Icons.add), findsNWidgets(6));
    expect(find.byKey(const Key('team-empty')), findsOneWidget);
  });

  testWidgets('add a Pokémon, choose ability and a move, then remove it', (
    tester,
  ) async {
    final bronzong = named('Bronzong');
    final team = await pump(tester);
    await tester.tap(find.byKey(const Key('team-slot-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('team-pick-search')),
      'bronzong',
    );
    await tester.pumpAndSettle();
    await tester.tap(pickRow(bronzong.id));
    await tester.pumpAndSettle();
    expect(team[0]!.pokemon, bronzong.id);
    expect(team[0]!.ability, bronzong.abilities.first, reason: 'defaulted');

    await tester.tap(find.byKey(Key('team-ability-${ability('heatproof')}')));
    await tester.pump();
    expect(team[0]!.ability, ability('heatproof'));

    await tester.tap(find.byKey(const Key('team-move-0')));
    await tester.pumpAndSettle();
    expect(find.text('Level-up moves'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('team-pick-search')),
      'earthquake',
    );
    await tester.pumpAndSettle();
    await tester.tap(pickRow(move('earthquake')));
    await tester.pumpAndSettle();
    expect(team[0]!.moves, [move('earthquake')]);
    expect(find.byKey(const Key('team-move-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('team-move-clear-0')));
    await tester.pump();
    expect(team[0]!.moves, isEmpty);

    await tester.tap(find.byKey(const Key('team-remove')));
    await tester.pumpAndSettle();
    expect(team[0], isNull);
    expect(find.byKey(const Key('team-empty')), findsOneWidget);
  });

  testWidgets('matchup rows count the team and expand to each member', (
    tester,
  ) async {
    final golem = named('Golem');
    final bronzong = named('Bronzong');
    await pump(
      tester,
      Team(
        slots: [
          TeamSlot(golem.id, ability: golem.abilities.first),
          TeamSlot(bronzong.id, ability: ability('levitate')),
          null,
          null,
          null,
          null,
        ],
      ),
    );
    expect(cellText(tester, 'team-weak-ground'), '1');
    expect(cellText(tester, 'team-weak-water'), '1');
    expect(cellText(tester, 'team-hitters-fire'), '1');
    final weakGrass = tester.widget<Container>(
      find.byKey(const Key('team-weak-grass')),
    );
    expect(
      (weakGrass.decoration! as BoxDecoration).color,
      isNull,
      reason: 'Golem weak, Bronzong resists: not a hole',
    );
    expect(find.byKey(const Key('team-detail-water')), findsNothing);
    await tester.tap(find.byKey(const Key('team-row-water')));
    await tester.pump();
    final detail = find.byKey(const Key('team-detail-water'));
    expect(find.descendant(of: detail, matching: find.text('4×')), findsOne);
    expect(
      find.descendant(of: detail, matching: find.text('Bronzong')),
      findsOne,
    );
  });

  Team golemBronzong() {
    final golem = named('Golem');
    return Team(
      slots: [
        TeamSlot(golem.id, ability: golem.abilities.first, moves: const []),
        TeamSlot(named('Bronzong').id, ability: ability('levitate')),
        null,
        null,
        null,
        null,
      ],
    );
  }

  testWidgets('long-press or right-click a slot goes straight to the chooser', (
    tester,
  ) async {
    final team = await pump(tester, golemBronzong());
    final pikachu = named('Pikachu');
    await tester.longPress(find.byKey(const Key('team-slot-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('team-pick-search')),
      'pikachu',
    );
    await tester.pumpAndSettle();
    await tester.tap(pickRow(pikachu.id));
    await tester.pumpAndSettle();
    expect(team[0]!.pokemon, pikachu.id);
    expect(
      find.byKey(const Key('team-remove')),
      findsNothing,
      reason: 'back on the planner, not the slot editor',
    );

    await tester.tap(
      find.byKey(const Key('team-slot-5')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-pick-search')), findsOneWidget);
  });

  List<String> rowOrder(WidgetTester tester) {
    final rows = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('team-row-'),
    );
    final hits = rows.evaluate().toList()
      ..sort(
        (a, b) => tester
            .getTopLeft(find.byWidget(a.widget))
            .dy
            .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
      );
    return [
      for (final e in hits)
        (e.widget.key! as ValueKey<String>).value.substring('team-row-'.length),
    ];
  }

  testWidgets('columns sort on tap and reverse on a second tap', (
    tester,
  ) async {
    await pump(tester, golemBronzong());
    // Chart order is alphabetical, so the first Attacking tap keeps it.
    expect(rowOrder(tester).take(3), ['bug', 'dark', 'dragon']);
    await tester.tap(find.byKey(const Key('team-sort-type')));
    await tester.pump();
    expect(rowOrder(tester).take(3), ['bug', 'dark', 'dragon']);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    await tester.tap(find.byKey(const Key('team-sort-type')));
    await tester.pump();
    expect(rowOrder(tester).first, 'water');
    expect(rowOrder(tester).last, 'bug');

    await tester.tap(find.byKey(const Key('team-sort-immune')));
    await tester.pump();
    // Golem: immune to Electric; Bronzong: Poison, and Ground via Levitate.
    // Ties stay alphabetical.
    expect(rowOrder(tester).take(3), ['electric', 'ground', 'poison']);
    await tester.tap(find.byKey(const Key('team-sort-immune')));
    await tester.pump();
    expect(rowOrder(tester).last, 'electric');
    expect(
      find.byIcon(Icons.arrow_upward),
      findsOneWidget,
      reason: 'fewest first',
    );
  });

  testWidgets('long-press a type pill opens it in the Type Chart', (
    tester,
  ) async {
    await pump(tester, golemBronzong());
    await tester.longPress(find.byKey(const Key('team-type-water')));
    await tester.pump();
    expect(openedTypes, ['water']);
    expect(
      find.byKey(const Key('team-detail-water')),
      findsNothing,
      reason: 'long-press does not toggle the row',
    );
    await tester.longPress(find.byKey(const Key('team-slot-type-steel')));
    await tester.pumpAndSettle();
    expect(openedTypes, ['water', 'steel']);
    expect(
      find.byKey(const Key('team-pick-search')),
      findsNothing,
      reason: 'the pill wins over the slot',
    );
  });

  testWidgets('right-click or long-press a move shows its details', (
    tester,
  ) async {
    final golem = named('Golem');
    final eq = moves.byId[move('earthquake')]!;
    final team = await pump(
      tester,
      Team(
        slots: [
          TeamSlot(golem.id, moves: [eq.id]),
          null,
          null,
          null,
          null,
          null,
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('team-slot-0')));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('team-move-0')));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('move-details-sheet'));
    expect(
      find.descendant(of: sheet, matching: find.text(eq.description!)),
      findsOne,
    );
    await tester.tapAt(const Offset(10, 10)); // dismiss
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);

    await tester.tap(find.byKey(const Key('team-move-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('team-pick-search')),
      'flamethrower',
    );
    await tester.pumpAndSettle();
    final flame = moves.byId[move('flamethrower')]!;
    await tester.tap(pickRow(flame.id), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: sheet, matching: find.text(flame.description!)),
      findsOne,
    );
    expect(team[0]!.moves, [eq.id], reason: 'peeking does not pick');
  });
}
