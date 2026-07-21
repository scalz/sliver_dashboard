import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';

// Random Layout Generator
List<LayoutItem> generateRandomLayout(int n, int cols, {int numStatics = 0}) {
  final random = Random(42); // Fixed seed
  final layout = <LayoutItem>[];
  for (var i = 0; i < n; i++) {
    layout.add(
      LayoutItem(
        id: '$i',
        x: random.nextInt(max(1, cols - 2)),
        y: random.nextInt(n),
        w: 1 + random.nextInt(3),
        h: 1 + random.nextInt(3),
        isStatic: i < numStatics,
      ),
    );
  }
  return layout;
}

// Overlap Checker
bool hasOverlaps(List<LayoutItem> layout) {
  for (var i = 0; i < layout.length; i++) {
    for (var j = i + 1; j < layout.length; j++) {
      // Ignore collisions between two static items (allowed by design)
      if (layout[i].isStatic && layout[j].isStatic) continue;

      if (collides(layout[i], layout[j])) {
        return true;
      }
    }
  }
  return false;
}

// Time Measurement
double measureTime(void Function() fn, {int iterations = 100}) {
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    fn();
  }
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds / iterations;
}

void main() {
  group('Compactor Strategies', () {
    const cols = 10;

    group('VerticalCompactor', () {
      const compactor = VerticalCompactor();

      test('compacts items upwards', () {
        final layout = [
          const LayoutItem(id: '1', x: 0, y: 2, w: 1, h: 1),
        ];
        final result = compactor.compact(layout, cols);
        expect(result.first.y, 0);
      });

      test('returns copy if allowOverlap is true', () {
        final layout = [
          const LayoutItem(id: '1', x: 0, y: 2, w: 1, h: 1),
        ];
        final result = compactor.compact(layout, cols, allowOverlap: true);
        // Should not move
        expect(result.first.y, 2);
      });

      test('resolveCollisions delegates to default logic', () {
        final layout = [
          const LayoutItem(id: 'A', x: 0, y: 0, w: 1, h: 1),
          const LayoutItem(id: 'B', x: 0, y: 0, w: 1, h: 1),
        ];
        final result = compactor.resolveCollisions(layout, cols);
        // B should be pushed down
        expect(result[1].y, 1);
      });
    });

    group('HorizontalCompactor', () {
      const compactor = HorizontalCompactor();

      test('compacts items leftwards', () {
        final layout = [
          const LayoutItem(id: '1', x: 2, y: 0, w: 1, h: 1),
        ];
        final result = compactor.compact(layout, cols);
        expect(result.first.x, 0);
      });

      test('returns copy if allowOverlap is true', () {
        final layout = [
          const LayoutItem(id: '1', x: 2, y: 0, w: 1, h: 1),
        ];
        final result = compactor.compact(layout, cols, allowOverlap: true);
        expect(result.first.x, 2);
      });

      test('wraps to next row if overflow', () {
        // Item at end of row
        final layout = [
          const LayoutItem(id: 'blocker', x: 0, y: 0, w: 9, h: 1),
          const LayoutItem(id: 'moving', x: 9, y: 0, w: 2, h: 1), // Width 2 -> Total 11 > 10
        ];
        // Compacting 'moving' left: hits blocker.
        // Blocker pushes right to x=9.
        // x=9 + w=2 = 11 > 10. Wrap!
        final result = compactor.compact(layout, cols);
        final moving = result.firstWhere((i) => i.id == 'moving');
        expect(moving.y, 1);
        expect(moving.x, 0);
      });
    });

    group('NoCompactor', () {
      const compactor = NoCompactor();

      test('does not move items (compact)', () {
        final layout = [
          const LayoutItem(id: '1', x: 0, y: 5, w: 1, h: 1),
        ];
        final result = compactor.compact(layout, cols);
        expect(result.first.y, 5);
      });

      test('resolves collisions vertically by default', () {
        final layout = [
          const LayoutItem(id: 'A', x: 0, y: 0, w: 1, h: 1),
          const LayoutItem(id: 'B', x: 0, y: 0, w: 1, h: 1),
        ];
        final result = compactor.resolveCollisions(layout, cols);
        expect(result[1].y, 1);
      });

      test('returns copy if allowOverlap is true', () {
        final layout = [
          const LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1),
        ];
        final result = compactor.compact(layout, cols, allowOverlap: true);
        expect(result.first, equals(layout.first));
      });
    });

    group('FastVerticalCompactor', () {
      const compactor = FastVerticalCompactor();

      test('compacts items upwards (Skyline)', () {
        final layout = [
          const LayoutItem(id: '1', x: 0, y: 5, w: 1, h: 1),
        ];
        final result = compactor.compact(layout, cols);
        expect(result.first.y, 0);
      });

      test('resolveCollisions delegates to vertical logic', () {
        final layout = [
          const LayoutItem(id: 'A', x: 0, y: 0, w: 1, h: 1),
          const LayoutItem(id: 'B', x: 0, y: 0, w: 1, h: 1),
        ];
        final result = compactor.resolveCollisions(layout, cols);
        expect(result[1].y, 1);
      });

      test('FastVerticalCompactor handles items with x >= slotCount correctly without overlap', () {
        const compactor = FastVerticalCompactor();
        // Setup a grid where slotCount (cols parameter) is 4 (cross-axis in horizontal scroll).
        // Items are placed at column x=5, which is >= 4!
        final layout = [
          const LayoutItem(id: 'A', x: 5, y: 2, w: 1, h: 2),
          const LayoutItem(id: 'B', x: 5, y: 1, w: 1, h: 1),
        ];

        final result = compactor.compact(layout, 4);

        final a = result.firstWhere((i) => i.id == 'A');
        final b = result.firstWhere((i) => i.id == 'B');

        // Under vertical compaction:
        // Items should be pulled to the top (y=0) on their same column x=5.
        // B (h=1) is placed at x=5, y=0.
        // A (h=2) is placed next to B at x=5, y=1.
        // They should NOT overlap!
        expect(b.x, 5);
        expect(a.x, 5);
        expect(b.y, 0);
        expect(a.y, 1);
      });

      test('FastVerticalCompactor comparator handles identical coordinates and IDs', () {
        const compactor = FastVerticalCompactor();
        final layout = [
          const LayoutItem(id: 'same', x: 0, y: 0, w: 1, h: 1, isStatic: false),
          const LayoutItem(id: 'same', x: 0, y: 0, w: 1, h: 1, isStatic: true),
        ];

        // Forces comparison internally on identical coords and IDs to cover tie-breaker lines
        final compacted = compactor.compact(layout, 4);
        expect(compacted.length, equals(2));
      });

      test('FastHorizontalCompactor comparator handles identical coordinates and IDs', () {
        const compactor = FastHorizontalCompactor();
        final layout = [
          const LayoutItem(id: 'same', x: 0, y: 0, w: 1, h: 1, isStatic: false),
          const LayoutItem(id: 'same', x: 0, y: 0, w: 1, h: 1, isStatic: true),
        ];

        final compacted = compactor.compact(layout, 4);
        expect(compacted.length, equals(2));
      });
    });

    group('FastHorizontalCompactor', () {
      const compactor = FastHorizontalCompactor();

      test('compacts items leftwards (Skyline)', () {
        final layout = [
          const LayoutItem(id: '1', x: 5, y: 0, w: 1, h: 1),
        ];
        final result = compactor.compact(layout, cols); // cols here means rows for horizontal
        expect(result.first.x, 0);
      });

      test('resolves static collisions by pushing right', () {
        final layout = [
          const LayoutItem(id: 'S', x: 2, y: 0, w: 2, h: 1, isStatic: true),
          const LayoutItem(id: 'A', x: 5, y: 0, w: 1, h: 1),
        ];
        final result = compactor.compact(layout, cols);
        final a = result.firstWhere((i) => i.id == 'A');
        // Should be at x=4 (after static S: 2+2)
        expect(a.x, 4);
      });

      test('resolveCollisions delegates to horizontal logic', () {
        final layout = [
          const LayoutItem(id: 'A', x: 0, y: 0, w: 1, h: 1),
          const LayoutItem(id: 'B', x: 0, y: 0, w: 1, h: 1),
        ];
        final result = compactor.resolveCollisions(layout, cols);
        // B should be pushed right (x=1)
        expect(result[1].x, 1);
      });

      test('sorts items by X then Y, prioritizing static items', () {
        final layout = [
          const LayoutItem(id: 'A', x: 0, y: 1, w: 1, h: 1),
          const LayoutItem(id: 'B', x: 0, y: 0, w: 1, h: 1),
          const LayoutItem(id: 'S', x: 0, y: 0, w: 1, h: 1, isStatic: true),
        ];

        final result = compactor.compact(layout, 10);

        final itemS = result.firstWhere((i) => i.id == 'S');
        final itemB = result.firstWhere((i) => i.id == 'B');
        final itemA = result.firstWhere((i) => i.id == 'A');

        // Verify proper compaction, sorting order, and static obstacle resolutions
        expect(itemS.x, 0);
        expect(itemS.y, 0);
        expect(itemB.x, 1); // Pushed right of static S
        expect(itemB.y, 0);
        expect(itemA.x, 0); // Moved left on row 1
        expect(itemA.y, 1);
      });

      test('resolves collision with static item by pushing right (collidesWithCoords)', () {
        final layout2 = [
          const LayoutItem(id: 'S', x: 0, y: 0, w: 2, h: 1, isStatic: true),
          const LayoutItem(id: 'A', x: 5, y: 0, w: 1, h: 1),
        ];
        final result2 = compactor.compact(layout2, 10);
        expect(result2.firstWhere((i) => i.id == 'A').x, 2);
      });

      test('collidesWithCoords returns false when no overlap', () {
        // This test aims to cover the "false" branches of collidesWithCoords
        // We need a scenario where we check collision but it returns false.
        // The algo iterates through statics.

        final layout = [
          const LayoutItem(id: 'S1', x: 0, y: 0, w: 1, h: 1, isStatic: true), // Top-Left
          const LayoutItem(id: 'S2', x: 0, y: 2, w: 1, h: 1, isStatic: true), // Bottom-Left
          const LayoutItem(id: 'A', x: 5, y: 1, w: 1, h: 1), // Middle Y
        ];

        // A tries x=0.
        // Checks S1 (y=0 vs A y=1). No Y overlap. Returns false. (Covers Y check)
        // Checks S2 (y=2 vs A y=1). No Y overlap. Returns false.
        // A is placed at x=0.

        final result = compactor.compact(layout, 10);
        expect(result.firstWhere((i) => i.id == 'A').x, 0);
      });

      test('resolves multiple static collisions sequentially', () {
        // Scenario: "Stairs" of static items.
        // S1 is at x=0. S2 is at x=2.
        // Dynamic item A tries to go to x=0.
        // 1. Hits S1. Pushed to x=2.
        // 2. Loop resets.
        // 3. Checks S1 again (no collision).
        // 4. Checks S2. Hits S2. Pushed to x=4.
        final layout = [
          const LayoutItem(id: 'S1', x: 0, y: 0, w: 2, h: 1, isStatic: true),
          const LayoutItem(id: 'S2', x: 2, y: 0, w: 2, h: 1, isStatic: true),
          const LayoutItem(id: 'A', x: 10, y: 0, w: 2, h: 1),
        ];

        final result = compactor.compact(layout, 10);

        final itemA = result.firstWhere((i) => i.id == 'A');
        // Should be pushed past both statics
        expect(itemA.x, 4);
      });

      test('collidesWithCoords handles non-overlapping items on all sides', () {
        // This test ensures that the collision check returns 'false' correctly
        // for items that are strictly above, below, or to the left of a static item.

        final layout = [
          // The Obstacle
          const LayoutItem(id: 'Static', x: 5, y: 5, w: 2, h: 2, isStatic: true),

          // Item Above (y=0, h=2) -> No Y overlap
          const LayoutItem(id: 'Above', x: 10, y: 0, w: 2, h: 2),

          // Item Below (y=8, h=2) -> No Y overlap
          const LayoutItem(id: 'Below', x: 10, y: 8, w: 2, h: 2),

          // Item Left (x=0, w=2) -> No X overlap (Candidate x will be 0)
          // Note: The algo calculates candidate X based on tide.
          // If tide is 0, candidate is 0.
          // 0 + 2 <= 5 (Static.x). No collision.
          const LayoutItem(id: 'Left', x: 0, y: 5, w: 2, h: 2),
        ];

        final result = compactor.compact(layout, 20); // 20 rows

        // Verify 'Above' moved to x=0 (passed the Y check)
        expect(result.firstWhere((i) => i.id == 'Above').x, 0);

        // Verify 'Below' moved to x=0 (passed the Y check)
        expect(result.firstWhere((i) => i.id == 'Below').x, 0);

        // Verify 'Left' stayed at x=0 (passed the X check)
        expect(result.firstWhere((i) => i.id == 'Left').x, 0);
      });

      test('Hits all collision branches in FastHorizontalCompactor (Strict)', () {
        // Setup: D starts before S. D is wide enough to hit S.
        // D at x=0, w=5. S at x=2, w=2.
        // Sort: D, S.
        // Processing D: staticOffset=0. Check S.
        // D tries x=0.
        // X Overlap? 0+5 > 2 AND 0 < 2+2. Yes.
        // Y Overlap? Same Y. Yes.
        // Collision! D pushed to x = 2+2 = 4.
        // Loop resets. Check S again.
        // D at x=4. S at x=2, w=2.
        // D.x (4) >= S.x (2) + S.w (2). True.
        final layoutCollision = [
          const LayoutItem(id: 'D', x: 0, y: 0, w: 5, h: 2),
          const LayoutItem(id: 'S', x: 2, y: 0, w: 2, h: 2, isStatic: true),
        ];
        final resCollision = compactor.compact(layoutCollision, 10);
        expect(resCollision.firstWhere((i) => i.id == 'D').x, 4);

        // Setup: D starts before S (same X, smaller Y).
        // D at x=0, y=0. S at x=0, y=5.
        // Sort: D, S.
        // Processing D: Check S.
        // X Overlap? Yes (same column).
        // Y Check: D.y(0) + h(2) <= S.y(5). True.
        final layoutAbove = [
          const LayoutItem(id: 'D', x: 0, y: 0, w: 2, h: 2),
          const LayoutItem(id: 'S', x: 0, y: 5, w: 2, h: 2, isStatic: true),
        ];
        final resAbove = compactor.compact(layoutAbove, 10);
        expect(resAbove.firstWhere((i) => i.id == 'D').x, 0);

        // Setup: D starts before S (smaller X), but is visually below (larger Y).
        // D at x=0, y=5, w=5. S at x=2, y=0, w=2.
        // Sort: D, S (because D.x < S.x).
        // Processing D: Check S.
        // X Overlap? D(0-5) vs S(2-4). Yes.
        // Y Check: D.y(5) >= S.y(0) + h(2). True.
        final layoutBelow = [
          const LayoutItem(id: 'D', x: 0, y: 5, w: 5, h: 2),
          const LayoutItem(id: 'S', x: 2, y: 0, w: 2, h: 2, isStatic: true),
        ];
        final resBelow = compactor.compact(layoutBelow, 10);
        expect(resBelow.firstWhere((i) => i.id == 'D').x, 0);
      });

      test('FastHorizontalCompactor handles items with y >= slotCount correctly without overlap',
          () {
        const compactor = FastHorizontalCompactor();
        // Setup a 4-column grid (rows parameter passed to compact is 4)
        // Items are placed at y=5 and y=6, which is >= 4!
        final layout = [
          const LayoutItem(id: 'A', x: 2, y: 5, w: 2, h: 1),
          const LayoutItem(id: 'B', x: 1, y: 5, w: 1, h: 1),
        ];

        final result = compactor.compact(layout, 4);

        final a = result.firstWhere((i) => i.id == 'A');
        final b = result.firstWhere((i) => i.id == 'B');

        // Under horizontal compaction:
        // Items should be pulled to the left (x=0) on their same row y=5.
        // B (w=1) is placed at x=0, y=5.
        // A (w=2) is placed next to B at x=1, y=5.
        // They should NOT overlap!
        expect(b.x, 0);
        expect(a.x, 1);
        expect(b.y, 5);
        expect(a.y, 5);
      });
    });
  });

  group('FastVerticalCompactor', () {
    const compactor = FastVerticalCompactor();
    const standardCompactor = VerticalCompactor();

    group('Correctness', () {
      test('produces a valid layout with no overlaps', () {
        for (var run = 0; run < 10; run++) {
          final cols = 1 + Random().nextInt(6);
          final numItems = 2 + Random().nextInt(20);
          final numStatics = Random().nextInt(numItems);

          final layout = generateRandomLayout(numItems, cols, numStatics: numStatics);
          final compacted = compactor.compact(layout, cols);

          expect(hasOverlaps(compacted), isFalse, reason: 'Run $run failed');
        }
      });

      test('is idempotent (compacting twice gives same result)', () {
        for (var run = 0; run < 5; run++) {
          final layout = generateRandomLayout(50, 12, numStatics: 5);

          final compacted1 = compactor.compact(layout, 12);
          final compacted2 = compactor.compact(compacted1, 12);

          expect(compacted1.length, compacted2.length);
          for (var i = 0; i < compacted1.length; i++) {
            // Compare by ID because order might change slightly depending on sort implementation
            final item1 = compacted1.firstWhere((l) => l.id == compacted2[i].id);
            final item2 = compacted2[i];
            expect(item1.x, item2.x);
            expect(item1.y, item2.y);
          }
        }
      });

      test('does not move static items', () {
        final layout = [
          const LayoutItem(id: 'static', x: 5, y: 5, w: 2, h: 2, isStatic: true),
          const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
          const LayoutItem(id: 'b', x: 5, y: 0, w: 2, h: 8),
        ];

        final compacted = compactor.compact(layout, 12);
        final staticItem = compacted.firstWhere((l) => l.id == 'static');

        expect(staticItem.x, 5);
        expect(staticItem.y, 5);
      });

      test('moves items around static items', () {
        final layout = [
          const LayoutItem(id: 'static', x: 0, y: 0, w: 12, h: 2, isStatic: true),
          const LayoutItem(id: 'a', x: 0, y: 5, w: 4, h: 2),
        ];

        final compacted = compactor.compact(layout, 12);
        final itemA = compacted.firstWhere((l) => l.id == 'a');

        // Item should be moved to y=2 (right below static)
        expect(itemA.y, 2);
      });
    });

    group('Performance Comparison', () {
      // Note: These tests might fail in Debug mode or on slow machines.
      // They are mostly informative.
      final testSizes = [50, 100, 200];

      for (final size in testSizes) {
        test('compares $size items (messy layout)', () {
          final layout = generateRandomLayout(size, 12);

          // Warm up
          standardCompactor.compact(layout, 12);
          compactor.compact(layout, 12);

          final stdTime = measureTime(() => standardCompactor.compact(layout, 12), iterations: 10);
          final fastTime = measureTime(() => compactor.compact(layout, 12), iterations: 10);

          debugPrint(
            'Size: $size | Standard: ${stdTime.toStringAsFixed(2)}µs | Fast: ${fastTime.toStringAsFixed(2)}µs',
          );

          // Fast compactor should be faster or comparable
          // We leave a margin because on small sets, overhead might play a role
          if (size >= 100) {
            expect(fastTime, lessThan(stdTime * 1.5));
          }
        });
      }
    });

    group('Edge Cases', () {
      test('handles empty layout', () {
        final compacted = compactor.compact([], 12);
        expect(compacted, isEmpty);
      });

      test('handles single item', () {
        final layout = [const LayoutItem(id: 'a', x: 5, y: 10, w: 2, h: 2)];
        final compacted = compactor.compact(layout, 12);

        expect(compacted[0].x, 5);
        expect(compacted[0].y, 0); // Should compact to top
      });

      test('handles items wider than grid', () {
        final layout = [const LayoutItem(id: 'a', x: 0, y: 0, w: 15, h: 2)];
        final compacted = compactor.compact(layout, 12);
        expect(compacted.length, 1);
      });
    });
  });

  test('FastVerticalCompactor & FastHorizontalCompactor comparator', () {
    const vCompactor = FastVerticalCompactor();
    const hCompactor = FastHorizontalCompactor();

    final layout1 = [
      const LayoutItem(id: 'same', x: 0, y: 0, w: 1, h: 1, isStatic: false),
      const LayoutItem(id: 'same', x: 0, y: 0, w: 1, h: 1, isStatic: true),
    ];
    vCompactor.compact(layout1, 4);
    hCompactor.compact(layout1, 4);

    final layout2 = [
      const LayoutItem(id: 'same', x: 0, y: 0, w: 1, h: 1, isStatic: true),
      const LayoutItem(id: 'same', x: 0, y: 0, w: 1, h: 1, isStatic: false),
    ];
    vCompactor.compact(layout2, 4);
    hCompactor.compact(layout2, 4);
  });

  group('LayoutEngine - Core Paths', () {
    test('HorizontalCompactor ensureRows grows rowRights dynamically', () {
      const compactor = HorizontalCompactor();
      // Item placed at y = 70 (exceeds initial rowRights size of 64)
      final layout = [
        const LayoutItem(id: 'a', x: 0, y: 70, w: 2, h: 2),
      ];
      final compacted = compactor.compact(layout, 10);
      expect(compacted.length, equals(1));
      expect(compacted.first.y, equals(70));
    });

    test('HorizontalCompactor compacts negative rows using historical path fallback', () {
      const compactor = HorizontalCompactor();
      final layout = [
        // Item at y = -1 (negative row)
        const LayoutItem(id: 'a', x: 2, y: -1, w: 2, h: 2),
      ];
      final compacted = compactor.compact(layout, 10);
      expect(compacted.length, equals(1));
    });

    test('HorizontalCompactor cellOwner collision and push-right resolution', () {
      const compactor = HorizontalCompactor();
      // Item 'b' is placed to collide with 'a' (static) on the left
      final layout = [
        const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2, isStatic: true),
        const LayoutItem(id: 'b', x: 1, y: 0, w: 2, h: 2), // overlaps columns 1-2
      ];
      final compacted = compactor.compact(layout, 10);

      // 'b' should be pushed right past 'a' (to x: 2)
      final b = compacted.firstWhere((i) => i.id == 'b');
      expect(b.x, equals(2));
    });

    test('sortLayoutItems horizontal sorting tie-breaker handles identical coordinates', () {
      final layout = [
        const LayoutItem(id: 'b', x: 0, y: 0, w: 1, h: 1),
        const LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
      ];
      // Triggers the horizontal tie-breaker
      final sorted = sortLayoutItems(layout, CompactType.horizontal);
      expect(sorted.first.id, equals('a'));
    });

    test('_resolveCollisionsDefault horizontal sort handles multiple collisions', () {
      const compactor = HorizontalCompactor();
      // item 'c' collides with two static obstacles at once
      final layout = [
        const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1, isStatic: true),
        const LayoutItem(id: 'b', x: 2, y: 0, w: 2, h: 1, isStatic: true),
        const LayoutItem(id: 'c', x: 1, y: 0, w: 1, h: 1),
      ];
      final compacted = compactor.compact(layout, 10);
      expect(compacted.length, equals(3));
    });

    test('correctBounds resolves overlaps of multiple static items', () {
      final layout = [
        const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2, isStatic: true),
        const LayoutItem(id: 'b', x: 0, y: 0, w: 2, h: 2, isStatic: true), // overlapping static
      ];
      final corrected = correctBounds(layout, 10);

      // 'b' should be pushed down below 'a' (to y: 2)
      final b = corrected.firstWhere((i) => i.id == 'b');
      expect(b.y, equals(2));
    });

    test('optimizeLayout ensureRowCounts grows rowCounts dynamically', () {
      // Static item placed at y = 70 (exceeds initial rowCounts size of 64)
      final layout = [
        const LayoutItem(id: 'a', x: 0, y: 70, w: 2, h: 2, isStatic: true),
        const LayoutItem(id: 'b', x: 0, y: 0, w: 1, h: 1), // dynamic item
      ];
      final optimized = optimizeLayout(layout, 10);
      expect(optimized.length, equals(2));
      expect(optimized.firstWhere((i) => i.id == 'a').y, equals(70)); // static stays at 70
    });

    test(
        'moveElement triggers residual overlap fallback when pre-existing overlaps remain untouched',
        () {
      final layout = [
        // Pre-existing overlaps untouched by the moved item's cascade
        const LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        const LayoutItem(id: 'b', x: 0, y: 0, w: 1, h: 1),
        // The item being moved
        const LayoutItem(id: 'c', x: 3, y: 3, w: 1, h: 1),
      ];

      // Moving 'c' triggers moveElement with preventCollision: true
      final result = moveElement(
        layout,
        const LayoutItem(id: 'c', x: 3, y: 3, w: 1, h: 1),
        4, 4, // Move 'c' to 4,4
        cols: 10,
        compactType: CompactType.none,
        preventCollision: true,
        force: true,
      );

      expect(result.length, equals(3));
    });

    test('resolveCollisions horizontal Default handles multiple collisions sorting', () {
      // Item 'c' (w: 2) collides with both static obstacles 'a' and 'b' on the horizontal axis
      // This forces a 2-element list inside hits.sort and covers the horizontal ternary branch
      final layout = [
        const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1, isStatic: true),
        const LayoutItem(id: 'b', x: 2, y: 0, w: 2, h: 1, isStatic: true),
        const LayoutItem(id: 'c', x: 1, y: 0, w: 2, h: 1), // overlaps with a at x=1 and b at x=2
      ];

      final resolved = resolveCollisions(layout, CompactType.horizontal);
      expect(resolved.length, equals(3));
    });

    test('correctBounds clamps item height when h < 1', () {
      final layout = [
        const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 0),
      ];

      final corrected = correctBounds(layout, 10);
      expect(corrected.first.h, equals(1)); // clamped to 1
    });

    test('resolveCollisions horizontal default handles multiple preceding collisions', () {
      final layout = [
        const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1, isStatic: true),
        const LayoutItem(id: 'b', x: 0, y: 1, w: 2, h: 1, isStatic: true),
        const LayoutItem(id: 'c', x: 1, y: 0, w: 2, h: 2),
      ];

      final resolved = resolveCollisions(layout, CompactType.horizontal);
      expect(resolved.length, equals(3));
      final c = resolved.firstWhere((i) => i.id == 'c');

      // The item should be pushed past the static obstacles on the horizontal axis
      expect(c.x, equals(2));
    });
  });
}
