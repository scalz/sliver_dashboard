import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

import '../test_helpers.dart';

/// Fails when any two items in [layout] overlap — the invariant every engine
/// mutation must preserve.
void expectNoOverlap(List<LayoutItem> layout) {
  for (var i = 0; i < layout.length; i++) {
    for (var j = i + 1; j < layout.length; j++) {
      final a = layout[i];
      final b = layout[j];
      final overlaps = a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
      expect(
        overlaps,
        isFalse,
        reason: 'overlap between ${a.id}(${a.x},${a.y},${a.w},${a.h}) '
            'and ${b.id}(${b.x},${b.y},${b.w},${b.h})',
      );
    }
  }
}

void expectSortedById(List<LayoutItem> layout) {
  final ids = layout.map((i) => i.id).toList();
  final sorted = [...ids]..sort();
  expect(ids, sorted, reason: 'engine results must stay id-sorted');
}

LayoutItem? byId(List<LayoutItem> layout, String id) {
  for (final item in layout) {
    if (item.id == id) return item;
  }
  return null;
}

/// A policy whose vetoes can be aimed at one specific item.
///
/// `swapElements` asks three separate questions, and a policy that answered
/// them uniformly could not tell them apart — hence the per-id targeting.
class _VetoPolicy extends DashboardPolicy {
  const _VetoPolicy({this.allowCollision = true, this.blockMoveOf = const <String>{}});

  final bool allowCollision;
  final Set<String> blockMoveOf;

  @override
  bool canCollide(LayoutItem itemA, LayoutItem itemB) => allowCollision;

  @override
  bool canMoveTo(
    LayoutItem item,
    int targetX,
    int targetY,
    List<LayoutItem> currentLayout,
  ) =>
      !blockMoveOf.contains(item.id);
}

/// Records what the engine asked, to pin down the argument order.
class _RecordingPolicy extends DashboardPolicy {
  final collisionChecks = <String>[];
  final moveChecks = <String>[];

  @override
  bool canCollide(LayoutItem itemA, LayoutItem itemB) {
    collisionChecks.add('${itemA.id}/${itemB.id}');
    return true;
  }

  @override
  bool canMoveTo(
    LayoutItem item,
    int targetX,
    int targetY,
    List<LayoutItem> currentLayout,
  ) {
    moveChecks.add('${item.id}->$targetX,$targetY');
    return true;
  }
}

void main() {
  group('swapElements — qualification', () {
    const cols = 8;

    test('exchanges positions on a full same-size cover', () {
      const layout = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
        LayoutItem(id: 'b', x: 4, y: 0, w: 2, h: 2),
      ];

      final result = swapElements(
        layout,
        layout[0],
        4,
        0,
        cols: cols,
        compactType: CompactType.vertical,
      )!;

      expect(byId(result, 'a')!.x, 4);
      expect(byId(result, 'a')!.y, 0);
      expect(byId(result, 'b')!.x, 0);
      expect(byId(result, 'b')!.y, 0);
      expectNoOverlap(result);
      expectSortedById(result);
    });

    test('the partner lands on the mover ORIGINAL slot, not the target', () {
      // The mover starts at (1,3). Landing it on b must send b to (1,3),
      // not to the coordinates the drag is requesting.
      const layout = [
        LayoutItem(id: 'a', x: 1, y: 3, w: 1, h: 1),
        LayoutItem(id: 'b', x: 5, y: 0, w: 1, h: 1),
      ];

      final result = swapElements(
        layout,
        layout[0],
        5,
        0,
        cols: cols,
        compactType: CompactType.vertical,
      )!;

      expect(byId(result, 'b')!.x, 1);
      expect(byId(result, 'b')!.y, 3);
      expect(byId(result, 'a')!.x, 5);
      expect(byId(result, 'a')!.y, 0);
    });

    test('returns null over empty space', () {
      const layout = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 5, y: 0, w: 1, h: 1),
      ];

      expect(
        swapElements(
          layout,
          layout[0],
          2,
          4,
          cols: cols,
          compactType: CompactType.vertical,
        ),
        isNull,
      );
    });

    test('returns null at exactly the threshold, swaps just above it', () {
      // A 2x1 mover over a 2x1 target: one column of overlap is exactly 50%
      // of the target's area, which does NOT qualify (strictly greater).
      const layout = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1),
        LayoutItem(id: 'b', x: 4, y: 0, w: 2, h: 1),
      ];

      expect(
        swapElements(
          layout,
          layout[0],
          5,
          0,
          cols: cols,
          compactType: CompactType.vertical,
        ),
        isNull,
        reason: '50% coverage is not > 50%',
      );
      expect(
        swapElements(
          layout,
          layout[0],
          4,
          0,
          cols: cols,
          compactType: CompactType.vertical,
        ),
        isNotNull,
        reason: '100% coverage qualifies',
      );
    });

    test('coverage is measured against the CANDIDATE area', () {
      // A 1x1 fully inside a 4x4: 1/16 of the target -> no swap, even though
      // 100% of the mover is covered. Measuring against the mover instead
      // would make every small tile swap the moment it touches a large one.
      const layout = [
        LayoutItem(id: 'small', x: 0, y: 6, w: 1, h: 1),
        LayoutItem(id: 'big', x: 0, y: 0, w: 4, h: 4),
      ];

      expect(
        swapElements(
          layout,
          layout[0],
          1,
          1,
          cols: cols,
          compactType: CompactType.vertical,
        ),
        isNull,
      );
    });

    test('picks the best-covered candidate deterministically', () {
      const layout = [
        LayoutItem(id: 'mover', x: 0, y: 4, w: 2, h: 1),
        LayoutItem(id: 'left', x: 2, y: 0, w: 1, h: 1),
        LayoutItem(id: 'right', x: 3, y: 0, w: 1, h: 1),
      ];

      // Landing at (3,0) fully covers "right" and misses "left".
      final result = swapElements(
        layout,
        layout[0],
        3,
        0,
        cols: cols,
        compactType: CompactType.vertical,
      )!;

      expect(byId(result, 'right')!.x, 0);
      expect(byId(result, 'right')!.y, 4);
      expect(byId(result, 'left')!.x, 2, reason: 'untouched');
      expect(byId(result, 'left')!.y, 0);
    });

    test('better coverage wins over an earlier candidate', () {
      // Two qualifying candidates in one probe. Without this, `best == null`
      // short-circuits on the first one and the ratio comparison in the
      // ordering rule is never evaluated at all.
      //
      // Probe = m at (4,0) spanning x4..6:
      //   wide (x5..7) -> 2 of 3 cells = 67%
      //   exact (x4)   -> 1 of 1 cell  = 100%  <- must win
      const layout = [
        LayoutItem(id: 'm', x: 0, y: 0, w: 3, h: 1),
        LayoutItem(id: 'wide', x: 5, y: 0, w: 3, h: 1),
        LayoutItem(id: 'exact', x: 4, y: 0, w: 1, h: 1),
      ];

      final result = swapElements(
        layout,
        layout[0],
        4,
        0,
        cols: cols,
        compactType: CompactType.vertical,
      )!;

      expect(byId(result, 'exact')!.x, 0, reason: '100% beats 67%');
      expect(byId(result, 'exact')!.y, 0);
      expectNoOverlap(result);
    });

    test('equal coverage breaks on the larger absolute overlap', () {
      // Both candidates are fully covered (ratio 1.0), so the tie falls to
      // the number of cells actually overlapped.
      //
      // Probe = m at (4,0) spanning x4..6:
      //   small (x4)    -> 1 of 1 = 100%, overlap 1
      //   pair  (x5..6) -> 2 of 2 = 100%, overlap 2  <- must win
      const layout = [
        LayoutItem(id: 'm', x: 0, y: 0, w: 3, h: 1),
        LayoutItem(id: 'small', x: 4, y: 0, w: 1, h: 1),
        LayoutItem(id: 'pair', x: 5, y: 0, w: 2, h: 1),
      ];

      final result = swapElements(
        layout,
        layout[0],
        4,
        0,
        cols: cols,
        compactType: CompactType.vertical,
      )!;

      expect(byId(result, 'pair')!.x, 0, reason: 'overlap 2 beats overlap 1');
      expect(byId(result, 'small')!.x, 4, reason: 'the loser does not move');
    });

    test('a perfect tie breaks on the lower id, whatever the layout order', () {
      // Same ratio AND same overlap: the last clause of the ordering rule.
      // Declared with the high id first so a stable result proves the
      // tie-break ran rather than the iteration order deciding.
      const layout = [
        LayoutItem(id: 'm', x: 0, y: 0, w: 2, h: 1),
        LayoutItem(id: 'zz', x: 4, y: 0, w: 1, h: 1),
        LayoutItem(id: 'aa', x: 5, y: 0, w: 1, h: 1),
      ];

      final result = swapElements(
        layout,
        layout[0],
        4,
        0,
        cols: cols,
        compactType: CompactType.vertical,
      )!;

      expect(byId(result, 'aa')!.x, 0, reason: 'lower id wins the tie');
      expect(byId(result, 'zz')!.x, 4, reason: 'the loser does not move');

      // And the mirror: reversing the declaration order must not change it.
      const mirrored = [
        LayoutItem(id: 'm', x: 0, y: 0, w: 2, h: 1),
        LayoutItem(id: 'aa', x: 5, y: 0, w: 1, h: 1),
        LayoutItem(id: 'zz', x: 4, y: 0, w: 1, h: 1),
      ];
      final mirroredResult = swapElements(
        mirrored,
        mirrored[0],
        4,
        0,
        cols: cols,
        compactType: CompactType.vertical,
      )!;
      expect(byId(mirroredResult, 'aa')!.x, 0);
    });

    test('refuses to swap with a static item', () {
      const layout = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'fixed', x: 5, y: 0, w: 1, h: 1, isStatic: true),
      ];

      expect(
        swapElements(
          layout,
          layout[0],
          5,
          0,
          cols: cols,
          compactType: CompactType.vertical,
        ),
        isNull,
      );
    });

    test('refuses to move a static mover', () {
      const layout = [
        LayoutItem(id: 'fixed', x: 0, y: 0, w: 1, h: 1, isStatic: true),
        LayoutItem(id: 'b', x: 5, y: 0, w: 1, h: 1),
      ];

      expect(
        swapElements(
          layout,
          layout[0],
          5,
          0,
          cols: cols,
          compactType: CompactType.vertical,
        ),
        isNull,
      );
    });

    test('a permissive policy does not get in the way', () {
      const layout = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 4, y: 0, w: 1, h: 1),
      ];

      final result = swapElements(
        layout,
        layout[0],
        4,
        0,
        cols: cols,
        compactType: CompactType.vertical,
        policy: const _VetoPolicy(),
      )!;

      expect(byId(result, 'a')!.x, 4);
      expect(byId(result, 'b')!.x, 0);
    });

    test('a canCollide veto blocks the swap', () {
      const layout = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 4, y: 0, w: 1, h: 1),
      ];

      expect(
        swapElements(
          layout,
          layout[0],
          4,
          0,
          cols: cols,
          compactType: CompactType.vertical,
          policy: const _VetoPolicy(allowCollision: false),
        ),
        isNull,
      );
    });

    test('a canMoveTo veto on the PARTNER blocks the swap', () {
      // The partner is sent to the mover's slot without being dragged, so it
      // must clear the policy just like the mover does — otherwise a locked
      // tile could be relocated by dropping something on it.
      const layout = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 4, y: 0, w: 1, h: 1),
      ];

      expect(
        swapElements(
          layout,
          layout[0],
          4,
          0,
          cols: cols,
          compactType: CompactType.vertical,
          policy: const _VetoPolicy(blockMoveOf: {'b'}),
        ),
        isNull,
      );
    });

    test('a canMoveTo veto on the MOVER blocks the swap', () {
      const layout = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 4, y: 0, w: 1, h: 1),
      ];

      expect(
        swapElements(
          layout,
          layout[0],
          4,
          0,
          cols: cols,
          compactType: CompactType.vertical,
          policy: const _VetoPolicy(blockMoveOf: {'a'}),
        ),
        isNull,
      );
    });

    test('the policy is asked about the right items and coordinates', () {
      const layout = [
        LayoutItem(id: 'a', x: 1, y: 3, w: 1, h: 1),
        LayoutItem(id: 'b', x: 5, y: 0, w: 1, h: 1),
      ];
      final policy = _RecordingPolicy();

      swapElements(
        layout,
        layout[0],
        5,
        0,
        cols: cols,
        compactType: CompactType.vertical,
        policy: policy,
      );

      expect(policy.collisionChecks, ['a/b']);
      // The partner is asked about the MOVER's pre-drag slot, the mover about
      // the requested target. Swapping these two would validate the move that
      // is not about to happen.
      expect(policy.moveChecks, ['b->1,3', 'a->5,0']);
    });

    test('the policy is never consulted when nothing qualifies', () {
      const layout = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 5, y: 0, w: 1, h: 1),
      ];
      final policy = _RecordingPolicy();

      // Empty space: no candidate, so the cheap geometry rejects before any
      // user code runs.
      expect(
        swapElements(
          layout,
          layout[0],
          2,
          4,
          cols: cols,
          compactType: CompactType.vertical,
          policy: policy,
        ),
        isNull,
      );
      expect(policy.collisionChecks, isEmpty);
      expect(policy.moveChecks, isEmpty);
    });

    test('restores the 0-overlap invariant when sizes differ', () {
      // Coverage is measured against the CANDIDATE, so a 1x1 landing on a
      // 2x2 covers only 25% and never swaps at all — the residual-overlap
      // case is a mover landing on a partner slightly LARGER than itself.
      // The partner then lands on the mover's narrower original slot and
      // spills onto a third tile that was perfectly placed before.
      //
      // a (2 wide) covers 2 of b's 3 cells = 67% > 50%.
      // b then goes to x=0..2 and collides with c at x=2.
      const layout = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1),
        LayoutItem(id: 'c', x: 2, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 4, y: 0, w: 3, h: 1),
      ];

      final result = swapElements(
        layout,
        layout[0],
        4,
        0,
        cols: cols,
        compactType: CompactType.vertical,
      )!;

      expect(byId(result, 'a')!.x, 4);
      expect(byId(result, 'b')!.x, 0);
      expect(
        byId(result, 'c')!.y,
        greaterThan(0),
        reason: 'the bystander must have been pushed, proving resolution ran',
      );
      expectNoOverlap(result);
      expectSortedById(result);
      expect(result.length, 3, reason: 'no item created or dropped');
    });

    test('resolves a bystander clipped by an EQUAL-size swap', () {
      // Regression: the resolution used to be gated on the two items having
      // different sizes. But the probe can qualify against one item while
      // merely clipping another it is not allowed to swap with — and that
      // bystander never moves. An equal-size exchange therefore landed on
      // top of it and returned an overlapping layout.
      //
      // Probe = a at (4,1) spanning y1..3:
      //   vs b (y0..2) -> 2 of 3 cells = 67%, qualifies as the partner;
      //   vs c (y3..4) -> 1 of 2 cells = 50%, does NOT qualify, but overlaps.
      const layout = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 3),
        LayoutItem(id: 'b', x: 4, y: 0, w: 1, h: 3),
        LayoutItem(id: 'c', x: 4, y: 3, w: 1, h: 2),
      ];

      final result = swapElements(
        layout,
        layout[0],
        4,
        1,
        cols: cols,
        compactType: CompactType.vertical,
      )!;

      expect(byId(result, 'b')!.y, 0, reason: 'partner takes the mover slot');
      expect(byId(result, 'b')!.x, 0);
      expect(
        byId(result, 'c')!.y,
        greaterThan(3),
        reason: 'the clipped bystander must be pushed out of the way',
      );
      expectNoOverlap(result);
      expectSortedById(result);
      expect(result.length, 3);
    });

    test('clamps the partner inside the grid', () {
      // The mover sits at x = 6 in an 8-column grid, and is 2 wide so it
      // covers 2 of the partner's 3 cells (67%). The 3-wide partner cannot
      // start at x = 6 without spilling past the last column.
      const layout = [
        LayoutItem(id: 'a', x: 6, y: 0, w: 2, h: 1),
        LayoutItem(id: 'wide', x: 0, y: 3, w: 3, h: 1),
      ];

      final result = swapElements(
        layout,
        layout[0],
        0,
        3,
        cols: cols,
        compactType: CompactType.vertical,
      )!;

      final wide = byId(result, 'wide')!;
      expect(wide.x, cols - wide.w, reason: 'clamped, not left at x = 6');
      expect(wide.x + wide.w, lessThanOrEqualTo(cols));
      expect(wide.x, greaterThanOrEqualTo(0));
      expect(byId(result, 'a')!.x, 0);
      expectNoOverlap(result);
    });
  });

  group('swapElements — fuzz', () {
    test('100 random swaps keep 0 overlap, id order and item count', () {
      // Fixed seed: a failure must be replayable, and a flaky invariant test
      // is worse than no test.
      final rng = Random(20260815);
      const cols = 6;

      for (var run = 0; run < 100; run++) {
        final layout = <LayoutItem>[];
        final occupied = <String>{};
        final count = 3 + rng.nextInt(6);

        for (var i = 0; i < count; i++) {
          final w = 1 + rng.nextInt(3);
          final h = 1 + rng.nextInt(3);
          for (var attempt = 0; attempt < 40; attempt++) {
            final x = rng.nextInt(cols - w + 1);
            final y = rng.nextInt(8);
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
            layout.add(LayoutItem(id: 'i$i', x: x, y: y, w: w, h: h));
            break;
          }
        }

        if (layout.length < 2) continue;
        expectNoOverlap(layout);

        final mover = layout[rng.nextInt(layout.length)];
        final targetX = rng.nextInt(cols - mover.w + 1);
        final targetY = rng.nextInt(8);

        final compactType = rng.nextBool() ? CompactType.vertical : CompactType.horizontal;

        final result = swapElements(
          layout,
          mover,
          targetX,
          targetY,
          cols: cols,
          compactType: compactType,
        );

        if (result == null) continue;

        expectNoOverlap(result);
        expectSortedById(result);
        expect(
          result.length,
          layout.length,
          reason: 'run $run created or dropped an item',
        );
        expect(
          result.map((i) => i.id).toSet(),
          layout.map((i) => i.id).toSet(),
          reason: 'run $run changed the id set',
        );
        for (final item in result) {
          expect(item.x, greaterThanOrEqualTo(0), reason: 'run $run');
          expect(item.y, greaterThanOrEqualTo(0), reason: 'run $run');
          if (compactType == CompactType.vertical) {
            // Column containment only holds under vertical resolution, which
            // pushes on y and never touches x.
            //
            // `_resolveCollisionsDefault` in horizontal mode pushes an
            // obstacle to `obstacle.x + obstacle.w` with NO column bound, so
            // it can carry an item past the last column. That is pre-existing
            // engine behaviour shared with `moveElement`, not something swap
            // introduces, and clamping afterwards is not a fix — it would put
            // the item back on top of whatever it was pushed off.
            expect(item.x + item.w, lessThanOrEqualTo(cols), reason: 'run $run');
          }
        }
      }
    });
  });

  group('getEffectiveDragMode', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 8,
        initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
      );
    });

    test('defaults to cascade — the package behaviour is unchanged', () {
      expect(controller.dragMode.value, DragMode.cascade);
      expect(controller.getEffectiveDragMode(), DragMode.cascade);
    });

    test('the modifier selects the opposite of the default, both ways', () {
      expect(
        controller.getEffectiveDragMode(modifierHeld: true),
        DragMode.swap,
      );

      controller.setDragMode(DragMode.swap);
      expect(controller.getEffectiveDragMode(), DragMode.swap);
      expect(
        controller.getEffectiveDragMode(modifierHeld: true),
        DragMode.cascade,
      );
    });

    test('falls back to the swapModifierHeld beacon when unspecified', () {
      controller.swapModifierHeld.value = true;
      expect(controller.getEffectiveDragMode(), DragMode.swap);

      controller.swapModifierHeld.value = false;
      expect(controller.getEffectiveDragMode(), DragMode.cascade);
    });

    test('an explicit argument overrides the beacon', () {
      controller.swapModifierHeld.value = true;
      expect(
        controller.getEffectiveDragMode(modifierHeld: false),
        DragMode.cascade,
      );
    });
  });

  group('swap mode — drag integration', () {
    late DashboardController controller;
    late ScrollController scrollController;

    const padding = EdgeInsets.all(20);
    // 800 - 40 = 760 cross extent, slotCount 8, spacing 8 -> slot 88, stride 96.
    const stride = 96.0;

    Offset cell(int x, int y) => Offset(
          padding.left + x * stride + 44,
          padding.top + y * stride + 44,
        );

    Future<void> pump(WidgetTester tester, {DragMode mode = DragMode.cascade}) async {
      controller = DashboardController(
        initialSlotCount: 8,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'b', x: 4, y: 0, w: 1, h: 1),
        ],
      );
      addTearDown(controller.dispose);
      controller
        ..setEditMode(true)
        ..setDragMode(mode)
        ..lassoStyle = LassoStyle.off;
      scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Dashboard<String>(
            controller: controller,
            scrollController: scrollController,
            breakpoints: null,
            padding: padding,
            slotAspectRatio: 1,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            itemBuilder: (context, item) => ColoredBox(
              color: Colors.blueGrey,
              child: Center(child: Text(item.id)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('cascade is the default: dragging a onto b pushes b away', (tester) async {
      await runOnDesktop(() async {
        await pump(tester);

        final gesture = await tester.startGesture(cell(0, 0), kind: PointerDeviceKind.mouse);
        await tester.pump();
        await gesture.moveTo(cell(4, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        // b was displaced rather than exchanged: it did not take a's slot.
        expect(byId(controller.layout.value, 'b')!.x, isNot(0));
      });
    });

    testWidgets('DragMode.swap exchanges positions', (tester) async {
      await runOnDesktop(() async {
        await pump(tester, mode: DragMode.swap);

        final gesture = await tester.startGesture(cell(0, 0), kind: PointerDeviceKind.mouse);
        await tester.pump();
        await gesture.moveTo(cell(4, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(byId(controller.layout.value, 'a')!.x, 4);
        expect(byId(controller.layout.value, 'b')!.x, 0);
        expectNoOverlap(controller.layout.value);
      });
    });

    testWidgets('holding Shift mid-drag switches to swap without moving the pointer',
        (tester) async {
      await runOnDesktop(() async {
        await pump(tester);

        final gesture = await tester.startGesture(cell(0, 0), kind: PointerDeviceKind.mouse);
        await tester.pump();
        await gesture.moveTo(cell(4, 0));
        await tester.pump();

        // Cascade so far: b has been pushed off its slot.
        expect(byId(controller.layout.value, 'b')!.x, isNot(0));

        // The pointer does NOT move. This is the case the boundary bypass
        // would swallow if the effective mode were not part of its key.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        try {
          await tester.pump();
          expect(controller.getEffectiveDragMode(), DragMode.swap);
          expect(
            byId(controller.layout.value, 'b')!.x,
            0,
            reason: 'the mode flip must re-run the layout immediately',
          );
        } finally {
          await gesture.up();
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.pumpAndSettle();
      });
    });

    testWidgets('releasing Shift mid-drag returns to cascade', (tester) async {
      await runOnDesktop(() async {
        await pump(tester);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        final gesture = await tester.startGesture(cell(0, 0), kind: PointerDeviceKind.mouse);
        await tester.pump();
        await gesture.moveTo(cell(4, 0));
        await tester.pump();

        // The key was already held at drag start, so no key event fired during
        // the drag: the seeding path is what makes this work.
        expect(byId(controller.layout.value, 'b')!.x, 0);

        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(byId(controller.layout.value, 'b')!.x, isNot(0));

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('an empty swapModeModifier disables the toggle', (tester) async {
      await runOnDesktop(() async {
        await pump(tester);
        controller.shortcuts = const DashboardShortcuts(swapModeModifier: []);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        try {
          final gesture = await tester.startGesture(cell(0, 0), kind: PointerDeviceKind.mouse);
          await tester.pump();
          await gesture.moveTo(cell(4, 0));
          await tester.pump();
          expect(controller.getEffectiveDragMode(), DragMode.cascade);
          await gesture.up();
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.pumpAndSettle();
      });
    });

    testWidgets('swap never applies to a multi-item drag', (tester) async {
      await runOnDesktop(() async {
        await pump(tester, mode: DragMode.swap);
        controller.selectedItemIds.value = {'a', 'b'};

        final gesture = await tester.startGesture(cell(0, 0), kind: PointerDeviceKind.mouse);
        await tester.pump();
        await gesture.moveTo(cell(1, 0));
        await tester.pump();

        // onDragStart reduces the selection to the pivot unless the pivot is
        // already selected; here it is, so the cluster survives and the drag
        // must stay in cascade.
        expect(controller.selectedItemIds.value.length, greaterThan(1));
        expectNoOverlap(controller.layout.value);

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });
  });
}
