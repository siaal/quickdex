import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/ui/type_grid.dart';

import 'type_focus_test.dart' show realChart;

void main() {
  final chart = realChart();

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TypeGrid(chart: chart)),
      ),
    );
  }

  testWidgets('headers stay put on the frozen axis while panning', (
    tester,
  ) async {
    await pump(tester);
    // At 1x the 18-row grid fits vertically on a phone; zoom so both axes can pan.
    tester
        .widget<InteractiveViewer>(find.byKey(const Key('grid-viewer')))
        .transformationController!
        .value = Matrix4.diagonal3Values(
      1.5,
      1.5,
      1,
    );
    await tester.pump();
    final colBefore = tester.getTopLeft(
      find.byKey(const Key('grid-col-normal')),
    );
    final rowBefore = tester.getTopLeft(
      find.byKey(const Key('grid-row-normal')),
    );
    await tester.drag(
      find.byKey(const Key('grid-viewer')),
      const Offset(-150, -150),
    );
    await tester.pumpAndSettle();
    final colAfter = tester.getTopLeft(
      find.byKey(const Key('grid-col-normal')),
    );
    final rowAfter = tester.getTopLeft(
      find.byKey(const Key('grid-row-normal')),
    );
    expect(colAfter.dy, colBefore.dy); // defender header row stays at the top
    expect(
      colAfter.dx,
      lessThan(colBefore.dx),
    ); // ...but follows the pan horizontally
    expect(rowAfter.dx, rowBefore.dx); // attacker column stays at the left
    expect(rowAfter.dy, lessThan(rowBefore.dy));
  });

  testWidgets('headers stay visible and scale when zoomed', (tester) async {
    await pump(tester);
    final before = tester.getSize(find.byKey(const Key('grid-col-normal')));
    final colTop = tester
        .getTopLeft(find.byKey(const Key('grid-col-normal')))
        .dy;
    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const Key('grid-viewer')),
    );
    viewer.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const Key('grid-col-normal'))).width,
      before.width * 2,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('grid-col-normal'))).dy,
      colTop,
    );
  });

  testWidgets('tapping a cell highlights its row and column', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('grid-cell-dark-dragon')));
    await tester.pump();
    BoxDecoration deco(String key) =>
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: find.byKey(Key(key)),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(
      deco('grid-cell-dark-bug').border,
      gridHighlightBorder,
    ); // same row
    expect(
      deco('grid-cell-bug-dragon').border,
      gridHighlightBorder,
    ); // same column
    expect(deco('grid-cell-bug-bug').border, isNot(gridHighlightBorder));
  });
}
