import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';

//
// ignore_for_file: cascade_invocations

/// Slot geometry used by every case below: stride 100 px on both axes, so a
/// pixel delta reads directly as a fraction of a slot.
const double _slot = 100;

void main() {
  /// Runs one resize update with the shared geometry.
  void update(
    DashboardControllerImpl controller,
    ResizeHandle handle,
    Offset delta, {
    double crossAxisSpacing = 0,
    double mainAxisSpacing = 0,
    double slotWidth = _slot,
    double slotHeight = _slot,
  }) {
    controller.onResizeUpdate(
      'a',
      handle,
      delta,
      slotWidth: slotWidth,
      slotHeight: slotHeight,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
    );
  }

  DashboardControllerImpl build({
    List<LayoutItem>? layout,
    int slotCount = 8,
    bool fluid = true,
  }) {
    final controller = DashboardController(
      initialSlotCount: slotCount,
      initialLayout: layout ??
          const [
            LayoutItem(id: 'a', x: 2, y: 2, w: 2, h: 2, minW: 1, minH: 1),
          ],
    ) as DashboardControllerImpl;
    controller.setFluidResize(fluid);
    return controller;
  }

  group('fluid resize — the snapped result is unchanged', () {
    // The feature may only change what is PAINTED. If any of these diverge,
    // the continuous candidate and its rounding have drifted apart.
    for (final handle in ResizeHandle.values) {
      test('$handle produces the same layout with the preview on and off', () {
        for (final delta in const [
          Offset(137, -84),
          Offset(-212, 260),
          Offset(49, 51),
        ]) {
          final off = build(fluid: false);
          final on = build();
          addTearDown(off.dispose);
          addTearDown(on.dispose);

          off.onResizeStart('a');
          on.onResizeStart('a');
          update(off, handle, delta);
          update(on, handle, delta);

          expect(
            on.layout.value,
            equals(off.layout.value),
            reason: '$handle with $delta must snap identically',
          );
        }
      });
    }
  });

  group('fluid resize — ghost lifecycle', () {
    test('start arms the ghost with a null rect', () {
      final controller = build();
      addTearDown(controller.dispose);

      expect(controller.resizeGhostId.value, isNull);

      controller.onResizeStart('a');

      expect(controller.resizeGhostId.value, 'a');
      expect(
        controller.resizeGhostRect.value,
        isNull,
        reason: 'the first frame must paint the tile where it already is',
      );
    });

    test('no ghost is armed when the feature is off', () {
      final controller = build(fluid: false);
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      update(controller, ResizeHandle.bottomRight, const Offset(37, 0));

      expect(controller.resizeGhostId.value, isNull);
      expect(controller.resizeGhostRect.value, isNull);
    });

    test('a refused resize (static item) arms nothing', () {
      final controller = build(
        layout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2, isStatic: true),
        ],
      );
      addTearDown(controller.dispose);

      controller.onResizeStart('a');

      expect(controller.isResizing.value, isFalse);
      expect(controller.resizeGhostId.value, isNull);
    });

    test('onResizeEnd drops the ghost', () {
      final controller = build();
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      update(controller, ResizeHandle.bottomRight, const Offset(30, 30));
      expect(controller.resizeGhostRect.value, isNotNull);

      controller.onResizeEnd('a');

      expect(controller.resizeGhostId.value, isNull);
      expect(controller.resizeGhostRect.value, isNull);
    });

    test('cancelInteraction drops the ghost', () {
      final controller = build();
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      update(controller, ResizeHandle.bottomRight, const Offset(30, 30));

      controller.cancelInteraction();

      expect(controller.resizeGhostId.value, isNull);
      expect(controller.resizeGhostRect.value, isNull);
    });

    test('setFluidResize(false) mid-gesture drops the ghost and stops previewing', () {
      final controller = build();
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      update(controller, ResizeHandle.bottomRight, const Offset(30, 0));
      expect(controller.resizeGhostRect.value, isNotNull);

      controller.setFluidResize(false);
      expect(controller.resizeGhostId.value, isNull);
      expect(controller.resizeGhostRect.value, isNull);

      // The gesture keeps working, snapped, and publishes nothing further:
      // the fluid path is keyed on the ghost being armed, not on the flag.
      update(controller, ResizeHandle.bottomRight, const Offset(230, 0));
      expect(controller.resizeGhostRect.value, isNull);
      expect(controller.layout.value.firstWhere((i) => i.id == 'a').w, 4);
    });

    test('setResizeGhost re-arms the ghost (settle handoff)', () {
      final controller = build();
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      update(controller, ResizeHandle.bottomRight, const Offset(30, 0));
      final frozen = controller.resizeGhostRect.value;
      controller.onResizeEnd('a');

      controller.setResizeGhost('a', frozen);

      expect(controller.resizeGhostId.value, 'a');
      expect(controller.resizeGhostRect.value, frozen);
      expect(
        controller.isResizing.value,
        isFalse,
        reason: 'armed + not resizing IS the settle phase',
      );
    });
  });

  group('fluid resize — the ghost tracks sub-slot movement', () {
    test('a 30 px move on a 100 px slot moves the rect and not the layout', () {
      final controller = build();
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      update(controller, ResizeHandle.bottomRight, Offset.zero);

      final layoutBefore = controller.layout.value;
      update(controller, ResizeHandle.bottomRight, const Offset(30, 0));

      final rect = controller.resizeGhostRect.value!;
      expect(rect.left, closeTo(200, 0.001)); // x: 2 * 100
      expect(rect.top, closeTo(200, 0.001)); // y: 2 * 100
      expect(rect.width, closeTo(230, 0.001)); // w: 2 * 100 + 30
      expect(rect.height, closeTo(200, 0.001));

      expect(
        identical(layoutBefore, controller.layout.value),
        isTrue,
        reason: 'the boundary bypass must still skip the engine call',
      );
      expect(controller.layout.value.firstWhere((i) => i.id == 'a').w, 2);
    });

    test('the rect is published even while the bypass short-circuits', () {
      final controller = build();
      addTearDown(controller.dispose);

      controller.onResizeStart('a');

      // Three events inside the same cell: the rect must advance every time.
      final widths = <double>[];
      for (final dx in const [10.0, 20.0, 30.0]) {
        update(controller, ResizeHandle.right, Offset(dx, 0));
        widths.add(controller.resizeGhostRect.value!.width);
      }

      expect(widths, [closeTo(210, 0.001), closeTo(220, 0.001), closeTo(230, 0.001)]);
    });

    test('spacing is subtracted from the painted rect like every other tile', () {
      final controller = build();
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      update(
        controller,
        ResizeHandle.right,
        const Offset(30, 0),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      );

      // stride = 110, fw = 2 + 30/110; width = fw * 110 - 10 = 220 - 10 + 30.
      final rect = controller.resizeGhostRect.value!;
      expect(rect.left, closeTo(220, 0.001)); // 2 * 110
      expect(rect.width, closeTo(240, 0.001)); // 2 * 110 - 10 + 30
    });
  });

  group('fluid resize — the ghost obeys every clamp the snap obeys', () {
    test('minW / minH', () {
      final controller = build();
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      update(controller, ResizeHandle.bottomRight, const Offset(-500, -500));

      final rect = controller.resizeGhostRect.value!;
      expect(rect.width, closeTo(100, 0.001)); // minW: 1
      expect(rect.height, closeTo(100, 0.001)); // minH: 1
      expect(controller.layout.value.firstWhere((i) => i.id == 'a').w, 1);
    });

    test('finite maxW / maxH', () {
      final controller = build(
        layout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2, minW: 1, minH: 1, maxW: 3, maxH: 3),
        ],
      );
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      update(controller, ResizeHandle.bottomRight, const Offset(500, 500));

      final rect = controller.resizeGhostRect.value!;
      expect(rect.width, closeTo(300, 0.001));
      expect(rect.height, closeTo(300, 0.001));
    });

    test('an anchored top resize stops at a static barrier, in pixels', () {
      final controller = build(
        layout: const [
          LayoutItem(id: 'barrier', x: 0, y: 0, w: 8, h: 1, isStatic: true),
          LayoutItem(id: 'a', x: 0, y: 1, w: 2, h: 2, minW: 1, minH: 1),
        ],
      );
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      update(controller, ResizeHandle.top, const Offset(0, -500));

      final rect = controller.resizeGhostRect.value!;
      // The barrier's bottom edge is row 1 -> 100 px. The ghost must not
      // cross a boundary the snapped placeholder respects.
      expect(rect.top, closeTo(100, 0.001));
      expect(rect.height, closeTo(200, 0.001));

      final item = controller.layout.value.firstWhere((i) => i.id == 'a');
      expect(item.y, 1);
      expect(item.h, 2);
    });

    test('an anchored left resize stops at a static barrier, in pixels', () {
      final controller = build(
        layout: const [
          LayoutItem(id: 's', x: 0, y: 0, w: 2, h: 2, isStatic: true),
          LayoutItem(id: 'a', x: 3, y: 0, w: 2, h: 2, minW: 1, minH: 1),
        ],
      );
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      update(controller, ResizeHandle.left, const Offset(-500, 0));

      final rect = controller.resizeGhostRect.value!;
      expect(rect.left, closeTo(200, 0.001)); // s.x + s.w == 2
      expect(rect.width, closeTo(300, 0.001)); // originalRight (5) - 2
    });

    test('the grid right edge', () {
      final controller = build(
        layout: const [
          LayoutItem(id: 'a', x: 6, y: 0, w: 2, h: 2, minW: 1, minH: 1),
        ],
      );
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      update(controller, ResizeHandle.right, const Offset(500, 0));

      expect(controller.resizeGhostRect.value!.width, closeTo(200, 0.001));
    });

    test('maxRows', () {
      final controller = build();
      addTearDown(controller.dispose);
      controller.setMaxRows(4);

      controller.onResizeStart('a'); // y: 2 -> cap height at 2
      update(controller, ResizeHandle.bottom, const Offset(0, 500));

      expect(controller.resizeGhostRect.value!.height, closeTo(200, 0.001));
      expect(controller.layout.value.firstWhere((i) => i.id == 'a').h, 2);
    });

    test('a negative origin is absorbed, not painted', () {
      final controller = build(
        layout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2, minW: 1, minH: 1),
        ],
      );
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      update(controller, ResizeHandle.bottomRight, Offset.zero);

      final rect = controller.resizeGhostRect.value!;
      expect(rect.left, 0);
      expect(rect.top, 0);
    });
  });

  group('fluid resize — horizontal grids', () {
    test('the cross axis is clamped to the slot count', () {
      final controller = build(
        layout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2, minW: 1, minH: 1),
        ],
        slotCount: 4,
      );
      addTearDown(controller.dispose);
      controller.setScrollDirection(Axis.horizontal);

      controller.onResizeStart('a');
      update(controller, ResizeHandle.bottom, const Offset(0, 500));

      // y: 0, slotCount 4 -> at most 4 rows of 100 px.
      expect(controller.resizeGhostRect.value!.height, closeTo(400, 0.001));
    });
  });

  test('onResizeUpdate clamps fluid fw against maxRows in horizontal scroll mode', () {
    final controller = DashboardController(
      initialLayout: const [
        LayoutItem(id: 'item_h', x: 0, y: 0, w: 2, h: 2, minW: 1),
      ],
    );
    final impl = controller as DashboardControllerImpl;
    impl.setScrollDirection(Axis.horizontal);
    controller.setMaxRows(4); // rowCap = 4
    controller.setFluidResize(true); // active fluid

    impl.onResizeStart('item_h');

    impl.onResizeUpdate(
      'item_h',
      ResizeHandle.right,
      const Offset(600, 0),
      slotWidth: 100,
      slotHeight: 100,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    );

    expect(controller.layout.value.first.w, 4);
    // Stride X horizontal = slotWidth(100) + mainAxisSpacing(10) = 110. 4 * 110 - 10 = 430
    expect(controller.resizeGhostRect.value!.width, 430.0);

    impl.onResizeEnd('item_h');
  });

  test('onResizeUpdate handles negative coordinates recovery when fluid is true', () {
    final controller = DashboardController(
      initialLayout: const [
        LayoutItem(id: 'neg_y', x: 0, y: -2, w: 2, h: 4, minH: 1),
        LayoutItem(id: 'neg_x', x: -2, y: 0, w: 4, h: 2, minW: 1),
      ],
    );
    final impl = controller as DashboardControllerImpl;
    controller.setFluidResize(true);

    impl.onResizeStart('neg_y');
    impl.onResizeUpdate(
      'neg_y',
      ResizeHandle.bottom,
      const Offset(0, 10),
      slotWidth: 100,
      slotHeight: 100,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    );
    impl.onResizeEnd('neg_y');

    impl.onResizeStart('neg_x');
    impl.onResizeUpdate(
      'neg_x',
      ResizeHandle.right,
      const Offset(10, 0),
      slotWidth: 100,
      slotHeight: 100,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    );
    impl.onResizeEnd('neg_x');
  });
}
