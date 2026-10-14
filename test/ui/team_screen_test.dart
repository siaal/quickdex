import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/search/search_index.dart';
import 'package:quickdex/team/builds.dart';
import 'package:quickdex/team/team.dart';
import 'package:quickdex/ui/team_screen.dart';
import 'package:quickdex/ui/matchup_section.dart';

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

  Future<Team> pump(
    WidgetTester tester, [
    Team? team,
    TeamPlanner? planner,
  ]) async {
    openedTypes.clear();
    tester.view.physicalSize = const Size(480, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final t = planner?.mine.team ?? team ?? Team();
    await tester.pumpWidget(
      MaterialApp(
        home: TeamScreen(
          dex: dex,
          planner: planner ?? TeamPlanner(mine: TeamSide(team: t)),
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

    await tester.tap(find.byKey(const Key('team-move-hide-0')));
    await tester.pump();
    expect(team[0]!.moves, [move('earthquake')], reason: 'still filled');
    expect(team[0]!.hidden, {move('earthquake')});
    await tester.tap(find.byKey(const Key('team-move-hide-0')));
    await tester.pump();
    expect(team[0]!.hidden, isEmpty);

    await tester.tap(find.byKey(const Key('team-move-hide-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('team-move-clear-0')));
    await tester.pump();
    expect(team[0]!.moves, isEmpty);
    expect(team[0]!.hidden, isEmpty, reason: 'cleared move forgets hidden');

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
    Color? rowTint(String t) =>
        tester.widget<ColoredBox>(find.byKey(Key('team-tint-$t'))).color;
    // Water: Golem takes 4× deals 1× (behind); Bronzong takes and deals 1× (even).
    expect(rowTint('water'), matchupTint(2, defending: true));
    // Normal: both resist it and deal 1× (ahead).
    expect(rowTint('normal'), matchupTint(2, defending: false));
    // Grass: Golem takes 4× deals 1× (behind); Bronzong takes ½× deals 1× (ahead).
    expect(rowTint('grass'), Colors.transparent);
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

  group('builds', () {
    List<TeamSlot?> slots(List<String> names) => [
      for (var i = 0; i < Team.size; i++)
        i < names.length ? TeamSlot(named(names[i]).id) : null,
    ];

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('save names the team; load brings it back, undoably', (
      tester,
    ) async {
      final planner = TeamPlanner(
        mine: TeamSide(team: Team(slots: slots(['Golem', 'Pikachu']))),
      );
      final team = await pump(tester, null, planner);
      await tapKey(tester, 'team-save');
      await tester.enterText(find.byKey(const Key('team-save-name')), 'Rocks');
      await tester.pump();
      await tapKey(tester, 'team-save-confirm');
      final build = planner.mine.builds.named('Rocks')!;
      expect(find.byKey(const Key('team-name')), findsOne);
      expect(planner.mine.frecency.isFrecent(build.id), isTrue);

      team[1] = null;
      await tester.pumpAndSettle();
      await tapKey(tester, 'team-save');
      expect(
        find.descendant(
          of: find.byKey(const Key('team-save-confirm')),
          matching: find.text('Overwrite'),
        ),
        findsOne,
        reason: 'the loaded name is offered again',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(planner.mine.builds.named('Rocks')!.slots[1], isNotNull);

      await tapKey(tester, 'team-load');
      await tapKey(tester, 'team-pick-row-${build.id}');
      expect(team[1]!.pokemon, named('Pikachu').id);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(team[1], isNull);

      await tapKey(tester, 'team-load');
      await tapKey(tester, 'team-pick-row-${build.id}');
      expect(find.byType(SnackBar), findsOne);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing, reason: 'gone within 5 s');
    });

    testWidgets('load lists builds most recently used first', (tester) async {
      final planner = TeamPlanner();
      final a = planner.mine.builds.save('Alpha', slots(['Golem']));
      final b = planner.mine.builds.save('Beta', slots(['Pikachu']));
      planner.mine.frecency
        ..visit(b.id)
        ..visit(a.id);
      await pump(tester, null, planner);
      await tapKey(tester, 'team-load');
      double top(int id) =>
          tester.getTopLeft(find.byKey(Key('team-pick-row-$id'))).dy;
      expect(top(a.id), lessThan(top(b.id)));
    });

    testWidgets('a build swipes away after confirming', (tester) async {
      final planner = TeamPlanner();
      final a = planner.mine.builds.save('Alpha', slots(['Golem']));
      planner.mine.frecency.visit(a.id);
      await pump(tester, null, planner);
      await tapKey(tester, 'team-load');
      await tester.drag(
        find.byKey(Key('build-dismiss-${a.id}')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'build-delete-confirm');
      expect(planner.mine.builds.builds, isEmpty);
      expect(planner.mine.frecency.isFrecent(a.id), isFalse);
      expect(find.byKey(Key('team-pick-row-${a.id}')), findsNothing);
    });

    testWidgets('Theirs saves and loads its own builds, plus boss teams', (
      tester,
    ) async {
      final boss = TeamBuild(7, 'Gym Leader · Lv. 20', slots(['Bronzong']));
      final planner = TeamPlanner(
        mine: TeamSide(team: Team(slots: slots(['Golem']))),
        theirs: TeamSide(
          builds: SavedBuilds(idBase: SavedBuilds.theirsIdBase),
          presets: [boss],
        ),
      );
      planner.mine.builds.save('Mine only', slots(['Pikachu']));
      await pump(tester, null, planner);
      await tester.tap(find.text('Theirs'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-empty')), findsOne);
      await tapKey(tester, 'team-load');
      expect(find.text('Mine only'), findsNothing);
      expect(
        find.byKey(const Key('build-dismiss-7')),
        findsNothing,
        reason: 'boss teams cannot be deleted',
      );
      await tapKey(tester, 'team-pick-row-7');
      final theirs = planner.theirs.team;
      expect(theirs[0]!.pokemon, named('Bronzong').id);
      expect(theirs.name, boss.name);
      expect(planner.mine.team[0]!.pokemon, named('Golem').id);
      expect(planner.theirs.frecency.isFrecent(7), isTrue);

      await tapKey(tester, 'team-save');
      await tester.enterText(find.byKey(const Key('team-save-name')), 'Iono');
      await tester.pump();
      await tapKey(tester, 'team-save-confirm');
      final saved = planner.theirs.builds.named('Iono')!;
      expect(saved.id, greaterThan(SavedBuilds.theirsIdBase));
      expect(planner.mine.builds.named('Iono'), isNull);
      await tapKey(tester, 'team-load');
      expect(find.byKey(Key('team-pick-row-${saved.id}')), findsOne);
      expect(find.byKey(Key('build-dismiss-${saved.id}')), findsOne);
    });

    testWidgets('save and load sit left of the Mine | Theirs toggle', (
      tester,
    ) async {
      await pump(tester);
      double left(String key) => tester.getTopLeft(find.byKey(Key(key))).dx;
      expect(left('team-save'), lessThan(left('team-load')));
      expect(left('team-load'), lessThan(left('team-side')));
      expect(
        tester.getTopRight(find.byKey(const Key('team-side'))).dx,
        greaterThan(480 - 24),
        reason: 'right-aligned',
      );
    });
  });
}
