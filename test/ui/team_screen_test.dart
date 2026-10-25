import 'package:flutter/gestures.dart';
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
import 'package:quickdex/team/builds.dart';
import 'package:quickdex/team/team.dart';
import 'package:quickdex/ui/team_screen.dart';
import 'package:quickdex/ui/type_badge.dart';
import 'package:quickdex/ui/versus_view.dart';
import 'package:quickdex/ui/matchup_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  late MoveDex moves;
  late ItemDex items;
  setUp(MovePicker.resetFilters);
  tearDown(MovePicker.resetFilters);
  setUpAll(() async {
    dex = await loadPokedex(rootBundle);
    moves = await loadMoves(rootBundle);
    items = await loadItems(rootBundle);
  });

  PokemonEntry named(String n) => dex.entries.firstWhere((e) => e.name == n);
  int ability(String key) =>
      dex.abilities.entries.firstWhere((a) => a.value.key == key).key;
  int move(String key) => moves.moves.firstWhere((m) => m.key == key).id;

  final openedTypes = <String>[];
  final openedPokemon = <int>[];

  Future<Team> pump(
    WidgetTester tester, [
    Team? team,
    TeamPlanner? planner,
  ]) async {
    openedTypes.clear();
    openedPokemon.clear();
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
          items: Future.value(items),
          itemFrecency: FrecencyStore(),
          onOpenType: openedTypes.add,
          onOpenPokemon: (e) => openedPokemon.add(e.id),
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
    expect(
      find.text('Unknown'),
      findsNWidgets(6),
      reason: 'the item, Tera type and moves start unknown',
    );

    await tester.tap(find.byKey(const Key('team-move-3')));
    await tester.pumpAndSettle();
    // Level up | All | TM toggle, All to start: level-up moves, then TMs.
    final learnset = moves.learnsets[bronzong.id]!;
    final levelUp = learnset.moves.first.move;
    final tm = learnset.machines.first.move;
    expect(learnset.moves.map((m) => m.move), isNot(contains(tm)));
    expect(find.byKey(const Key('learn-filter')), findsOneWidget);
    expect(pickRow(levelUp), findsOneWidget);
    await tester.tap(find.byKey(const Key('learn-filter-tm')));
    await tester.pumpAndSettle();
    expect(pickRow(levelUp), findsNothing);
    expect(pickRow(tm), findsOneWidget);
    await tester.tap(find.byKey(const Key('learn-filter-levelUp')));
    await tester.pumpAndSettle();
    expect(pickRow(tm), findsNothing);
    expect(pickRow(levelUp), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('team-pick-search')),
      'earthquake',
    );
    await tester.pumpAndSettle();
    await tester.tap(pickRow(move('earthquake')));
    await tester.pumpAndSettle();
    expect(team[0]!.moves, [move('earthquake')]);
    expect(find.byKey(const Key('team-move-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('team-move-1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<LearnFilter>>(
            find.byKey(const Key('learn-filter')),
          )
          .selected,
      {LearnFilter.levelUp},
      reason: 'the next move keeps the previous picker choice',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

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

  testWidgets('long-press or right-click a filled slot opens its page', (
    tester,
  ) async {
    final team = await pump(tester, golemBronzong());
    await tester.longPress(find.byKey(const Key('team-slot-0')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('team-slot-1')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(openedPokemon, [named('Golem').id, named('Bronzong').id]);
    expect(find.byKey(const Key('team-pick-search')), findsNothing);
    expect(find.byKey(const Key('team-remove')), findsNothing);
    expect(team.deck.length, 2, reason: 'the team is untouched');

    // An empty slot has no page: holding it goes to the chooser.
    await tester.tap(
      find.byKey(const Key('team-slot-5')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-pick-search')), findsOneWidget);
  });

  testWidgets('changing the Pok\u00e9mon in the editor benches the old one', (
    tester,
  ) async {
    final golem = named('Golem');
    final pikachu = named('Pikachu');
    final start = golemBronzong();
    start[0] = start[0]!.copyWith(moves: [move('earthquake')]);
    final team = await pump(tester, start);
    await tester.tap(find.byKey(const Key('team-slot-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-pokemon')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('team-pick-search')),
      'pikachu',
    );
    await tester.pumpAndSettle();
    await tester.tap(pickRow(pikachu.id));
    await tester.pumpAndSettle();

    expect(team[0]!.pokemon, pikachu.id);
    expect(team[0]!.moves, isEmpty, reason: 'a new member');
    final old = team.deck.indexWhere((s) => s.pokemon == golem.id);
    expect(team.slotOf(old), isNull, reason: 'benched');
    expect(team.deck[old].moves, [move('earthquake')], reason: 'kept as is');
    expect(find.text('Slot 1'), findsOneWidget, reason: 'still editing');
    expect(find.text('Pikachu'), findsWidgets);

    // The editor now edits Pikachu: its trash benches Pikachu, not Golem.
    await tester.tap(find.byKey(const Key('team-remove')));
    await tester.pumpAndSettle();
    expect(team[0], isNull);
    expect(team.deck.length, 3, reason: 'only deleting deletes');

    // Picking the same Pok\u00e9mon again is no change.
    await tester.tap(find.byKey(const Key('team-slot-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-pokemon')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('team-pick-search')),
      'bronzong',
    );
    await tester.pumpAndSettle();
    await tester.tap(pickRow(named('Bronzong').id));
    await tester.pumpAndSettle();
    expect(team.deck.length, 3);
  });

  testWidgets('in the slot editor, hold the Pokemon to open its page', (
    tester,
  ) async {
    final team = await pump(tester, golemBronzong());
    await tester.tap(find.byKey(const Key('team-slot-0')));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const Key('team-pokemon')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('team-pokemon')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(openedPokemon, [named('Golem').id, named('Golem').id]);
    expect(find.byKey(const Key('team-pick-search')), findsNothing);
    expect(team.deck.length, 2, reason: 'the team is untouched');
  });

  Future<void> dragSlot(WidgetTester tester, int from, int to) async {
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(Key('team-slot-$from'))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await g.moveTo(tester.getCenter(find.byKey(Key('team-slot-$to'))));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('hold and drag a slot onto another to swap them', (tester) async {
    final golem = named('Golem').id;
    final bronzong = named('Bronzong').id;
    final team = await pump(tester, golemBronzong());
    final deck = team.deck;
    await dragSlot(tester, 0, 1);
    expect([team[0]?.pokemon, team[1]?.pokemon], [bronzong, golem]);
    await dragSlot(tester, 1, 4);
    expect([team[1], team[4]?.pokemon], [null, golem], reason: 'moved');
    expect(team.deck, deck, reason: 'only the squad order changes');
    expect(openedPokemon, isEmpty, reason: 'a drag is not a hold');
    expect(find.byKey(const Key('team-pick-search')), findsNothing);

    // An empty slot has nothing to drag: holding it opens the chooser.
    await dragSlot(tester, 1, 0);
    expect(team[0]?.pokemon, bronzong);
    expect(find.byKey(const Key('team-pick-search')), findsOneWidget);
  });

  testWidgets('a mouse drags a slot straight away; a click still edits', (
    tester,
  ) async {
    final golem = named('Golem').id;
    final bronzong = named('Bronzong').id;
    final team = await pump(tester, golemBronzong());
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('team-slot-0'))),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(20, 0));
    await tester.pump();
    await g.moveTo(tester.getCenter(find.byKey(const Key('team-slot-1'))));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect([team[0]?.pokemon, team[1]?.pokemon], [bronzong, golem]);
    expect(find.byKey(const Key('team-pokemon')), findsNothing);

    await tester.tap(
      find.byKey(const Key('team-slot-0')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-pokemon')), findsOne);
  });

  testWidgets('a held item on the card does not block the drag', (
    tester,
  ) async {
    final leftovers = items.items.firstWhere((i) => i.key == 'leftovers');
    final golem = named('Golem');
    final team = await pump(
      tester,
      Team(
        slots: [
          TeamSlot(golem.id, item: leftovers.id),
          null,
          null,
          null,
          null,
          null,
        ],
      ),
    );
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('team-slot-item-0'))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await g.moveTo(tester.getCenter(find.byKey(const Key('team-slot-2'))));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(team[2]?.pokemon, golem.id);
  });

  testWidgets('the card shows the chosen ability and Tera type', (
    tester,
  ) async {
    final golem = named('Golem');
    await pump(
      tester,
      Team(
        slots: [
          TeamSlot(
            golem.id,
            ability: ability('sturdy'),
            tera: 'water',
            item: items.items.firstWhere((i) => i.key == 'leftovers').id,
          ),
          TeamSlot(named('Bronzong').id),
          null,
          null,
          null,
          null,
        ],
      ),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('team-slot-ability-0'))).data,
      'Sturdy',
    );
    expect(find.byKey(const Key('team-slot-ability-1')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('team-slot-tera-0')),
        matching: find.text('Tera: Water'),
      ),
      findsOne,
      reason: "a pill like the types', in the type's colours",
    );
    expect(find.byKey(const Key('team-slot-tera-1')), findsNothing);

    Rect rect(String k) => tester.getRect(find.byKey(Key(k)));
    Rect sprite(int slot) => tester.getRect(
      find
          .descendant(
            of: find.byKey(Key('team-slot-$slot')),
            matching: find.byType(Image),
          )
          .first,
    );
    Rect name(int slot) => tester.getRect(
      find.descendant(
        of: find.byKey(Key('team-slot-$slot')),
        matching: find.text(slot == 0 ? 'Golem' : 'Bronzong'),
      ),
    );

    // Narrow (three to a phone): the sprite, name, types, then the Tera
    // type, item and ability, all flush left.
    var [tera, item, ab] = [
      'team-slot-tera-0',
      'team-slot-item-0',
      'team-slot-ability-0',
    ].map(rect).toList();
    expect(sprite(0).left, name(0).left, reason: 'sprite and name aligned');
    expect(tera.top, greaterThan(rect('team-slot-type-rock').bottom));
    expect(tera.bottom, lessThanOrEqualTo(item.top));
    expect(item.bottom, lessThanOrEqualTo(ab.top));
    expect(name(1).top, name(0).top, reason: 'names line up across cards');
    expect(sprite(1).size, sprite(0).size);

    // Wide: the Tera type, item and ability beside a bigger sprite.
    final narrowSprite = sprite(0).height;
    tester.view.physicalSize = const Size(1200, 2400);
    await tester.pumpAndSettle();
    [tera, item, ab] = [
      'team-slot-tera-0',
      'team-slot-item-0',
      'team-slot-ability-0',
    ].map(rect).toList();
    for (final r in [tera, item, ab]) {
      expect(r.left, greaterThanOrEqualTo(sprite(0).right - 1));
      expect(r.bottom, lessThan(name(0).top));
    }
    expect(tera.bottom, lessThanOrEqualTo(item.top));
    expect(item.bottom, lessThanOrEqualTo(ab.top));
    expect(sprite(0).left, name(0).left, reason: 'sprite and name aligned');
    expect(sprite(0).height, greaterThan(narrowSprite * 1.4));
    expect(name(1).top, name(0).top, reason: 'names line up across cards');
  });

  testWidgets('a Tera type is picked in the editor and cleared', (
    tester,
  ) async {
    final team = await pump(tester, golemBronzong());
    await tester.tap(find.byKey(const Key('team-slot-0')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('team-tera')),
        matching: find.text('Unknown'),
      ),
      findsOne,
    );
    await tester.tap(find.byKey(const Key('team-tera')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-tera-pick-water')));
    await tester.pumpAndSettle();
    expect(team[0]!.tera, 'water');
    expect(team[0]!.ability, isNotNull, reason: 'the rest is kept');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-slot-tera-0')), findsOne);
    await tester.tap(find.byKey(const Key('team-slot-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-tera-clear')));
    await tester.pump();
    expect(team[0]!.tera, isNull);
  });

  testWidgets('before Gen 9 there are no Tera types', (tester) async {
    // rootBundle's cached loads never finish in this test's fake-async zone.
    final bundle = PlatformAssetBundle();
    final emerald = (await tester.runAsync(() async {
      final games = await loadGames(bundle);
      return loadPokedex(bundle, games.firstWhere((g) => g.key == 'emerald'));
    }))!;
    final golem = emerald.entries.firstWhere((e) => e.name == 'Golem');
    final planner = TeamPlanner(
      mine: TeamSide(
        team: Team(
          slots: [
            TeamSlot(golem.id, tera: 'water'),
            null,
            null,
            null,
            null,
            null,
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TeamScreen(
          dex: emerald,
          planner: planner,
          index: SearchIndex(emerald.entries),
          frecency: FrecencyStore(),
          moveFrecency: FrecencyStore(),
          moves: Future.value(moves),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-slot-tera-0')), findsNothing);
    await tester.tap(find.byKey(const Key('team-slot-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-tera')), findsNothing);
  });

  Finder inSection(String section, String pill) => find.descendant(
    of: find.byKey(Key(section)),
    matching: find.byKey(Key(pill)),
  );

  testWidgets(
    'the slot editor shows matchups, 1\u00d7 included, from its moves',
    (tester) async {
      final pikachu = named('Pikachu');
      await pump(
        tester,
        Team(
          slots: [
            TeamSlot(
              pikachu.id,
              ability: pikachu.abilities.first,
              moves: [
                move('thunderbolt'),
                move('thunder-wave'),
                move('growl'),
                move('tail-whip'),
              ],
            ),
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
      expect(find.byKey(const Key('team-matchups')), findsOneWidget);
      expect(inSection('def-section-Weak to', 'def-2.0-ground'), findsOne);
      expect(inSection('def-section-Neutral', 'def-1.0-fire'), findsOne);
      expect(inSection('def-section-Resistant to', 'def-0.5-flying'), findsOne);
      // Only Thunderbolt deals damage: Electric coverage.
      expect(inSection('off-section', 'off-water'), findsOne);
      expect(inSection('off-section-neutral', 'off-normal'), findsOne);
      expect(inSection('off-section-weak', 'off-grass'), findsOne);
      expect(inSection('off-section-none', 'off-ground'), findsOne);
    },
  );

  testWidgets('editor matchups name an ability immunity and status-only sets', (
    tester,
  ) async {
    final bronzong = named('Bronzong');
    final team = await pump(
      tester,
      Team(
        slots: [
          TeamSlot(
            bronzong.id,
            ability: ability('levitate'),
            moves: [
              move('hypnosis'),
              move('trick-room'),
              move('rain-dance'),
              move('sunny-day'),
            ],
          ),
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
    expect(inSection('def-section-Immune to', 'def-guard-ground'), findsOne);
    expect(find.text('(Levitate)'), findsOneWidget);
    expect(find.byKey(const Key('off-no-damage')), findsOneWidget);

    await tester.tap(find.byKey(Key('team-ability-${ability('heatproof')}')));
    await tester.pump();
    expect(team[0]!.ability, ability('heatproof'));
    expect(inSection('def-section-Weak to', 'def-2.0-ground'), findsOne);
    expect(find.byKey(const Key('def-guard-ground')), findsNothing);
  });

  testWidgets('a held item starts unknown, is picked, shown and cleared', (
    tester,
  ) async {
    final leftovers = items.items.firstWhere((i) => i.key == 'leftovers');
    final team = await pump(tester, golemBronzong());
    expect(team[0]!.item, isNull);
    expect(find.byKey(const Key('team-slot-item-0')), findsNothing);
    await tester.tap(find.byKey(const Key('team-slot-0')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('team-item')),
        matching: find.text('Unknown'),
      ),
      findsOne,
    );
    await tester.tap(find.byKey(const Key('team-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('team-pick-search')),
      'leftovers',
    );
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('item-details-sheet'));
    await tester.longPress(pickRow(leftovers.id));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: sheet, matching: find.text(leftovers.effect!)),
      findsOne,
      reason: 'holding a picker row previews it',
    );
    await tester.tapAt(const Offset(10, 10)); // dismiss
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    await tester.tap(pickRow(leftovers.id));
    await tester.pumpAndSettle();
    expect(team[0]!.item, leftovers.id);
    expect(team[0]!.moves, isEmpty, reason: 'the rest is kept');
    expect(
      find.descendant(
        of: find.byKey(const Key('team-item')),
        matching: find.text('Leftovers'),
      ),
      findsOne,
    );
    await tester.tap(
      find.byKey(const Key('team-item')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: sheet, matching: find.text(leftovers.effect!)),
      findsOne,
      reason: 'right-clicking the chosen item previews it',
    );
    expect(team[0]!.item, leftovers.id, reason: 'not a pick');
    await tester.tapAt(const Offset(10, 10)); // dismiss
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byKey(const Key('team-slot-0')));
    final badge = tester.getRect(find.byKey(const Key('team-slot-item-0')));
    expect(
      badge.height,
      greaterThanOrEqualTo(22),
      reason: 'big enough to read',
    );
    expect(card.contains(badge.bottomRight), isTrue, reason: 'inside its card');
    expect(find.text('Leftovers'), findsOne, reason: 'named beside its sprite');
    expect(find.byKey(const Key('team-slot-item-1')), findsNothing);

    await tester.tap(find.byKey(const Key('team-slot-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-item-clear')));
    await tester.pump();
    expect(team[0]!.item, isNull);
    expect(find.text('Unknown'), findsWidgets);
  });

  testWidgets("a complete moveset's empty move slots read None", (
    tester,
  ) async {
    final golem = named('Golem');
    await pump(
      tester,
      Team(
        slots: [
          TeamSlot(golem.id, moves: [move('earthquake')], movesKnown: true),
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
    expect(find.text('None'), findsNWidgets(3));
    expect(
      find.text('Unknown'),
      findsNWidgets(2),
      reason: 'only the item and Tera type',
    );
  });

  testWidgets('the slot cards stay three across, capped in height', (
    tester,
  ) async {
    await pump(tester, golemBronzong());
    final narrow = tester.getRect(find.byKey(const Key('team-slot-0')));
    final third = tester.getRect(find.byKey(const Key('team-slot-2')));
    expect(third.top, narrow.top, reason: 'three to a row on a phone');
    expect(narrow.height, lessThanOrEqualTo(220));
    tester.view.physicalSize = const Size(2400, 2400);
    await tester.pumpAndSettle();
    final wide = tester.getSize(find.byKey(const Key('team-slot-0')));
    expect(wide.height, lessThanOrEqualTo(240), reason: 'never huge');
  });

  testWidgets('an ability outside the species list still shows, chosen', (
    tester,
  ) async {
    final golem = named('Golem');
    final levitate = ability('levitate');
    expect([...golem.abilities, golem.hidden], isNot(contains(levitate)));
    await pump(
      tester,
      Team(
        slots: [
          TeamSlot(golem.id, ability: levitate),
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
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(Key('team-ability-$levitate')))
          .selected,
      isTrue,
    );
  });

  testWidgets('picking a benched Pokemon for a slot brings it back', (
    tester,
  ) async {
    final golem = named('Golem');
    final start = golemBronzong();
    start[0] = start[0]!.copyWith(moves: [move('earthquake')]);
    start[0] = null; // Golem benched, moves kept
    final team = await pump(tester, start);
    await tester.tap(find.byKey(const Key('team-slot-3')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('team-pick-search')), 'golem');
    await tester.pumpAndSettle();
    await tester.tap(pickRow(golem.id));
    await tester.pumpAndSettle();
    expect(team.deck.length, 2, reason: 'no duplicate Golem');
    expect(team[3]!.pokemon, golem.id);
    expect(team[3]!.moves, [move('earthquake')]);
    expect(
      find.byKey(const Key('team-remove')),
      findsOne,
      reason: 'opens its editor, as for a new one',
    );
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

  testWidgets('tapping a type pill opens it in the Type Chart', (tester) async {
    await pump(tester, golemBronzong());
    await tester.tap(find.byKey(const Key('team-type-water')));
    await tester.pump();
    expect(openedTypes, ['water']);
    expect(
      find.byKey(const Key('team-detail-water')),
      findsNothing,
      reason: 'the pill does not toggle the row',
    );
    await tester.tap(find.byKey(const Key('team-slot-type-steel')));
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
      find.descendant(
        of: sheet,
        matching: find.text(eq.description!.split('\n\n').last),
      ),
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
    Lineup lineup(List<String> names) => Lineup.ofSlots(slots(names));

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
      expect(find.byKey(Key('build-thumb-${build.id}-1')), findsOne);
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

    testWidgets('save lists builds recent first; picking one overwrites it', (
      tester,
    ) async {
      final builds = SavedBuilds();
      final frecency = FrecencyStore();
      final older = builds.save('Older', lineup(['Golem']));
      final newer = builds.save('Newer', lineup(['Pikachu']));
      frecency.visit(older.id);
      frecency.visit(newer.id);
      final planner = TeamPlanner(
        mine: TeamSide(
          team: Team(slots: slots(['Bronzong'])),
          builds: builds,
          frecency: frecency,
        ),
      );
      await pump(tester, null, planner);
      await tapKey(tester, 'team-save');
      double top(int id) =>
          tester.getTopLeft(find.byKey(Key('team-save-pick-$id'))).dy;
      expect(top(newer.id), lessThan(top(older.id)));
      expect(find.byKey(Key('build-thumb-${older.id}-0')), findsOne);
      expect(find.text('Golem'), findsNothing, reason: 'thumbnails, not names');

      await tester.enterText(find.byKey(const Key('team-save-name')), 'old');
      await tester.pump();
      expect(find.byKey(Key('team-save-pick-${newer.id}')), findsNothing);

      await tapKey(tester, 'team-save-pick-${older.id}');
      expect(
        find.descendant(
          of: find.byKey(const Key('team-save-confirm')),
          matching: find.text('Overwrite'),
        ),
        findsOne,
      );
      await tapKey(tester, 'team-save-confirm');
      expect(builds.builds, hasLength(2));
      expect(builds.named('Older')!.slots.first!.pokemon, named('Bronzong').id);
    });

    testWidgets('load lists builds most recently used first', (tester) async {
      final planner = TeamPlanner();
      final a = planner.mine.builds.save('Alpha', lineup(['Golem']));
      final b = planner.mine.builds.save('Beta', lineup(['Pikachu']));
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
      final a = planner.mine.builds.save('Alpha', lineup(['Golem']));
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
      final boss = TeamBuild(7, 'Gym Leader · Lv. 20', lineup(['Bronzong']));
      final planner = TeamPlanner(
        mine: TeamSide(team: Team(slots: slots(['Golem']))),
        theirs: TeamSide(
          builds: SavedBuilds(idBase: SavedBuilds.theirsIdBase),
          presets: [boss],
        ),
      );
      planner.mine.builds.save('Mine only', lineup(['Pikachu']));
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

    group('versus', () {
      test('2x and 4x hits differ in colour, not thickness', () {
        expect(lineColor(2, mine: true), Colors.green);
        expect(lineColor(4, mine: true), Colors.blue);
        expect(lineColor(2, mine: false), Colors.red);
        expect(lineColor(4, mine: false), Colors.purple);
        expect(lineColor(1, mine: true), Colors.grey);
      });

      Future<TeamPlanner> theirsPage(
        WidgetTester tester, {
        List<String> mine = const ['Golem', 'Pikachu'],
        List<String> theirs = const ['Pelipper', 'Bronzong'],
      }) async {
        final planner = TeamPlanner(
          mine: TeamSide(team: Team(slots: slots(mine))),
          theirs: TeamSide(team: Team(slots: slots(theirs))),
        );
        await pump(tester, null, planner);
        await tester.tap(find.text('Theirs'));
        await tester.pumpAndSettle();
        return planner;
      }

      /// Drawn lines as (your slot, their slot, your hit, their hit).
      List<(int, int, double?, double?)> lines(WidgetTester tester) => [
        for (final (l, _, _)
            in tester
                .widgetList<CustomPaint>(
                  find.descendant(
                    of: find.byKey(const Key('versus')),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .map((c) => c.painter)
                .whereType<VersusLinesPainter>()
                .single
                .lines)
          (l.mineSlot, l.theirSlot, l.mineHit, l.theirHit),
      ];

      test('lines fan out from the picked Pokémon like a {, then run flat', () {
        const hub = Offset(48, 28);
        for (final far in const [Offset(400, 308), Offset(400, 28)]) {
          final (hubHalf, farHalf) = VersusLinesPainter.shape(hub, far);
          final bend = hubHalf.computeMetrics().single;
          expect(bend.getTangentForOffset(0)!.position, hub);
          // Out to the target's row within the fan, flat from there on.
          final atFan = bend
              .getTangentForOffset(bend.length - (224 - 48 - 40))!
              .position;
          expect(atFan.dx, closeTo(48 + VersusLinesPainter.fan, 0.5));
          expect(atFan.dy, closeTo(far.dy, 0.5));
          expect(farHalf.getBounds(), Rect.fromLTRB(224, far.dy, 400, far.dy));
        }
        // The same from the right.
        final (hubHalf, _) = VersusLinesPainter.shape(
          const Offset(400, 28),
          const Offset(48, 308),
        );
        expect(hubHalf.getBounds(), const Rect.fromLTRB(224, 28, 400, 308));
      });

      testWidgets('only on Theirs, above the type table', (tester) async {
        await theirsPage(tester);
        expect(find.byKey(const Key('versus')), findsOne);
        expect(
          tester.getTopLeft(find.byKey(const Key('versus'))).dy,
          lessThan(tester.getTopLeft(find.text('Team matchups')).dy),
        );
        await tester.tap(find.text('Mine'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('versus')), findsNothing);
      });

      testWidgets(
        'tapping yours draws a line to each of theirs; again clears',
        (tester) async {
          await theirsPage(tester);
          expect(lines(tester), isEmpty);
          await tester.tap(find.byKey(const Key('versus-mine-0'))); // Golem
          await tester.pump();
          expect(lines(tester), [
            (0, 0, 2, 4), // vs Pelipper
            (0, 1, 2, 2), // vs Bronzong: ground 2× on it, its steel 2× on rock
          ]);
          await tester.tap(find.byKey(const Key('versus-mine-0')));
          await tester.pump();
          expect(lines(tester), isEmpty);
        },
      );

      testWidgets('a pill above each half names the types it hits with', (
        tester,
      ) async {
        await theirsPage(tester);
        await tester.tap(find.byKey(const Key('versus-mine-0'))); // Golem
        await tester.pump();
        List<String> via(String k) => [
          for (final b in tester.widgetList<TypeBadge>(
            find.descendant(
              of: find.byKey(Key('versus-via-$k')),
              matching: find.byType(TypeBadge),
            ),
          ))
            b.type,
        ];
        expect(via('mine-0-0'), ['rock'], reason: 'Rock 2x on Pelipper');
        expect(via('theirs-0-0'), ['water'], reason: 'Water 4x on Golem');
        expect(via('mine-0-1'), ['ground']);
        expect(via('theirs-0-1'), ['steel']);
        // Each sits above its own half, on the target's row.
        final versus = tester.getRect(find.byKey(const Key('versus')));
        final mine = tester.getRect(
          find.byKey(const Key('versus-via-mine-0-1')),
        );
        final theirs = tester.getRect(
          find.byKey(const Key('versus-via-theirs-0-1')),
        );
        expect(mine.right, lessThanOrEqualTo(versus.center.dx));
        expect(theirs.left, greaterThanOrEqualTo(versus.center.dx));
        final rowCentre = versus.top + VersusView.rowHeight * 1.5;
        expect(mine.bottom, lessThan(rowCentre));
        expect(mine.bottom, greaterThan(rowCentre - VersusView.rowHeight / 2));
      });

      testWidgets('tapping theirs draws to each of yours', (tester) async {
        await theirsPage(tester);
        await tester.tap(find.byKey(const Key('versus-theirs-0'))); // Pelipper
        await tester.pump();
        expect(lines(tester), [
          (0, 0, 2, 4), // Golem
          (1, 0, 4, 1), // Pikachu
        ]);
      });

      testWidgets("right-click or long-press opens that side's slot editor", (
        tester,
      ) async {
        final planner = await theirsPage(tester);
        await tester.tap(
          find.byKey(const Key('versus-mine-1')), // Pikachu
          buttons: kSecondaryButton,
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const Key('team-pokemon')),
            matching: find.text('Pikachu'),
          ),
          findsOne,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('versus')), findsOne, reason: 'on Theirs');
        expect(lines(tester), isEmpty, reason: 'not a pick');

        await tester.longPress(find.byKey(const Key('versus-theirs-1')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const Key('team-pokemon')),
            matching: find.text('Bronzong'),
          ),
          findsOne,
        );
        await tester.tap(find.byKey(const Key('team-remove')));
        await tester.pumpAndSettle();
        expect(planner.theirs.team[1], isNull, reason: 'edits Theirs');
        expect(planner.mine.team[1], isNotNull);
      });

      testWidgets("a side's Tera Orb dropped on its Pokémon terastallizes it", (
        tester,
      ) async {
        final planner = TeamPlanner(
          mine: TeamSide(team: Team(slots: slots(['Golem', 'Pikachu']))),
          theirs: TeamSide(
            team: Team(
              slots: [
                TeamSlot(named('Pelipper').id, tera: 'grass'),
                TeamSlot(named('Bronzong').id),
                null,
                null,
                null,
                null,
              ],
            ),
          ),
        );
        await pump(tester, null, planner);
        await tester.tap(find.text('Theirs'));
        await tester.pumpAndSettle();
        Future<void> dragOrb(String from, Offset to) async {
          await tester.dragFrom(
            tester.getCenter(find.byKey(Key(from))),
            to - tester.getCenter(find.byKey(Key(from))),
          );
          await tester.pumpAndSettle();
        }

        Offset at(String key) => tester.getCenter(find.byKey(Key(key)));

        // Not onto a Pokémon without a Tera type, nor the other side's.
        await dragOrb('versus-orb-theirs', at('versus-theirs-1'));
        await dragOrb('versus-orb-theirs', at('versus-mine-0'));
        await dragOrb('versus-orb-mine', at('versus-theirs-0'));
        expect(find.byKey(const Key('versus-orb-theirs')), findsOne);
        expect(find.byKey(const Key('versus-orb-mine')), findsOne);

        await tester.tap(find.byKey(const Key('versus-theirs-0')));
        await tester.pump();
        expect(lines(tester), [(0, 0, 2, 4), (1, 0, 4, 1)]);

        await dragOrb('versus-orb-theirs', at('versus-theirs-0'));
        expect(find.byKey(const Key('versus-orb-theirs')), findsNothing);
        expect(find.byKey(const Key('versus-tera-theirs-0')), findsOne);
        expect(lines(tester), [
          (0, 0, 1, 4), // Golem: rock 1×, ground 0.5× on Grass; Grass 4× back
          (1, 0, 0.5, 1), // Pikachu: Electric 0.5× on Grass
        ]);

        // Dragged off to nowhere, it's back above the column.
        await dragOrb('versus-tera-theirs-0', const Offset(240, 5));
        expect(find.byKey(const Key('versus-orb-theirs')), findsOne);
        expect(lines(tester), [(0, 0, 2, 4), (1, 0, 4, 1)]);
      });

      testWidgets('with Mine empty it says so', (tester) async {
        await theirsPage(tester, mine: const []);
        expect(find.byKey(const Key('versus-empty')), findsOne);
        expect(find.byKey(const Key('versus')), findsNothing);
      });
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

    testWidgets('the header scrolls away with the team', (tester) async {
      await pump(tester, Team(slots: slots(['Golem', 'Pikachu'])));
      tester.view.physicalSize = const Size(480, 900); // phone-sized
      await tester.pumpAndSettle();
      final top = tester.getTopLeft(find.byKey(const Key('team-side'))).dy;
      await tester.drag(
        find.byKey(const Key('team-scroll')),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('team-side')).hitTestable(),
        findsNothing,
        reason: 'not pinned (was at y=$top)',
      );
    });
  });

  group('sidedeck', () {
    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    String count(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('deck-count'))).data!;

    testWidgets('the button sits between Load and Mine | Theirs', (
      tester,
    ) async {
      await pump(tester);
      double left(String key) => tester.getTopLeft(find.byKey(Key(key))).dx;
      expect(left('team-load'), lessThan(left('team-deck')));
      expect(left('team-deck'), lessThan(left('team-side')));
    });

    testWidgets('lists the deck with types and moves; tap toggles the squad', (
      tester,
    ) async {
      final golem = named('Golem');
      final team = Team()
        ..add(TeamSlot(golem.id, moves: [move('earthquake')]))
        ..add(TeamSlot(named('Pikachu').id));
      team[1] = null; // Pikachu benched
      await pump(tester, team);
      await tapKey(tester, 'team-deck');
      expect(count(tester), '1/6');
      final golemRow = find.byKey(const Key('deck-row-0'));
      Finder inRow(Finder f) => find.descendant(of: golemRow, matching: f);
      expect(inRow(find.text('Rock')), findsOne);
      expect(inRow(find.text('Ground')), findsOne);
      final quake = inRow(
        find.byKey(Key('deck-move-${golem.id}-${move('earthquake')}')),
      );
      expect(
        find.descendant(of: quake, matching: find.text('Earthquake')),
        findsOne,
      );
      expect(
        find.descendant(
          of: quake,
          matching: find.byKey(const Key('cat-physical')),
        ),
        findsOne,
      );
      for (var k = 1; k < 4; k++) {
        expect(inRow(find.byKey(Key('deck-unknown-${golem.id}-$k'))), findsOne);
      }
      expect(find.byKey(const Key('deck-in-0-true')), findsOne);
      expect(find.byKey(const Key('deck-add')), findsOne);

      await tapKey(tester, 'deck-row-1');
      expect(count(tester), '2/6');
      expect(team[1]!.pokemon, named('Pikachu').id);
      await tapKey(tester, 'deck-row-0');
      expect(count(tester), '1/6');
      expect(team[0], isNull);
      expect(team.deck, hasLength(2), reason: 'still in the deck');
    });

    testWidgets(
      'a full squad allows an extra selection and explains the limit',
      (tester) async {
        final team = Team();
        for (final n in [
          'Golem',
          'Pikachu',
          'Bronzong',
          'Pelipper',
          'Torkoal',
          'Garchomp',
          'Gengar',
        ]) {
          team.add(TeamSlot(named(n).id));
        }
        await pump(tester, team);
        await tapKey(tester, 'team-deck');
        expect(count(tester), '6/6');
        await tapKey(tester, 'deck-row-6');
        expect(count(tester), '7/6');
        expect(find.byKey(const Key('deck-legality')), findsOne);
        expect(team.slotOf(6), isNotNull);
      },
    );

    testWidgets('+ adds and edits; long-press edits; swipe deletes', (
      tester,
    ) async {
      final team = await pump(tester);
      await tapKey(tester, 'team-deck');
      await tapKey(tester, 'deck-add');
      await tester.enterText(
        find.byKey(const Key('team-pick-search')),
        'golem',
      );
      await tester.pumpAndSettle();
      await tester.tap(pickRow(named('Golem').id));
      await tester.pumpAndSettle();
      expect(find.text('Slot 1'), findsOne, reason: 'editor, in the squad');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(count(tester), '1/6');

      await tapKey(tester, 'deck-row-0'); // bench it
      await tester.longPress(find.byKey(const Key('deck-row-0')));
      await tester.pumpAndSettle();
      expect(
        find.text('Sidedeck'),
        findsOne,
        reason: 'editor of a benched one',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const Key('deck-row-0')),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'deck-delete-confirm');
      expect(team.deck, isEmpty);
      expect(find.byKey(const Key('deck-row-0')), findsNothing);
    });

    testWidgets("removing from a slot benches it; it's back in the deck", (
      tester,
    ) async {
      final team = await pump(tester, Team()..add(TeamSlot(named('Golem').id)));
      await tapKey(tester, 'team-slot-0');
      await tapKey(tester, 'team-remove');
      expect(team[0], isNull);
      await tapKey(tester, 'team-deck');
      expect(find.byKey(const Key('deck-in-0-false')), findsOne);
    });
  });
}
