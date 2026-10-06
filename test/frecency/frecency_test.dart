import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/frecency/frecency.dart';

void main() {
  var now = DateTime.utc(2026, 10, 7);
  DateTime clock() => now;

  setUp(() => now = DateTime.utc(2026, 10, 7));

  test('visit adds 1', () {
    final f = FrecencyStore(clock: clock)..visit(25);
    expect(f.score(25), 1);
    expect(f.isFrecent(25), isTrue);
    expect(f.score(26), 0);
    expect(f.isFrecent(26), isFalse);
  });

  test('score halves every 3 days', () {
    final f = FrecencyStore(clock: clock)..visit(25);
    now = now.add(const Duration(days: 3));
    expect(f.score(25), closeTo(0.5, 1e-9));
  });

  test('visit decays then adds', () {
    final f = FrecencyStore(clock: clock)..visit(25);
    now = now.add(const Duration(days: 3));
    f.visit(25);
    expect(f.score(25), closeTo(1.5, 1e-9));
  });

  test('remove then restore round-trips the record', () {
    final f = FrecencyStore(clock: clock)
      ..visit(25)
      ..visit(25);
    final removed = f.remove(25)!;
    expect(f.isFrecent(25), isFalse);
    f.restore(25, removed);
    expect(f.score(25), 2);
  });

  test('persists through toJson/fromJson (survives restart)', () {
    String? saved;
    FrecencyStore(clock: clock, onChanged: (j) => saved = j).visit(10100);
    final reloaded = FrecencyStore.fromJson(saved, clock: clock);
    expect(reloaded.score(10100), 1);
  });

  test('corrupt or missing json yields an empty store', () {
    expect(
      FrecencyStore.fromJson('not json', clock: clock).isFrecent(1),
      isFalse,
    );
    expect(FrecencyStore.fromJson(null, clock: clock).isFrecent(1), isFalse);
  });

  test('every mutation notifies onChanged', () {
    var calls = 0;
    final f = FrecencyStore(clock: clock, onChanged: (_) => calls++);
    f.visit(1);
    final r = f.remove(1)!;
    f.restore(1, r);
    expect(calls, 3);
  });
}
