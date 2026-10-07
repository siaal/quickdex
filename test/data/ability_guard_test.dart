import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/defense.dart';
import 'package:quickdex/data/models.dart';

import 'models_test.dart' show realDex;

void main() {
  late Pokedex dex;
  setUpAll(() => dex = realDex());

  PokemonEntry named(String n) => dex.entries.firstWhere((e) => e.name == n);

  test('abilities, catch rate and weight are parsed', () {
    final bulbasaur = dex[1];
    expect(bulbasaur.abilities.map((a) => dex.abilities[a]!.name), [
      'Overgrow',
    ]);
    expect(dex.abilities[bulbasaur.hidden]!.name, 'Chlorophyll');
    expect(bulbasaur.catchRate, 45);
    expect(bulbasaur.weightKg, 6.9);
    expect(dex.abilities[26]!.effect, 'Evades Ground moves.');
  });

  test('Levitate-only Gastly is guaranteed Ground immunity', () {
    final g = named('Gastly').guard!;
    expect(g.ability, 'Levitate');
    expect(g.types, ['ground']);
  });

  test('Koffing only might have Levitate, so no guard', () {
    expect(named('Koffing').guard, isNull);
    expect(dex[1].guard, isNull);
  });

  test('Volt Absorb Zeraora and Water Absorb Wellspring Ogerpon', () {
    expect(named('Zeraora').guard!.types, ['electric']);
    expect(named('Ogerpon (Wellspring Mask)').guard!.types, ['water']);
    expect(named('Ogerpon').guard, isNull);
  });

  test('Wonder Guard: Shedinja immune to everything not super effective', () {
    final g = named('Shedinja').guard!;
    expect(g.ability, 'Wonder Guard');
    final weak = {'fire', 'flying', 'rock', 'ghost', 'dark'};
    final typeImmune = {'normal', 'fighting'};
    expect(
      g.types.toSet(),
      dex.types.order.toSet().difference(weak).difference(typeImmune),
    );
  });

  test(
    'exactly the 37 entries whose guaranteed immunity matters get a guard',
    () {
      // 38 entries are guaranteed an immunity ability, but Rotom (Fan) is
      // Electric/Flying: already immune to Ground, so Levitate adds nothing.
      expect(dex.entries.where((e) => e.guard != null).length, 37);
      expect(named('Rotom (Fan)').guard, isNull);
    },
  );

  test('guarded types move from their bucket to Immune', () {
    final gastly = named('Gastly');
    final groups = defenseGroups(
      gastly.defense,
      dex.types.order,
      guard: gastly.guard,
    );
    final weak = groups.firstWhere((g) => g.label == 'Weak to');
    expect(weak.buckets.expand((b) => b.$2), isNot(contains('ground')));
    final immune = groups.firstWhere((g) => g.label == 'Immune to');
    expect(immune.buckets.single.$1, 0.0);
    expect(immune.buckets.single.$2, ['fighting', 'normal']);
    expect(immune.guard!.types, ['ground']);
  });

  test('Shedinja keeps only weaknesses plus Immune', () {
    final s = named('Shedinja');
    final labels = defenseGroups(
      s.defense,
      dex.types.order,
      guard: s.guard,
    ).map((g) => g.label);
    expect(labels, ['Weak to', 'Immune to']);
  });
}
