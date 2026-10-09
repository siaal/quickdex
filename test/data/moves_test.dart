import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/search/search_index.dart';

MoveDex realMoves() =>
    MoveDex.parse(File('assets/data/moves.json').readAsStringSync());

class _NoScores implements FrecencyScores {
  @override
  double score(int id) => 0;
}

void main() {
  late MoveDex moves;
  setUpAll(() => moves = realMoves());

  Move named(String n) => moves.moves.firstWhere((m) => m.name == n);

  test('parses real data and invariants hold', () {
    expect(moves.moves.length, greaterThan(800));
    moves.assertInvariants();
  });

  test('Thunderbolt fields', () {
    final t = named('Thunderbolt');
    expect(t.type, 'electric');
    expect(t.category, MoveCategory.special);
    expect(
      (t.power, t.accuracy, t.pp, t.priority, t.chance),
      (90, 100, 15, 0, 10),
    );
    expect(t.inScarlet, isTrue);
    expect(t.flags, isEmpty);
    expect(t.contact, isFalse);
    expect(t.text, contains('paralysis'));
    expect(t.description, startsWith('Inflicts regular damage.'));
  });

  test('nullable fields', () {
    final sd = named('Swords Dance');
    expect((sd.power, sd.accuracy), (null, null));
    expect(named('Glaive Rush').contact, isTrue, reason: 'Gen 9, via Showdown');
    expect(named('Glaive Rush').description, isNull);
    expect(named('Return').inScarlet, isFalse);
  });

  test(
    'learnsets: Scarlet unlabelled, evolution moves first, fallback labelled',
    () {
      final pika = moves.learnsets[25]!;
      expect(pika.game, isNull);
      expect(pika.moves, contains((level: 36, move: named('Thunderbolt').id)));
      expect(moves.learnsets[700]!.moves.first, (
        level: 0,
        move: named('Disarming Voice').id,
      ));
      expect(moves.learnsets[63]!.game, 'Sword/Shield');
    },
  );

  test('search ignores punctuation and has no numeric matches', () {
    final index = SearchIndex(moves.moves);
    expect(index.search('uturn', _NoScores()).first.entry.name, 'U-turn');
    expect(index.search('25', _NoScores()), isEmpty);
  });
}
