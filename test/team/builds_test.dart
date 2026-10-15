import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/game.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/team/builds.dart';
import 'package:quickdex/team/team.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  setUpAll(() async => dex = await loadPokedex(rootBundle));

  List<TeamSlot?> team(List<String> names) => [
    for (var i = 0; i < Team.size; i++)
      i < names.length
          ? TeamSlot(dex.entries.firstWhere((e) => e.name == names[i]).id)
          : null,
  ];
  Lineup lineup(List<String> names) => Lineup.ofSlots(team(names));

  test('saving under an existing name overwrites it, keeping its id', () {
    final saved = <String>[];
    final builds = SavedBuilds(onChanged: saved.add);
    final rain = builds.save('Rain', lineup(['Pelipper']));
    final sun = builds.save('Sun', lineup(['Torkoal']));
    expect(sun.id, isNot(rain.id));
    final again = builds.save('  rain ', lineup(['Pelipper', 'Barraskewda']));
    expect(again.id, rain.id);
    expect(builds.builds.map((b) => b.name), ['rain', 'Sun']);
    final back = SavedBuilds.fromJson(saved.last, dex);
    expect(back.named('RAIN')!.slots.nonNulls, hasLength(2));
    builds.delete(sun.id);
    expect(SavedBuilds.fromJson(saved.last, dex).builds, hasLength(1));
  });

  test('a build keeps its sidedeck; older squad-only builds still load', () {
    final saved = <String>[];
    final builds = SavedBuilds(onChanged: saved.add);
    final t = Team(slots: team(['Pelipper']))
      ..add(TeamSlot(lineup(['Torkoal']).deck.single.pokemon));
    t[0] = null; // Pelipper benched, Torkoal in the squad
    builds.save('Deck', t.lineup);
    final back = SavedBuilds.fromJson(saved.last, dex).named('Deck')!;
    expect(back.lineup.deck, hasLength(2));
    expect(back.slots.nonNulls.single.pokemon, t.deck[1].pokemon);

    final pelipper = t.deck[0].pokemon;
    final legacy = SavedBuilds.fromJson(
      '[{"i":1,"n":"Old","s":[{"p":$pelipper,"m":[]}]}]',
      dex,
    );
    expect(legacy.named('Old')!.lineup.deck.single.pokemon, pelipper);
    expect(legacy.named('Old')!.lineup.squad.first, 0);
  });

  test('corrupt or missing JSON gives no builds', () {
    expect(SavedBuilds.fromJson('{nope', dex).builds, isEmpty);
    expect(SavedBuilds.fromJson(null, dex).builds, isEmpty);
  });

  test(
    'Scrambled Scarlet bosses become builds; other games have none',
    () async {
      expect(bossBuilds(dex), isEmpty);
      final games = await loadGames(rootBundle);
      final scrambled = await loadPokedex(
        rootBundle,
        games.firstWhere((g) => g.key == 'scrambled'),
      );
      final bosses = bossBuilds(scrambled);
      expect(bosses.length, greaterThan(50));
      final iono = bosses.firstWhere(
        (b) => b.name == '6th Gym Leader Iono · Lv. 47 · Reverse',
      );
      expect([
        for (final s in iono.slots.nonNulls) scrambled[s.pokemon].name,
      ], contains('Rotom (Wash)'));
      final magneton = bosses
          .firstWhere((b) => b.name.startsWith('3rd Gym Leader Iono'))
          .slots
          .nonNulls
          .firstWhere((s) => scrambled[s.pokemon].species == 'Magneton');
      expect(
        scrambled.abilities[magneton.ability]!.name,
        'Levitate',
        reason: "kept though Magneton can't have it",
      );
      expect(bosses.map((b) => b.id).toSet(), hasLength(bosses.length));
    },
  );
}
