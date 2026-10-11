import 'dart:convert';
import 'dart:math';

import '../search/search_index.dart';
import '../trace.dart';

class FrecencyRecord {
  const FrecencyRecord(this.score, this.updated);
  final double score;
  final DateTime updated;
}

/// Exponentially-decayed visit score per entry id. O(1) state per entry.
class FrecencyStore implements FrecencyScores {
  FrecencyStore({
    DateTime Function()? clock,
    Map<int, FrecencyRecord>? records,
    this.onChanged,
  }) : _clock = clock ?? DateTime.now,
       _records = records ?? {};

  factory FrecencyStore.fromJson(
    String? raw, {
    DateTime Function()? clock,
    void Function(String json)? onChanged,
  }) {
    if (raw == null) {
      trace('frecency.load.empty');
      return FrecencyStore(clock: clock, onChanged: onChanged);
    }
    try {
      final map = (jsonDecode(raw) as Map<String, dynamic>).map((k, v) {
        final pair = (v as List).cast<num>();
        return MapEntry(
          int.parse(k),
          FrecencyRecord(
            pair[0].toDouble(),
            DateTime.fromMillisecondsSinceEpoch(pair[1].toInt(), isUtc: true),
          ),
        );
      });
      trace('frecency.load.ok', {'records': map.length});
      return FrecencyStore(clock: clock, records: map, onChanged: onChanged);
    } catch (e) {
      trace('frecency.load.corrupt', {'error': e.runtimeType.toString()});
      return FrecencyStore(clock: clock, onChanged: onChanged);
    }
  }

  static const halfLife = Duration(days: 3);
  static const prefsKey = 'frecency.v1';
  static const movesPrefsKey = 'frecency.moves.v1';

  final DateTime Function() _clock;
  final Map<int, FrecencyRecord> _records;
  final void Function(String json)? onChanged;

  @override
  double score(int id) {
    final r = _records[id];
    return r == null ? 0 : _decayed(r, _clock());
  }

  @override
  DateTime? lastVisit(int id) => _records[id]?.updated;

  bool isFrecent(int id) => _records.containsKey(id);

  void visit(int id) {
    final now = _clock();
    final r = _records[id];
    final base = r == null ? 0.0 : _decayed(r, now);
    _records[id] = FrecencyRecord(base + 1, now);
    trace('frecency.visit.credit', {'id': id, 'score': base + 1});
    _changed();
  }

  FrecencyRecord? remove(int id) {
    final r = _records.remove(id);
    trace(r == null ? 'frecency.remove.absent' : 'frecency.remove.ok', {
      'id': id,
    });
    if (r != null) _changed();
    return r;
  }

  void restore(int id, FrecencyRecord r) {
    assert(
      !_records.containsKey(id),
      'restore over an existing record for $id',
    );
    _records[id] = r;
    trace('frecency.restore', {'id': id});
    _changed();
  }

  String toJson() => jsonEncode({
    for (final e in _records.entries)
      '${e.key}': [e.value.score, e.value.updated.millisecondsSinceEpoch],
  });

  void _changed() => onChanged?.call(toJson());

  static double _decayed(FrecencyRecord r, DateTime now) {
    final age = now.difference(r.updated).inMilliseconds;
    assert(age >= -1000, 'frecency record from the future');
    return r.score * pow(0.5, max(age, 0) / halfLife.inMilliseconds);
  }
}
