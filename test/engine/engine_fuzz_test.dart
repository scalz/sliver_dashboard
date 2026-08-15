import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

/// Shared invariant checks for engine mutations.
///
/// The engine's contract is small enough to state exhaustively, which is what
/// makes fuzzing worthwhile: any random input must satisfy all of it.
/// Renders a layout compactly enough to paste straight into a unit test.
///
/// A fuzz failure that only names the two offending items is a lead, not a
/// reproduction. Dumping the full input is what turns a run index into a
/// deterministic test case.
String describeLayout(List<LayoutItem> layout) => layout
    .map(
      (i) => "LayoutItem(id: '${i.id}', x: ${i.x}, y: ${i.y}, "
          'w: ${i.w}, h: ${i.h}'
          '${i.isStatic ? ', isStatic: true' : ''}),',
    )
    .join('\n  ');

void expectEngineInvariants(
  List<LayoutItem> before,
  List<LayoutItem> after, {
  required int cols,
  required CompactType compactType,
  required String reason,
}) {
  final dump = '\n--- input (cols $cols, $compactType) ---\n  '
      '${describeLayout(before)}'
      '\n--- output ---\n  ${describeLayout(after)}\n';
  // 1. No item created, dropped or renamed.
  expect(after.length, before.length, reason: '$reason — item count$dump');
  expect(
    after.map((i) => i.id).toSet(),
    before.map((i) => i.id).toSet(),
    reason: '$reason — id set',
  );

  // 2. Ascending id order: sliver child indices must stay stable across
  // frames, which is what keeps element identity (and therefore item state)
  // alive during a drag.
  final ids = after.map((i) => i.id).toList();
  expect(ids, [...ids]..sort(), reason: '$reason — id ordering$dump');

  // 3. Sizes are never altered by a move.
  final sizeBefore = {for (final i in before) i.id: '${i.w}x${i.h}'};
  for (final item in after) {
    expect(item.w, greaterThan(0), reason: '$reason — ${item.id} width');
    expect(item.h, greaterThan(0), reason: '$reason — ${item.id} height');
    expect(
      '${item.w}x${item.h}',
      sizeBefore[item.id],
      reason: '$reason — ${item.id} was resized by a move',
    );
  }

  // 4. Statics never move.
  final staticBefore = {
    for (final i in before)
      if (i.isStatic && !i.isSectionBarrier) i.id: '${i.x},${i.y}',
  };
  for (final item in after) {
    final was = staticBefore[item.id];
    if (was == null) continue;
    expect('${item.x},${item.y}', was, reason: '$reason — static ${item.id} moved$dump');
  }

  // 5. Non-negative coordinates.
  for (final item in after) {
    expect(item.x, greaterThanOrEqualTo(0), reason: '$reason — ${item.id}.x');
    expect(item.y, greaterThanOrEqualTo(0), reason: '$reason — ${item.id}.y');
  }

  // 6. Column containment.
  for (final item in after) {
    expect(
      item.x + item.w,
      lessThanOrEqualTo(cols),
      reason: '$reason — ${item.id} out of bounds$dump',
    );
  }

  // 7. Zero overlap — the central invariant, asserted on all three modes.
  //
  // It was once skipped for `CompactType.horizontal` while two defects were
  // open there. Both are fixed; re-narrowing this silently reopens them.
  for (var i = 0; i < after.length; i++) {
    for (var j = i + 1; j < after.length; j++) {
      final a = after[i];
      final b = after[j];
      final overlaps = a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
      expect(
        overlaps,
        isFalse,
        reason: '$reason — overlap between '
            '${a.id}(${a.x},${a.y},${a.w},${a.h}) and '
            '${b.id}(${b.x},${b.y},${b.w},${b.h})$dump',
      );
    }
  }
}

/// Builds a random, valid (0-overlap) layout.
///
/// Returns fewer items than requested when placement fails, which is fine:
/// the point is a varied corpus, not an exact count.
List<LayoutItem> randomLayout(
  Random rng, {
  required int cols,
  required int count,
  int rows = 8,
  double staticChance = 0,
}) {
  final layout = <LayoutItem>[];
  final occupied = <String>{};

  for (var i = 0; i < count; i++) {
    final w = 1 + rng.nextInt(min(3, cols));
    final h = 1 + rng.nextInt(3);
    for (var attempt = 0; attempt < 40; attempt++) {
      final x = rng.nextInt(cols - w + 1);
      final y = rng.nextInt(rows);
      var free = true;
      for (var dx = 0; dx < w && free; dx++) {
        for (var dy = 0; dy < h && free; dy++) {
          if (occupied.contains('${x + dx}:${y + dy}')) free = false;
        }
      }
      if (!free) continue;
      for (var dx = 0; dx < w; dx++) {
        for (var dy = 0; dy < h; dy++) {
          occupied.add('${x + dx}:${y + dy}');
        }
      }
      layout.add(
        LayoutItem(
          id: 'i$i',
          x: x,
          y: y,
          w: w,
          h: h,
          isStatic: rng.nextDouble() < staticChance,
        ),
      );
      break;
    }
  }

  layout.sort((a, b) => a.id.compareTo(b.id));
  return layout;
}

void main() {
  // Fixed seeds: a fuzz failure must be replayable from the reported run
  // index alone. A flaky invariant test is worse than no invariant test.
  const seed = 20260815;
  const runs = 200;

  // All three modes. `CompactType.horizontal` used to be excluded here: its
  // collision resolution was column-blind and broke both column containment
  // and zero overlap. Keeping it in this list is now the regression guard for
  // that fix — do not narrow it again.
  const modes = CompactType.values;

  group('moveElement — fuzz', () {
    test('$runs random single moves preserve every engine invariant', () {
      final rng = Random(seed);

      for (var run = 0; run < runs; run++) {
        final cols = 4 + rng.nextInt(5);
        final layout = randomLayout(
          rng,
          cols: cols,
          count: 3 + rng.nextInt(7),
          staticChance: 0.15,
        );
        if (layout.length < 2) continue;

        final compactType = modes[rng.nextInt(modes.length)];
        final mover = layout[rng.nextInt(layout.length)];
        final targetX = rng.nextInt(cols - mover.w + 1);
        final targetY = rng.nextInt(8);
        final preventCollision = rng.nextBool();

        final result = moveElement(
          layout,
          mover,
          targetX,
          targetY,
          cols: cols,
          compactType: compactType,
          isUserAction: true,
          preventCollision: preventCollision,
        );

        expectEngineInvariants(
          layout,
          result,
          cols: cols,
          compactType: compactType,
          reason: 'moveElement run $run (cols $cols, $compactType) '
              'move ${mover.id} -> ($targetX,$targetY) '
              'preventCollision=$preventCollision',
        );
      }
    });
  });

  group('moveCluster — fuzz', () {
    test('$runs random cluster moves preserve every engine invariant', () {
      final rng = Random(seed + 1);

      for (var run = 0; run < runs; run++) {
        final cols = 4 + rng.nextInt(5);
        final layout = randomLayout(
          rng,
          cols: cols,
          count: 3 + rng.nextInt(7),
          staticChance: 0.15,
        );
        if (layout.length < 2) continue;

        // A cluster of 1..3 arbitrary items, which is what a multi-selection
        // drag produces. Statics are included on purpose: `moveCluster` is
        // documented to treat them as obstacles rather than members, and that
        // is exactly the kind of rule a fuzz should hold to.
        final clusterIds = <String>{};
        final clusterSize = 1 + rng.nextInt(3);
        for (var k = 0; k < clusterSize; k++) {
          clusterIds.add(layout[rng.nextInt(layout.length)].id);
        }

        final compactType = modes[rng.nextInt(modes.length)];

        // Clamp the target to the CLUSTER BOUNDING BOX, not to a single item.
        // `moveCluster`'s contract is that the caller hands it a target the
        // cluster fits in — `onDragUpdate` clamps before calling — so feeding
        // it an impossible one tests nothing but the absence of a defensive
        // clamp it never promised.
        final members = layout.where((i) => clusterIds.contains(i.id));
        final bboxLeft = members.map((i) => i.x).reduce(min);
        final bboxRight = members.map((i) => i.x + i.w).reduce(max);
        final bboxW = bboxRight - bboxLeft;
        if (bboxW > cols) continue;
        final targetX = rng.nextInt(cols - bboxW + 1);
        final targetY = rng.nextInt(8);
        final preventCollision = rng.nextBool();

        final result = moveCluster(
          layout,
          clusterIds,
          targetX,
          targetY,
          cols: cols,
          compactType: compactType,
          preventCollision: preventCollision,
          allowAutoShrink: false,
        );

        expectEngineInvariants(
          layout,
          result,
          cols: cols,
          compactType: compactType,
          reason: 'moveCluster run $run '
              '(cols $cols, $compactType, cluster $clusterIds) '
              '-> ($targetX,$targetY) preventCollision=$preventCollision',
        );
      }
    });

    test('$runs random cluster moves are idempotent at the same target', () {
      // Replaying the same move on the same input must land on the same
      // layout. `onDragUpdate` recomputes from the pre-drag snapshot on every
      // pointer event, so a non-deterministic engine would make a stationary
      // cursor shuffle the grid.
      final rng = Random(seed + 2);

      for (var run = 0; run < runs; run++) {
        final cols = 4 + rng.nextInt(5);
        final layout = randomLayout(rng, cols: cols, count: 3 + rng.nextInt(7));
        if (layout.length < 2) continue;

        final pivot = layout[rng.nextInt(layout.length)];
        final clusterIds = {pivot.id};
        final compactType = modes[rng.nextInt(modes.length)];
        final targetX = rng.nextInt(cols - pivot.w + 1);
        final targetY = rng.nextInt(8);

        List<LayoutItem> run1() => moveCluster(
              layout,
              clusterIds,
              targetX,
              targetY,
              cols: cols,
              compactType: compactType,
            );

        final a = run1();
        final b = run1();
        expect(
          a.map((i) => '${i.id}:${i.x},${i.y},${i.w},${i.h}').join('|'),
          b.map((i) => '${i.id}:${i.x},${i.y},${i.w},${i.h}').join('|'),
          reason: 'moveCluster run $run is not deterministic',
        );
      }
    });
  });
}
