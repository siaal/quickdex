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
    this.lastBenched = 0,
  }) : assert(lastBenched >= 0),
       assert(moves.length <= maxMoves, 'at most $maxMoves moves: $moves'),
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

  /// Removal-order counter within this team; zero means never benched.
  final int lastBenched;

  /// Replacing [moves] keeps only the hidden ids still among them.
  TeamSlot copyWith({
    int? ability,
    List<int>? moves,
    Set<int>? hidden,
    int? lastBenched,
  }) {
    final m = moves ?? this.moves;
    return TeamSlot(
      pokemon,
      ability: ability ?? this.ability,
      moves: m,
      hidden: (hidden ?? this.hidden).intersection(m.toSet()),
      lastBenched: lastBenched ?? this.lastBenched,
    );
  }

  Map<String, dynamic> toJson() => {
    'p': pokemon,
    if (ability != null) 'a': ability,
    'm': moves,
    if (hidden.isNotEmpty) 'h': hidden.toList(),
    if (lastBenched > 0) 'b': lastBenched,
  };
}

enum SidedeckSort { recency, name }

/// A sidedeck and its squad: deck indices, null for empty slots. The first
/// six slots are the planner view; extra selections persist while editing.
class Lineup {
  Lineup(List<TeamSlot> deck, List<int?> squad)
    : deck = List.unmodifiable(deck),
      squad = List.unmodifiable(squad) {
    assert(
      squad.length >= Team.size,
      'a squad has at least ${Team.size} slots',
    );
    assert(
      squad.nonNulls.every((d) => d >= 0 && d < deck.length),
      'squad $squad points outside a deck of ${deck.length}',
    );
    assert(
      squad.nonNulls.toSet().length == squad.nonNulls.length,
      'a deck member fills one slot at most: $squad',
    );
  }

  /// A deck of just [slots]' Pokémon, all in the squad.
  factory Lineup.ofSlots(List<TeamSlot?> slots) {
    assert(slots.length == Team.size, 'a team has ${Team.size} slots');
    final deck = <TeamSlot>[];
    final squad = <int?>[
      for (final s in slots)
        if (s == null) null else (deck..add(s)).length - 1,
    ];
    return Lineup(deck, squad);
  }

  static final empty = Lineup(const [], List.filled(Team.size, null));

  /// Reads [toJson]'s `{"d": deck, "q": squad}`, or the older `{"s": slots}`.
  /// Unknown Pokémon leave the deck (and their slot); bad squad indices empty
  /// their slot.
  factory Lineup.fromJson(Map<String, dynamic> j, Pokedex dex) {
    if (j['d'] case final List<dynamic> rawDeck) {
      final deck = <TeamSlot>[];
      final moved = <int, int>{}; // json index -> deck index
      for (final (i, raw) in rawDeck.indexed) {
        if (Team.parseSlot(raw as Map<String, dynamic>, dex, i) case final s?) {
          moved[i] = deck.length;
          deck.add(s);
        }
      }
      final rawSquad = (j['q'] as List).cast<int?>();
      final squad = List<int?>.filled(
        rawSquad.length > Team.size ? rawSquad.length : Team.size,
        null,
      );
      for (var i = 0; i < rawSquad.length; i++) {
        final d = moved[rawSquad[i]];
        if (d == null || squad.contains(d)) {
          if (rawSquad[i] != null) {
            trace('team.load.bad_squad', {'slot': i, 'index': rawSquad[i]});
          }
          continue;
        }
        squad[i] = d;
      }
      return Lineup(deck, squad);
    }
    trace('team.load.legacy_slots');
    return Lineup.ofSlots(Team.parseSlots(j['s'] as List, dex));
  }

  final List<TeamSlot> deck;
  final List<int?> squad;

  /// The six-slot planner view, even during an overfull Sidedeck edit.
  List<TeamSlot?> get slots => [
    for (final d in squad.take(Team.size)) d == null ? null : deck[d],
  ];

  Map<String, dynamic> toJson() => {
    'd': [for (final s in deck) s.toJson()],
    'q': squad,
  };
}

/// A sidedeck of Pokémon, with temporary extra squad selections allowed by
/// [toggle]; persisted as JSON through [onChanged]. The slot API (`team[i]`)
/// edits squad members: setting an empty slot adds to the deck, clearing a
/// slot only takes its member out of the squad.
class Team extends ChangeNotifier {
  Team({
    List<TeamSlot?>? slots,
    String? name,
    void Function(String json)? onChanged,
  }) : this._lineup(
         Lineup.ofSlots(slots ?? List.filled(size, null)),
         name,
         onChanged,
       );

  Team._lineup(
    Lineup l,
    this._name,
    this.onChanged, {
    SidedeckSort sort = SidedeckSort.recency,
  }) : _deck = List.of(l.deck),
       _squad = List.of(l.squad),
       _memberIds = List.generate(l.deck.length, (i) => i),
       _nextMemberId = l.deck.length,
       _sidedeckSort = sort {
    _settleSquad();
  }

  /// Reads [toJson]'s `{"n": name, ...}` with a [Lineup], or the older bare
  /// slot list. Corrupt JSON gives an empty team.
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
      final (lineup, name) = j is List
          ? (Lineup.ofSlots(parseSlots(j, dex)), null)
          : (
              Lineup.fromJson(j as Map<String, dynamic>, dex),
              j['n'] as String?,
            );
      trace('team.load.ok', {
        'deck': lineup.deck.length,
        'squad': lineup.squad.nonNulls.length,
      });
      return Team._lineup(
        lineup,
        name,
        onChanged,
        sort: j is Map && j['sort'] == 'name'
            ? SidedeckSort.name
            : SidedeckSort.recency,
      );
    } catch (e) {
      trace('team.load.corrupt', {'error': e.runtimeType.toString()});
      return Team(onChanged: onChanged);
    }
  }

  /// Slot JSON (as in [TeamSlot.toJson]) to [size] slots; see [parseSlot].
  static List<TeamSlot?> parseSlots(List<dynamic> list, Pokedex dex) {
    final slots = List<TeamSlot?>.filled(size, null);
    for (var i = 0; i < size && i < list.length; i++) {
      if (list[i] case final Map<String, dynamic> j) {
        slots[i] = parseSlot(j, dex, i);
      }
    }
    return slots;
  }

  /// One member's JSON; null for an unknown Pokémon (e.g. dropped by a data
  /// rebuild). An unknown ability is cleared. Any known ability is kept, as
  /// bosses can have one their species can't.
  static TeamSlot? parseSlot(Map<String, dynamic> j, Pokedex dex, int i) {
    final e = dex.byId[j['p'] as int];
    if (e == null) {
      trace('team.load.unknown_pokemon', {'slot': i, 'id': j['p']});
      return null;
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
    return TeamSlot(
      e.id,
      ability: ability,
      moves: moves.toList(),
      hidden: hidden.intersection(moves.toSet()),
      lastBenched: switch (j['b']) {
        final int b when b >= 0 => b,
        _ => 0,
      },
    );
  }

  static const size = 6;
  static const prefsKey = 'team.v1';

  final void Function(String json)? onChanged;
  final List<TeamSlot> _deck;
  final List<int?> _squad;
  final List<int> _memberIds;
  int _nextMemberId;
  SidedeckSort _sidedeckSort;
  String? _name;

  /// Stable for this member's lifetime, even when edited or reindexed.
  int memberId(int d) => _memberIds[d];

  SidedeckSort get sidedeckSort => _sidedeckSort;
  set sidedeckSort(SidedeckSort sort) {
    trace('team.deck.sort', {'sort': sort.name});
    _sidedeckSort = sort;
    _changed();
  }

  void _bench(int d) {
    assert(slotOf(d) != null);
    final latest = _deck.fold(
      0,
      (n, s) => s.lastBenched > n ? s.lastBenched : n,
    );
    _deck[d] = _deck[d].copyWith(lastBenched: latest + 1);
    trace('team.member.benched', {'deck_index': d, 'order': latest + 1});
  }

  /// The build last loaded or saved as, kept through edits so saving again
  /// offers to overwrite it. Null for a team never saved or loaded.
  String? get name => _name;
  set name(String? n) {
    trace('team.name', {'named': n != null});
    _name = n;
    _changed();
  }

  Lineup get lineup => Lineup(_deck, _squad);
  List<TeamSlot> get deck => List.unmodifiable(_deck);
  List<TeamSlot?> get slots => lineup.slots;

  /// No squad members (the deck may still have some).
  bool get isEmpty => _squad.every((d) => d == null);
  int get squadCount => _squad.nonNulls.length;
  bool get isLegal => squadCount <= size;

  TeamSlot? operator [](int i) => switch (_squad[i]) {
    final d? => _deck[d],
    null => null,
  };

  /// Sets slot [i]: replaces its member, or adds one to the deck if the slot
  /// is empty. Null takes the member out of the squad, keeping it in the deck.
  void operator []=(int i, TeamSlot? slot) {
    assert(i >= 0 && i < size, 'slot $i out of range');
    final d = _squad[i];
    if (slot == null) {
      trace('team.slot.clear', {'slot': i, 'deck_index': d});
      if (d != null) _bench(d);
      _squad[i] = null;
    } else if (d != null) {
      trace('team.slot.set', {
        'slot': i,
        'pokemon': slot.pokemon,
        'moves': slot.moves.length,
      });
      _deck[d] = slot.copyWith(lastBenched: _deck[d].lastBenched);
    } else {
      trace('team.slot.add', {'slot': i, 'pokemon': slot.pokemon});
      _deck.add(slot);
      _memberIds.add(_nextMemberId++);
      _squad[i] = _deck.length - 1;
    }
    _changed();
  }

  /// The squad slot deck member [d] fills, or null if it's out.
  int? slotOf(int d) {
    final i = _squad.indexOf(d);
    return i < 0 ? null : i;
  }

  /// Replaces deck member [d] (in the squad or not).
  void setMember(int d, TeamSlot slot) {
    assert(d >= 0 && d < _deck.length, 'deck index $d out of range');
    trace('team.member.set', {'deck_index': d, 'pokemon': slot.pokemon});
    _deck[d] = slot.copyWith(lastBenched: _deck[d].lastBenched);
    _changed();
  }

  /// Adds [slot] to the deck, into the first empty squad slot if any; returns
  /// its deck index.
  int add(TeamSlot slot) {
    _deck.add(slot);
    _memberIds.add(_nextMemberId++);
    final d = _deck.length - 1;
    final free = _squad.indexOf(null);
    trace('team.member.add', {'deck_index': d, 'slot': free < 0 ? null : free});
    if (free >= 0) _squad[free] = d;
    _changed();
    return d;
  }

  /// Puts deck member [d] into the first empty slot, or takes it out.
  /// Only Sidedeck opts into [allowOverflow]; other callers retain the limit.
  bool toggle(int d, {bool allowOverflow = false}) {
    assert(d >= 0 && d < _deck.length, 'deck index $d out of range');
    if (slotOf(d) case final i?) {
      trace('team.member.out', {'deck_index': d, 'slot': i});
      _bench(d);
      _squad[i] = null;
    } else {
      final free = _squad.indexOf(null);
      if (free < 0) {
        if (!allowOverflow) {
          trace('team.member.squad_full', {'deck_index': d});
          return false;
        }
        trace('team.member.overflow', {'deck_index': d, 'count': squadCount});
        _squad.add(d);
      } else {
        trace('team.member.in', {'deck_index': d, 'slot': free});
        _squad[free] = d;
      }
    }
    _changed();
    return true;
  }

  /// Deletes deck member [d], emptying its slot if it had one.
  void remove(int d) {
    assert(d >= 0 && d < _deck.length, 'deck index $d out of range');
    trace('team.member.remove', {'deck_index': d, 'slot': slotOf(d)});
    _deck.removeAt(d);
    _memberIds.removeAt(d);
    for (var i = 0; i < _squad.length; i++) {
      final q = _squad[i];
      if (q == null) continue;
      _squad[i] = q == d ? null : (q > d ? q - 1 : q);
    }
    _changed();
  }

  /// Replaces the deck and squad (a loaded build), as one change.
  void load(Lineup lineup, {required String? name}) {
    trace('team.load_build', {
      'deck': lineup.deck.length,
      'squad': lineup.squad.nonNulls.length,
    });
    _deck
      ..clear()
      ..addAll(lineup.deck);
    _memberIds
      ..clear()
      ..addAll(List.generate(_deck.length, (_) => _nextMemberId++));
    _squad
      ..clear()
      ..addAll(lineup.squad);
    _name = name;
    _changed();
  }

  // Move extra selections into vacancies without losing any member. Keep the
  // original six slots (including holes) when no extras remain.
  void _settleSquad() {
    final extras = _squad.skip(size).nonNulls.toList();
    if (extras.isEmpty && _squad.length == size) return;
    final count = squadCount;
    trace('team.squad.settle', {'extras': extras.length, 'count': count});
    _squad.removeRange(size, _squad.length);
    for (final d in extras) {
      final free = _squad.indexOf(null);
      if (free < 0) {
        trace('team.squad.keep_extra', {'deck_index': d});
        _squad.add(d);
      } else {
        trace('team.squad.promote', {'deck_index': d, 'slot': free});
        _squad[free] = d;
      }
    }
    assert(squadCount == count, 'settling must preserve every selection');
    assert(_squad.length == size || !_squad.contains(null));
  }

  void _changed() {
    _settleSquad();
    assert(_memberIds.length == _deck.length);
    assert(_memberIds.toSet().length == _memberIds.length);
    assert(lineup.deck.length == _deck.length); // Lineup checks the indices
    notifyListeners();
    onChanged?.call(toJson());
  }

  String toJson() => jsonEncode({
    'n': ?_name,
    ...lineup.toJson(),
    if (_sidedeckSort != SidedeckSort.recency) 'sort': _sidedeckSort.name,
  });
}
