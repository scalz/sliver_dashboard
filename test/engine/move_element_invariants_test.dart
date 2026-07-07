import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

void main() {
  group('LayoutEngine moveElement Invariants', () {
    // Helper to generate dense randomized layouts
    List<LayoutItem> randomDenseLayout(Random random, {required int count, required int cols}) {
      var layout = <LayoutItem>[];
      for (var i = 0; i < count; i++) {
        final item = LayoutItem(
          id: 'item_$i',
          x: -1,
          y: -1,
          w: random.nextInt(2) + 1,
          h: random.nextInt(2) + 1,
        );
        layout = placeNewItems(
          existingLayout: layout,
          newItems: [item],
          cols: cols,
        );
      }
      return layout;
    }

    int countOverlaps(List<LayoutItem> layout) {
      var overlaps = 0;
      for (var i = 0; i < layout.length; i++) {
        for (var j = i + 1; j < layout.length; j++) {
          if (collides(layout[i], layout[j])) {
            overlaps++;
          }
        }
      }
      return overlaps;
    }

    test('never leaves residual overlaps (seeded fuzz, dense layouts)', () {
      final random = Random(42);
      for (var trial = 0; trial < 150; trial++) {
        final layout = randomDenseLayout(random, count: 35, cols: 8);
        if (layout.isEmpty) continue;

        final moved = layout[random.nextInt(layout.length)];
        final result = moveElement(
          layout,
          moved,
          random.nextInt(6),
          random.nextInt(15),
          cols: 8,
          compactType: CompactType.vertical,
          preventCollision: true,
          force: true,
        );

        // Verification: Ensure the monotonic re-push resolver has resolved all collisions
        expect(
          countOverlaps(result),
          equals(0),
          reason: 'Trial $trial left residual overlapping items after cascade movement',
        );
      }
    });

    test('result is always sorted by ID alphabetically (index stability)', () {
      final random = Random(99);
      final layout = randomDenseLayout(random, count: 15, cols: 8);
      final moved = layout.first;

      final result = moveElement(
        layout,
        moved,
        2,
        3,
        cols: 8,
        compactType: CompactType.vertical,
        preventCollision: true,
      );

      for (var i = 0; i < result.length - 1; i++) {
        expect(
          result[i].id.compareTo(result[i + 1].id),
          lessThan(0),
          reason: 'Layout array was not sorted alphabetically by ID, violating index stability',
        );
      }
    });
  });
}
