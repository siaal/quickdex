import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/defense.dart';
import 'package:quickdex/data/models.dart';

import 'models_test.dart' show realDex;

Map<String, Map<double, List<String>>> flatten(List<DefenseGroup> groups) => {
  for (final g in groups) g.label: {for (final (m, ts) in g.buckets) m: ts},
};

void main() {
  late Pokedex dex;
  setUpAll(() => dex = realDex());

  test('Gyarados groups match Bulbapedia', () {
    final gyarados = dex.entries.firstWhere((e) => e.name == 'Gyarados');
    final g = flatten(defenseGroups(gyarados.defense, dex.types.order));
    expect(g['Weak to'], {
      4.0: ['electric'],
      2.0: ['rock'],
    });
    expect(g['Resistant to'], {
      0.5: ['bug', 'fighting', 'fire', 'steel', 'water'],
    });
    expect(g['Immune to'], {
      0.0: ['ground'],
    });
    expect(g.containsKey('Damaged normally by'), isFalse);
  });

  test('Shedinja groups match Bulbapedia', () {
    final shedinja = dex.entries.firstWhere((e) => e.name == 'Shedinja');
    final g = flatten(defenseGroups(shedinja.defense, dex.types.order));
    expect(g['Weak to'], {
      2.0: ['dark', 'fire', 'flying', 'ghost', 'rock'],
    });
    expect(g['Resistant to'], {
      0.5: ['bug', 'grass', 'ground', 'poison'],
    });
    expect(g['Immune to'], {
      0.0: ['fighting', 'normal'],
    });
  });

  test('empty categories are omitted', () {
    final pikachu = dex[25];
    final labels = defenseGroups(
      pikachu.defense,
      dex.types.order,
    ).map((g) => g.label);
    expect(labels, isNot(contains('Immune to')));
  });

  test('multLabel', () {
    expect(multLabel(0.25), '¼×');
    expect(multLabel(0.5), '½×');
    expect(multLabel(4), '4×');
    expect(multLabel(0), '0×');
  });
}
