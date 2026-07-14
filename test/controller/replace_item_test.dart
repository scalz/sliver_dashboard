import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';

void main() {
  group('DashboardController - replaceItem Invariants', () {
    test('replaceItem should replace an item in-place and maintain ascending ID order', () {
      final controller = DashboardController(
        initialSlotCount: 8,
        initialLayout: const [
          LayoutItem(id: 'item_1', x: 0, y: 0, w: 2, h: 2),
          LayoutItem(id: 'item_2', x: 2, y: 0, w: 2, h: 2),
          LayoutItem(id: 'item_3', x: 4, y: 0, w: 2, h: 2),
        ],
      );

      const replacement = LayoutItem(
        id: 'item_replacement', // New ID
        x: 2,
        y: 0,
        w: 2,
        h: 2,
        hasNestedGrid: true,
      );

      // Replace 'item_2' with 'item_replacement'
      controller.replaceItem('item_2', replacement);

      final result = controller.layout.value;

      // 1. Verify 'item_2' is gone, and 'item_replacement' is present
      expect(result.any((i) => i.id == 'item_2'), isFalse);
      expect(result.any((i) => i.id == 'item_replacement'), isTrue);

      // 2. Index Stability Invariant: Check that layout list remains sorted by ID alphabetically
      final ids = result.map((i) => i.id).toList();
      final sortedIds = List<String>.from(ids)..sort();
      expect(ids, equals(sortedIds), reason: 'replaceItem must preserve ascending ID sequence.');
    });

    test('replaceItem should correct bounds of the replacement item', () {
      final controller = DashboardController(
        initialSlotCount: 8,
        initialLayout: const [
          LayoutItem(id: 'item_1', x: 0, y: 0, w: 2, h: 2),
        ],
      );

      // Malformed replacement item: width too wide for 8-slot grid, x out of bounds
      const malformedReplacement = LayoutItem(
        id: 'item_replacement',
        x: 10, // out of bounds
        y: 0,
        w: 12, // wider than 8 slots
        h: 2,
      );

      controller.replaceItem('item_1', malformedReplacement);

      final replaced = controller.layout.value.firstWhere((i) => i.id == 'item_replacement');

      // Verify bounds correction was applied successfully
      expect(replaced.x + replaced.w, lessThanOrEqualTo(8));
      expect(replaced.w, lessThanOrEqualTo(8));
    });

    test('replaceItem should write through to originalLayoutOnStart snapshot if dragging', () {
      final controller = DashboardController(
        initialSlotCount: 8,
        initialLayout: const [
          LayoutItem(id: 'item_1', x: 0, y: 0, w: 2, h: 2),
          LayoutItem(id: 'item_2', x: 2, y: 0, w: 2, h: 2),
        ],
      ) as DashboardControllerImpl

        // Simulate active drag session
        ..onDragStart('item_1');

      const replacement = LayoutItem(
        id: 'item_replacement',
        x: 2,
        y: 0,
        w: 2,
        h: 2,
        hasNestedGrid: true,
      );

      // Replace 'item_2' while dragging 'item_1'
      controller.replaceItem('item_2', replacement);

      // Verify the write-through on originalLayoutOnStart snapshot
      final snapshot = controller.originalLayoutOnStart.value;
      expect(snapshot.any((i) => i.id == 'item_2'), isFalse);
      expect(snapshot.any((i) => i.id == 'item_replacement'), isTrue);

      // Cancel drag and verify layout reverts to snapshot containing replacement
      controller.cancelInteraction();
      expect(controller.layout.value.any((i) => i.id == 'item_replacement'), isTrue);
    });

    test('replaceItem on unknown ID should be a silent no-op', () {
      final controller = DashboardController(
        initialSlotCount: 8,
        initialLayout: const [
          LayoutItem(id: 'item_1', x: 0, y: 0, w: 2, h: 2),
        ],
      );

      const replacement = LayoutItem(
        id: 'item_replacement',
        x: 0,
        y: 0,
        w: 2,
        h: 2,
      );

      // Try replacing non-existent 'unknown_item'
      controller.replaceItem('unknown_item', replacement);

      expect(controller.layout.value.length, equals(1));
      expect(controller.layout.value.first.id, equals('item_1'));
    });
  });
}
