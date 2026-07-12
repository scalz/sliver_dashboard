import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart'
    show CrossGridExitOutcome;
import 'package:sliver_dashboard/src/controller/utility.dart';

void main() {
  Future<void> runOnDesktop(Future<void> Function() body) async {
    final original = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = original;
    }
  }

  group('impl primitives: dragOriginSnapshot & freezeDragPushes', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
        ],
      )..setEditMode(true);
    });

    tearDown(() => controller.dispose());

    test('dragOriginSnapshot is null outside a drag and pre-drag during one', () {
      final impl = controller.internal;
      expect(impl.dragOriginSnapshot, isNull);

      impl.onDragStart('a');
      final snapshot = impl.dragOriginSnapshot;
      expect(snapshot, isNotNull);
      expect(snapshot!.firstWhere((i) => i.id == 'b').y, 0);

      impl.onDragEnd('a');
      expect(impl.dragOriginSnapshot, isNull);
    });

    test(
        'freezeDragPushes reverts pushes, keeps the drag alive, and resets '
        'the bbox bypass so the next update re-applies the pushes', () {
      final impl = controller.internal
        ..onDragStart('a')

        // Drag a onto b's cell: b gets pushed down.
        ..onDragUpdate(
          'a',
          const Offset(100, 0),
          slotWidth: 100,
          slotHeight: 100,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
        );
      LayoutItem b() => controller.layout.value.firstWhere((i) => i.id == 'b');
      expect(b().y, 1, reason: 'b must be pushed by the drag');

      // Freeze: snapshot restored, drag still alive.
      impl.freezeDragPushes();
      expect(b().y, 0, reason: 'freeze must revert the push');
      expect(controller.isDragging.value, isTrue);

      // Same target cell again: WITHOUT the bbox-cache reset this would hit
      // the "bbox unchanged" fast path and never re-apply the push.
      impl.onDragUpdate(
        'a',
        const Offset(100, 0),
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
      );
      expect(b().y, 1, reason: 'resume must re-apply the push');

      impl.onDragEnd('a');
    });

    test(
        'mid-drag updateItem survives snapshot-based recomputes '
        '(onDragUpdate rebuilds from originalLayoutOnStart)', () {
      final impl = controller.internal..onDragStart('a');

      // Mid-drag conversion, exactly what the same-grid arming does.
      controller.updateItem(
        'b',
        (i) => i.copyWith(hasNestedGrid: true),
        recompact: false,
      );
      LayoutItem b() => controller.layout.value.firstWhere((i) => i.id == 'b');
      expect(b().hasNestedGrid, isTrue);
      expect(
        impl.originalLayoutOnStart.peek().firstWhere((i) => i.id == 'b').hasNestedGrid,
        isTrue,
        reason: 'the write-through must patch the pre-drag snapshot',
      );

      // A drag update rebuilds the layout from the snapshot: the flag must
      // survive (this is the move-after-conversion path).
      impl.onDragUpdate(
        'a',
        const Offset(100, 0),
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
      );
      expect(
        b().hasNestedGrid,
        isTrue,
        reason: 'snapshot-derived recompute must not erase the flag',
      );

      impl.onDragEnd('a');
    });

    test(
        'mid-drag updateItem survives the cross-grid exit '
        '(movedAway keeps the flag, canceled restores it too)', () {
      final impl = controller.internal

        // movedAway: the release-into-child path from the same-grid handoff.
        ..onDragStart('a');
      controller.updateItem(
        'b',
        (i) => i.copyWith(hasNestedGrid: true),
        recompact: false,
      );
      final removed = impl.beginCrossGridExit({'a'});
      expect(removed.map((i) => i.id), ['a']);
      LayoutItem b() => controller.layout.value.firstWhere((i) => i.id == 'b');
      expect(
        b().hasNestedGrid,
        isTrue,
        reason: 'the exit rebuild from the snapshot must keep the flag',
      );
      impl.finishCrossGridExit(outcome: CrossGridExitOutcome.movedAway);
      expect(b().hasNestedGrid, isTrue);
      expect(controller.layout.value.map((i) => i.id), isNot(contains('a')));

      // canceled: flag also patched into the exit snapshot used for restore.
      final c2 = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
        ],
      )..setEditMode(true);
      addTearDown(c2.dispose);
      final impl2 = c2.internal
        ..onDragStart('a')
        ..beginCrossGridExit({'a'});
      c2.updateItem(
        'b',
        (i) => i.copyWith(hasNestedGrid: true),
        recompact: false,
      );
      impl2.finishCrossGridExit(outcome: CrossGridExitOutcome.canceled);
      expect(
        c2.layout.value.firstWhere((i) => i.id == 'b').hasNestedGrid,
        isTrue,
        reason: 'the canceled restore must not erase a post-exit mutation',
      );
      expect(c2.layout.value.map((i) => i.id), contains('a'));
    });

    test('freezeDragPushes is a no-op outside a drag', () {
      final before = controller.layout.value;
      controller.internal.freezeDragPushes();
      expect(controller.layout.value, same(before));
    });
  });

  group('subGridDynamicSameGrid (widget flow)', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
        ],
      )..setEditMode(true);
    });

    tearDown(() => controller.dispose());

    Widget build({
      required DashboardNestedCoordinator coordinator,
      required bool sameGrid,
      bool subGridDynamic = true,
      DashboardNestedGridRequestCallback? onRequested,
      DashboardNestedGridAbandonedCallback? onAbandoned,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: DashboardNestedScope(
            coordinator: coordinator,
            subGridDynamic: subGridDynamic,
            subGridDynamicSameGrid: sameGrid,
            nestHoverDelay: const Duration(milliseconds: 200),
            onNestedGridRequested: onRequested ?? (h, d, c) {},
            onNestedGridRequestAbandoned: onAbandoned,
            child: SizedBox(
              width: 400,
              height: 400,
              child: Dashboard<String>(
                controller: controller,
                itemBuilder: (context, item) =>
                    ColoredBox(color: Colors.blue, child: Text('T-${item.id}')),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
        'pause freezes + highlights, delay fires the request, and a '
        'real move disarms and resumes the pushes', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);

        LayoutItem? requestedHost;
        LayoutItem? requestedDragged;
        DashboardController? requestedGrid;

        await tester.pumpWidget(
          build(
            coordinator: coordinator,
            sameGrid: true,
            onRequested: (host, dragged, grid) {
              requestedHost = host;
              requestedDragged = dragged;
              requestedGrid = grid;
            },
          ),
        );
        await tester.pumpAndSettle();

        LayoutItem b() => controller.layout.value.firstWhere((i) => i.id == 'b');
        final aCenter = tester.getCenter(find.text('T-a'));
        final bCenter = tester.getCenter(find.text('T-b'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();
        await gesture.moveTo(bCenter);
        await tester.pump();
        expect(b().y, 1, reason: 'in-grid drag must push b');

        // Stationary for the pause delay (350ms): freeze + highlight.
        await tester.pump(const Duration(milliseconds: 400));
        expect(controller.internal.hoveredNestTargetId.value, 'b');
        expect(b().y, 0, reason: 'freeze must revert the push');
        expect(requestedHost, isNull, reason: 'not fired yet');

        // Then the arming delay (200ms): the request fires.
        await tester.pump(const Duration(milliseconds: 250));
        expect(requestedHost?.id, 'b');
        expect(requestedDragged?.id, 'a');
        expect(identical(requestedGrid, controller), isTrue);

        // A real move disarms, clears the highlight and re-applies the push.
        await gesture.moveTo(bCenter + const Offset(40, 0));
        await tester.pump();
        expect(controller.internal.hoveredNestTargetId.value, isNull);

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('moving before the arming delay cancels: no request fires', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);

        var fired = 0;
        await tester.pumpWidget(
          build(
            coordinator: coordinator,
            sameGrid: true,
            onRequested: (h, d, c) => fired++,
          ),
        );
        await tester.pumpAndSettle();

        final aCenter = tester.getCenter(find.text('T-a'));
        final bCenter = tester.getCenter(find.text('T-b'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();
        await gesture.moveTo(bCenter);
        await tester.pump();

        // Pause long enough to arm (350ms) but move before the 200ms fires.
        await tester.pump(const Duration(milliseconds: 400));
        expect(controller.internal.hoveredNestTargetId.value, 'b');
        await gesture.moveTo(bCenter + const Offset(40, 0));
        await tester.pump();
        expect(controller.internal.hoveredNestTargetId.value, isNull);

        await tester.pump(const Duration(milliseconds: 400));
        expect(fired, 0, reason: 'disarmed before nestHoverDelay elapsed');

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('flag off: pausing mid-drag never freezes nor fires', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);

        var fired = 0;
        await tester.pumpWidget(
          build(
            coordinator: coordinator,
            sameGrid: false, // subGridDynamic on, same-grid variant OFF
            onRequested: (h, d, c) => fired++,
          ),
        );
        await tester.pumpAndSettle();

        LayoutItem b() => controller.layout.value.firstWhere((i) => i.id == 'b');
        final aCenter = tester.getCenter(find.text('T-a'));
        final bCenter = tester.getCenter(find.text('T-b'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();
        await gesture.moveTo(bCenter);
        await tester.pump();

        await tester.pump(const Duration(seconds: 2));
        expect(controller.internal.hoveredNestTargetId.value, isNull);
        expect(b().y, 1, reason: 'pushes must stay applied: no freeze');
        expect(fired, 0);

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('same-grid arming is independent of subGridDynamic', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);

        LayoutItem? requestedHost;
        await tester.pumpWidget(
          build(
            coordinator: coordinator,
            sameGrid: true,
            subGridDynamic: false, // cross-grid hover OFF, same-grid pause ON
            onRequested: (h, d, c) => requestedHost = h,
          ),
        );
        await tester.pumpAndSettle();

        final aCenter = tester.getCenter(find.text('T-a'));
        final bCenter = tester.getCenter(find.text('T-b'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();
        await gesture.moveTo(bCenter);
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 400));
        expect(
          controller.internal.hoveredNestTargetId.value,
          'b',
          reason: 'the flags are orthogonal: sameGrid alone must arm',
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(requestedHost?.id, 'b');

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets(
        'releasing after the request without dropping into the child '
        'fires onNestedGridRequestAbandoned', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);

        final abandoned = <(String, DashboardController)>[];
        await tester.pumpWidget(
          build(
            coordinator: coordinator,
            sameGrid: true,
            onRequested: (h, d, c) {}, // app does nothing: host never converts
            onAbandoned: (host, grid) => abandoned.add((host.id, grid)),
          ),
        );
        await tester.pumpAndSettle();

        final aCenter = tester.getCenter(find.text('T-a'));
        final bCenter = tester.getCenter(find.text('T-b'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();
        await gesture.moveTo(bCenter);
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 400)); // freeze
        await tester.pump(const Duration(milliseconds: 250)); // fire
        expect(abandoned, isEmpty, reason: 'not resolved while dragging');

        await gesture.up(); // plain release in the same grid
        await tester.pumpAndSettle();

        expect(abandoned.length, 1);
        expect(abandoned.single.$1, 'b');
        expect(identical(abandoned.single.$2, controller), isTrue);
      });
    });

    testWidgets(
        'END-TO-END: releasing over a freshly converted host drops '
        'the item INTO the child grid and never fires abandoned', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);

        // Root uses a bigger host tile so the mounted child grid comfortably
        // contains the (stationary) release point.
        final rootCtrl = DashboardController(
          initialSlotCount: 4,
          initialLayout: const [
            LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
            LayoutItem(id: 'b', x: 1, y: 0, w: 2, h: 2),
          ],
        )..setEditMode(true);
        addTearDown(rootCtrl.dispose);

        // Example-like app state: dynamic conversions + abandon bookkeeping.
        final dynamicChildren = <String, DashboardController>{};
        final abandoned = <String>[];
        addTearDown(() {
          for (final c in dynamicChildren.values) {
            c.dispose();
          }
        });

        late StateSetter rebuild;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return DashboardNestedScope(
                    coordinator: coordinator,
                    subGridDynamicSameGrid: true,
                    nestHoverDelay: const Duration(milliseconds: 200),
                    // Mimics the example: convert the host, mount the grid.
                    onNestedGridRequested: (host, dragged, hostGrid) {
                      if (dynamicChildren.containsKey(host.id)) return;
                      final child = DashboardController(initialSlotCount: 2)..setEditMode(true);
                      dynamicChildren[host.id] = child;
                      hostGrid.updateItem(
                        host.id,
                        (i) => i.copyWith(hasNestedGrid: true),
                        recompact: false,
                      );
                      rebuild(() {});
                    },
                    onNestedGridRequestAbandoned: (host, grid) => abandoned.add(host.id),
                    child: SizedBox(
                      width: 400,
                      height: 400,
                      child: Dashboard<String>(
                        controller: rootCtrl,
                        itemBuilder: (context, item) {
                          final child = dynamicChildren[item.id];
                          if (item.hasNestedGrid && child != null) {
                            return NestedDashboard(
                              controller: child,
                              parentItemId: item.id,
                              autoSlotCount: false,
                              itemBuilder: (context, nested) => Text('N-${nested.id}'),
                            );
                          }
                          return ColoredBox(
                            color: Colors.blue,
                            child: Text('T-${item.id}'),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final aCenter = tester.getCenter(find.text('T-a'));
        final bCenter = tester.getCenter(find.text('T-b'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();
        await gesture.moveTo(bCenter);
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 400)); // freeze
        await tester.pump(const Duration(milliseconds: 250)); // fire+convert
        await tester.pump(); // let the NestedDashboard mount and register

        expect(
          dynamicChildren.containsKey('b'),
          isTrue,
          reason: 'the request must have converted the host',
        );
        final child = dynamicChildren['b']!;
        expect(
          coordinator.childGridsOf(rootCtrl)['b'],
          same(child),
          reason: 'the mounted NestedDashboard must have linked itself',
        );

        // The user gesture under test: plain release while still frozen over
        // the freshly converted host.
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          child.layout.value.map((i) => i.id),
          contains('a'),
          reason: 'the release must drop the item INTO the child grid',
        );
        expect(
          rootCtrl.layout.value.map((i) => i.id),
          isNot(contains('a')),
          reason: 'the item must have left the root grid',
        );
        expect(
          rootCtrl.layout.value.firstWhere((i) => i.id == 'b').hasNestedGrid,
          isTrue,
          reason: 'the host must stay converted',
        );
        expect(
          abandoned,
          isEmpty,
          reason: 'a drop into the requested child confirms the request — '
              'abandoned firing here is the bug that destroys the child',
        );
      });
    });

    testWidgets('scope syncs subGridDynamicSameGrid onto the coordinator', (tester) async {
      final coordinator = DashboardNestedCoordinator();
      addTearDown(coordinator.dispose);
      expect(coordinator.subGridDynamicSameGrid, isFalse);

      await tester.pumpWidget(build(coordinator: coordinator, sameGrid: true));
      expect(coordinator.subGridDynamicSameGrid, isTrue);

      await tester.pumpWidget(build(coordinator: coordinator, sameGrid: false));
      expect(coordinator.subGridDynamicSameGrid, isFalse);
    });

    testWidgets('an already-hosting sibling is not armed', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);
        final childOfB = DashboardController(initialSlotCount: 2);
        addTearDown(childOfB.dispose);

        var fired = 0;
        await tester.pumpWidget(
          build(
            coordinator: coordinator,
            sameGrid: true,
            onRequested: (h, d, c) => fired++,
          ),
        );
        await tester.pumpAndSettle();

        // 'b' already hosts a grid (link map is the runtime truth).
        coordinator.linkChildGrid(
          parent: controller,
          parentItemId: 'b',
          child: childOfB,
        );

        final aCenter = tester.getCenter(find.text('T-a'));
        final bCenter = tester.getCenter(find.text('T-b'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();
        await gesture.moveTo(bCenter);
        await tester.pump();

        await tester.pump(const Duration(seconds: 2));
        expect(controller.internal.hoveredNestTargetId.value, isNull);
        expect(fired, 0);

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });
  });
}
