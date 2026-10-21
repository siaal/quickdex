import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/team/builds.dart';
import 'package:quickdex/team/team.dart';
import 'package:quickdex/team/team_analysis.dart';

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

  group('Team persistence', () {
    test('round-trips through JSON and reports every change', () {
      final saved = <String>[];
      final team = Team(onChanged: saved.add);
      final golem = named('Golem');
      team[2] = TeamSlot(golem.id, ability: golem.abilities.first, moves: [1]);
      expect(saved, hasLength(1));
      final back = Team.fromJson(saved.single, dex);
      expect(back[2]!.pokemon, golem.id);
      expect(back[2]!.ability, golem.abilities.first);
      expect(back[2]!.moves, [1]);
      expect(back.slots.where((s) => s == null), hasLength(5));
    });

    test('drops unknown Pokémon and abilities; keeps any known ability', () {
      final golem = named('Golem');
      final t = Team.fromJson(
        '[{"p":999999,"m":[]},{"p":${golem.id},"a":999999,"m":[]},'
        '{"p":${golem.id},"a":${ability('levitate')},"m":[]}]',
        dex,
      );
      expect(t[0], isNull);
      expect(t[1]!.pokemon, golem.id);
      expect(t[1]!.ability, isNull);
      expect(
        t[2]!.ability,
        ability('levitate'),
        reason: "a boss can have one its species can't",
      );
    });

    test('the build name round-trips; load replaces every slot at once', () {
      final saved = <String>[];
      final team = Team(onChanged: saved.add);
      team[0] = TeamSlot(named('Golem').id);
      final slots = List<TeamSlot?>.filled(Team.size, null);
      slots[3] = TeamSlot(named('Pikachu').id);
      team.load(Lineup.ofSlots(slots), name: 'Rain');
      expect(saved, hasLength(2), reason: 'one change per load');
      final back = Team.fromJson(saved.last, dex);
      expect(back.name, 'Rain');
      expect(back[0], isNull);
      expect(back[3]!.pokemon, named('Pikachu').id);
      team[3] = null;
      expect(Team.fromJson(saved.last, dex).name, 'Rain', reason: 'kept');
    });

    test(
      'hidden moves round-trip; hidden ids not in the moves are dropped',
      () {
        final golem = named('Golem');
        final t = Team(onChanged: (_) {});
        t[0] = TeamSlot(golem.id, moves: [1, 2], hidden: {2});
        expect(Team.fromJson(t.toJson(), dex)[0]!.hidden, {2});
        final stray = Team.fromJson(
          '[{"p":${golem.id},"m":[1],"h":[1,7]}]',
          dex,
        );
        expect(stray[0]!.hidden, {1});
        expect(
          Team.fromJson('[{"p":${golem.id},"m":[1]}]', dex)[0]!.hidden,
          isEmpty,
          reason: 'teams saved before hiding existed',
        );
      },
    );

    test('corrupt or missing JSON gives an empty team', () {
      expect(Team.fromJson('{not json', dex).isEmpty, isTrue);
      expect(Team.fromJson('[{"p":"x"}]', dex).isEmpty, isTrue);
      expect(Team.fromJson(null, dex).isEmpty, isTrue);
    });
  });

  group('sidedeck', () {
    test('swap benches the old member and puts the new one in its place', () {
      final t = Team();
      t.add(TeamSlot(named('Golem').id, moves: [1]));
      t.add(TeamSlot(named('Pikachu').id));
      final pikachuId = t.memberId(1);
      final d = t.swap(1, TeamSlot(named('Bronzong').id));
      expect(d, 2);
      expect(t.deck.length, 3, reason: 'nothing deleted');
      expect(t[1]!.pokemon, named('Bronzong').id, reason: 'same squad slot');
      expect(t.slotOf(1), isNull);
      expect(t.deck[1].pokemon, named('Pikachu').id);
      expect(t.memberId(1), pikachuId);
      expect(t.deck[1].lastBenched, greaterThan(0), reason: 'just benched');

      // A benched member's swap stays out of the squad.
      final out = t.swap(1, TeamSlot(named('Gastly').id));
      expect(t.slotOf(out), isNull);
      expect(t.squadCount, 2);
      expect(t.deck.length, 4);
    });

    test('swap keeps an overflow position', () {
      final t = Team();
      for (var i = 0; i < 7; i++) {
        t.add(TeamSlot(named('Golem').id)); // the first six go in
      }
      t.toggle(6, allowOverflow: true);
      expect(t.squadCount, 7);
      final d = t.swap(6, TeamSlot(named('Pikachu').id));
      expect(t.squadCount, 7);
      expect(t.slotOf(d), 6);
      expect(t.slotOf(6), isNull);
    });

    test('bench recency survives edits, serialization and later removals', () {
      final t = Team();
      t.add(TeamSlot(named('Golem').id));
      t.add(TeamSlot(named('Pikachu').id));
      t.toggle(1);
      t[0] = null;
      expect(t.deck[0].lastBenched, greaterThan(t.deck[1].lastBenched));
      final last = t.deck[0].lastBenched;
      t.setMember(0, TeamSlot(named('Bronzong').id));
      expect(t.deck[0].lastBenched, last);
      final back = Team.fromJson(t.toJson(), dex);
      expect(
        back.deck.map((s) => s.lastBenched),
        t.deck.map((s) => s.lastBenched),
      );
      back.toggle(1);
      back[0] = back[0]!.copyWith(moves: [1]);
      expect(back.deck[1].lastBenched, t.deck[1].lastBenched);
      back.toggle(1);
      expect(back.deck[1].lastBenched, greaterThan(last));
      expect(back.deck[1].moves, [1]);
    });

    test(
      'member ids survive edits and index compaction, including duplicates',
      () {
        final t = Team();
        final duplicate = TeamSlot(named('Golem').id);
        t.add(duplicate);
        t.add(duplicate);
        final first = t.memberId(0);
        final second = t.memberId(1);
        expect(first, isNot(second));
        t.setMember(1, TeamSlot(named('Pikachu').id));
        t.toggle(1);
        expect(t.memberId(1), second);
        t.remove(0);
        expect(t.memberId(0), second);
        t.add(duplicate);
        expect(t.memberId(1), isNot(isIn([first, second])));
      },
    );

    test('sort preference persists per team and survives loading a build', () {
      final saved = <String>[];
      final t = Team(onChanged: saved.add);
      expect(t.sidedeckSort, SidedeckSort.recency);
      t.sidedeckSort = SidedeckSort.name;
      expect(Team.fromJson(saved.last, dex).sidedeckSort, SidedeckSort.name);
      t.load(Lineup.empty, name: 'Empty');
      expect(t.sidedeckSort, SidedeckSort.name);
      final legacy = Team.fromJson('[{"p":${named('Golem').id},"m":[]}]', dex);
      expect(legacy.sidedeckSort, SidedeckSort.recency);
      expect(legacy.deck.single.lastBenched, 0);
    });

    TeamSlot slot(String n) => TeamSlot(named(n).id);
    List<String> squad(Team t) => [
      for (final s in t.slots) s == null ? '-' : dex[s.pokemon].name,
    ];

    test(
      'clearing a slot benches its member; filling one adds to the deck',
      () {
        final t = Team();
        t[2] = slot('Golem');
        t[2] = null;
        expect(t.deck.map((s) => s.pokemon), [named('Golem').id]);
        expect(t.isEmpty, isTrue);
        expect(t.slotOf(0), isNull);
        t[2] = slot('Pikachu');
        expect(t.deck, hasLength(2));
        t[2] = slot('Bronzong'); // replaces the member in that slot
        expect(t.deck.map((s) => dex[s.pokemon].name), ['Golem', 'Bronzong']);
      },
    );

    test('add joins the first free slot; toggle refuses a full squad', () {
      final t = Team();
      for (final n in ['Golem', 'Pikachu', 'Bronzong', 'Pelipper']) {
        t.add(slot(n));
      }
      t[1] = null;
      for (final n in ['Torkoal', 'Garchomp', 'Gengar']) {
        t.add(slot(n));
      }
      expect(squad(t), [
        'Golem',
        'Torkoal',
        'Bronzong',
        'Pelipper',
        'Garchomp',
        'Gengar',
      ]);
      expect(t.squadCount, 6);
      expect(t.toggle(1), isFalse, reason: 'Pikachu benched, squad full');
      expect(t.toggle(0), isTrue);
      expect(t.toggle(1), isTrue);
      expect(squad(t).first, 'Pikachu');
    });

    test(
      'temporary extra selections persist and promote without truncation',
      () {
        final saved = <String>[];
        final t = Team(onChanged: saved.add);
        for (var i = 0; i < 8; i++) {
          t.add(slot('Golem'));
        }
        expect(t.toggle(6, allowOverflow: true), isTrue);
        expect(t.toggle(7, allowOverflow: true), isTrue);
        expect(t.squadCount, 8);
        expect(t.isLegal, isFalse);
        expect(t.slots, hasLength(Team.size));
        expect(t.lineup.squad, [0, 1, 2, 3, 4, 5, 6, 7]);
        final back = Team.fromJson(saved.last, dex);
        expect(back.lineup.squad, t.lineup.squad);
        expect(back.isLegal, isFalse);
        final builds = SavedBuilds()..save('Temporary', t.lineup);
        final restored = SavedBuilds.fromJson(
          builds.toJson(),
          dex,
        ).builds.single;
        expect(restored.lineup.squad, t.lineup.squad);
        expect(restored.slots, hasLength(Team.size));
        expect(() => t[Team.size] = null, throwsAssertionError);
        expect(t.toggle(1), isTrue);
        expect(
          t.toggle(1),
          isFalse,
          reason: 'default toggle still caps the squad',
        );
        back.toggle(1);
        back.toggle(3);
        expect(back.isLegal, isTrue);
        expect(back.lineup.squad, [0, 6, 2, 7, 4, 5]);
        expect(back.deck, hasLength(8));
        expect(back.slots.every((s) => s != null), isTrue);
      },
    );

    test(
      'overflow removal and build loading preserve all selected members',
      () {
        final t = Team();
        for (var i = 0; i < 9; i++) {
          t.add(slot('Golem'));
        }
        t.toggle(6, allowOverflow: true);
        t.toggle(7, allowOverflow: true);
        final loaded = Team()..load(t.lineup, name: 'Temporary');
        expect(loaded.squadCount, 8);
        loaded.remove(6);
        expect(loaded.lineup.squad, [0, 1, 2, 3, 4, 5, 6]);
        loaded.remove(0);
        expect(loaded.lineup.squad, [5, 0, 1, 2, 3, 4]);
        expect(loaded.isLegal, isTrue);
        loaded.load(Lineup.empty, name: null);
        expect(loaded.squadCount, 0);
        expect(loaded.isLegal, isTrue);
      },
    );

    test('legacy six-slot formats migrate without changing empty slots', () {
      final p = named('Golem').id;
      for (final raw in [
        '[null,{"p":$p,"m":[]}]',
        '{"s":[null,{"p":$p,"m":[]}]}',
        '{"d":[{"p":$p,"m":[]}],"q":[null,0]}',
      ]) {
        final t = Team.fromJson(raw, dex);
        expect(t.lineup.squad, [null, 0, null, null, null, null]);
        expect(t.isLegal, isTrue);
        expect(Team.fromJson(t.toJson(), dex).lineup.squad, t.lineup.squad);
      }
    });

    test(
      'unknown and duplicate overflow indices are removed, not valid ones',
      () {
        final p = named('Golem').id;
        final t = Team.fromJson(
          '{"d":[${List.filled(8, '{"p":$p,"m":[]}').join(',')}],'
          '"q":[0,1,2,3,4,5,999,6,6,7]}',
          dex,
        );
        expect(t.lineup.squad.nonNulls, [0, 1, 2, 3, 4, 5, 6, 7]);
        expect(t.squadCount, 8);
      },
    );

    test('remove deletes a member and keeps the squad pointing right', () {
      final t = Team();
      for (final n in ['Golem', 'Pikachu', 'Bronzong']) {
        t.add(slot(n));
      }
      t.remove(0);
      expect(squad(t), ['-', 'Pikachu', 'Bronzong', '-', '-', '-']);
      expect(t.deck, hasLength(2));
    });

    test('the deck and squad round-trip; unknown Pokémon leave both', () {
      final saved = <String>[];
      final t = Team(onChanged: saved.add);
      t.add(slot('Golem'));
      t.add(slot('Pikachu'));
      t[0] = null;
      final back = Team.fromJson(saved.last, dex);
      expect(back.deck, hasLength(2));
      expect(squad(back), ['-', 'Pikachu', '-', '-', '-', '-']);

      final gone = Team.fromJson(
        '{"d":[{"p":999999,"m":[]},{"p":${named('Golem').id},"m":[]}],'
        '"q":[0,1,1,7,null,null]}',
        dex,
      );
      expect(gone.deck, hasLength(1));
      expect(squad(gone), ['-', 'Golem', '-', '-', '-', '-']);
    });
  });

  group('analysis', () {
    test('hit is the best multiplier either way, ability included', () {
      TeamMember member(
        String name, {
        String? ab,
        List<String> mv = const [],
      }) => resolveMember(
        0,
        TeamSlot(
          named(name).id,
          ability: ab == null ? null : ability(ab),
          moves: [for (final k in mv) move(k)],
        ),
        dex,
        moves,
      );
      final golem = member('Golem'); // rock/ground STAB
      final pelipper = member('Pelipper'); // water/flying
      expect(hit(golem, pelipper), 2, reason: 'rock 2× beats ground 0×');
      expect(hit(pelipper, golem), 4);
      final quake = member(
        'Garchomp',
        mv: ['earthquake', 'swords-dance', 'protect', 'rest'],
      );
      expect(
        hit(
          member('Garchomp', mv: ['earthquake']),
          member('Bronzong', ab: 'levitate'),
        ),
        0.5,
        reason: 'unknown slots could be its Dragon STAB',
      );
      expect(hit(quake, member('Bronzong', ab: 'heatproof')), 2);
      expect(hit(quake, member('Bronzong', ab: 'levitate')), 0);
    });

    test('the chosen ability adds its immunity', () {
      final bronzong = named('Bronzong');
      expect(bronzong.defense['ground'], 2, reason: 'chart alone');
      final heatproof = resolveMember(
        0,
        TeamSlot(bronzong.id, ability: ability('heatproof')),
        dex,
        moves,
      );
      expect(heatproof.defense['ground'], 2);
      final levitate = resolveMember(
        0,
        TeamSlot(bronzong.id, ability: ability('levitate')),
        dex,
        moves,
      );
      expect(levitate.defense['ground'], 0);
    });

    test('with no ability chosen only a guaranteed immunity counts', () {
      final gastly = named('Gastly'); // Levitate only
      final m = resolveMember(0, TeamSlot(gastly.id), dex, moves);
      expect(m.defense['ground'], 0);
    });

    test('chosen damaging moves plus STAB while any move slot is unknown', () {
      final golem = named('Golem');
      List<String> attack(List<String> keys, {Set<String> hidden = const {}}) =>
          resolveMember(
            0,
            TeamSlot(
              golem.id,
              moves: [for (final k in keys) move(k)],
              hidden: {for (final k in hidden) move(k)},
            ),
            dex,
            moves,
          ).attackTypes;
      expect(attack([]), golem.types, reason: 'four unknown slots');
      expect(
        attack(['flamethrower', 'swords-dance']),
        ['fire', ...golem.types],
        reason: "two unknown slots could still be STAB",
      );
      expect(
        attack(['flamethrower', 'swords-dance', 'protect', 'rest']),
        ['fire'],
        reason: 'all four known; status moves deal nothing',
      );
      expect(
        attack(
          ['flamethrower', 'u-turn', 'protect', 'rest'],
          hidden: {'u-turn'},
        ),
        ['fire'],
        reason: 'hidden U-turn ignored',
      );
      expect(
        attack(
          ['flamethrower', 'u-turn', 'protect', 'rest'],
          hidden: {'flamethrower', 'u-turn'},
        ),
        isEmpty,
        reason: "hidden moves aren't unknown",
      );
      expect(
        resolveMember(0, TeamSlot(golem.id, moves: [1]), dex, null).attackTypes,
        golem.types,
        reason: 'moves not loaded yet',
      );
    });

    test('only status moves: no hits, no Hit SE, edges from defence only', () {
      final espeon = named('Espeon');
      final gravity = resolveMember(
        0,
        TeamSlot(
          espeon.id,
          moves: [
            for (final k in ['gravity', 'protect', 'rest', 'calm-mind'])
              move(k),
          ],
        ),
        dex,
        moves,
      );
      final scizor = resolveMember(1, TeamSlot(named('Scizor').id), dex, moves);
      expect(hit(gravity, scizor), isNull);
      expect(hit(scizor, gravity), 2, reason: 'bug still hits psychic');
      final bug = analyseTeam([
        gravity,
      ], dex.types).firstWhere((r) => r.type == 'bug');
      expect(bug.offense, [null]);
      expect(bug.hitters, 0);
      expect(bug.edges, [-1], reason: 'takes 2×, deals nothing');
    });

    test(
      'ahead/behind: deals minus takes, in doubling steps; 0× is 3 steps',
      () {
        // takes 2 deals 2 (even), takes ½ deals 1 (ahead), immune (ahead),
        // takes 1 deals ½ (behind), takes 0 deals 0 (even).
        final r = TypeMatchup(
          'x',
          const [2, 0.5, 0, 1, 0],
          const [2, 1, 1, 0.5, 0],
        );
        expect(r.edges, [0, 1, 3, -1, 0]);
        expect((r.ahead, r.behind), (2, 1));
      },
    );

    test(
      'Toxapex is ahead of Fighting without hitting it super-effectively',
      () {
        final members = [
          resolveMember(0, TeamSlot(named('Toxapex').id), dex, moves),
          resolveMember(1, TeamSlot(named('Annihilape').id), dex, moves),
        ];
        final rows = {
          for (final r in analyseTeam(members, dex.types)) r.type: r,
        };
        expect(rows['fighting']!.edges.first, greaterThan(0));
        expect(
          rows['normal']!.edges.last,
          greaterThanOrEqualTo(3),
          reason: 'immune',
        );
      },
    );

    test('counts weak/resist/immune and super-effective hitters per type', () {
      final members = [
        resolveMember(0, TeamSlot(named('Golem').id), dex, moves),
        resolveMember(
          1,
          TeamSlot(named('Bronzong').id, ability: ability('levitate')),
          dex,
          moves,
        ),
      ];
      final rows = {for (final r in analyseTeam(members, dex.types)) r.type: r};
      expect(rows.length, 18);
      final ground = rows['ground']!;
      expect(ground.defense, [2, 0]);
      expect((ground.weak, ground.resist, ground.immune), (1, 0, 1));
      final water = rows['water']!;
      expect(water.defense, [4, 1]);
      expect(water.weak, 1);
      expect(rows['fire']!.hitters, 1, reason: 'Golem\'s Rock/Ground');
      expect(rows['fire']!.offense, [
        2,
        1,
      ], reason: 'Psychic beats Steel\'s ½×');
    });
  });
}
