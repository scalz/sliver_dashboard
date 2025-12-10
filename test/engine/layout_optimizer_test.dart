import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';

void main() {
  group('Layout Optimizer (Defrag)', () {
    test('Should compact simple layout to top-left (Tetris style)', () {
      // Scenario: 3 items scattered diagonally
      // [A] [ ] [ ]
      // [ ] [B] [ ]
      // [ ] [ ] [C]
      final input = [
        const LayoutItem(id: 'A', x: 0, y: 0, w: 1, h: 1),
        const LayoutItem(id: 'B', x: 1, y: 1, w: 1, h: 1),
        const LayoutItem(id: 'C', x: 2, y: 2, w: 1, h: 1),
      ];

      // Cols = 3
      final result = optimizeLayout(input, 3);

      // Expected:
      // [A] [B] [C]
      expect(result.length, 3);

      final a = result.firstWhere((i) => i.id == 'A');
      final b = result.firstWhere((i) => i.id == 'B');
      final c = result.firstWhere((i) => i.id == 'C');

      expect(a.x, 0);
      expect(a.y, 0);
      expect(b.x, 1);
      expect(b.y, 0); // Moved up and left
      expect(c.x, 2);
      expect(c.y, 0); // Moved up and left
    });

    test('Should respect static items as immovable walls', () {
      // Scenario: Static item in the middle, dynamic item below it
      // [ ] [S] [ ]
      // [ ] [ ] [ ]
      // [D] [ ] [ ]
      final input = [
        const LayoutItem(id: 'S', x: 1, y: 0, w: 1, h: 1, isStatic: true),
        const LayoutItem(id: 'D', x: 0, y: 2, w: 1, h: 1),
      ];

      final result = optimizeLayout(input, 3);

      final s = result.firstWhere((i) => i.id == 'S');
      final d = result.firstWhere((i) => i.id == 'D');

      // Static should NOT move
      expect(s.x, 1);
      expect(s.y, 0);

      // Dynamic should fill the first available slot (0,0)
      expect(d.x, 0);
      expect(d.y, 0);
    });

    test('Should preserve visual order (Z-order)', () {
      // Scenario: Item 1 is visually before Item 2, even if Item 2 is processed later in the list
      // We pass them in wrong order in the list to verify the sort logic
      final input = [
        const LayoutItem(id: '2', x: 0, y: 2, w: 1, h: 1), // Visually last
        const LayoutItem(id: '1', x: 0, y: 1, w: 1, h: 1), // Visually first
      ];

      final result = optimizeLayout(input, 1); // 1 Column

      final i1 = result.firstWhere((i) => i.id == '1');
      final i2 = result.firstWhere((i) => i.id == '2');

      // Item 1 should be at top
      expect(i1.y, 0);
      // Item 2 should be right below
      expect(i2.y, 1);
    });

    test('Large items should skip gaps that are too small', () {
      // Scenario:
      // [A] [ ] [B] (Gap of 1 in the middle)
      // [ Large... ] (Width 2)
      //
      // Large item cannot fit in the gap between A and B.
      final input = [
        const LayoutItem(id: 'A', x: 0, y: 0, w: 1, h: 1),
        const LayoutItem(id: 'B', x: 2, y: 0, w: 1, h: 1),
        const LayoutItem(id: 'L', x: 0, y: 2, w: 2, h: 1), // Large item
      ];

      final result = optimizeLayout(input, 3);

      final l = result.firstWhere((i) => i.id == 'L');

      // A is at (0,0), B moves to (1,0).
      // Row 0 is now: [A][B][ ]
      // Large needs 2 slots. Row 0 has only 1 slot left at (2,0).
      // Large must go to Row 1.
      expect(l.x, 0);
      expect(l.y, 1);
    });
  });
}
