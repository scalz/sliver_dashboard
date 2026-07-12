import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';

void main() {
  group('Cross-grid controller protocol', () {
    late DashboardController controller;
    late int layoutChangedCalls;

    setUp(() {
      layoutChangedCalls = 0;
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1),
          const LayoutItem(id: 'b', x: 2, y: 0, w: 2, h: 1),
          const LayoutItem(id: 'c', x: 0, y: 1, w: 2, h: 1),
        ],
        onLayoutChanged: (_, __) => layoutChangedCalls++,
      );
    });

    tearDown(() => controller.dispose());

    test('beginCrossGridExit removes silently and returns pre-drag geometry', () {
      final removed = controller.internal.beginCrossGridExit({'a'});

      expect(removed, hasLength(1));
      expect(removed.first.id, 'a');
      expect(removed.first.w, 2);
      // Temporary removal: the item is gone from the live layout...
      expect(controller.layout.value.any((i) => i.id == 'a'), isFalse);
      // ...but the move is NOT committed yet: no layout-changed event.
      expect(layoutChangedCalls, 0);
      expect(controller.internal.hasPendingCrossGridExit, isTrue);
      // The internal drag state is fully reset.
      expect(controller.isDragging.value, isFalse);
    });

    test('beginCrossGridExit uses the drag-start snapshot when present', () {
      controller.internal.onDragStart('a');
      // Simulate mid-drag pushes by mutating the live layout.
      controller.layout.value = [
        for (final i in controller.layout.value)
          if (i.id == 'b') i.copyWith(y: 5) else i,
      ];

      final removed = controller.internal.beginCrossGridExit({'a'});
      expect(removed.single.x, 0);
      expect(removed.single.y, 0);

      // Cancel must restore the PRE-DRAG layout, not the pushed one.
      controller.internal.finishCrossGridExit(outcome: CrossGridExitOutcome.canceled);
      final b = controller.layout.value.firstWhere((i) => i.id == 'b');
      expect(b.y, 0);
      expect(controller.layout.value.any((i) => i.id == 'a'), isTrue);
      expect(layoutChangedCalls, 0);
    });

    test('finishCrossGridExit(movedAway) commits and fires exactly one event', () {
      controller.internal.beginCrossGridExit({'a'});
      controller.internal.finishCrossGridExit(outcome: CrossGridExitOutcome.movedAway);

      expect(controller.layout.value.any((i) => i.id == 'a'), isFalse);
      expect(layoutChangedCalls, 1);
      expect(controller.internal.hasPendingCrossGridExit, isFalse);

      // Resolving twice is a no-op.
      controller.internal.finishCrossGridExit(outcome: CrossGridExitOutcome.movedAway);
      expect(layoutChangedCalls, 1);
    });

    test('finishCrossGridExit(returned) discards the snapshot silently', () {
      controller.internal.beginCrossGridExit({'a'});
      controller.internal.finishCrossGridExit(outcome: CrossGridExitOutcome.returned);

      // The item stays removed (the external-drop path re-inserted it and
      // already emitted its own event in the real flow).
      expect(controller.layout.value.any((i) => i.id == 'a'), isFalse);
      expect(layoutChangedCalls, 0);
      expect(controller.internal.hasPendingCrossGridExit, isFalse);
    });

    test('onDropExternalItem preserves id, constraints and flags', () {
      const template = LayoutItem(
        id: 'foreign',
        x: 9,
        y: 9,
        w: 2,
        h: 2,
        minW: 2,
        minH: 2,
        maxW: 3,
        maxH: 3,
        isResizable: false,
      );

      controller.internal.showPlaceholder(x: 2, y: 1, w: 2, h: 2);
      final placed = controller.internal.onDropExternalItem(template: template);

      expect(placed, isNotNull);
      expect(placed!.id, 'foreign');
      final inLayout = controller.layout.value.firstWhere((i) => i.id == 'foreign');
      expect(inLayout.minW, 2);
      expect(inLayout.minH, 2);
      expect(inLayout.maxW, 3);
      expect(inLayout.maxH, 3);
      expect(inLayout.isResizable, isFalse);
      expect(inLayout.w, 2);
      expect(inLayout.h, 2);
      // Placeholder fully cleaned up.
      expect(controller.currentDragPlaceholder, isNull);
      expect(controller.layout.value.any((i) => i.id == '__placeholder__'), isFalse);
      expect(layoutChangedCalls, 1);
    });

    test('onDropExternalItem without an active placeholder is a no-op', () {
      final placed = controller.internal.onDropExternalItem(
        template: const LayoutItem(id: 'x', x: 0, y: 0, w: 1, h: 1),
      );
      expect(placed, isNull);
      expect(layoutChangedCalls, 0);
    });

    test('setItemSize resizes, clamps to constraints and fires one event', () {
      controller.internal.layout.value = [
        const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1, minH: 1, maxH: 3),
      ];
      layoutChangedCalls = 0;

      final resized = controller.internal.setItemSize('a', h: 2);
      expect(resized!.h, 2);
      expect(layoutChangedCalls, 1);

      // Clamped to maxH.
      final clamped = controller.internal.setItemSize('a', h: 10);
      expect(clamped!.h, 3);

      // Unchanged size: no event.
      layoutChangedCalls = 0;
      controller.internal.setItemSize('a', h: 3);
      expect(layoutChangedCalls, 0);

      // Unknown id: null, no event.
      expect(controller.internal.setItemSize('zzz', h: 1), isNull);
      expect(layoutChangedCalls, 0);
    });
  });
}
