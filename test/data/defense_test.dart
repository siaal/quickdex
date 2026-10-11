import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/defense.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/ui/matchup_section.dart';

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

  test('coverageFor takes the best multiplier of either attacking type', () {
    final c = dex.types.coverageFor(['electric', 'ice']);
    expect(c['ground'], 2, reason: 'Ice covers the Electric immunity');
    expect(c['water'], 2);
    expect(dex.types.coverageFor(['fire', 'water'])['dragon'], 0.5);
    expect(dex.types.coverageFor(['electric'])['ground'], 0);
  });

  test('matchupTint: red when bad for the viewer, stronger at 4× / ¼×', () {
    final weak4 = matchupTint(4, defending: true);
    final weak2 = matchupTint(2, defending: true);
    expect(weak4.r, greaterThan(weak4.g));
    expect(weak4.a, greaterThan(weak2.a));
    final se = matchupTint(2, defending: false);
    expect(se.g, greaterThan(se.r), reason: 'super effective is good');
    expect(matchupTint(1, defending: true), Colors.transparent);
    expect(extremeMultiplier([4, 2]), 4);
    expect(extremeMultiplier([0.5, 0.25]), 0.25);
    expect(extremeMultiplier([2, 0]), 0);
  });

  test('multLabel', () {
    expect(multLabel(0.25), '¼×');
    expect(multLabel(0.5), '½×');
    expect(multLabel(4), '4×');
    expect(multLabel(0), '0×');
  });
}
