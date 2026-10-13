import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/game.dart';
import 'package:quickdex/team/team.dart';
import 'package:quickdex/ui/game_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<GameInfo> games;
  setUpAll(() async => games = await loadGames(rootBundle));

  GameInfo game(String key) => games.firstWhere((g) => g.key == key);

  /// Asset loads are real I/O: let them run, then settle the frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<SharedPreferences> pumpHost(
    WidgetTester tester, [
    Map<String, Object> saved = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(saved);
    final prefs = await SharedPreferences.getInstance();
    // A fresh bundle per test: rootBundle caches load futures, and one created
    // in an earlier test's fake-async zone never completes in the next.
    final bundle = PlatformAssetBundle();
    final session = (await tester.runAsync(
      () => GameSession.load(bundle, prefs, savedGame(prefs, games)),
    ))!;
    await tester.pumpWidget(
      GameHost(prefs: prefs, games: games, initial: session, bundle: bundle),
    );
    await settle(tester);
    return prefs;
  }

  Future<void> search(WidgetTester tester, String q) async {
    await tester.enterText(find.byKey(const Key('search-field')), q);
    await tester.pump();
  }

  testWidgets('the cog opens settings; picking Emerald reloads with its data', (
    tester,
  ) async {
    final prefs = await pumpHost(tester);
    await search(tester, 'sylveon');
    expect(find.byKey(const Key('row-700')), findsOne);

    await tester.tap(find.byKey(const Key('search-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOne);
    final scarlet = tester.widget<RadioListTile<GameInfo>>(
      find.byKey(const Key('game-scarlet')),
    );
    expect(scarlet.value, GameInfo.scarlet);

    await tester.tap(find.byKey(const Key('game-emerald')));
    await settle(tester);
    expect(prefs.getString(gamePrefsKey), 'emerald');
    expect(find.text('Settings'), findsNothing, reason: 'back on Search');
    await search(tester, 'sylveon');
    expect(find.byKey(const Key('row-700')), findsNothing, reason: 'Gen 6');
    await search(tester, 'treecko');
    expect(find.text('Hoenn #001 · #252'), findsOne);
    await search(tester, 'nightmare');
    expect(find.text('Not in Emerald'), findsOne);
  });

  testWidgets('starts in the saved game; team and recents are per game', (
    tester,
  ) async {
    final pikachu = Team(slots: [TeamSlot(25), null, null, null, null, null]);
    final prefs = await pumpHost(tester, {
      gamePrefsKey: 'emerald',
      Team.prefsKey: pikachu.toJson(),
    });
    expect(savedGame(prefs, games), game('emerald'));
    await search(tester, 'treecko');
    expect(find.text('Hoenn #001 · #252'), findsOne);
    final emeraldKey = game('emerald').prefsKey(Team.prefsKey);
    expect(emeraldKey, 'team.v1.emerald');
    expect(
      prefs.getString(emeraldKey),
      isNull,
      reason: 'Scarlet team not shared',
    );
    expect(GameInfo.scarlet.prefsKey(Team.prefsKey), Team.prefsKey);
  });

  testWidgets(
    'Emerald screens render: Pokémon page, ??? Curse, 17-type chart',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await pumpHost(tester, {gamePrefsKey: 'emerald'});
      await search(tester, 'clefairy');
      await tester.tap(find.byKey(const Key('row-35')));
      await settle(tester);
      expect(find.text('Normal'), findsWidgets, reason: 'Gen 3 typing');
      expect(find.text('Fairy'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Search'));
      await settle(tester);
      await search(tester, 'curse');
      await tester.tap(find.byKey(const Key('move-row-174')));
      await settle(tester);
      expect(find.text('???'), findsOne);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Type Chart'));
      await settle(tester);
      expect(find.byKey(const Key('focus-type-fairy')), findsNothing);
      expect(find.byKey(const Key('focus-type-steel')), findsOne);
      await tester.tap(find.text('Team Planner'));
      await settle(tester);
      expect(tester.takeException(), isNull);
    },
  );

  test('an unknown saved game falls back to Scarlet', () async {
    SharedPreferences.setMockInitialValues({gamePrefsKey: 'gold'});
    final prefs = await SharedPreferences.getInstance();
    expect(savedGame(prefs, games), GameInfo.scarlet);
  });
}
