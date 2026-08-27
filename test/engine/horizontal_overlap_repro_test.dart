import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

/// Regression suite: horizontal compaction must not return overlapping items.
///
/// `moveElement` skipped its residual-overlap verification unless
/// `preventCollision` was set, relying on the cascade being "overlap-free by
/// construction" — a property earned from monotonicity, which only the
/// unbounded vertical axis provides. See the Axis Asymmetry invariant in
/// ARCHITECTURE.md.
///
/// The two layouts below are verbatim fuzz inputs (moveElement run 188,
/// moveCluster run 55). The fuzz reported the input but not the mover and
/// target it used, so each case **sweeps every legal move** on its layout
/// instead of guessing: a bounded, exhaustive, fully deterministic search.
///
/// These run unconditionally. They were skipped while the defect was open;
/// re-skipping them silently reopens it.

/// Returns the first overlapping pair, or null when the layout is valid.
({LayoutItem a, LayoutItem b})? firstOverlap(List<LayoutItem> layout) {
  for (var i = 0; i < layout.length; i++) {
    for (var j = i + 1; j < layout.length; j++) {
      final a = layout[i];
      final b = layout[j];
      if (a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h) {
        return (a: a, b: b);
      }
    }
  }
  return null;
}

String describe(({LayoutItem a, LayoutItem b}) pair) =>
    '${pair.a.id}(${pair.a.x},${pair.a.y},${pair.a.w},${pair.a.h}) / '
    '${pair.b.id}(${pair.b.x},${pair.b.y},${pair.b.w},${pair.b.h})';

void main() {
  group('horizontal compaction overlap', () {
    // moveElement run 188, cols 5. Reported overlap: i2(0,6,3,1) / i3(1,6,3,3).
    const layout188 = [
      LayoutItem(id: 'i0', x: 2, y: 0, w: 2, h: 3),
      LayoutItem(id: 'i1', x: 0, y: 5, w: 3, h: 2),
      LayoutItem(id: 'i2', x: 0, y: 3, w: 3, h: 1),
      LayoutItem(id: 'i3', x: 0, y: 7, w: 3, h: 3),
      LayoutItem(id: 'i4', x: 3, y: 4, w: 1, h: 2, isStatic: true),
      LayoutItem(id: 'i5', x: 0, y: 2, w: 2, h: 1),
      LayoutItem(id: 'i6', x: 3, y: 7, w: 2, h: 2),
      LayoutItem(id: 'i7', x: 0, y: 4, w: 3, h: 1),
    ];

    // moveCluster run 55, cols 6. Reported overlap: i4(2,10,3,1) / i6(3,10,1,3).
    const layout55 = [
      LayoutItem(id: 'i0', x: 2, y: 4, w: 2, h: 1, isStatic: true),
      LayoutItem(id: 'i1', x: 3, y: 6, w: 2, h: 1, isStatic: true),
      LayoutItem(id: 'i2', x: 4, y: 3, w: 2, h: 2),
      LayoutItem(id: 'i3', x: 1, y: 7, w: 1, h: 1, isStatic: true),
      LayoutItem(id: 'i4', x: 2, y: 2, w: 3, h: 1),
      LayoutItem(id: 'i5', x: 0, y: 0, w: 2, h: 1, isStatic: true),
      LayoutItem(id: 'i6', x: 0, y: 6, w: 1, h: 3),
      LayoutItem(id: 'i7', x: 2, y: 7, w: 3, h: 3, isStatic: true),
      LayoutItem(id: 'i8', x: 3, y: 0, w: 3, h: 2, isStatic: true),
    ];

    // ---------------------------------------------------------------------
    // Run these three FIRST. Each one answers a single question, and together
    // they localize the defect without a debugger.
    // ---------------------------------------------------------------------

    test(
      'A. the exact reported move, with and without preventCollision',
      () {
        // `moveElement` skips its residual-overlap verification entirely when
        // preventCollision is false:
        //
        //   if (preventCollision && _hasResidualOverlap(...)) { ... }
        //
        // Both reported failures were preventCollision=false. If the `true`
        // variant below is clean and the `false` one is not, the cascade is
        // NOT overlap-free by construction on the horizontal axis, and that
        // gate is the bug.
        const mover = LayoutItem(id: 'i3', x: 0, y: 7, w: 3, h: 3);

        final relaxed = moveElement(
          layout188,
          mover,
          1,
          2,
          cols: 5,
          compactType: CompactType.horizontal,
          isUserAction: true,
          preventCollision: false,
        );
        final strict = moveElement(
          layout188,
          mover,
          1,
          2,
          cols: 5,
          compactType: CompactType.horizontal,
          isUserAction: true,
          preventCollision: true,
        );

        final relaxedOverlap = firstOverlap(relaxed);
        final strictOverlap = firstOverlap(strict);

        expect(
          strictOverlap,
          isNull,
          reason: 'preventCollision: true -> '
              '${strictOverlap == null ? '' : describe(strictOverlap)}',
        );
        expect(
          relaxedOverlap,
          isNull,
          reason: 'preventCollision: false -> '
              '${relaxedOverlap == null ? '' : describe(relaxedOverlap)}',
        );
      },
    );

    test(
      'B. the exact reported cluster move, with and without preventCollision',
      () {
        final relaxed = moveCluster(
          layout55,
          {'i6'},
          3,
          0,
          cols: 6,
          compactType: CompactType.horizontal,
          preventCollision: false,
        );
        final strict = moveCluster(
          layout55,
          {'i6'},
          3,
          0,
          cols: 6,
          compactType: CompactType.horizontal,
          preventCollision: true,
        );

        final relaxedOverlap = firstOverlap(relaxed);
        final strictOverlap = firstOverlap(strict);

        expect(
          strictOverlap,
          isNull,
          reason: 'preventCollision: true -> '
              '${strictOverlap == null ? '' : describe(strictOverlap)}',
        );
        expect(
          relaxedOverlap,
          isNull,
          reason: 'preventCollision: false -> '
              '${relaxedOverlap == null ? '' : describe(relaxedOverlap)}',
        );
      },
    );

    test(
      'moveElement: no legal move on the run-188 layout may overlap',
      () {
        const cols = 5;
        final failures = <String>[];

        for (final mover in layout188) {
          if (mover.isStatic) continue;
          for (var x = 0; x + mover.w <= cols; x++) {
            for (var y = 0; y < 12; y++) {
              for (final prevent in [false, true]) {
                final result = moveElement(
                  layout188,
                  mover,
                  x,
                  y,
                  cols: cols,
                  compactType: CompactType.horizontal,
                  isUserAction: true,
                  preventCollision: prevent,
                );
                final overlap = firstOverlap(result);
                if (overlap != null) {
                  failures.add(
                    'move ${mover.id} -> ($x,$y) preventCollision=$prevent '
                    'produced ${describe(overlap)}',
                  );
                }
              }
            }
          }
        }

        expect(
          failures,
          isEmpty,
          reason: '${failures.length} overlapping outcomes, first few:\n'
              '${failures.take(5).join('\n')}',
        );
      },
    );

    test(
      'moveCluster: no legal move on the run-55 layout may overlap',
      () {
        const cols = 6;
        final failures = <String>[];

        for (final mover in layout55) {
          if (mover.isStatic) continue;
          for (var x = 0; x + mover.w <= cols; x++) {
            for (var y = 0; y < 12; y++) {
              final result = moveCluster(
                layout55,
                {mover.id},
                x,
                y,
                cols: cols,
                compactType: CompactType.horizontal,
              );
              final overlap = firstOverlap(result);
              if (overlap != null) {
                failures.add(
                  'move ${mover.id} -> ($x,$y) produced ${describe(overlap)}',
                );
              }
            }
          }
        }

        expect(
          failures,
          isEmpty,
          reason: '${failures.length} overlapping outcomes, first few:\n'
              '${failures.take(5).join('\n')}',
        );
      },
    );

    test(
      'compact alone is overlap-free on both layouts',
      () {
        // Stage isolation. `moveElement` = cascade, then compaction. Running
        // the compactor on its own input tells you which stage to blame:
        //   this test RED   -> the defect is in HorizontalCompactor.compact
        //   this test GREEN -> the defect is in the cascade, and compaction
        //                      merely fails to repair what it is handed
        // Note the second case still implicates compaction as the last line
        // of defence, but the fix belongs upstream.
        for (final entry in [(layout188, 5), (layout55, 6)]) {
          final result = compact(entry.$1, CompactType.horizontal, entry.$2);
          final overlap = firstOverlap(result);
          expect(
            overlap,
            isNull,
            reason: 'compact(cols ${entry.$2}) produced '
                '${overlap == null ? '' : describe(overlap)}',
          );
        }
      },
    );

    test(
      'compaction is idempotent on both layouts',
      () {
        // A compactor that does not reach a fixed point in one pass is a
        // strong signal on its own, and it is cheap to check.
        for (final entry in [(layout188, 5), (layout55, 6)]) {
          final once = compact(entry.$1, CompactType.horizontal, entry.$2);
          final twice = compact(once, CompactType.horizontal, entry.$2);
          expect(
            twice.map((i) => '${i.id}:${i.x},${i.y}').join('|'),
            once.map((i) => '${i.id}:${i.x},${i.y}').join('|'),
            reason: 'compaction is not a fixed point (cols ${entry.$2})',
          );
        }
      },
    );
  });
}
