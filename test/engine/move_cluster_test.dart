import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';

void main() {
  group('Cluster Logic (Multi-Selection)', () {
    test('calculateBoundingBox returns correct dimensions', () {
      final items = [
        const LayoutItem(id: '1', x: 0, y: 0, w: 2, h: 2),
        const LayoutItem(id: '2', x: 2, y: 1, w: 2, h: 1),
      ];
      // BBox: x=0, y=0, w=4 (0 to 4), h=2 (0 to 2)
      final bbox = calculateBoundingBox(items);

      expect(bbox.x, 0);
      expect(bbox.y, 0);
      expect(bbox.w, 4);
      expect(bbox.h, 2);
    });

    test('moveCluster moves all items by the same delta', () {
      // Layout:
      // [A][A]
      // [B][B]
      // Cluster: A and B.
      final layout = [
        const LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 1),
        const LayoutItem(id: 'B', x: 0, y: 1, w: 2, h: 1),
      ];

      // Move cluster to x=2, y=0 (Shift right by 2)
      final result = moveCluster(
        layout,
        {'A', 'B'},
        2,
        0,
        cols: 4,
        compactType: CompactType.none,
      );

      final a = result.firstWhere((i) => i.id == 'A');
      final b = result.firstWhere((i) => i.id == 'B');

      expect(a.x, 2);
      expect(a.y, 0);
      expect(b.x, 2);
      expect(b.y, 1); // Relative position maintained
    });

    test('moveCluster pushes obstacles correctly', () {
      // Layout:
      // [A][A] [O]
      // [B][B]
      // Cluster: A and B. Obstacle: O at (2,0).
      final layout = [
        const LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 1),
        const LayoutItem(id: 'B', x: 0, y: 1, w: 2, h: 1),
        const LayoutItem(id: 'O', x: 2, y: 0, w: 2, h: 2),
      ];

      // Move cluster to x=1. BBox becomes x=1, w=2. Ends at x=3.
      // Overlaps O (starts at 2).
      // O should be pushed down.
      final result = moveCluster(
        layout,
        {'A', 'B'},
        1, 0,
        cols: 10,
        compactType: CompactType.vertical,
        preventCollision: true, // Ensure push happens
      );

      final a = result.firstWhere((i) => i.id == 'A');
      final b = result.firstWhere((i) => i.id == 'B');
      final o = result.firstWhere((i) => i.id == 'O');

      // Cluster moved to x=1
      expect(a.x, 1);
      expect(b.x, 1);

      // Obstacle O pushed down
      // BBox height is 2. BBox Y is 0. BBox ends at 2.
      // O should be pushed to y=2.
      expect(o.y, 2);
    });

    test('moveCluster does not move static items even if included in clusterIds', () {
      // Layout:
      // [A][A] [ ] [S]
      // [B][B]
      // Cluster contains dynamic A, B and static S at (3,0)
      final layout = [
        const LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 1),
        const LayoutItem(id: 'B', x: 0, y: 1, w: 2, h: 1),
        const LayoutItem(id: 'S', x: 3, y: 0, w: 1, h: 1, isStatic: true),
      ];

      final result = moveCluster(
        layout,
        {'A', 'B', 'S'},
        1, 0, // Request shift right of 1 column
        cols: 10,
        compactType: CompactType.none,
      );

      final a = result.firstWhere((i) => i.id == 'A');
      final b = result.firstWhere((i) => i.id == 'B');
      final s = result.firstWhere((i) => i.id == 'S');

      // The static item S must not move from (3,0)
      expect(s.x, 3);
      expect(s.y, 0);

      // The dynamic items A and B should still move correctly by the delta (dx: 1)
      expect(a.x, 1);
      expect(a.y, 0);
      expect(b.x, 1);
      expect(b.y, 1);
    });
  });

  group('moveCluster Invariants', () {
    test('moveCluster preserves ID alphabetical sorting across movement cycles', () {
      final layout = [
        const LayoutItem(id: 'item_a', x: 0, y: 0, w: 2, h: 2),
        const LayoutItem(id: 'item_b', x: 2, y: 0, w: 2, h: 2),
        const LayoutItem(id: 'item_c', x: 4, y: 0, w: 2, h: 2),
      ];

      final result = moveCluster(
        layout,
        {'item_a', 'item_b'},
        1,
        1,
        cols: 8,
        compactType: CompactType.vertical,
        preventCollision: true,
      );

      // Verification: Elements must retain ID stability so that sliver indices do not shift
      // and force widget element teardown and recreation during drags.
      for (var i = 0; i < result.length - 1; i++) {
        expect(
          result[i].id.compareTo(result[i + 1].id),
          lessThan(0),
          reason: 'moveCluster output is not properly sorted by ID',
        );
      }
    });
    test('moveCluster with static item in selection must not duplicate IDs', () {
      // 1. Initial layout containing a static item and a dynamic item
      const initialLayout = [
        LayoutItem(id: 'dynamic_1', x: 0, y: 0, w: 2, h: 2),
        LayoutItem(id: 'static_1', x: 2, y: 0, w: 2, h: 2, isStatic: true),
      ];

      // 2. Select both items programmatically (simulating group selection)
      final clusterIds = {'dynamic_1', 'static_1'};

      // 3. Perform moveCluster
      final result = moveCluster(
        initialLayout,
        clusterIds,
        1, // targetX
        0, // targetY
        cols: 8,
        compactType: CompactType.none,
      );

      // 4. Verify no duplicates exist in the output layout
      final ids = result.map((i) => i.id).toList();
      final uniqueIds = ids.toSet();

      expect(
        ids.length,
        equals(uniqueIds.length),
        reason: 'moveCluster must not duplicate static item IDs in the output layout array.',
      );

      // Verify the static item is still preserved at its original coordinates
      final staticItem = result.firstWhere((i) => i.id == 'static_1');
      expect(staticItem.x, equals(2));
      expect(staticItem.y, equals(0));
    });

    test('Section barriers must remain movable/draggable in edit mode', () {
      const initialLayout = [
        LayoutItem(
          id: 'barrier_1',
          x: 0,
          y: 0,
          w: 8,
          h: 1,
          isSectionBarrier: true,
          sectionTitle: 'Section 1',
        ),
        LayoutItem(id: 'dynamic_1', x: 0, y: 1, w: 2, h: 2),
      ];

      // Section barriers have isStatic: true, but because they are section barriers,
      // they must be allowed to move when selected.
      final clusterIds = {'barrier_1'};

      final result = moveCluster(
        initialLayout,
        clusterIds,
        0, // targetX
        1, // targetY (moved down by 1 row)
        cols: 8,
        compactType: CompactType.none,
      );

      final barrier = result.firstWhere((i) => i.id == 'barrier_1');
      expect(
        barrier.y,
        equals(1),
        reason: 'Section barriers must be draggable/movable in edit mode.',
      );
    });
  });

  group('Auto-Shrink on Drag Engine Logic', () {
    test('moveCluster with allowAutoShrink: true shrinks colliding items vertically if possible',
        () {
      // Setup:
      // Moving A [0,0] 2x2. Target is y=1.
      // Neighbor B [0,2] 2x2 with minH: 1.
      final layout = [
        const LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2),
        const LayoutItem(id: 'B', x: 0, y: 2, w: 2, h: 2, minH: 1),
      ];

      // Move cluster A vertically down to y=1 (overlaps B at y=2 by 1 slot)
      final result = moveCluster(
        layout,
        {'A'},
        0, 1,
        cols: 4,
        compactType: CompactType.none,
        allowAutoShrink: true, // Enabled
      );

      final a = result.firstWhere((i) => i.id == 'A');
      final b = result.firstWhere((i) => i.id == 'B');

      // A should move successfully to y=1
      expect(a.y, 1);
      // B should have dynamically contracted its height from 2 to 1 (shifting down its starting y to 3)
      expect(b.y, 3);
      expect(b.h, 1);
    });

    test('moveCluster falls back to classic push if neighboring items hit minHeight limits', () {
      // Setup: Neighbor B has minH: 2. It cannot shrink anymore.
      final layout = [
        const LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2),
        const LayoutItem(id: 'B', x: 0, y: 2, w: 2, h: 2, minH: 2),
      ];

      final result = moveCluster(
        layout,
        {'A'},
        0,
        1,
        cols: 4,
        compactType: CompactType.none,
        preventCollision: true,
        allowAutoShrink: true,
      );

      final a = result.firstWhere((i) => i.id == 'A');
      final b = result.firstWhere((i) => i.id == 'B');

      // A moves to y=1
      expect(a.y, 1);
      // Shrinking failed (due to minH: 2). B falls back to being pushed down, keeping h: 2
      expect(b.y, 3);
      expect(b.h, 2);
    });
  });
}
