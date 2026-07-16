import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';

class MyTestPolicy extends DashboardPolicy {
  @override
  bool canDrag(LayoutItem item) => item.id != 'no-drag';

  @override
  bool canResize(LayoutItem item) => item.id != 'no-resize';

  @override
  bool canMoveTo(LayoutItem item, int targetX, int targetY, List<LayoutItem> currentLayout) {
    // Cannot move to row 0
    return targetY > 0;
  }

  @override
  bool canCollide(LayoutItem itemA, LayoutItem itemB) {
    // Block chart pushing kpi
    if (itemA.id == 'chart' && itemB.id == 'kpi') return false;
    return true;
  }
}

class DefaultTestPolicy extends DashboardPolicy {
  const DefaultTestPolicy();
}

class NoFolderCollisionPolicy extends DashboardPolicy {
  const NoFolderCollisionPolicy();

  @override
  bool canCollide(LayoutItem itemA, LayoutItem itemB) {
    // Prevent collisions with items that have hasNestedGrid enabled
    if (itemB.hasNestedGrid) return false;
    return true;
  }
}

void main() {
  group('DashboardPolicy Integration', () {
    late DashboardControllerImpl controller;
    late MyTestPolicy policy;

    setUp(() {
      policy = MyTestPolicy();
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          const LayoutItem(id: 'no-drag', x: 0, y: 1, w: 1, h: 1),
          const LayoutItem(id: 'no-resize', x: 1, y: 1, w: 1, h: 1),
          const LayoutItem(id: 'chart', x: 0, y: 2, w: 2, h: 1),
          const LayoutItem(id: 'kpi', x: 2, y: 2, w: 1, h: 1),
        ],
      ) as DashboardControllerImpl
        ..policy = policy;
    });

    tearDown(() => controller.dispose());

    test('canDrag policy blocks drag start', () {
      controller.onDragStart('no-drag');
      // Drag should have been blocked
      expect(controller.isDragging.value, isFalse);

      controller.onDragStart('chart');
      expect(controller.isDragging.value, isTrue);
    });

    test('canResize policy blocks resize start', () {
      controller.onResizeStart('no-resize');
      expect(controller.isResizing.value, isFalse);

      controller.onResizeStart('chart');
      expect(controller.isResizing.value, isTrue);
    });

    test('canMoveTo policy blocks visual movement to row 0', () {
      controller
        ..onDragStart('chart')
        ..onDragUpdate(
          'chart',
          const Offset(0, -110), // Try moving up to row 0 (assuming slotSize: 100)
          slotWidth: 100,
          slotHeight: 100,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
        );

      final item = controller.layout.value.firstWhere((i) => i.id == 'chart');
      // Movement to row 0 should be blocked, keeping y = 2
      expect(item.y, 2);
    });

    test('canCollide policy blocks item from pushing protected neighbor', () {
      controller
        ..onDragStart('chart') // occupies (0,2) to (1,2)
        ..onDragUpdate(
          'chart',
          const Offset(100, 200), // Drag right to collide with 'kpi' at (2,2)
          slotWidth: 100,
          slotHeight: 100,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
        );

      final kpi = controller.layout.value.firstWhere((i) => i.id == 'kpi');
      final chart = controller.layout.value.firstWhere((i) => i.id == 'chart');

      // KPI is protected from being pushed by chart.
      // Chart should slide/jump past it, but KPI stays at (2,2)
      expect(kpi.x, 2);
      expect(kpi.y, 2);
      expect(chart.y, greaterThanOrEqualTo(3)); // Chart pushed past
    });

    test('DashboardPolicy default implementations return true', () {
      const policy = DefaultTestPolicy();
      const item = LayoutItem(id: 'test', x: 0, y: 0, w: 1, h: 1);

      expect(policy.canDrag(item), isTrue);
      expect(policy.canResize(item), isTrue);
      expect(policy.canMoveTo(item, 0, 0, []), isTrue);
      expect(policy.canCollide(item, item), isTrue);
    });
  });

  group('DashboardController - showPlaceholder Policy', () {
    test('showPlaceholder must respect DashboardPolicy when resolving collisions', () {
      final controller = DashboardController(
        initialSlotCount: 8,
        initialLayout: const [
          LayoutItem(id: 'folder_item', x: 2, y: 0, w: 2, h: 2, hasNestedGrid: true),
        ],
      ) as DashboardControllerImpl;

      addTearDown(controller.dispose);

      controller
        ..policy = const NoFolderCollisionPolicy()

        // Show placeholder directly overlapping folder_item at x: 2, y: 0
        ..showPlaceholder(x: 2, y: 0, w: 2, h: 2);

      final result = controller.layout.value;

      // Verify the folder_item was NOT pushed (x and y remain unchanged)
      final folder = result.firstWhere((i) => i.id == 'folder_item');
      expect(folder.x, equals(2));
      expect(folder.y, equals(0));
    });
  });
}
