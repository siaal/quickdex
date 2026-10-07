import '../trace.dart';
import 'normalise.dart';
import 'searchable.dart';

abstract interface class FrecencyScores {
  double score(int id);
}

enum MatchTier { prefix, wordPrefix, substring }

class SearchHit<T extends Searchable> {
  const SearchHit(this.entry, this.tier, this.score);
  final T entry;
  final MatchTier tier;
  final double score;
  bool get frecent => score > 0;
}

class _Key<T extends Searchable> {
  _Key(this.entry, this.order)
    : name = normalise(entry.name),
      words = splitWords(entry.name),
      dex = entry.number?.toString(),
      dexPadded = entry.number?.toString().padLeft(3, '0');
  final T entry;
  final int order;
  final String name;
  final List<String> words;
  final String? dex;
  final String? dexPadded;
}

/// Whether [b] ranks strictly before [a]: frecency score first, then match tier.
bool _before(SearchHit b, SearchHit a) {
  if ((a.score > 0 || b.score > 0) && a.score != b.score) {
    return b.score > a.score;
  }
  return b.tier.index < a.tier.index;
}

/// Merges two ranked result lists (e.g. Pokémon and moves) by the same rule
/// [SearchIndex.search] ranks with; [first] wins ties.
List<SearchHit<Searchable>> mergeHits(
  List<SearchHit<Searchable>> first,
  List<SearchHit<Searchable>> second,
) {
  final out = <SearchHit<Searchable>>[];
  var i = 0, j = 0;
  while (i < first.length && j < second.length) {
    out.add(_before(second[j], first[i]) ? second[j++] : first[i++]);
  }
  out
    ..addAll(first.skip(i))
    ..addAll(second.skip(j));
  assert(out.length == first.length + second.length);
  return out;
}

/// Ties keep the order of the list passed in (dex order, or name order for moves).
class SearchIndex<T extends Searchable> {
  SearchIndex(List<T> entries)
    : _keys = [for (var i = 0; i < entries.length; i++) _Key(entries[i], i)];

  final List<_Key<T>> _keys;
  static final _digits = RegExp(r'^[0-9]+$');

  List<SearchHit<T>> search(String query, FrecencyScores frecency) {
    final q = normalise(query);
    final numeric = _digits.hasMatch(q);
    final hits = <(SearchHit<T>, int)>[];
    for (final k in _keys) {
      final tier = q.isEmpty
          ? MatchTier.prefix
          : numeric
          ? _dexTier(k, q)
          : _nameTier(k, q);
      if (tier == null) continue;
      hits.add((SearchHit(k.entry, tier, frecency.score(k.entry.id)), k.order));
    }
    hits.sort((a, b) {
      final fa = a.$1.score, fb = b.$1.score;
      if (fa > 0 || fb > 0) {
        final c = fb.compareTo(fa);
        if (c != 0) return c;
      }
      final t = a.$1.tier.index.compareTo(b.$1.tier.index);
      return t != 0 ? t : a.$2.compareTo(b.$2);
    });
    if (hits.isEmpty) trace('search.rank.no_hits', {'len': q.length});
    return [for (final h in hits) h.$1];
  }

  MatchTier? _nameTier(_Key<T> k, String q) {
    if (k.name.startsWith(q)) return MatchTier.prefix;
    if (k.words.any((w) => w.startsWith(q))) return MatchTier.wordPrefix;
    if (k.name.contains(q)) return MatchTier.substring;
    return null;
  }

  MatchTier? _dexTier(_Key<T> k, String q) {
    if (k.dex == null) return null;
    if (int.tryParse(q) == k.entry.number) return MatchTier.prefix;
    if (k.dex!.startsWith(q) || k.dexPadded!.startsWith(q)) {
      return MatchTier.substring;
    }
    return null;
  }
}
