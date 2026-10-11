import '../trace.dart';
import 'models.dart';

/// Types an entry is immune to because *every* ability it can have grants it.
class AbilityGuard {
  const AbilityGuard(this.ability, this.types);

  /// Display name, e.g. `Levitate` (several names joined with ` / `).
  final String ability;

  /// Types made immune that the type chart alone would let through, in chart order.
  final List<String> types;
}

/// Abilities that make attacking types deal no damage (Gen 9).
const _immunityAbilities = <String, Set<String>>{
  'levitate': {'ground'},
  'earth-eater': {'ground'},
  'flash-fire': {'fire'},
  'well-baked-body': {'fire'},
  'water-absorb': {'water'},
  'storm-drain': {'water'},
  'dry-skin': {'water'},
  'volt-absorb': {'electric'},
  'lightning-rod': {'electric'},
  'motor-drive': {'electric'},
  'sap-sipper': {'grass'},
};

/// Wonder Guard blocks every type that isn't super effective.
const _wonderGuard = 'wonder-guard';

/// Attacking types [a] blocks for an entry with chart [defense] (Wonder Guard:
/// everything not super effective); empty if it grants no immunity.
Set<String> abilityImmunities(Ability a, Map<String, double> defense) =>
    a.key == _wonderGuard
    ? {
        for (final t in defense.keys)
          if (defense[t]! < 2) t,
      }
    : _immunityAbilities[a.key] ?? const {};

AbilityGuard? guaranteedGuard(
  List<Ability> abilities,
  Map<String, double> defense,
) {
  assert(abilities.isNotEmpty, 'entry has no abilities');
  Set<String>? common;
  for (final a in abilities) {
    final immune = abilityImmunities(a, defense);
    if (immune.isEmpty) {
      return null; // one ability without an immunity breaks the guarantee
    }
    common = common == null ? immune : common.intersection(immune);
  }
  final types = [
    for (final t in defense.keys)
      if (common!.contains(t) && defense[t]! > 0) t,
  ];
  if (types.isEmpty) {
    trace('ability.guard.none_effective', {
      'abilities': [for (final a in abilities) a.key],
    });
    return null;
  }
  final names = {for (final a in abilities) a.name}.join(' / ');
  return AbilityGuard(names, types);
}
