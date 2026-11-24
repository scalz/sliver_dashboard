import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart' as engine;
import 'package:sliver_dashboard/src/models/dashboard_policy.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/nested/dashboard_nested_scope.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';

// Repeated onResizeStart/update calls read better unchained.
// ignore_for_file: cascade_invocations

/// Allows a fixed set of sizes (plus, by contract, an item's own size).
class _Sizes extends DashboardPolicy {
  _Sizes(this.allowed);

  final Set<(int, int)> allowed;
  int calls = 0;

  @override
  bool isSizeAllowed(LayoutItem item, int w, int h) {
    calls++;
    return allowed.contains((w, h));
  }
}

const double _slot = 100;

final Set<(int, int)> _everySize = {
  for (var w = 1; w <= 8; w++)
    for (var h = 1; h <= 8; h++) (w, h),
};

void main() {
  DashboardControllerImpl build({
    List<LayoutItem>? layout,
    Set<(int, int)> allowed = const {(1, 1), (2, 2), (4, 2), (2, 4)},
    int slotCount = 8,
    bool fluid = false,
    Axis axis = Axis.vertical,
  }) {
    final c = DashboardController(
      initialSlotCount: slotCount,
      initialLayout:
          layout ?? const [LayoutItem(id: 'a', x: 2, y: 2, w: 2, h: 2, minW: 1, minH: 1)],
    ) as DashboardControllerImpl;
    c
      ..policy = _Sizes(allowed)
      ..setFluidResize(fluid)
      ..scrollDirection.value = axis;
    addTearDown(c.dispose);
    return c;
  }

  void update(
    DashboardControllerImpl c,
    ResizeHandle handle,
    Offset delta, {
    double mainAxisSpacing = 0,
    double crossAxisSpacing = 0,
  }) {
    c.onResizeUpdate(
      'a',
      handle,
      delta,
      slotWidth: _slot,
      slotHeight: _slot,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
    );
  }

  LayoutItem itemA(DashboardControllerImpl c) => c.layout.value.firstWhere((i) => i.id == 'a');

  bool overlapFree(List<LayoutItem> l) {
    for (var i = 0; i < l.length; i++) {
      for (var j = i + 1; j < l.length; j++) {
        if (engine.collides(l[i], l[j])) return false;
      }
    }
    return true;
  }

  group('resize — the snapped size is always allowed', () {
    for (final handle in ResizeHandle.values) {
      test('$handle never lands on a refused size', () {
        final c = build();
        c.onResizeStart('a');
        for (var dx = -260.0; dx <= 260; dx += 37) {
          for (var dy = -260.0; dy <= 260; dy += 41) {
            update(c, handle, Offset(dx, dy));
            final a = itemA(c);
            expect(
              {(1, 1), (2, 2), (4, 2), (2, 4)}.contains((a.w, a.h)),
              isTrue,
              reason: '$handle with ($dx, $dy) gave ${a.w}x${a.h}',
            );
            expect(overlapFree(c.layout.value), isTrue);
          }
        }
      });
    }
  });

  group('resize — a refused size is skipped', () {
    test('a short pull stays on the current size', () {
      final c = build();
      c.onResizeStart('a');
      update(c, ResizeHandle.right, const Offset(60, 0)); // fw 2.6 -> 3 refused
      expect((itemA(c).w, itemA(c).h), (2, 2));
    });

    test('a long pull jumps over the refused width', () {
      final c = build();
      c.onResizeStart('a');
      update(c, ResizeHandle.right, const Offset(160, 0)); // fw 3.6 -> 4
      expect((itemA(c).x, itemA(c).w, itemA(c).h), (2, 4, 2));
    });

    test('the anchored left edge keeps the right edge in place', () {
      final c = build();
      c.onResizeStart('a');
      update(c, ResizeHandle.left, const Offset(-160, 0));
      final a = itemA(c);
      expect((a.x, a.w), (0, 4));
      expect(a.x + a.w, 4, reason: 'right edge is the anchor');
    });

    test('the anchored top edge keeps the bottom edge in place', () {
      final c = build();
      c.onResizeStart('a');
      update(c, ResizeHandle.top, const Offset(0, -160)); // fh 3.6 -> 4, y = 0
      final a = itemA(c);
      expect((a.y, a.h), (0, 4));
    });

    test('an allowed rounding is kept as is (no projection)', () {
      final c = build(allowed: _everySize);
      c.onResizeStart('a');
      update(c, ResizeHandle.bottomRight, const Offset(70, 130));
      expect((itemA(c).w, itemA(c).h), (3, 3));
    });

    test('a size reachable only past a static barrier is not taken', () {
      // Static at x=0..1: a left resize can grow a to w=3 at most, refused.
      final c = build(
        layout: const [
          LayoutItem(id: 'a', x: 2, y: 2, w: 2, h: 2, minW: 1, minH: 1),
          LayoutItem(id: 's', x: 0, y: 2, w: 1, h: 2, isStatic: true),
        ],
      );
      c.onResizeStart('a');
      update(c, ResizeHandle.left, const Offset(-200, 0));
      expect((itemA(c).x, itemA(c).w), (2, 2));
    });
  });

  test('a corner resize never takes a size that would cover a static the clamps miss', () {
    // a = (4,4) 2x2, anchored at right 6 / bottom 6. The static sits at
    // x 2..3, y 1..3: outside the Y barrier's x-range [3, 6) and the X
    // barrier's y-range [3, 6) of the rounded 3x3 probe, so no clamp sees it.
    // 3x3 is refused; 4x4 is nearest but its rect (x 2..6, y 2..6) covers the
    // static, so the item keeps its own 2x2.
    final c = build(
      allowed: {(2, 2), (4, 4)},
      layout: const [
        LayoutItem(id: 'a', x: 4, y: 4, w: 2, h: 2, minW: 1, minH: 1),
        LayoutItem(id: 's', x: 2, y: 1, w: 1, h: 2, isStatic: true),
      ],
    );
    c.onResizeStart('a');
    update(c, ResizeHandle.topLeft, const Offset(-150, -150));
    final a = itemA(c);
    expect((a.x, a.y, a.w, a.h), (4, 4, 2, 2));
    expect(overlapFree(c.layout.value), isTrue);

    // The same gesture without the static takes 4x4.
    final free = build(
      allowed: {(2, 2), (4, 4)},
      layout: const [
        LayoutItem(id: 'a', x: 4, y: 4, w: 2, h: 2, minW: 1, minH: 1),
      ],
    );
    free.onResizeStart('a');
    update(free, ResizeHandle.topLeft, const Offset(-150, -150));
    expect((itemA(free).w, itemA(free).h), (4, 4));
  });

  group('resize — cost', () {
    test('the policy is not consulted while the pointer stays in a cell', () {
      final c = build();
      final policy = c.policy! as _Sizes;
      c.onResizeStart('a');
      update(c, ResizeHandle.right, const Offset(60, 0));
      final after = policy.calls;
      expect(after, greaterThan(0));
      for (final dx in const [62.0, 65.0, 70.0, 74.0]) {
        update(c, ResizeHandle.right, Offset(dx, 0));
      }
      expect(policy.calls, after);
    });

    test('no policy: identical result and no projection', () {
      final withPolicy = build(allowed: _everySize);
      final without = DashboardController(
        initialSlotCount: 8,
        initialLayout: const [LayoutItem(id: 'a', x: 2, y: 2, w: 2, h: 2, minW: 1, minH: 1)],
      ) as DashboardControllerImpl;
      addTearDown(without.dispose);
      for (final handle in ResizeHandle.values) {
        withPolicy.onResizeStart('a');
        without.onResizeStart('a');
        update(withPolicy, handle, const Offset(137, -84));
        update(without, handle, const Offset(137, -84));
        expect(withPolicy.layout.value, without.layout.value, reason: '$handle');
        withPolicy.onResizeEnd('a');
        without.onResizeEnd('a');
      }
    });
  });

  group('resize — fluid ghost', () {
    test('the ghost tracks the raw pointer, the snapped item the allowed size', () {
      final c = build(fluid: true);
      c.onResizeStart('a');
      update(c, ResizeHandle.right, const Offset(60, 0));
      // Ghost: x = 2 slots, width = 2.6 slots, spacing 0.
      final rect = c.resizeGhostRect.value!;
      expect(rect.left, closeTo(200, 1e-9));
      expect(rect.width, closeTo(260, 1e-9));
      // Snapped (the settle target): still 2 wide.
      expect(itemA(c).w, 2);

      update(c, ResizeHandle.right, const Offset(160, 0));
      expect(c.resizeGhostRect.value!.width, closeTo(360, 1e-9));
      expect(itemA(c).w, 4);
    });
  });

  group('resize — horizontal grid, asymmetric spacings', () {
    // Horizontal: x runs along the MAIN axis, strideX = 100 + 20 = 120.
    // A 112 px pull is 0.93 slot: 2.93 -> refused 3 -> nearest allowed is 2.
    // The vertical convention (strideX = 100 + 4) would read 1.08 slot -> 4.
    test('the right edge uses the main-axis stride', () {
      final c = build(axis: Axis.horizontal);
      c.onResizeStart('a');
      update(c, ResizeHandle.right, const Offset(112, 0), mainAxisSpacing: 20, crossAxisSpacing: 4);
      expect(itemA(c).w, 2);
      update(c, ResizeHandle.right, const Offset(190, 0), mainAxisSpacing: 20, crossAxisSpacing: 4);
      expect(itemA(c).w, 4);
    });

    test('the bottom edge uses the cross-axis stride and the slot count', () {
      // slotCount 5 bounds y + h on a horizontal grid: h = 4 would end at 6.
      final c = build(axis: Axis.horizontal, slotCount: 5);
      c.onResizeStart('a');
      update(
        c,
        ResizeHandle.bottom,
        const Offset(0, 250),
        mainAxisSpacing: 20,
        crossAxisSpacing: 4,
      );
      final a = itemA(c);
      expect(a.y + a.h, lessThanOrEqualTo(5));
      expect((a.w, a.h), (2, 2));
    });
  });

  group('auto-shrink never produces a refused size', () {
    test('resize with ResizeBehavior.shrink falls back to a push', () {
      // a grows right into b; shrinking b to 1x1 is refused, so b is pushed.
      final layout = engine.resizeItem(
        const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1),
          LayoutItem(id: 'b', x: 2, y: 0, w: 2, h: 1),
        ],
        const LayoutItem(id: 'a', x: 0, y: 0, w: 3, h: 1),
        behavior: engine.ResizeBehavior.shrink,
        cols: 4,
        policy: _Sizes({(2, 1), (3, 1)}),
      );
      final b = layout.firstWhere((i) => i.id == 'b');
      expect((b.w, b.h), (2, 1));
      expect(overlapFree(layout), isTrue);
    });

    test('growing LEFT shrinks the neighbour from its right edge', () {
      List<LayoutItem> grow(Set<(int, int)> allowed) => engine.resizeItem(
            const [
              LayoutItem(id: 'a', x: 2, y: 0, w: 2, h: 1),
              LayoutItem(id: 'b', x: 0, y: 0, w: 2, h: 1),
            ],
            const LayoutItem(id: 'a', x: 1, y: 0, w: 3, h: 1),
            behavior: engine.ResizeBehavior.shrink,
            cols: 4,
            policy: _Sizes(allowed),
          );

      final shrunk = grow({(1, 1), (2, 1), (3, 1)}).firstWhere((i) => i.id == 'b');
      expect((shrunk.x, shrunk.w), (0, 1));

      final refused = grow({(2, 1), (3, 1)});
      final b = refused.firstWhere((i) => i.id == 'b');
      expect((b.w, b.h), (2, 1), reason: 'refused: b keeps its size and is pushed');
      expect(overlapFree(refused), isTrue);
    });

    test('the same shrink is applied when the size is allowed', () {
      final layout = engine.resizeItem(
        const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1),
          LayoutItem(id: 'b', x: 2, y: 0, w: 2, h: 1),
        ],
        const LayoutItem(id: 'a', x: 0, y: 0, w: 3, h: 1),
        behavior: engine.ResizeBehavior.shrink,
        cols: 4,
        policy: _Sizes({(1, 1), (2, 1), (3, 1)}),
      );
      final b = layout.firstWhere((i) => i.id == 'b');
      expect((b.x, b.w), (3, 1));
    });

    test('moveCluster with allowAutoShrink does not shrink to a refused height', () {
      const start = [
        LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1),
        LayoutItem(id: 'b', x: 0, y: 1, w: 2, h: 3),
      ];
      List<LayoutItem> move(Set<(int, int)> allowed) => engine.moveCluster(
            start,
            {'a'},
            0,
            1,
            cols: 4,
            compactType: engine.CompactType.none,
            allowAutoShrink: true,
            policy: _Sizes(allowed),
          );

      final shrunk = move({(2, 1), (2, 2), (2, 3)}).firstWhere((i) => i.id == 'b');
      expect(shrunk.h, 2, reason: 'allowed: b shrinks under a');

      final pushed = move({(2, 1), (2, 3)}).firstWhere((i) => i.id == 'b');
      expect(pushed.h, 3, reason: 'refused: b keeps its size');
    });
  });

  group('engine.nearestAllowedSize', () {
    test('returns the fallback when nothing nearer is allowed', () {
      final s = engine.nearestAllowedSize(
        w: 2.6,
        h: 2,
        minW: 1,
        maxW: 8,
        minH: 1,
        maxH: 8,
        isAllowed: (w, h) => false,
        fallback: (2, 2),
      );
      expect(s, (2, 2));
    });

    test('the fallback distance bounds the search', () {
      final seen = <(int, int)>{};
      engine.nearestAllowedSize(
        w: 3.2,
        h: 2,
        minW: 1,
        maxW: 10000,
        minH: 1,
        maxH: 10000,
        isAllowed: (w, h) {
          seen.add((w, h));
          return false;
        },
        fallback: (2, 2),
      );
      // Radius 1.2 around (3.2, 2): nothing at w >= 5 or h >= 4 is visited.
      expect(seen.every((s) => s.$1 <= 4 && s.$2 <= 3), isTrue, reason: '$seen');
    });

    test('ties: larger area, then smaller width', () {
      // (3,3) refused; (4,2) and (2,4) are both 2.0 away and both 8 slots.
      final s = engine.nearestAllowedSize(
        w: 3.1,
        h: 3.1,
        minW: 1,
        maxW: 8,
        minH: 1,
        maxH: 8,
        isAllowed: (w, h) => {(4, 2), (2, 4), (2, 2)}.contains((w, h)),
        fallback: (2, 2),
      );
      expect(s, (2, 4));
    });

    test('without a fallback the whole box is scanned, null when empty', () {
      expect(
        engine.nearestAllowedSize(
          w: 1,
          h: 1,
          minW: 1,
          maxW: 6,
          minH: 1,
          maxH: 6,
          isAllowed: (w, h) => w == 6 && h == 6,
        ),
        (6, 6),
      );
      expect(
        engine.nearestAllowedSize(
          w: 1,
          h: 1,
          minW: 1,
          maxW: 3,
          minH: 1,
          maxH: 3,
          isAllowed: (w, h) => false,
        ),
        isNull,
      );
    });
  });

  group('cross-grid projection honours the target allowed sizes (D1)', () {
    late DashboardNestedCoordinator coordinator;
    setUp(() => coordinator = DashboardNestedCoordinator());
    tearDown(() => coordinator.dispose());

    LayoutItem project(LayoutItem item, Set<(int, int)>? allowed, {int target = 8}) =>
        coordinator.projectItem(
          item,
          sourceSlotCount: 8,
          targetSlotCount: target,
          targetPolicy: allowed == null ? null : _Sizes(allowed),
        );

    test('a refused size becomes the nearest allowed one', () {
      final p = project(
        const LayoutItem(id: 'a', x: 0, y: 0, w: 3, h: 2),
        {(1, 1), (2, 2), (4, 2)},
      );
      // (3,2): (2,2) and (4,2) are both 1 away -> larger area wins.
      expect((p.w, p.h), (4, 2));
    });

    test('an allowed size is returned as the same instance', () {
      const item = LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2);
      expect(identical(project(item, {(2, 2)}), item), isTrue);
    });

    test('min constraints stay satisfiable after the fold', () {
      final p = project(
        const LayoutItem(id: 'a', x: 0, y: 0, w: 3, h: 3, minW: 3, minH: 3),
        {(1, 1)},
      );
      expect((p.w, p.h, p.minW, p.minH), (1, 1, 1, 1));
    });

    test('the fold stays inside the target width', () {
      // Only 6x1 is allowed but the target has 4 columns: nothing fits, the
      // item keeps its (sanitized) size.
      final p = project(const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1), {(6, 1)}, target: 4);
      expect((p.w, p.h), (2, 1));
    });

    test('no target policy: unchanged behaviour', () {
      final p = project(const LayoutItem(id: 'a', x: 0, y: 0, w: 3, h: 2), null);
      expect((p.w, p.h), (3, 2));
    });
  });

  test('fuzz: 100 random gestures never land on a refused size', () {
    final rnd = Random(42);
    for (var run = 0; run < 100; run++) {
      final allowed = <(int, int)>{
        for (var k = 0; k < 6; k++) (1 + rnd.nextInt(5), 1 + rnd.nextInt(5)),
      };
      final c = build(
        allowed: allowed,
        fluid: rnd.nextBool(),
        layout: [
          const LayoutItem(id: 'a', x: 2, y: 2, w: 2, h: 2, minW: 1, minH: 1),
          for (var i = 0; i < 8; i++)
            LayoutItem(id: 'n$i', x: rnd.nextInt(7), y: 5 + i * 2, w: 1 + rnd.nextInt(2), h: 1),
        ],
      );
      final handle = ResizeHandle.values[rnd.nextInt(ResizeHandle.values.length)];
      c.onResizeStart('a');
      for (var step = 0; step < 10; step++) {
        update(c, handle, Offset(rnd.nextDouble() * 500 - 250, rnd.nextDouble() * 500 - 250));
        final a = itemA(c);
        expect(
          (a.w == 2 && a.h == 2) || allowed.contains((a.w, a.h)),
          isTrue,
          reason: 'run $run, $handle: ${a.w}x${a.h} not in $allowed',
        );
        expect(overlapFree(c.layout.value), isTrue, reason: 'run $run');
        final ids = [for (final i in c.layout.value) i.id];
        expect(ids, [...ids]..sort(), reason: 'run $run: id order');
      }
      c.onResizeEnd('a');
    }
  });
}
