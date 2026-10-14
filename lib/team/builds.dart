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
/// it. New ids are above [idBase], so they can't collide with presets below it.
class SavedBuilds extends ChangeNotifier {
  SavedBuilds({List<TeamBuild>? builds, this.onChanged, this.idBase = 0})
    : _builds = builds ?? [];

  /// Corrupt JSON gives no builds; slots are cleaned as in [Team.parseSlots].
  factory SavedBuilds.fromJson(
    String? raw,
    Pokedex dex, {
    void Function(String json)? onChanged,
    int idBase = 0,
  }) {
    if (raw == null) {
      trace('builds.load.empty');
      return SavedBuilds(onChanged: onChanged, idBase: idBase);
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
      return SavedBuilds(builds: builds, onChanged: onChanged, idBase: idBase);
    } catch (e) {
      trace('builds.load.corrupt', {'error': e.runtimeType.toString()});
      return SavedBuilds(onChanged: onChanged, idBase: idBase);
    }
  }

  static const prefsKey = 'team.builds.v1';
  static const theirsPrefsKey = 'team.theirs.builds.v1';

  /// Above every boss id (a crc mod 1e9), for the Theirs side's builds.
  static const theirsIdBase = 1000000000;

  final void Function(String json)? onChanged;
  final int idBase;
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
      old?.id ?? _builds.fold(idBase, (m, b) => b.id > m ? b.id : m) + 1,
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

/// One side of the Team Planner: its team, the builds saved from it, and
/// read-only [presets] (boss teams) also offered when loading. Saved builds
/// and presets share one frecency, so ids must not collide.
class TeamSide {
  TeamSide({
    Team? team,
    SavedBuilds? builds,
    FrecencyStore? frecency,
    this.presets = const [],
  }) : team = team ?? Team(),
       builds = builds ?? SavedBuilds(),
       frecency = frecency ?? FrecencyStore(),
       assert(
         presets.every((p) => p.id <= (builds?.idBase ?? 0)),
         'preset ids must sit below the saved builds\' idBase',
       );

  final Team team;
  final SavedBuilds builds;
  final FrecencyStore frecency;
  final List<TeamBuild> presets;

  /// Saved builds first, then presets.
  List<TeamBuild> get loadable => [...builds.builds, ...presets];
}

/// Everything the Team Planner keeps for one game: your side and theirs (whose
/// presets are the game's boss teams).
class TeamPlanner {
  TeamPlanner({TeamSide? mine, TeamSide? theirs})
    : mine = mine ?? TeamSide(),
      theirs = theirs ?? TeamSide();

  static const theirsPrefsKey = 'team.theirs.v1';
  static const buildFrecencyPrefsKey = 'frecency.builds.v1';
  static const theirsFrecencyPrefsKey = 'frecency.theirs.v1';

  final TeamSide mine;
  final TeamSide theirs;
}
