import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../trace.dart';

/// One team member: a Pokémon entry, its chosen ability and up to four moves.
class TeamSlot {
  TeamSlot(this.pokemon, {this.ability, this.moves = const []})
    : assert(moves.length <= maxMoves, 'at most $maxMoves moves: $moves');

  static const maxMoves = 4;

  /// Pokémon entry id.
  final int pokemon;

  /// Ability id; null means "not chosen" (only a guaranteed immunity counts).
  final int? ability;

  /// Move ids in slot order, no gaps.
  final List<int> moves;

  TeamSlot copyWith({int? ability, List<int>? moves}) => TeamSlot(
    pokemon,
    ability: ability ?? this.ability,
    moves: moves ?? this.moves,
  );

  Map<String, dynamic> toJson() => {
    'p': pokemon,
    if (ability != null) 'a': ability,
    'm': moves,
  };
}

/// Six team slots (null = empty), persisted as JSON through [onChanged].
class Team extends ChangeNotifier {
  Team({List<TeamSlot?>? slots, this.onChanged})
    : _slots = List.of(slots ?? List<TeamSlot?>.filled(size, null)) {
    assert(_slots.length == size, 'a team has $size slots');
  }

  /// Unknown Pokémon (e.g. dropped by a data rebuild) empty their slot; an
  /// ability the entry can't have is cleared. Corrupt JSON gives an empty team.
  factory Team.fromJson(
    String? raw,
    Pokedex dex, {
    void Function(String json)? onChanged,
  }) {
    if (raw == null) {
      trace('team.load.empty');
      return Team(onChanged: onChanged);
    }
    try {
      final list = jsonDecode(raw) as List;
      final slots = List<TeamSlot?>.filled(size, null);
      for (var i = 0; i < size && i < list.length; i++) {
        final j = list[i] as Map<String, dynamic>?;
        if (j == null) continue;
        final e = dex.byId[j['p'] as int];
        if (e == null) {
          trace('team.load.unknown_pokemon', {'slot': i, 'id': j['p']});
          continue;
        }
        var ability = j['a'] as int?;
        if (ability != null && ![...e.abilities, ?e.hidden].contains(ability)) {
          trace('team.load.unknown_ability', {'slot': i, 'ability': ability});
          ability = null;
        }
        final moves = (j['m'] as List).cast<int>();
        slots[i] = TeamSlot(
          e.id,
          ability: ability,
          moves: moves.take(TeamSlot.maxMoves).toList(),
        );
      }
      trace('team.load.ok', {'filled': slots.nonNulls.length});
      return Team(slots: slots, onChanged: onChanged);
    } catch (e) {
      trace('team.load.corrupt', {'error': e.runtimeType.toString()});
      return Team(onChanged: onChanged);
    }
  }

  static const size = 6;
  static const prefsKey = 'team.v1';

  final void Function(String json)? onChanged;
  final List<TeamSlot?> _slots;

  List<TeamSlot?> get slots => List.unmodifiable(_slots);
  bool get isEmpty => _slots.every((s) => s == null);

  TeamSlot? operator [](int i) => _slots[i];

  /// Sets slot [i]; null empties it.
  void operator []=(int i, TeamSlot? slot) {
    assert(i >= 0 && i < size, 'slot $i out of range');
    trace(slot == null ? 'team.slot.clear' : 'team.slot.set', {
      'slot': i,
      'pokemon': slot?.pokemon,
      'moves': slot?.moves.length,
    });
    _slots[i] = slot;
    notifyListeners();
    onChanged?.call(toJson());
  }

  String toJson() => jsonEncode([for (final s in _slots) s?.toJson()]);
}
