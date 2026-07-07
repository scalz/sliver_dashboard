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
  });
}
