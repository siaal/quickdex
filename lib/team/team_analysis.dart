import '../data/ability_guard.dart';
import '../data/models.dart';
import '../data/moves.dart';
import '../trace.dart';
import 'team.dart';

/// A filled team slot resolved against the data.
class TeamMember {
  const TeamMember(this.slot, this.entry, this.defense, this.attackTypes);
  final int slot;
  final PokemonEntry entry;

  /// Chart multipliers, with the chosen ability's immunities set to 0×. With
  /// no ability chosen, only a guaranteed immunity (all abilities) counts.
  final Map<String, double> defense;

  /// Types of the chosen damaging moves that aren't hidden; empty when the
  /// counted moves are all status moves (it deals no damage). The entry's own
  /// types when no moves count (none chosen, all hidden, or not loaded yet).
  final List<String> attackTypes;
}

TeamMember resolveMember(int i, TeamSlot s, Pokedex dex, MoveDex? moves) {
  final e = dex[s.pokemon];
  final defense = Map.of(e.defense);
  final Set<String> immune;
  if (s.ability case final a?) {
    immune = abilityImmunities(dex.abilities[a]!, e.defense, dex.game.gen);
  } else {
    immune = e.guard?.types.toSet() ?? const {};
  }
  for (final t in immune) {
    defense[t] = 0;
  }
  final moveTypes = <String>[];
  var counted = 0;
  if (moves == null) {
    trace('team.member.moves_not_loaded', {'slot': i});
  } else {
    for (final id in s.moves) {
      final m = moves.byId[id];
      if (m == null) {
        trace('team.member.unknown_move', {'slot': i, 'move': id});
      } else if (s.hidden.contains(id)) {
        trace('team.member.hidden_move', {'slot': i, 'move': id});
      } else {
        counted++;
        if (m.category != MoveCategory.status && !moveTypes.contains(m.type)) {
          moveTypes.add(m.type);
        }
      }
    }
  }
  final attack = counted == 0 ? e.types : moveTypes;
  trace(
    switch ((counted, moveTypes.length)) {
      (0, _) => 'team.member.stab',
      (_, 0) => 'team.member.status_only',
      _ => 'team.member.moves',
    },
    {'slot': i, 'attack': attack, 'immune': immune.toList()},
  );
  return TeamMember(i, e, defense, attack);
}

/// How hard [attacker] hits [defender]: the best multiplier any of its attack
/// types deals, counting the defender's ability immunity (as [analyseTeam]
/// does). Null when it has only status moves.
double? hit(TeamMember attacker, TeamMember defender) {
  if (attacker.attackTypes.isEmpty) return null;
  return attacker.attackTypes
      .map((t) => defender.defense[t]!)
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
            m.attackTypes.isEmpty
                ? null
                : m.attackTypes
                      .map((a) => chart.multiplier(a, t))
                      .reduce((x, y) => x > y ? x : y),
        ],
      ),
  ];
}
