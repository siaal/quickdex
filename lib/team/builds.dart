import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../frecency/frecency.dart';
import '../search/normalise.dart';
import '../search/searchable.dart';
import '../trace.dart';
import 'team.dart';

/// A named team to load: one the user saved, or a boss's.
class TeamBuild implements Searchable {
  TeamBuild(this.id, this.name, this.slots)
    : assert(slots.length == Team.size, 'a build has ${Team.size} slots');

  @override
  final int id;
  @override
  final String name;
  final List<TeamSlot?> slots;

  @override
  List<int> get numbers => const [];
}

/// The boss teams of [dex] as builds, e.g. "6th Gym Leader Iono · Lv. 47 ·
/// Reverse".
List<TeamBuild> bossBuilds(Pokedex dex) => [
  for (final b in dex.bosses)
    TeamBuild(
      b.id,
      [b.name, 'Lv. ${b.level}', ?b.path].join(' · '),
      Team.parseSlots([
        for (final m in b.team) {'p': m.pokemon, 'a': ?m.ability, 'm': m.moves},
      ], dex),
    ),
];

/// The user's saved builds, persisted as JSON through [onChanged]. Names are
/// unique ignoring case and spacing: saving under an existing name overwrites
/// it.
class SavedBuilds extends ChangeNotifier {
  SavedBuilds({List<TeamBuild>? builds, this.onChanged})
    : _builds = builds ?? [];

  /// Corrupt JSON gives no builds; slots are cleaned as in [Team.parseSlots].
  factory SavedBuilds.fromJson(
    String? raw,
    Pokedex dex, {
    void Function(String json)? onChanged,
  }) {
    if (raw == null) {
      trace('builds.load.empty');
      return SavedBuilds(onChanged: onChanged);
    }
    try {
      final builds = [
        for (final b in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
          TeamBuild(
            b['i'] as int,
            b['n'] as String,
            Team.parseSlots(b['s'] as List, dex),
          ),
      ];
      trace('builds.load.ok', {'count': builds.length});
      return SavedBuilds(builds: builds, onChanged: onChanged);
    } catch (e) {
      trace('builds.load.corrupt', {'error': e.runtimeType.toString()});
      return SavedBuilds(onChanged: onChanged);
    }
  }

  static const prefsKey = 'team.builds.v1';

  final void Function(String json)? onChanged;
  final List<TeamBuild> _builds;

  /// In the order first saved.
  List<TeamBuild> get builds => List.unmodifiable(_builds);

  TeamBuild? named(String name) {
    final n = normalise(name);
    return _builds.where((b) => normalise(b.name) == n).firstOrNull;
  }

  /// Saves [slots] as [name], overwriting (and keeping the id of) a build of
  /// that name.
  TeamBuild save(String name, List<TeamSlot?> slots) {
    assert(name.trim().isNotEmpty, 'a build needs a name');
    final old = named(name);
    final build = TeamBuild(
      old?.id ?? _builds.fold(0, (m, b) => b.id > m ? b.id : m) + 1,
      name.trim(),
      List.of(slots),
    );
    if (old != null) {
      trace('builds.save.overwrite', {'id': old.id});
      _builds[_builds.indexOf(old)] = build;
    } else {
      trace('builds.save.new', {'id': build.id});
      _builds.add(build);
    }
    _changed();
    return build;
  }

  void delete(int id) {
    final before = _builds.length;
    _builds.removeWhere((b) => b.id == id);
    trace(before == _builds.length ? 'builds.delete.absent' : 'builds.delete', {
      'id': id,
    });
    _changed();
  }

  String toJson() => jsonEncode([
    for (final b in _builds)
      {
        'i': b.id,
        'n': b.name,
        's': [for (final s in b.slots) s?.toJson()],
      },
  ]);

  void _changed() {
    notifyListeners();
    onChanged?.call(toJson());
  }
}

/// Everything the Team Planner keeps for one game: your team and theirs, your
/// saved builds and the boss teams, each list with its own frecency.
class TeamPlanner {
  TeamPlanner({
    Team? mine,
    Team? theirs,
    SavedBuilds? builds,
    FrecencyStore? buildFrecency,
    this.bosses = const [],
    FrecencyStore? bossFrecency,
  }) : mine = mine ?? Team(),
       theirs = theirs ?? Team(),
       builds = builds ?? SavedBuilds(),
       buildFrecency = buildFrecency ?? FrecencyStore(),
       bossFrecency = bossFrecency ?? FrecencyStore();

  static const theirsPrefsKey = 'team.theirs.v1';
  static const buildFrecencyPrefsKey = 'frecency.builds.v1';
  static const bossFrecencyPrefsKey = 'frecency.bosses.v1';

  final Team mine;
  final Team theirs;
  final SavedBuilds builds;
  final FrecencyStore buildFrecency;
  final List<TeamBuild> bosses;
  final FrecencyStore bossFrecency;
}
