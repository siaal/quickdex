import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../trace.dart';

/// One team member: a Pokémon entry, its chosen ability and up to four moves.
class TeamSlot {
  TeamSlot(
    this.pokemon, {
    this.ability,
    this.moves = const [],
    this.hidden = const {},
  }) : assert(moves.length <= maxMoves, 'at most $maxMoves moves: $moves'),
       assert(
         moves.toSet().containsAll(hidden),
         'hidden $hidden not in $moves',
       );

  static const maxMoves = 4;

  /// Pokémon entry id.
  final int pokemon;

  /// Ability id; null means "not chosen" (only a guaranteed immunity counts).
  final int? ability;

  /// Move ids in slot order, no gaps.
  final List<int> moves;

  /// Move ids (a subset of [moves]) left out of the team analysis, e.g. a
  /// U-turn that doesn't define the matchup.
  final Set<int> hidden;

  /// Replacing [moves] keeps only the hidden ids still among them.
  TeamSlot copyWith({int? ability, List<int>? moves, Set<int>? hidden}) {
    final m = moves ?? this.moves;
    return TeamSlot(
      pokemon,
      ability: ability ?? this.ability,
      moves: m,
      hidden: (hidden ?? this.hidden).intersection(m.toSet()),
    );
  }

  Map<String, dynamic> toJson() => {
    'p': pokemon,
    if (ability != null) 'a': ability,
    'm': moves,
    if (hidden.isNotEmpty) 'h': hidden.toList(),
  };
}

/// Six team slots (null = empty), persisted as JSON through [onChanged].
class Team extends ChangeNotifier {
  Team({List<TeamSlot?>? slots, String? name, this.onChanged})
    : _slots = List.of(slots ?? List<TeamSlot?>.filled(size, null)),
      _name = name {
    assert(_slots.length == size, 'a team has $size slots');
  }

  /// Reads [toJson]'s `{"n": name, "s": slots}`, or the older bare slot list.
  /// Corrupt JSON gives an empty team.
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
      final j = jsonDecode(raw);
      final (list, name) = j is List
          ? (j, null)
          : ((j as Map<String, dynamic>)['s'] as List, j['n'] as String?);
      final slots = parseSlots(list, dex);
      trace('team.load.ok', {'filled': slots.nonNulls.length});
      return Team(slots: slots, name: name, onChanged: onChanged);
    } catch (e) {
      trace('team.load.corrupt', {'error': e.runtimeType.toString()});
      return Team(onChanged: onChanged);
    }
  }

  /// Slot JSON (as in [toJson]) to [size] slots. Unknown Pokémon (e.g. dropped
  /// by a data rebuild) empty their slot; an unknown ability is cleared. Any
  /// known ability is kept, as bosses can have one their species can't.
  static List<TeamSlot?> parseSlots(List<dynamic> list, Pokedex dex) {
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
      if (ability != null && !dex.abilities.containsKey(ability)) {
        trace('team.load.unknown_ability', {'slot': i, 'ability': ability});
        ability = null;
      }
      final moves = (j['m'] as List).cast<int>().take(TeamSlot.maxMoves);
      final hidden = ((j['h'] as List?) ?? const []).cast<int>().toSet();
      if (!moves.toSet().containsAll(hidden)) {
        trace('team.load.stray_hidden', {'slot': i, 'hidden': hidden.length});
      }
      slots[i] = TeamSlot(
        e.id,
        ability: ability,
        moves: moves.toList(),
        hidden: hidden.intersection(moves.toSet()),
      );
    }
    return slots;
  }

  static const size = 6;
  static const prefsKey = 'team.v1';

  final void Function(String json)? onChanged;
  final List<TeamSlot?> _slots;
  String? _name;

  /// The build last loaded or saved as, kept through edits so saving again
  /// offers to overwrite it. Null for a team never saved or loaded.
  String? get name => _name;
  set name(String? n) {
    trace('team.name', {'named': n != null});
    _name = n;
    _changed();
  }

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
    _changed();
  }

  /// Replaces every slot (a loaded build), as one change.
  void load(List<TeamSlot?> slots, {required String? name}) {
    assert(slots.length == size, 'a team has $size slots');
    trace('team.load_build', {'filled': slots.nonNulls.length});
    _slots.setAll(0, slots);
    _name = name;
    _changed();
  }

  void _changed() {
    notifyListeners();
    onChanged?.call(toJson());
  }

  String toJson() => jsonEncode({
    'n': ?_name,
    's': [for (final s in _slots) s?.toJson()],
  });
}
