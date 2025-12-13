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
  });
}
