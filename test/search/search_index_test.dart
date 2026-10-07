import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/search/search_index.dart';

import '../support/fixture.dart';

class FakeScores implements FrecencyScores {
  FakeScores([this.scores = const {}]);
  final Map<int, double> scores;
  @override
  double score(int id) => scores[id] ?? 0;
}

List<String> names(List<SearchHit> hits) => [
  for (final h in hits) h.entry.name,
];

void main() {
  final index = SearchIndex(fixtureEntries);

  test('mrmime / mr mime / Mr. Mime all find Mr. Mime', () {
    for (final q in ['mrmime', 'mr mime', 'Mr. Mime']) {
      expect(names(index.search(q, FakeScores())).first, 'Mr. Mime', reason: q);
    }
  });

  test('dex number with or without padding', () {
    expect(names(index.search('025', FakeScores())).first, 'Pikachu');
    expect(names(index.search('25', FakeScores())).first, 'Pikachu');
  });

  test('match tiers: prefix, then word prefix, then substring', () {
    final hits = index.search('mime', FakeScores());
    expect(names(hits), ['Mime Jr.', 'Mr. Mime']);
    expect(hits.map((h) => h.tier), [MatchTier.prefix, MatchTier.wordPrefix]);
    expect(
      index
          .search('chu', FakeScores())
          .every((h) => h.tier == MatchTier.substring),
      isTrue,
    );
  });

  test('form label matches', () {
    expect(names(index.search('alolan', FakeScores())), ['Raichu (Alolan)']);
  });

  test('frecent match outranks better non-frecent match', () {
    final hits = index.search('mime', FakeScores({122: 0.5}));
    expect(names(hits), ['Mr. Mime', 'Mime Jr.']);
    expect(hits.first.frecent, isTrue);
  });

  test('frecent entries ordered by score', () {
    final hits = index.search('', FakeScores({151: 1, 25: 3}));
    expect(names(hits).take(3), ['Pikachu', 'Mew', 'Raichu']);
  });

  test('empty query lists everything in dex order after frecent', () {
    final hits = index.search('', FakeScores());
    expect(hits.length, fixtureEntries.length);
    expect(names(hits).take(2), ['Pikachu', 'Raichu']);
  });

  test('no match returns empty', () {
    expect(index.search('zzz', FakeScores()), isEmpty);
  });

  group('mergeHits', () {
    // A second kind of searchable, standing in for moves.
    final other = SearchIndex([fx(1, 'Mimic'), fx(2, 'Thunder Shock')]);

    test('tier decides; first list wins ties', () {
      final merged = mergeHits(
        index.search('mi', FakeScores()),
        other.search('mi', FakeScores()),
      );
      expect(names(merged), ['Mime Jr.', 'Mimic', 'Mr. Mime']);
    });

    test('frecency outranks tier across both lists', () {
      final merged = mergeHits(
        index.search('mi', FakeScores({122: 1})),
        other.search('mi', FakeScores({1: 2})),
      );
      expect(names(merged), ['Mimic', 'Mr. Mime', 'Mime Jr.']);
    });
  });
}
