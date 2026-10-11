import '../trace.dart';
import 'normalise.dart';
import 'searchable.dart';

abstract interface class FrecencyScores {
  double score(int id);

  /// When [id] was last visited, or null if it never was (or was forgotten).
  DateTime? lastVisit(int id);
}

enum MatchTier { prefix, wordPrefix, substring }

class SearchHit<T extends Searchable> {
  const SearchHit(this.entry, this.tier, this.score, [this.visited]);
  final T entry;
  final MatchTier tier;
  final double score;
  final DateTime? visited;
  bool get frecent => score > 0;
}

class _Key<T extends Searchable> {
  _Key(this.entry, this.order)
    : name = normalise(entry.name),
      words = splitWords(entry.name),
      numbers = [
        for (final n in entry.numbers) ...[
          n.toString(),
          n.toString().padLeft(3, '0'),
        ],
      ];
  final T entry;
  final int order;
  final String name;
  final List<String> words;

  /// Each dex number, unpadded and zero-padded to 3 digits.
  final List<String> numbers;
}

/// Whether a query lists everything by recency (nothing typed) rather than
/// ranking matches by frecency.
bool isRecencyQuery(String query) => normalise(query).isEmpty;

/// Negative when [a] ranks before [b], ignoring list order. [byRecency]: most
/// recently visited first; otherwise frecency score first, then match tier.
int _compare(SearchHit a, SearchHit b, bool byRecency) {
  if (byRecency) {
    final va = a.visited, vb = b.visited;
    if (va != null || vb != null) {
      if (va == null) return 1;
      if (vb == null) return -1;
      final c = vb.compareTo(va);
      if (c != 0) return c;
    }
  } else if (a.score > 0 || b.score > 0) {
    final c = b.score.compareTo(a.score);
    if (c != 0) return c;
  }
  return a.tier.index.compareTo(b.tier.index);
}

/// Merges two result lists (e.g. Pokémon and moves) ranked by
/// [SearchIndex.search] for the same query; [first] wins ties.
List<SearchHit<Searchable>> mergeHits(
  List<SearchHit<Searchable>> first,
  List<SearchHit<Searchable>> second, {
  bool byRecency = false,
}) {
  final out = <SearchHit<Searchable>>[];
  var i = 0, j = 0;
  while (i < first.length && j < second.length) {
    out.add(
      _compare(second[j], first[i], byRecency) < 0 ? second[j++] : first[i++],
    );
  }
  out
    ..addAll(first.skip(i))
    ..addAll(second.skip(j));
  assert(out.length == first.length + second.length);
  return out;
}

/// An empty query lists everything, most recently visited first; any typed
/// query ranks matches by frecency, then tier. Ties keep the order of the list
/// passed in (dex order, or name order for moves).
class SearchIndex<T extends Searchable> {
  SearchIndex(List<T> entries)
    : _keys = [for (var i = 0; i < entries.length; i++) _Key(entries[i], i)];

  final List<_Key<T>> _keys;
  static final _digits = RegExp(r'^[0-9]+$');

  List<SearchHit<T>> search(String query, FrecencyScores frecency) {
    final q = normalise(query);
    final numeric = _digits.hasMatch(q);
    final byRecency = q.isEmpty;
    final hits = <(SearchHit<T>, int)>[];
    for (final k in _keys) {
      final tier = q.isEmpty
          ? MatchTier.prefix
          : numeric
          ? _dexTier(k, q)
          : _nameTier(k, q);
      if (tier == null) continue;
      final id = k.entry.id;
      hits.add((
        SearchHit(k.entry, tier, frecency.score(id), frecency.lastVisit(id)),
        k.order,
      ));
    }
    hits.sort((a, b) {
      final c = _compare(a.$1, b.$1, byRecency);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    trace(byRecency ? 'search.rank.recency' : 'search.rank.frecency', {
      'len': q.length,
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
    if (k.numbers.isEmpty) return null;
    if (k.entry.numbers.contains(int.tryParse(q))) return MatchTier.prefix;
    if (k.numbers.any((n) => n.startsWith(q))) return MatchTier.substring;
    return null;
  }
}
