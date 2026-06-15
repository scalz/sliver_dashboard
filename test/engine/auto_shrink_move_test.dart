import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';

void main() {
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
