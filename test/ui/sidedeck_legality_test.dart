import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/data/loader.dart';
import 'package:quickdex/data/models.dart';
import 'package:quickdex/data/moves.dart';
import 'package:quickdex/team/team.dart';
import 'package:quickdex/ui/sidedeck_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Pokedex dex;
  late MoveDex moves;
  setUpAll(() async {
    dex = await loadPokedex(PlatformAssetBundle());
    moves = await loadMoves(PlatformAssetBundle());
  });

  Future<NavigatorState> open(WidgetTester tester, Team team) async {
    tester.view.physicalSize = const Size(480, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        home: const Scaffold(body: Text('Planner')),
      ),
    );
    key.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => SidedeckPage(
          team: team,
          dex: dex,
          moves: Future.value(moves),
          onEdit: (context, _) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  Scaffold(appBar: AppBar(title: const Text('Member editor'))),
            ),
          ),
          onAdd: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  Team full() {
    final t = Team();
    for (var i = 0; i < 8; i++) {
      t.add(TeamSlot(dex.entries.first.id));
    }
    return t;
  }

  testWidgets('add two, block all back paths, remove two, then leave', (
    tester,
  ) async {
    final team = full();
    final nav = await open(tester, team);
    for (final d in [6, 7]) {
      await tester.tap(find.byKey(Key('deck-row-$d')));
      await tester.pumpAndSettle();
    }
    expect(team.squadCount, 8);
    expect(find.text('8/6'), findsOneWidget);
    expect(find.byKey(const Key('deck-legality')), findsOneWidget);
    expect(
      tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
      isFalse,
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Sidedeck'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Sidedeck'), findsOneWidget);
    expect(await nav.maybePop(), isTrue, reason: 'blocked pop was handled');
    await tester.pumpAndSettle();
    expect(find.text('Sidedeck'), findsOneWidget);
    expect(team.squadCount, 8, reason: 'back never truncates selection');

    await tester.tap(find.byKey(const Key('deck-row-0')));
    await tester.pumpAndSettle();
    expect(team.squadCount, 7);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Sidedeck'), findsOneWidget);
    await tester.tap(find.byKey(const Key('deck-row-1')));
    await tester.pumpAndSettle();
    expect(team.squadCount, 6);
    expect(find.byKey(const Key('deck-legality')), findsNothing);
    expect(team.slotOf(6), isNotNull);
    expect(team.slotOf(7), isNotNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Planner'), findsOneWidget);
    expect(find.text('Sidedeck'), findsNothing);
  });

  testWidgets('restored overflow is guarded; nested editor can still close', (
    tester,
  ) async {
    final saved = full()..toggle(6, allowOverflow: true);
    final team = Team.fromJson(saved.toJson(), dex);
    await open(tester, team);
    await tester.longPress(find.byKey(const Key('deck-row-0')));
    await tester.pumpAndSettle();
    expect(find.text('Member editor'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Sidedeck'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Sidedeck'), findsOneWidget);
    expect(team.squadCount, 7);
    await tester.tap(find.byKey(const Key('deck-row-6')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Planner'), findsOneWidget);
  });

  testWidgets('empty squad is legal and can leave with Android back', (
    tester,
  ) async {
    await open(tester, Team());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Planner'), findsOneWidget);
    expect(find.text('Sidedeck'), findsNothing);
  });
}
