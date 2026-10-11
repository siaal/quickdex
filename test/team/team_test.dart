import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
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

    test('drops unknown Pokémon and abilities the entry cannot have', () {
      final golem = named('Golem');
      final t = Team.fromJson(
        '[{"p":999999,"m":[]},{"p":${golem.id},"a":${ability('levitate')},"m":[]}]',
        dex,
      );
      expect(t[0], isNull);
      expect(t[1]!.pokemon, golem.id);
      expect(t[1]!.ability, isNull);
    });

    test('corrupt or missing JSON gives an empty team', () {
      expect(Team.fromJson('{not json', dex).isEmpty, isTrue);
      expect(Team.fromJson('[{"p":"x"}]', dex).isEmpty, isTrue);
      expect(Team.fromJson(null, dex).isEmpty, isTrue);
    });
  });

  group('analysis', () {
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

    test('damaging moves set attack types; none falls back to STAB', () {
      final golem = named('Golem');
      final stab = resolveMember(0, TeamSlot(golem.id), dex, moves);
      expect(stab.attackTypes, golem.types);
      final withMoves = resolveMember(
        0,
        TeamSlot(golem.id, moves: [move('flamethrower'), move('swords-dance')]),
        dex,
        moves,
      );
      expect(withMoves.attackTypes, ['fire'], reason: 'status moves ignored');
      final onlyStatus = resolveMember(
        0,
        TeamSlot(golem.id, moves: [move('swords-dance')]),
        dex,
        moves,
      );
      expect(onlyStatus.attackTypes, golem.types);
      expect(
        resolveMember(0, TeamSlot(golem.id, moves: [1]), dex, null).attackTypes,
        golem.types,
        reason: 'moves not loaded yet',
      );
    });

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
