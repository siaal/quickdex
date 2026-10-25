import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/game.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/team/builds.dart';
import 'package:quickdex/team/team.dart';
import 'package:quickdex/team/team_analysis.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('scratch', () async {
    for (final g in await loadGames(rootBundle)) {
      if (g.gen != 9) continue;
      final dex = await loadPokedex(rootBundle, g);
      final moves = await loadMoves(rootBundle, g);
      final p = dex[1012];
      print(
        '${g.key} P ${p.types} def fire=${p.defense['fire']} normal=${p.defense['normal']}',
      );
      for (final b in bossBuilds(dex)) {
        for (final s in b.slots.nonNulls) {
          if (s.pokemon != 1012) continue;
          for (final tera in [false, if (s.tera != null) true]) {
            final pm = resolveMember(0, s, dex, moves, terastallized: tera);
            final l = resolveMember(0, TeamSlot(667), dex, moves);
            print(
              '${b.name} tera=${s.tera}/$tera P->L ${hit(pm, l)} L->P ${hit(l, pm)} ${pm.attacks}',
            );
          }
        }
      }
    }
  });
}
