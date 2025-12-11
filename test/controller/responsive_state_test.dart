import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';

void main() {
  group('Responsive State Preservation', () {
    late DashboardControllerImpl controller;

    setUp(() {
      controller = DashboardControllerImpl(
        initialSlotCount: 8, // Desktop
        initialLayout: [
          const LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2),
          const LayoutItem(id: 'B', x: 6, y: 0, w: 2, h: 2), // Far right
        ],
      );
    });

    test('Should remember layout when switching back to previous breakpoint', () {
      // 1. Initial State (Desktop 8 cols)
      // A is at 0,0. B is at 6,0.

      // 2. Switch to Mobile (4 cols)
      controller.setSlotCount(4);

      // B should have moved because x=6 is out of bounds for 4 cols.
      final bMobile = controller.layout.value.firstWhere((i) => i.id == 'B');
      expect(bMobile.x, lessThan(4));

      // 3. Move A in Mobile view (Change state)
      // We move A to 0, 5 (far down)
      final itemA = controller.layout.value.firstWhere((i) => i.id == 'A');
      controller.onDragStart('A');
      controller.layout.value = [itemA.copyWith(y: 5), bMobile]; // Force move
      controller
        ..onDragEnd('A')

        // 4. Switch back to Desktop (8 cols)
        ..setSlotCount(8);

      // EXPECTATION:
      // - B should return to 6,0 (Restored from cache)
      // - A should return to 0,0 (Restored from cache, ignoring the mobile move)
      // Note: In "Passive" mode, moves in one breakpoint do NOT affect the other.

      final aDesktop = controller.layout.value.firstWhere((i) => i.id == 'A');
      final bDesktop = controller.layout.value.firstWhere((i) => i.id == 'B');

      expect(bDesktop.x, 6, reason: 'B should return to its original desktop position');
      expect(aDesktop.y, 0, reason: 'A should return to its original desktop position');
    });

    test('Should sync DELETED items across breakpoints', () {
      // 1. Start Desktop
      // 2. Switch Mobile
      controller
        ..setSlotCount(4)

        // 3. Delete A in Mobile
        ..removeItem('A');
      expect(controller.layout.value.any((i) => i.id == 'A'), isFalse);

      // 4. Switch back to Desktop
      controller.setSlotCount(8);

      // EXPECTATION: A should be gone in Desktop too
      expect(
        controller.layout.value.any((i) => i.id == 'A'),
        isFalse,
        reason: 'Deleted item should not reappear when switching layouts',
      );
    });

    test('Should sync ADDED items across breakpoints', () {
      // 1. Start Desktop
      // 2. Switch Mobile
      controller
        ..setSlotCount(4)

        // 3. Add C in Mobile
        ..addItem(const LayoutItem(id: 'C', x: 0, y: 0, w: 1, h: 1));
      expect(controller.layout.value.any((i) => i.id == 'C'), isTrue);

      // 4. Switch back to Desktop
      controller.setSlotCount(8);

      // EXPECTATION: C should appear in Desktop
      final cDesktop = controller.layout.value.firstWhere((i) => i.id == 'C');
      expect(cDesktop, isNotNull, reason: 'New item C should be present in Desktop');

      // It should be placed at the bottom or valid spot
      expect(cDesktop.x, greaterThanOrEqualTo(0));
    });
  });
}
