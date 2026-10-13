import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/ability_guard.dart';
import 'package:quickdex/data/game.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameInfo emerald;
  late Pokedex dex;
  late MoveDex moves;
  setUpAll(() async {
    final games = await loadGames(rootBundle);
    expect(games.map((g) => g.key), ['scarlet', 'emerald', 'scrambled']);
    emerald = games[1];
    dex = await loadPokedex(rootBundle, emerald);
    moves = await loadMoves(rootBundle, emerald);
  });

  PokemonEntry named(String n) => dex.entries.firstWhere((e) => e.name == n);
  Move move(String key) => moves.moves.firstWhere((m) => m.key == key);

  test('Emerald bundle is Gen 3: 386 species, 17 types, Gen 3 typings', () {
    expect(dex.game, emerald);
    expect((emerald.name, emerald.gen), ('Emerald', 3));
    expect(dex.entries.map((e) => e.dex).toSet().length, 386);
    expect(dex.types.order, isNot(contains('fairy')));
    expect(dex.types.order, hasLength(17));
    expect(named('Clefairy').types, ['normal']);
    expect(named('Skarmory').defense['ghost'], 0.5, reason: 'Gen 2–5 Steel');
    expect(named('Treecko').dexLabel, 'Hoenn #001 · #252');
    expect(named('Bulbasaur').dexLabel, '#001', reason: 'not in the Hoenn dex');
  });

  test('ability immunities follow the generation', () {
    final rod = dex.abilities.values.firstWhere(
      (a) => a.key == 'lightning-rod',
    );
    final d = named('Pikachu').defense;
    expect(abilityImmunities(rod, d, 3), isEmpty);
    expect(abilityImmunities(rod, d, 9), {'electric'});
    expect(named('Gastly').guard?.types, ['ground'], reason: 'Levitate');
  });

  test('Emerald moves: type-based category, Gen 3 numbers, ??? Curse', () {
    expect(moves.game, emerald);
    expect(moves.moves, hasLength(354));
    expect(move('shadow-ball').category, MoveCategory.physical);
    expect(move('thunderbolt').power, 95);
    expect(move('curse').type, 'unknown');
    expect(moves.learnsets[25]!.game, isNull);
  });
}
