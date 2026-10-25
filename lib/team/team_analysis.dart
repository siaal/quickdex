import 'package:flutter/foundation.dart';

import '../data/ability_guard.dart';
import '../data/models.dart';
import '../data/moves.dart';
import '../trace.dart';
import 'team.dart';

/// A filled team slot resolved against the data.
class TeamMember {
  const TeamMember(
    this.slot,
    this.entry,
    this.defense,
    this.attacks, {
    this.tera,
  });
  final int slot;
  final PokemonEntry entry;

  /// The Tera type it has terastallized into; null when it hasn't.
  final String? tera;

  /// Chart multipliers, with the chosen ability's immunities set to 0×. With
  /// no ability chosen, only a guaranteed immunity (all abilities) counts.
  final Map<String, double> defense;

  /// What it can hit with: one list of types per distinct attack (its
  /// multipliers multiply, e.g. Flying Press is `[fighting, flying]`; see
  /// [Move.hitTypes]). From the chosen damaging moves that aren't hidden, plus
  /// one per own type while any of its four move slots is unknown (not yet
  /// chosen, or moves not loaded; a boss's full moveset has none). Empty when it has four moves and none deal
  /// damage.
  final List<List<String>> attacks;
}

/// Slot [i]'s [TeamMember]: its defence (with ability immunities) and attacks.
/// [terastallized] with a Tera type set: it defends as that type alone. Its
/// moves keep their types (Tera Blast aside), so unknown move slots still
/// count as its own types' STAB, not the Tera type's.
TeamMember resolveMember(
  int i,
  TeamSlot s,
  Pokedex dex,
  MoveDex? moves, {
  bool terastallized = false,
}) {
  final e = dex[s.pokemon];
  final tera = terastallized ? s.tera : null;
  assert(!terastallized || tera != null, 'no Tera type to terastallize into');
  final base = tera == null ? e.defense : dex.types.defenseFor([tera]);
  final defense = Map.of(base);
  final Set<String> immune;
  if (s.ability case final a?) {
    immune = abilityImmunities(dex.abilities[a]!, base, dex.game.gen);
  } else if (tera != null) {
    trace('team.member.tera_guard', {'slot': i, 'tera': tera});
    immune =
        guaranteedGuard(
          [
            for (final a in [...e.abilities, ?e.hidden]) dex.abilities[a]!,
          ],
          base,
          dex.game.gen,
        )?.types.toSet() ??
        const {};
  } else {
    immune = e.guard?.types.toSet() ?? const {};
  }
  for (final t in immune) {
    defense[t] = 0;
  }
  final attack = <List<String>>[];
  void addAttack(List<String> types) {
    if (!attack.any((a) => listEquals(a, types))) attack.add(types);
  }

  // Move slots not yet chosen are unknown, not empty: they could be STAB.
  final unknown = moves == null ? TeamSlot.maxMoves : s.unknownMoves;
  assert(unknown >= 0, 'at most ${TeamSlot.maxMoves} moves');
  if (moves == null) {
    trace('team.member.moves_not_loaded', {'slot': i});
  } else {
    for (final id in s.moves) {
      final m = moves.byId[id];
      if (m == null) {
        trace('team.member.unknown_move', {'slot': i, 'move': id});
      } else if (s.hidden.contains(id)) {
        trace('team.member.hidden_move', {'slot': i, 'move': id});
      } else if (m.category != MoveCategory.status) {
        addAttack(m.hitTypes(e.types, tera: tera));
      }
    }
  }
  if (unknown > 0) {
    for (final t in e.types) {
      addAttack([t]);
    }
  }
  trace(attack.isEmpty ? 'team.member.no_damage' : 'team.member.attack', {
    'slot': i,
    'attack': attack,
    'unknown_moves': unknown,
    'immune': immune.toList(),
    'tera': tera,
  });
  return TeamMember(i, e, defense, attack, tera: tera);
}

/// How hard [attacker] hits [defender]: the best multiplier any of its
/// attacks deals, counting the defender's ability immunity (as [analyseTeam]
/// does). Null when it has only status moves.
double? hit(TeamMember attacker, TeamMember defender) =>
    _best(attacker.attacks, (t) => defender.defense[t]!);

/// The attacks (each a list of types, multiplied) with which [attacker]
/// gets [hit] on [defender]; ties all count, in move order. Empty when it
/// has only status moves.
List<List<String>> hitWith(TeamMember attacker, TeamMember defender) {
  final best = hit(attacker, defender);
  if (best == null) return const [];
  double of(List<String> a) =>
      a.map((t) => defender.defense[t]!).reduce((x, y) => x * y);
  final via = [
    for (final a in attacker.attacks)
      if (of(a) == best) a,
  ];
  assert(via.isNotEmpty);
  return via;
}

/// The best multiplier [m]'s attacks deal to each pure defending type, in
/// chart order; null when it has only status moves.
Map<String, double>? coverageOf(TeamMember m, TypeChart chart) {
  if (m.attacks.isEmpty) {
    trace('team.coverage.no_damage', {'slot': m.slot});
    return null;
  }
  return {
    for (final t in chart.order)
      t: _best(m.attacks, (a) => chart.multiplier(a, t))!,
  };
}

/// The best of [attacks], each the product of its types' multipliers [of];
/// null when there are none.
double? _best(List<List<String>> attacks, double Function(String type) of) {
  if (attacks.isEmpty) return null;
  return attacks
      .map((a) => a.map(of).reduce((x, y) => x * y))
      .reduce((x, y) => x > y ? x : y);
}

/// The team against one type: as attacker (defense) and defender (offense).
class TypeMatchup {
  const TypeMatchup(this.type, this.defense, this.offense);
  final String type;

  /// Multiplier [type] deals to each member, in member order.
  final List<double> defense;

  /// Best multiplier each member's attack types deal to a pure [type]; null
  /// for a member with only status moves.
  final List<double?> offense;

  int get weak => defense.where((m) => m > 1).length;
  int get resist => defense.where((m) => m > 0 && m < 1).length;
  int get immune => defense.where((m) => m == 0).length;

  /// Members that hit [type] super-effectively.
  int get hitters => offense.where((m) => m != null && m > 1).length;

  /// Each member's edge over [type]: doublings dealt minus doublings taken,
  /// with 0× counting as three halvings. Positive = ahead, negative = behind;
  /// takes 2× and deals 2× is even. Dealing no damage counts as neutral.
  List<double> get edges => [
    for (var i = 0; i < defense.length; i++)
      _steps(offense[i] ?? 1) - _steps(defense[i]),
  ];

  int get ahead => edges.where((e) => e > 0).length;
  int get behind => edges.where((e) => e < 0).length;

  static double _steps(double m) {
    assert(const [0, 0.25, 0.5, 1, 2, 4].contains(m), 'multiplier $m');
    return switch (m) {
      0 => -3,
      0.25 => -2,
      0.5 => -1,
      2 => 1,
      4 => 2,
      _ => 0,
    };
  }
}

/// One row per type in chart order.
List<TypeMatchup> analyseTeam(List<TeamMember> members, TypeChart chart) {
  assert(members.isNotEmpty, 'analyse a team with at least one member');
  return [
    for (final t in chart.order)
      TypeMatchup(
        t,
        [for (final m in members) m.defense[t]!],
        [
          for (final m in members)
            _best(m.attacks, (a) => chart.multiplier(a, t)),
        ],
      ),
  ];
}
