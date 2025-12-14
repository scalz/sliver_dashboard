import 'dart:math';
import 'package:flutter/foundation.dart';
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
}
