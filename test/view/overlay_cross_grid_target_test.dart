import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';

/// Exercises the [CrossGridDragTarget] surface of a real mounted overlay —
/// the paths the coordinator drives during cross-grid drags — without
/// synthesizing full gestures.
void main() {
  late DashboardController controller;

  setUp(() {
    controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a1', x: 0, y: 0, w: 2, h: 1),
        LayoutItem(id: 'a2', x: 2, y: 0, w: 2, h: 1),
      ],
    )..setEditMode(true);
  });

  tearDown(() => controller.dispose());

  Widget build({bool crossGridDragOut = true}) => MaterialApp(
        home: Scaffold(
          body: DashboardNestedScope(
            child: SizedBox(
              width: 400,
              height: 400,
              child: Dashboard<String>(
                controller: controller,
                crossGridDragOut: crossGridDragOut,
                itemBuilder: (context, item) =>
                    ColoredBox(color: Colors.blue, child: Text('T-${item.id}')),
              ),
            ),
          ),
        ),
      );

  CrossGridDragTarget targetOf(WidgetTester tester) =>
      tester.state(find.byWidgetPredicate((w) => w is DashboardOverlay)) as CrossGridDragTarget;

  testWidgets('canDragItemsOut reflects the crossGridDragOut flag', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(targetOf(tester).canDragItemsOut, isTrue);

    await tester.pumpWidget(build(crossGridDragOut: false));
    await tester.pumpAndSettle();
    expect(targetOf(tester).canDragItemsOut, isFalse);
  });

  testWidgets(
      'itemAtGlobal resolves the item under a global position, honors '
      'excludeId, and returns null off-grid', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    final target = targetOf(tester);

    final centerA1 = tester.getCenter(find.text('T-a1'));
    expect(target.itemAtGlobal(centerA1)?.id, 'a1');
    expect(target.itemAtGlobal(centerA1, excludeId: 'a1'), isNull);

    final centerA2 = tester.getCenter(find.text('T-a2'));
    expect(target.itemAtGlobal(centerA2)?.id, 'a2');

    // Far below any item: empty cell.
    expect(target.itemAtGlobal(centerA1 + const Offset(0, 300)), isNull);
  });

  testWidgets('setNestHoverHighlight drives the controller hover beacon', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    final target = targetOf(tester)..setNestHoverHighlight('a1');
    expect(controller.internal.hoveredNestTargetId.value, 'a1');
    target.setNestHoverHighlight(null);
    expect(controller.internal.hoveredNestTargetId.value, isNull);
  });

  testWidgets('currentSlotMetrics exposes the live sliver metrics', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    final metrics = targetOf(tester).currentSlotMetrics();
    expect(metrics, isNotNull);
    expect(metrics!.slotCount, 4);
  });
}
