import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';

/// Regressions for the batch-scaling optimizations:
///
/// * compaction "rise/slide" is now a closed-form bound (single scan) instead
///   of a one-cell-at-a-time walk with a full collision scan per step —
///   appending a 500-item batch below 500 existing rows previously cost
///   ~70M collision tests (multi-second UI freeze on a stress-add button);
/// * `placeNewItems` tests candidates against an occupancy set of covered
///   cells (O(w*h) per candidate) instead of scanning the whole layout.
///
/// These tests pin OUTPUT EQUIVALENCE (the optimizations must not change a
/// single position) and the layout invariants on large batches.
void main() {
  bool overlapFree(List<LayoutItem> layout) {
    for (var i = 0; i < layout.length; i++) {
      for (var j = i + 1; j < layout.length; j++) {
        if (collides(layout[i], layout[j])) return false;
      }
    }
    return true;
  }

  group('Vertical compaction — closed-form rise equivalence', () {
    test('a floating item lands exactly on the max lower edge above it', () {
      const layout = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
        LayoutItem(id: 'b', x: 0, y: 8, w: 1, h: 1), // floats far below 'a'
        LayoutItem(id: 'c', x: 3, y: 5, w: 1, h: 1), // floats, no obstacle
      ];
      final out = const VerticalCompactor().compact(layout, 4);
      final b = out.firstWhere((i) => i.id == 'b');
      final c = out.firstWhere((i) => i.id == 'c');
      expect(b.y, 2, reason: 'rests on the lower edge of a (y+h = 2)');
      expect(c.y, 0, reason: 'no horizontal overlap above: rises to 0');
    });

    test('a static acts as a ceiling obstacle: no tunneling through it', () {
      const layout = [
        LayoutItem(id: 's', x: 0, y: 3, w: 4, h: 1, isStatic: true),
        LayoutItem(id: 'a', x: 1, y: 9, w: 2, h: 1),
      ];
      final out = const VerticalCompactor().compact(layout, 4);
      final a = out.firstWhere((i) => i.id == 'a');
      final st = out.firstWhere((i) => i.id == 's');
      expect(st.y, 3, reason: 'statics never move');
      expect(a.y, 4, reason: 'rests under the static, cannot tunnel above');
    });

    test('compaction is idempotent and preserves invariants on a big batch', () {
      // 300 items appended far below their compacted home — the exact shape
      // of the stress-button batch that exposed the quadratic-in-rows cost.
      final layout = <LayoutItem>[
        for (var i = 0; i < 300; i++)
          LayoutItem(
            id: 'i${i.toString().padLeft(3, '0')}',
            x: i % 6,
            y: 100 + i, // pathological: everyone floats deep
            w: 1 + (i % 2),
            h: 1 + ((i ~/ 2) % 2),
          ),
      ];
      final once = const VerticalCompactor().compact(layout, 8);
      final twice = const VerticalCompactor().compact(once, 8);
      expect(overlapFree(once), isTrue);
      expect(once.every((i) => i.y >= 0 && i.x >= 0), isTrue);
      // Idempotence: a compacted layout is a fixed point.
      for (var i = 0; i < once.length; i++) {
        expect(
          (twice[i].id, twice[i].x, twice[i].y),
          equals((once[i].id, once[i].x, once[i].y)),
        );
      }
      // ID-order invariant preserved by the index-map rewrite.
      final ids = once.map((i) => i.id).toList();
      expect(ids, equals([...ids]..sort()));
    });
  });

  group('Vertical compaction — randomized oracle equivalence', () {
    /// The HISTORICAL algorithm, verbatim: statics-first obstacle list,
    /// visual-order iteration, one-cell-at-a-time rise, then down-resolution
    /// to the first collider's lower edge. The optimized compactor
    /// (occupancy set + column skyline + closed form) must match it exactly,
    /// item for item — including statics BELOW items and colliding starts.
    List<LayoutItem> referenceCompactVertical(List<LayoutItem> layout, int cols) {
      final compareWith = layout.where((i) => i.isStatic).toList();
      // EXACT mirror of sortLayoutItems(CompactType.vertical): (y, x, id),
      // statics interleaved. The id tiebreak matters: colliding-start inputs
      // can share identical coordinates.
      final sorted = List<LayoutItem>.of(layout)
        ..sort((a, b) {
          if (a.y != b.y) return a.y.compareTo(b.y);
          if (a.x != b.x) return a.x.compareTo(b.x);
          return a.id.compareTo(b.id);
        });
      final result = <LayoutItem>[];
      for (final l in sorted) {
        var current = l;
        if (!l.isStatic) {
          while (current.y > 0 && getFirstCollision(compareWith, current) == null) {
            current = current.copyWith(y: current.y - 1);
          }
          LayoutItem? hit;
          while ((hit = getFirstCollision(compareWith, current)) != null) {
            current = current.copyWith(y: hit!.y + hit.h);
          }
          current = current.copyWith(y: max(current.y, 0));
          compareWith.add(current);
        }
        result.add(current);
      }
      result.sort((a, b) => a.id.compareTo(b.id));
      return result;
    }

    test(
        'optimized compact matches the historical algorithm exactly '
        '(randomized, statics above AND below, colliding starts)', () {
      for (final seed in [1, 7, 42, 1337]) {
        final rng = Random(seed);
        const cols = 8;
        final layout = <LayoutItem>[
          // Statics scattered everywhere, including deep rows BELOW most
          // dynamics (the skyline fast path must fall back for those).
          for (var i = 0; i < 6; i++)
            LayoutItem(
              id: 's${i.toString().padLeft(2, '0')}',
              x: rng.nextInt(cols - 1),
              y: rng.nextInt(40),
              w: 1 + rng.nextInt(2),
              h: 1 + rng.nextInt(2),
              isStatic: true,
            ),
          for (var i = 0; i < 120; i++)
            LayoutItem(
              id: 'd${i.toString().padLeft(3, '0')}',
              // Deliberately overlapping input (colliding starts).
              x: rng.nextInt(cols - 1),
              y: rng.nextInt(45),
              w: 1 + rng.nextInt(2),
              h: 1 + rng.nextInt(2),
            ),
        ];

        final expected = referenceCompactVertical(layout, cols);
        final actual = const VerticalCompactor().compact(layout, cols);

        expect(actual.length, expected.length, reason: 'seed $seed');
        for (var i = 0; i < expected.length; i++) {
          expect(
            (actual[i].id, actual[i].x, actual[i].y),
            equals((expected[i].id, expected[i].x, expected[i].y)),
            reason: 'seed $seed, item ${expected[i].id}',
          );
        }
      }
    });
  });

  group('Horizontal compaction — closed-form slide equivalence', () {
    test('a floating item slides exactly to the max right edge left of it', () {
      const layout = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
        LayoutItem(id: 'b', x: 7, y: 0, w: 1, h: 1), // floats far right
      ];
      final out = const HorizontalCompactor().compact(layout, 8);
      final b = out.firstWhere((i) => i.id == 'b');
      expect(b.x, 2, reason: 'rests against the right edge of a (x+w = 2)');
    });

    test('big-batch invariants and idempotence hold horizontally', () {
      final layout = <LayoutItem>[
        for (var i = 0; i < 200; i++)
          LayoutItem(
            id: 'i${i.toString().padLeft(3, '0')}',
            x: 50 + i,
            y: i % 6,
            w: 1 + (i % 2),
            h: 1,
          ),
      ];
      final once = const HorizontalCompactor().compact(layout, 200);
      final twice = const HorizontalCompactor().compact(once, 200);
      expect(overlapFree(once), isTrue);
      for (var i = 0; i < once.length; i++) {
        expect((twice[i].x, twice[i].y), equals((once[i].x, once[i].y)));
      }
    });
  });

  group('Top-of-grid push cascade — integrity under load', () {
    test('resolveCompactionCollision is a pure single-axis move', () {
      const layout = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
        LayoutItem(id: 'b', x: 0, y: 2, w: 2, h: 2),
        LayoutItem(id: 'c', x: 0, y: 4, w: 2, h: 2),
      ];
      final moved = resolveCompactionCollision(layout, layout[1], 6, 'y');
      expect((moved.x, moved.y), (0, 6));
      // No side effects: the input instances are untouched.
      expect(layout[2].y, 4);
    });

    test(
        'growing the TOP item of a dense brick grid keeps the cascade '
        'overlap-free (regression: the 4N safety cap broke silently, '
        'returning an overlapping layout)', () {
      const cols = 6;
      // Brick pattern: 2-wide items offset by 1 column every other row, so
      // a push propagates ACROSS columns and each obstacle is re-pushed by
      // several pushers — the multiplicative cascade shape.
      final layout = <LayoutItem>[
        const LayoutItem(id: 'top', x: 0, y: 0, w: cols, h: 1),
        for (var row = 0; row < 120; row++)
          for (var i = 0; i < 3; i++)
            LayoutItem(
              id: 'b_${row.toString().padLeft(3, '0')}_$i',
              x: (i * 2 + (row.isOdd ? 1 : 0)) % cols,
              y: 1 + row,
              w: 2,
              h: 1,
            ),
      ];

      // Grow the top item by 5 rows with the push behavior.
      final grown = layout.first.copyWith(h: 6);
      final result = resizeItem(
        layout,
        grown,
        behavior: ResizeBehavior.push,
        cols: cols,
      );

      expect(result.length, layout.length);
      // Integrity: the cascade must complete without the silent cap break —
      // no residual overlap anywhere in 361 items.
      for (var i = 0; i < result.length; i++) {
        for (var j = i + 1; j < result.length; j++) {
          expect(
            collides(result[i], result[j]),
            isFalse,
            reason: '${result[i].id} overlaps ${result[j].id}',
          );
        }
      }
      // Everything that was below the top item moved down by its growth.
      final top = result.firstWhere((i) => i.id == 'top');
      expect(top.h, 6);
      expect(
        result.where((i) => i.id != 'top').every((i) => i.y >= top.y + top.h),
        isTrue,
      );
    });
  });

  group('placeNewItems — occupancy-set equivalence', () {
    test('appendBottom packs a batch left-to-right below the content', () {
      const existing = [LayoutItem(id: 'a', x: 0, y: 0, w: 4, h: 2)];
      final placed = placeNewItems(
        existingLayout: existing,
        newItems: const [
          LayoutItem(id: 'n1', x: -1, y: -1, w: 2, h: 1),
          LayoutItem(id: 'n2', x: -1, y: -1, w: 2, h: 1),
          LayoutItem(id: 'n3', x: -1, y: -1, w: 2, h: 1),
        ],
        cols: 4,
      );
      final n1 = placed.firstWhere((i) => i.id == 'n1');
      final n2 = placed.firstWhere((i) => i.id == 'n2');
      final n3 = placed.firstWhere((i) => i.id == 'n3');
      // Same cursor semantics as the historical scan: start at bottom(=2),
      // fill left to right, wrap.
      expect((n1.x, n1.y), (0, 2));
      expect((n2.x, n2.y), (2, 2));
      expect((n3.x, n3.y), (0, 3));
      expect(overlapFree(placed), isTrue);
    });

    test('firstFit fills gaps between existing items', () {
      const existing = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 3, y: 0, w: 1, h: 1),
      ];
      final placed = placeNewItems(
        existingLayout: existing,
        newItems: const [LayoutItem(id: 'n', x: -1, y: -1, w: 2, h: 1)],
        cols: 4,
        strategy: AutoPlacementStrategy.firstFit,
      );
      final n = placed.firstWhere((i) => i.id == 'n');
      expect((n.x, n.y), (1, 0), reason: 'the 2-wide gap at (1,0) is taken');
    });

    test('pre-positioned new items are respected and act as obstacles', () {
      final placed = placeNewItems(
        existingLayout: const [],
        newItems: const [
          LayoutItem(id: 'fixed', x: 0, y: 0, w: 2, h: 1),
          LayoutItem(id: 'auto', x: -1, y: -1, w: 2, h: 1),
        ],
        cols: 4,
        strategy: AutoPlacementStrategy.firstFit,
      );
      final auto = placed.firstWhere((i) => i.id == 'auto');
      expect((auto.x, auto.y), (2, 0));
      expect(overlapFree(placed), isTrue);
    });

    test('a 500-item batch into 500 existing stays overlap-free', () {
      final existing = const VerticalCompactor().compact(
        [
          for (var i = 0; i < 500; i++)
            LayoutItem(
              id: 'e${i.toString().padLeft(3, '0')}',
              x: i % 8,
              y: i ~/ 8 * 2,
              w: 1 + (i % 2),
              h: 1 + (i % 2),
            ),
        ],
        8,
      );
      final batch = [
        for (var i = 0; i < 500; i++)
          LayoutItem(
            id: 'n${i.toString().padLeft(3, '0')}',
            x: -1,
            y: -1,
            w: 1 + (i % 2),
            h: 1 + ((i ~/ 3) % 2),
          ),
      ];
      final placed = placeNewItems(
        existingLayout: existing,
        newItems: batch,
        cols: 8,
      );
      expect(placed.length, 1000);
      expect(overlapFree(placed), isTrue);
      final compacted = const VerticalCompactor().compact(placed, 8);
      expect(overlapFree(compacted), isTrue);
    });
  });
}
