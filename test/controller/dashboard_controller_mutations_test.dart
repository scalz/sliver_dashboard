import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';

void main() {
  group('DashboardController.updateItem', () {
    late DashboardController controller;
    late int layoutChangedCalls;

    setUp(() {
      layoutChangedCalls = 0;
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1, minW: 1, minH: 1, maxW: 4, maxH: 4),
          LayoutItem(id: 'b', x: 2, y: 0, w: 2, h: 1),
          LayoutItem(id: 'c', x: 0, y: 1, w: 2, h: 1),
        ],
        onLayoutChanged: (_, __) => layoutChangedCalls++,
      );
    });

    tearDown(() => controller.dispose());

    LayoutItem itemById(String id) => controller.layout.value.firstWhere((i) => i.id == id);

    test('applies a metadata-only change without moving other items', () {
      controller.updateItem(
        'a',
        (i) => i.copyWith(hasNestedGrid: true),
        recompact: false,
      );

      expect(itemById('a').hasNestedGrid, isTrue);
      // Neighbours untouched.
      expect(itemById('b').x, 2);
      expect(itemById('c').y, 1);
      expect(layoutChangedCalls, 1);
    });

    test('no-op on unknown id: no mutation, no event', () {
      final before = controller.layout.value;
      controller.updateItem('does-not-exist', (i) => i.copyWith(w: 4));
      expect(controller.layout.value, same(before));
      expect(layoutChangedCalls, 0);
    });

    test('no-op when the transform returns an equal item', () {
      controller.updateItem('a', (i) => i); // identity
      expect(layoutChangedCalls, 0);

      // Also equal via copyWith with no changes.
      controller.updateItem('a', (i) => i.copyWith());
      expect(layoutChangedCalls, 0);
    });

    test('corrects invalid geometry from the transform (w < 1)', () {
      controller.updateItem('a', (i) => i.copyWith(w: 0));
      // correctBounds clamps width up to at least 1.
      expect(itemById('a').w, greaterThanOrEqualTo(1));
    });

    test('clamps an out-of-grid position back inside the grid', () {
      controller.updateItem('a', (i) => i.copyWith(x: 99));
      final a = itemById('a');
      expect(a.x + a.w, lessThanOrEqualTo(4)); // slotCount
      expect(a.x, greaterThanOrEqualTo(0));
    });

    test('recompact:true resolves overlaps introduced by a resize', () {
      // Grow 'a' to overlap 'b'; recompaction must leave no overlaps.
      controller.updateItem('a', (i) => i.copyWith(w: 4));

      final layout = controller.layout.value;
      for (final x in layout) {
        for (final y in layout) {
          if (x.id == y.id) continue;
          final overlap = x.x < y.x + y.w && x.x + x.w > y.x && x.y < y.y + y.h && x.y + x.h > y.y;
          expect(overlap, isFalse, reason: '${x.id} overlaps ${y.id}');
        }
      }
      expect(layoutChangedCalls, 1);
    });

    test('fires exactly one onLayoutChanged per effective update', () {
      controller.updateItem('a', (i) => i.copyWith(h: 2));
      expect(layoutChangedCalls, 1);
      controller.updateItem('a', (i) => i.copyWith(h: 3));
      expect(layoutChangedCalls, 2);
    });

    test('changing the id is rejected: item keeps its original id', () {
      // In debug the assert fires; guard so the release-path (defensive
      // restore) is what we exercise here.
      void run() => controller.updateItem('a', (i) => i.copyWith(id: 'zzz'));

      if (kDebugMode) {
        expect(run, throwsA(isA<AssertionError>()));
      } else {
        run();
        expect(controller.layout.value.any((i) => i.id == 'zzz'), isFalse);
        expect(controller.layout.value.any((i) => i.id == 'a'), isTrue);
      }
    });

    test('preserves constraints and flags carried by the transform', () {
      controller.updateItem(
        'a',
        (i) => i.copyWith(isResizable: false, maxW: 3),
      );
      final a = itemById('a');
      expect(a.isResizable, isFalse);
      expect(a.maxW, 3);
    });

    test('updateItem with compactionType none and recompact true resolves collisions', () {
      controller
        ..setCompactionType(CompactType.none)
        ..updateItem('a', (i) => i.copyWith(w: 4));

      // Should fallback to vertical collision resolution by default
      expect(controller.layout.value.firstWhere((i) => i.id == 'a').w, 4);
    });

    test('updateItem handles defensive ID fallback when assert is bypassed', () {
      debugBypassUpdateItemIdAssert = true;
      try {
        controller.updateItem('a', (i) => i.copyWith(id: 'zzz'), recompact: false);

        // The ID must be defensively restored back to 'a'
        expect(controller.layout.value.any((i) => i.id == 'a'), isTrue);
        expect(controller.layout.value.any((i) => i.id == 'zzz'), isFalse);
      } finally {
        debugBypassUpdateItemIdAssert = false;
      }
    });
  });

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
      addTearDown(controller.dispose);

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
      addTearDown(controller.dispose);

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
      ) as DashboardControllerImpl;
      addTearDown(controller.dispose);

      controller.onDragStart('item_1');

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
      addTearDown(controller.dispose);

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
