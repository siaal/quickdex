import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/search/search_index.dart';
import 'package:quickdex/search/searchable.dart';
import 'package:quickdex/team/builds.dart';
import 'package:quickdex/team/team.dart';
import 'package:quickdex/ui/team_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  late MoveDex moves;
  setUpAll(() async {
    dex = await loadPokedex(PlatformAssetBundle());
    moves = await loadMoves(PlatformAssetBundle());
  });
  setUp(MovePicker.resetFilters);
  tearDown(MovePicker.resetFilters);

  for (final kind in ['Pokémon', 'moves', 'builds']) {
    for (final filter
        in kind == 'moves' ? LearnFilter.values : [LearnFilter.all]) {
      for (final query in [
        '',
        kind == 'Pokémon' ? 'pika' : 'thunder',
        'no-such-result-xyz',
      ]) {
        testWidgets(
          '$kind ${filter.name}: Enter selects the first displayed result for "$query"',
          (tester) async {
            final frecency = FrecencyStore();
            final builds = SavedBuilds();
            builds.save(
              'Thunder team',
              Lineup.ofSlots([TeamSlot(25), null, null, null, null, null]),
            );
            builds.save(
              'Thunder squad',
              Lineup.ofSlots([TeamSlot(74), null, null, null, null, null]),
            );
            final recent = builds.builds.last;
            frecency.visit(recent.id);
            final picker = switch (kind) {
              'Pokémon' => PokemonPicker(
                index: SearchIndex(dex.entries),
                frecency: frecency,
              ),
              'moves' => MovePicker(
                moves: moves,
                frecency: frecency,
                pokemon: 25,
              ),
              _ => BuildPicker(
                builds: () => builds.builds,
                frecency: frecency,
                dex: dex,
              ),
            };
            Object? selected;
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () async {
                        selected = await Navigator.of(context).push<Object>(
                          MaterialPageRoute(builder: (_) => picker),
                        );
                      },
                      child: const Text('Open picker'),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Open picker'));
            await tester.pumpAndSettle();
            if (kind == 'moves') {
              await tester.tap(find.byKey(Key('learn-filter-${filter.name}')));
              await tester.pumpAndSettle();
            }
            await tester.enterText(
              find.byKey(const Key('team-pick-search')),
              query,
            );
            await tester.pump();
            final rows = find.byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith(
                    'team-pick-row-',
                  ),
            );
            final int? first = rows.evaluate().isEmpty
                ? null
                : int.parse(
                    (tester.firstWidget(rows).key! as ValueKey<String>).value
                        .substring('team-pick-row-'.length),
                  );
            expect(first, query == 'no-such-result-xyz' ? isNull : isNotNull);
            await tester.testTextInput.receiveAction(TextInputAction.done);
            await tester.pumpAndSettle();
            if (first == null) {
              expect(selected, isNull);
              expect(find.byKey(const Key('team-pick-search')), findsOneWidget);
            } else {
              expect(selected, isA<Searchable>());
              expect((selected as Searchable).id, first);
              expect(find.byKey(const Key('team-pick-search')), findsNothing);
              if (kind == 'builds' && query.isEmpty) expect(first, recent.id);
            }
          },
        );
      }
    }
  }
}
