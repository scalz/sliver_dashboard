import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

void main() {
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
}
