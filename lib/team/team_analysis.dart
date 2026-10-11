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

  /// Types of the chosen damaging moves, or the entry's own types when none
  /// are chosen (or moves haven't loaded).
  final List<String> attackTypes;
}

TeamMember resolveMember(int i, TeamSlot s, Pokedex dex, MoveDex? moves) {
  final e = dex[s.pokemon];
  final defense = Map.of(e.defense);
  final Set<String> immune;
  if (s.ability case final a?) {
    immune = abilityImmunities(dex.abilities[a]!, e.defense);
  } else {
    immune = e.guard?.types.toSet() ?? const {};
  }
  for (final t in immune) {
    defense[t] = 0;
  }
  final moveTypes = <String>[];
  if (moves == null) {
    trace('team.member.moves_not_loaded', {'slot': i});
  } else {
    for (final id in s.moves) {
      final m = moves.byId[id];
      if (m == null) {
        trace('team.member.unknown_move', {'slot': i, 'move': id});
      } else if (m.category != MoveCategory.status &&
          !moveTypes.contains(m.type)) {
        moveTypes.add(m.type);
      }
    }
  }
  final attack = moveTypes.isEmpty ? e.types : moveTypes;
  trace(moveTypes.isEmpty ? 'team.member.stab' : 'team.member.moves', {
    'slot': i,
    'attack': attack,
    'immune': immune.toList(),
  });
  return TeamMember(i, e, defense, attack);
}

/// The team against one type: as attacker (defense) and defender (offense).
class TypeMatchup {
  const TypeMatchup(this.type, this.defense, this.offense);
  final String type;

  /// Multiplier [type] deals to each member, in member order.
  final List<double> defense;

  /// Best multiplier each member's attack types deal to a pure [type].
  final List<double> offense;

  int get weak => defense.where((m) => m > 1).length;
  int get resist => defense.where((m) => m > 0 && m < 1).length;
  int get immune => defense.where((m) => m == 0).length;

  /// Members that hit [type] super-effectively.
  int get hitters => offense.where((m) => m > 1).length;
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
            m.attackTypes
                .map((a) => chart.multiplier(a, t))
                .reduce((x, y) => x > y ? x : y),
        ],
      ),
  ];
}
