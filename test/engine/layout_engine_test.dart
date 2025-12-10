import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';

void main() {
  group('LayoutEngine static item logic', () {
    const cols = 10;
    const compactType = CompactType.vertical;

    test('compact() should not move static items', () {
      // Layout with a static item and a movable item above a gap.
      final layout = [
        const LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1), // Movable
        const LayoutItem(id: 'b', x: 0, y: 2, w: 1, h: 1, isStatic: true), // Static
      ];

      final compactedLayout = compact(layout, compactType, cols);

      final itemA = compactedLayout.firstWhere((item) => item.id == 'a');
      final itemB = compactedLayout.firstWhere((item) => item.id == 'b');

      // Item A should not have moved as there's no space above it.
      expect(itemA.y, 0);
      // Item B is static and MUST NOT move, even though there is a gap at y=1.
      expect(itemB.y, 2);
      expect(itemB.isStatic, isTrue);
    });

    test('compact() should move non-static items around static ones', () {
      // Layout with a static item, and a movable item below it with a gap above.
      final layout = [
        const LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1, isStatic: true), // Static
        const LayoutItem(id: 'b', x: 0, y: 2, w: 1, h: 1), // Movable
      ];

      final compactedLayout = compact(layout, compactType, cols);

      final itemA = compactedLayout.firstWhere((item) => item.id == 'a');
      final itemB = compactedLayout.firstWhere((item) => item.id == 'b');

      // Item A is static and must not move.
      expect(itemA.y, 0);
      // Item B should move up to fill the gap at y=1.
      expect(itemB.y, 1);
    });

    test('moveElement() should not move a static item', () {
      final layout = [const LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1, isStatic: true)];
      final staticItem = layout.first;

      final newLayout = moveElement(
        layout,
        staticItem,
        5, // Attempt to move to x=5
        5, // Attempt to move to y=5
        cols: cols,
        compactType: compactType,
      );

      // The layout should be unchanged.
      expect(newLayout, equals(layout));
    });

    test('moveElement() should push other items around a static item', () {
      final layout = [
        const LayoutItem(id: 'static', x: 2, y: 2, w: 2, h: 2, isStatic: true),
        const LayoutItem(id: 'moving', x: 0, y: 0, w: 1, h: 1),
      ];
      final movingItem = layout.firstWhere((item) => item.id == 'moving');

      // Move 'moving' to collide with 'static'
      final newLayout = moveElement(layout, movingItem, 2, 2, cols: cols, compactType: compactType);

      final staticAfterMove = newLayout.firstWhere((item) => item.id == 'static');
      final movingAfterMove = newLayout.firstWhere((item) => item.id == 'moving');

      // The static item should not have moved.
      expect(staticAfterMove.x, 2);
      expect(staticAfterMove.y, 2);

      // The moving item should have been pushed down below the static item.
      expect(movingAfterMove.y, greaterThanOrEqualTo(4));
    });

    test('moveElement() should push item past a static one on collision', () {
      final layout = [
        const LayoutItem(id: 'static', x: 2, y: 2, w: 2, h: 2, isStatic: true),
        const LayoutItem(id: 'moving', x: 0, y: 0, w: 1, h: 1),
      ];
      final movingItem = layout.firstWhere((item) => item.id == 'moving');

      final newLayout = moveElement(
        layout,
        movingItem,
        2, // Target X
        2, // Target Y (collides with static)
        cols: 10,
        compactType: CompactType.vertical,
        preventCollision: false,
      );

      final newMovingItem = newLayout.firstWhere((i) => i.id == 'moving');

      // The moving item should be pushed below the static item.
      expect(newMovingItem.y, 4);
      expect(newMovingItem.x, 2);
    });

    test('moveElement() should correctly push a chain of items that hits a static item', () {
      final layout = [
        const LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2),
        const LayoutItem(id: 'B', x: 0, y: 2, w: 2, h: 2),
        const LayoutItem(id: 'static', x: 0, y: 4, w: 2, h: 2, isStatic: true),
      ];
      final itemA = layout.firstWhere((item) => item.id == 'A');

      final newLayout = moveElement(
        layout,
        itemA,
        0, // Target X
        1, // Target Y (collides with B, which then collides with static)
        cols: 10,
        compactType: CompactType.vertical,
      );

      final itemAAfter = newLayout.firstWhere((i) => i.id == 'A');
      final itemBAfter = newLayout.firstWhere((i) => i.id == 'B');
      final staticAfter = newLayout.firstWhere((i) => i.id == 'static');

      // A moves to y=1, pushing B. B would move to y=3, but hits static at y=4.
      // So B is pushed past static to y=6.
      expect(itemAAfter.y, 1);
      expect(itemBAfter.y, 6);
      expect(staticAfter.y, 4); // Static item does not move.
    });

    group('Collision and Overlap Logic', () {
      const cols = 10;

      test('moveElement pushes items when compactType is set', () {
        final layout = [
          const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
          const LayoutItem(id: 'b', x: 0, y: 1, w: 2, h: 2),
        ];
        final itemToMove = layout.first; // Move 'a'

        final newLayout = moveElement(
          layout,
          itemToMove,
          0, // Move 'a' down to y=1, colliding with 'b'
          1,
          cols: cols,
          compactType: CompactType.vertical, // Enable "push"
          preventCollision: false,
        );

        final movedItemA = newLayout.firstWhere((item) => item.id == 'a');
        final pushedItemB = newLayout.firstWhere((item) => item.id == 'b');

        // 'a' should be at its target position
        expect(movedItemA.y, 1);
        // 'b' should have been pushed down
        expect(pushedItemB.y, greaterThan(1));
      });
    });
  });

  group('correctBounds', () {
    const cols = 10;

    test('should correct item extending beyond right edge', () {
      final layout = [const LayoutItem(id: 'a', x: 8, y: 0, w: 4, h: 1)];
      final corrected = correctBounds(layout, cols);
      expect(corrected.first.x, 6); // 10 - 4
      expect(corrected.first.w, 4);
    });

    test('should correct item starting before left edge', () {
      // This scenario is tricky. If an item is at x: -2, w: 4,
      // correcting it to x: 0 would make it x:0, w:4.
      // The current implementation corrects it to x:0, w:10, which is aggressive.
      // Let's test the current behavior.
      final layout = [const LayoutItem(id: 'a', x: -2, y: 0, w: 4, h: 1)];
      final corrected = correctBounds(layout, cols);
      expect(corrected.first.x, 0);
      expect(corrected.first.w, 10); // As per current implementation
    });

    test('should not change items within bounds', () {
      final layout = [const LayoutItem(id: 'a', x: 0, y: 0, w: 10, h: 1)];
      final corrected = correctBounds(layout, cols);
      expect(corrected, equals(layout));
    });
  });

  group('resizeItem', () {
    const cols = 20;

    group('with ResizeBehavior.shrink', () {
      test('should shrink colliding item on right expansion', () {
        final layout = [
          const LayoutItem(id: 'resizing', x: 0, y: 0, w: 5, h: 2),
          const LayoutItem(id: 'colliding', x: 6, y: 0, w: 4, h: 2, minW: 2),
        ];
        final itemToResize = layout.first;
        // Expand 'resizing' by 2, causing 1 unit of overlap with 'colliding'
        final resized = itemToResize.copyWith(w: 7);

        final newLayout = resizeItem(layout, resized, behavior: ResizeBehavior.shrink, cols: cols);

        final shrunkItem = newLayout.firstWhere((i) => i.id == 'colliding');
        // Should be pushed right by 1 and shrunk by 1
        expect(shrunkItem.x, 7);
        expect(shrunkItem.w, 3);
      });
    });

    test('resizeItem moves item past static item if overlapping with preventCollision: true', () {
      // The engine is robust: instead of reverting, it moves the resizing item
      // past the static obstacle.
      final layout = [
        const LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2),
        const LayoutItem(id: 'Static', x: 2, y: 0, w: 2, h: 2, isStatic: true),
      ];

      final itemA = layout.first;

      // Resize A to width 4 (overlapping Static at x=2)
      final resizedA = itemA.copyWith(w: 4);

      final result = resizeItem(
        layout,
        resizedA,
        behavior: ResizeBehavior.push,
        cols: 10,
        preventCollision: true,
      );

      final resultA = result.firstWhere((i) => i.id == 'A');

      // Expectation: A is moved down to y=2 (below Static) to resolve collision
      // because moveElement resolves static collisions by jumping over them.
      expect(resultA.y, 2);
      expect(resultA.w, 4);
    });

    test('resizeItem falls back to vertical push if shrink fails due to minWidth', () {
      final layout = [
        const LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2),
        // B is right next to A, with minW = 2
        const LayoutItem(id: 'B', x: 2, y: 0, w: 2, h: 2, minW: 2),
      ];

      final itemA = layout.first;

      // Resize A to width 3. Overlaps B by 1.
      // B cannot shrink (minW=2). Fallback to push.
      final resizedA = itemA.copyWith(w: 3);

      final result = resizeItem(
        layout,
        resizedA,
        behavior: ResizeBehavior.shrink,
        cols: 10,
        preventCollision: false,
      );

      final resultB = result.firstWhere((i) => i.id == 'B');

      // B should NOT be shrunk (w=2)
      expect(resultB.w, 2);
      // B should be pushed VERTICALLY (default push behavior) to y=2
      expect(resultB.y, 2);
      expect(resultB.x, 2); // X stays same
    });

    test('resizeItem resolves secondary overlaps between pushed items', () {
      // Scenario: Item A is resizing. It pushes B and C.
      // Without the fix, B and C are both pushed to the same Y coordinate and overlap.
      // Setup:
      // A [0,0] 2x2
      // B [2,0] 2x1 (Right of A)
      // C [2,1] 2x1 (Below B, Right of A)
      final layout = [
        const LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2),
        const LayoutItem(id: 'B', x: 2, y: 0, w: 2, h: 1),
        const LayoutItem(id: 'C', x: 2, y: 1, w: 2, h: 1),
      ];

      // Action: Resize A to width 3. It now overlaps both B and C at x=2.
      final resizedA = layout[0].copyWith(w: 3);

      final result = resizeItem(
        layout,
        resizedA,
        behavior: ResizeBehavior.push,
        cols: 10,
        preventCollision: true,
      );

      final b = result.firstWhere((i) => i.id == 'B');
      final c = result.firstWhere((i) => i.id == 'C');

      // Verification:
      // 1. A should be resized
      expect(result.firstWhere((i) => i.id == 'A').w, 3);

      // 2. B and C should be pushed down (y >= 2)
      expect(b.y, greaterThanOrEqualTo(2));
      expect(c.y, greaterThanOrEqualTo(2));

      // 3. CRITICAL: B and C should NOT overlap each other
      // Without the fix, both end up at y=2.
      expect(collides(b, c), isFalse, reason: 'Pushed items B and C should not overlap');
      expect(b.y != c.y, isTrue);
    });
  });

  group('Horizontal Compaction', () {
    const cols = 20;
    test('sortLayoutItems should sort by x then y for horizontal', () {
      final layout = [
        const LayoutItem(id: 'c', x: 2, y: 1, w: 1, h: 1),
        const LayoutItem(id: 'a', x: 0, y: 1, w: 1, h: 1),
        const LayoutItem(id: 'b', x: 0, y: 0, w: 1, h: 1),
        const LayoutItem(id: 'd', x: 2, y: 0, w: 1, h: 1),
      ];

      final sorted = sortLayoutItems(layout, CompactType.horizontal);

      expect(sorted.map((i) => i.id).toList(), ['b', 'a', 'd', 'c']);
    });

    test('compactItem should work with horizontal compaction', () {
      final compareWith = [const LayoutItem(id: 'static', x: 0, y: 0, w: 1, h: 2, isStatic: true)];
      const itemToCompact = LayoutItem(id: 'a', x: 2, y: 0, w: 1, h: 1);

      final compacted = compactItem(compareWith, itemToCompact, CompactType.horizontal, cols, [
        ...compareWith,
        itemToCompact,
      ]);

      // Should move left until it hits the static item
      expect(compacted.x, 1);
      expect(compacted.y, 0);
    });

    test('compactItem handles horizontal overflow correctly', () {
      // Scenario: Horizontal compaction pushes an item beyond 'cols'.
      // It should wrap to the next row (y+1) and reset x.
      final layout = [
        const LayoutItem(id: 'blocker', x: 0, y: 0, w: 2, h: 1),
        const LayoutItem(id: 'moving', x: 2, y: 0, w: 1, h: 1),
      ];

      // With cols=2, 'moving' is at the edge.
      // Compacting horizontally tries to push it left into 'blocker'.
      // Blocker pushes it right to x=2.
      // x=2 >= cols(2). Logic wraps it to x = cols - w = 1, y = y + 1 = 1.
      final result = compactItem(
        layout,
        layout.last, // moving
        CompactType.horizontal,
        2, // cols
        layout,
      );

      expect(result.y, 1);
      expect(result.x, 1);
    });
  });

  group('ResizeBehavior.shrink coverage', () {
    test('resizeItem shrinks neighbor when expanding right', () {
      // A [0,0] 2x2 | B [2,0] 2x2
      const itemA = LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2);
      const itemB = LayoutItem(id: 'B', x: 2, y: 0, w: 2, h: 2, minW: 1);
      final layout = [itemA, itemB];

      // Resize A to width 3 (overlap B by 1)
      final resizedA = itemA.copyWith(w: 3);

      final newLayout = resizeItem(
        layout,
        resizedA,
        behavior: ResizeBehavior.shrink,
        cols: 10,
      );

      // B should have shrunk to width 1 and moved to x=3
      final newB = newLayout.firstWhere((i) => i.id == 'B');
      expect(newB.w, 1);
      expect(newB.x, 3);
    });

    test('resizeItem fails to shrink if neighbor hits minWidth (fallback to push)', () {
      // A [0,0] 2x2 | B [2,0] 1x2 (minW: 1)
      const itemA = LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2);
      const itemB = LayoutItem(id: 'B', x: 2, y: 0, w: 1, h: 2, minW: 1);
      final layout = [itemA, itemB];

      // Resize A to width 3. B cannot shrink (w=1, minW=1).
      final resizedA = itemA.copyWith(w: 3);

      final newLayout = resizeItem(
        layout,
        resizedA,
        behavior: ResizeBehavior.shrink,
        cols: 10,
        preventCollision: true, // Force check
      );

      // Since shrink failed, it falls back to push logic.
      // Standard behavior is Vertical Compaction -> Push DOWN.
      final newB = newLayout.firstWhere((i) => i.id == 'B');

      // B stays at x=2 (vertical push doesn't change x)
      expect(newB.x, 2);

      // B is pushed down below A (y = A.y + A.h = 0 + 2 = 2)
      expect(newB.y, 2);

      // Width unchanged
      expect(newB.w, 1);
    });

    test('resizeItem shrinks neighbor when expanding left', () {
      // A [0,0] 2x2 | B [2,0] 2x2
      // We resize B to the left, overlapping A.
      const itemA = LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2, minW: 1);
      const itemB = LayoutItem(id: 'B', x: 2, y: 0, w: 2, h: 2);
      final layout = [itemA, itemB];

      // Resize B to start at x=1 (width 3)
      final resizedB = itemB.copyWith(x: 1, w: 3);

      final newLayout = resizeItem(
        layout,
        resizedB,
        behavior: ResizeBehavior.shrink,
        cols: 10,
      );

      // A should shrink: width 1
      final newA = newLayout.firstWhere((i) => i.id == 'A');
      expect(newA.w, 1);
      expect(newA.x, 0);
    });
  });

  group('placeNewItems', () {
    test('should return existing layout if no new items provided', () {
      final existing = [
        const LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1),
      ];
      final result = placeNewItems(
        existingLayout: existing,
        newItems: [],
        cols: 4,
      );
      expect(result, equals(existing));
    });

    test('should place a single item at (0,0) if layout is empty', () {
      const newItem = LayoutItem(id: 'new', x: -1, y: -1, w: 2, h: 2);
      final result = placeNewItems(
        existingLayout: [],
        newItems: [newItem],
        cols: 4,
      );

      expect(result.length, 1);
      expect(result.first.id, 'new');
      expect(result.first.x, 0);
      expect(result.first.y, 0);
    });

    test('should append items below existing content', () {
      // Existing item at y=0, height=2. Bottom is y=2.
      final existing = [
        const LayoutItem(id: '1', x: 0, y: 0, w: 4, h: 2),
      ];
      const newItem = LayoutItem(id: 'new', x: -1, y: -1, w: 2, h: 1);

      final result = placeNewItems(
        existingLayout: existing,
        newItems: [newItem],
        cols: 4,
      );

      final placedItem = result.firstWhere((i) => i.id == 'new');
      // Should start at y=2 (bottom of existing)
      expect(placedItem.y, 2);
      expect(placedItem.x, 0);
    });

    test('should wrap to next row if item does not fit in width', () {
      // Grid width = 4. Existing item takes 3 slots.
      final existing = [
        const LayoutItem(id: '1', x: 0, y: 0, w: 3, h: 1),
      ];
      // New item needs 2 slots. 3+2 > 4, so it shouldn't fit on row 0.
      const newItem = LayoutItem(id: 'new', x: -1, y: -1, w: 2, h: 1);

      final result = placeNewItems(
        existingLayout: existing,
        newItems: [newItem],
        cols: 4,
      );

      final placedItem = result.firstWhere((i) => i.id == 'new');
      // Should be on next row
      expect(placedItem.x, 0);
      expect(placedItem.y, 1);
    });

    test('should place multiple new items sequentially', () {
      final newItems = [
        const LayoutItem(id: 'A', x: -1, y: -1, w: 2, h: 1),
        const LayoutItem(id: 'B', x: -1, y: -1, w: 2, h: 1),
        const LayoutItem(id: 'C', x: -1, y: -1, w: 2, h: 1),
      ];

      final result = placeNewItems(
        existingLayout: [],
        newItems: newItems,
        cols: 4, // 2 items per row
      );

      final a = result.firstWhere((i) => i.id == 'A');
      final b = result.firstWhere((i) => i.id == 'B');
      final c = result.firstWhere((i) => i.id == 'C');

      // Row 0: [A, A, B, B]
      expect(a.x, 0);
      expect(a.y, 0);
      expect(b.x, 2);
      expect(b.y, 0);

      // Row 1: [C, C, _, _]
      expect(c.x, 0);
      expect(c.y, 1);
    });

    test('should handle mixed input (fixed and unknown positions)', () {
      final newItems = [
        const LayoutItem(id: 'Fixed', x: 2, y: 0, w: 1, h: 1),
        const LayoutItem(id: 'Auto', x: -1, y: -1, w: 1, h: 1),
      ];

      final result = placeNewItems(
        existingLayout: [],
        newItems: newItems,
        cols: 4,
      );

      final fixed = result.firstWhere((i) => i.id == 'Fixed');
      final auto = result.firstWhere((i) => i.id == 'Auto');

      // Fixed stays fixed
      expect(fixed.x, 2);
      expect(fixed.y, 0);

      // Auto logic starts at bottom.
      // Bottom of "Fixed" is 1.
      // So Auto starts checking at y=1.
      // Note: Ideally it could fit at (0,0), but the algorithm starts at bottom()
      // to avoid fragmentation.
      expect(auto.y, greaterThanOrEqualTo(1));
    });

    test('should respect collisions with items placed in the same batch', () {
      // Scenario: Placing a large item, then a small one.
      // The small one must not overlap the large one we just placed.
      final newItems = [
        const LayoutItem(id: 'Big', x: -1, y: -1, w: 4, h: 2),
        const LayoutItem(id: 'Small', x: -1, y: -1, w: 1, h: 1),
      ];

      final result = placeNewItems(
        existingLayout: [],
        newItems: newItems,
        cols: 4,
      );

      final big = result.firstWhere((i) => i.id == 'Big');
      final small = result.firstWhere((i) => i.id == 'Small');

      expect(big.x, 0);
      expect(big.y, 0);

      // Small should be below Big (y=2), not overlapping inside it
      expect(small.y, 2);
    });
  });

  test('moveElement resolves secondary overlaps (stacking) when pushing multiple items', () {
    // Scenario:
    // A [0,0] 2x2
    // B [2,0] 2x1 (Right of A)
    // C [2,1] 2x1 (Below B)
    final layout = [
      const LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2),
      const LayoutItem(id: 'B', x: 2, y: 0, w: 2, h: 1),
      const LayoutItem(id: 'C', x: 2, y: 1, w: 2, h: 1),
    ];

    // Action: Move A to the right (x=1).
    // It will overlap B (at x=2) and C (at x=2).
    // Both B and C will be pushed to y=2 (bottom of A).
    // Without the fix, B and C will overlap at y=2.
    final result = moveElement(
      layout,
      layout[0], // Item A
      1, // New X
      0, // New Y
      cols: 10,
      compactType: CompactType.vertical,
      preventCollision: true,
    );

    final b = result.firstWhere((i) => i.id == 'B');
    final c = result.firstWhere((i) => i.id == 'C');

    // Verification:
    // 1. A should be at x=1
    expect(result.firstWhere((i) => i.id == 'A').x, 1);

    // 2. B and C should be pushed down
    expect(b.y, greaterThanOrEqualTo(2));
    expect(c.y, greaterThanOrEqualTo(2));

    // 3. CRITICAL: B and C should NOT overlap each other
    expect(collides(b, c), isFalse, reason: 'Pushed items B and C should not overlap');
    expect(b.y != c.y, isTrue, reason: 'B and C should have different Y coordinates');
  });
}
