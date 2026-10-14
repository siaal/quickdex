import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/game.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/frecency/frecency.dart';
import 'package:quickdex/ui/learnset_table.dart';
import 'package:quickdex/ui/pokemon_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameInfo scrambled;
  late Pokedex dex;
  late MoveDex moves;
  setUpAll(() async {
    final games = await loadGames(rootBundle);
    scrambled = games.firstWhere((g) => g.key == 'scrambled');
    dex = await loadPokedex(rootBundle, scrambled);
    moves = await loadMoves(rootBundle, scrambled);
  });

  PokemonEntry named(String n) => dex.entries.firstWhere((e) => e.name == n);
  Move move(String name) => moves.moves.firstWhere((m) => m.name == name);
  String ability(int id) => dex.abilities[id]!.name;
  List<String> tms(PokemonEntry e) => [
    for (final t in moves.learnsets[e.id]!.tms) moves.byId[t.move]!.name,
  ];

  test('Scrambled Scarlet is the Doozdex Pokémon with their new data', () {
    expect((scrambled.name, scrambled.gen), ('Scrambled Scarlet', 9));
    expect(dex.game, scrambled);
    expect(dex.types.order, hasLength(18));
    expect(dex.entries.length, greaterThan(700));
    final meow = named('Meowscarada');
    expect(meow.abilities.map(ability), [
      'Dazzling',
      'Technician',
      'Versatility',
    ]);
    expect(meow.hidden, isNull, reason: 'three abilities, all swappable');
    expect(meow.notes, contains('Flower Trick'));
    expect(named('Slakoth (Doozian)').form, 'Doozian');
  });

  test('renamed abilities and moves keep the vanilla key they replace', () {
    final versatility = dex.abilities.values.firstWhere(
      (a) => a.name == 'Versatility',
    );
    expect(versatility.key, 'protean');
    expect(move('Poison Dart').key, 'poison-sting');
    expect(move('High Jump Kick').key, 'axe-kick');
    expect(move('Divebomb').key, 'high-jump-kick');
    expect(move('Poison Dart').flags, contains('Mega Launcher'));
  });

  test('Great Tusk evolves from Donphan', () {
    final tusk = named('Great Tusk');
    final chain = dex.chains[tusk.chain]!;
    final edge = chain.edges.firstWhere((e) => e.to == tusk.id);
    expect(dex[edge.from].name, 'Donphan');
    expect(edge.method, contains('Primal Energy'));
  });

  test('TMs by badge, with stage-only TMs', () {
    expect(tms(named('Sprigatito')), contains('Shock Wave'));
    expect(
      tms(named('Floragato')),
      isNot(contains('Shock Wave')),
      reason: '"*No Floragato"',
    );
    expect(tms(named('Sprigatito')), isNot(contains('Low Kick')));
    expect(tms(named('Meowscarada')), contains('Low Kick'));
  });

  testWidgets('a Pokémon page shows notes and TMs grouped by badge', (
    tester,
  ) async {
    // Scrambled starts on All, so the TMs show without touching the toggle.
    expect(LearnsetTable.defaultFilter(moves.game), LearnFilter.all);
    await tester.pumpWidget(
      MaterialApp(
        home: PokemonPage(
          dex: dex,
          frecency: FrecencyStore(),
          initialId: named('Sprigatito').id,
          moves: Future.value(moves),
          moveFrecency: FrecencyStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pokemon-notes')), findsOne);
    final page = find.byType(Scrollable).first;
    final heading = find.byKey(const Key('tm-badges-0'));
    await tester.scrollUntilVisible(heading, 300, scrollable: page);
    expect(find.byKey(const Key('tms')), findsOne);
    expect(
      find.descendant(of: heading, matching: find.text('0 badges')),
      findsOne,
    );
    final row = find.byKey(Key('tm-0-${move('Shock Wave').id}'));
    await tester.scrollUntilVisible(row, 300, scrollable: page);
    expect(
      find.descendant(of: row, matching: find.text('Shock Wave')),
      findsOne,
    );
  });
}
