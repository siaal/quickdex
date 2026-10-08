import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/models.dart';

Pokedex realDex() => Pokedex.parse(
  File('assets/data/pokedex.json').readAsStringSync(),
  File('assets/data/types.json').readAsStringSync(),
);

void main() {
  late Pokedex dex;
  setUpAll(() => dex = realDex());

  test('parses real data and invariants hold', () {
    expect(dex.entries.length, greaterThan(1025));
    dex.assertInvariants();
  });

  test('lookup by id', () {
    expect(dex[25].name, 'Pikachu');
    expect(dex[25].dexLabel, 'Paldea #074 · #025');
    expect(dex[1].dexLabel, 'Blueberry #164 · #001');
    expect(dex[63].dexLabel, '#063', reason: 'Abra is not in Scarlet');
    expect(dex[63].region, isNull);
    expect(dex[906].region, (name: 'Paldea', number: 1));
    expect(dex[10100].name, 'Raichu (Alolan)');
    expect(dex[10100].chipLabel, 'Alolan');
    expect(dex[26].chipLabel, 'Raichu');
  });

  test('defense is derived from types and shared per typing', () {
    final gyarados = dex.entries.firstWhere((e) => e.name == 'Gyarados');
    expect(gyarados.defense['electric'], 4);
    expect(gyarados.defense['ground'], 0);
    final raichu = dex[26];
    expect(
      identical(dex[25].defense, raichu.defense),
      isTrue,
    ); // both pure Electric
  });

  test('chainFor returns null for non-evolving species', () {
    final tauros = dex.entries.firstWhere((e) => e.name == 'Tauros');
    expect(dex.chainFor(tauros), isNull);
    expect(dex.chainFor(dex[133])!.from(133).length, 8);
  });
}
