import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';

//
// ignore_for_file: cascade_invocations

/// Every case here uses **asymmetric spacings**. That is the whole point: the
/// stride defect this file guards is worth exactly
/// `(mainAxisSpacing - crossAxisSpacing) * x` pixels, so a suite that only ever
/// passes `mainAxisSpacing == crossAxisSpacing` — or only ever scrolls
/// vertically — cannot observe it. See AGENTS §1, Value Coverage.
const double _slot = 100;
const double _main = 24;
const double _cross = 4;

/// Stride along x, per scroll direction.
const double _xStrideVertical = _slot + _cross; // 104
const double _xStrideHorizontal = _slot + _main; // 124

/// Stride along y, per scroll direction.
const double _yStrideVertical = _slot + _main; // 124
const double _yStrideHorizontal = _slot + _cross; // 104

void main() {
  group('gridCellRect', () {
    test('swaps the two spacings with the scroll direction', () {
      const args = (x: 2, y: 1, w: 2, h: 1);

      final vertical = gridCellRect(
        x: args.x,
        y: args.y,
        w: args.w,
        h: args.h,
        slotWidth: _slot,
        slotHeight: _slot,
        mainAxisSpacing: _main,
        crossAxisSpacing: _cross,
        scrollDirection: Axis.vertical,
      );

      // Vertical: x is the CROSS axis (4), y is the MAIN axis (24).
      expect(vertical.left, closeTo(208, 0.001)); // 2 * 104
      expect(vertical.top, closeTo(124, 0.001)); // 1 * 124
      expect(vertical.width, closeTo(204, 0.001)); // 2 * 104 - 4
      expect(vertical.height, closeTo(100, 0.001)); // 1 * 124 - 24

      final horizontal = gridCellRect(
        x: args.x,
        y: args.y,
        w: args.w,
        h: args.h,
        slotWidth: _slot,
        slotHeight: _slot,
        mainAxisSpacing: _main,
        crossAxisSpacing: _cross,
        scrollDirection: Axis.horizontal,
      );

      // Horizontal: x is the MAIN axis (24), y is the CROSS axis (4).
      expect(horizontal.left, closeTo(248, 0.001)); // 2 * 124
      expect(horizontal.top, closeTo(104, 0.001)); // 1 * 104
      expect(horizontal.width, closeTo(224, 0.001)); // 2 * 124 - 24
      expect(horizontal.height, closeTo(100, 0.001)); // 1 * 104 - 4
    });

    test('accepts fractional coordinates (the fluid-resize path)', () {
      final rect = gridCellRect(
        x: 0,
        y: 0,
        w: 2.5,
        h: 1,
        slotWidth: _slot,
        slotHeight: _slot,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
        scrollDirection: Axis.vertical,
      );

      expect(rect.width, closeTo(250, 0.001));
    });

    test('never returns a negative extent', () {
      final rect = gridCellRect(
        x: 0,
        y: 0,
        w: 0,
        h: 0,
        slotWidth: _slot,
        slotHeight: _slot,
        mainAxisSpacing: _main,
        crossAxisSpacing: _cross,
        scrollDirection: Axis.vertical,
      );

      expect(rect.width, 0);
      expect(rect.height, 0);
    });
  });

  group('SlotMetrics strides', () {
    SlotMetrics metrics(Axis direction) => SlotMetrics(
          slotWidth: _slot,
          slotHeight: _slot,
          mainAxisSpacing: _main,
          crossAxisSpacing: _cross,
          padding: EdgeInsets.zero,
          scrollDirection: direction,
          slotCount: 8,
        );

    test('strideX / strideY follow the scroll direction', () {
      expect(metrics(Axis.vertical).strideX, _xStrideVertical);
      expect(metrics(Axis.vertical).strideY, _yStrideVertical);
      expect(metrics(Axis.horizontal).strideX, _xStrideHorizontal);
      expect(metrics(Axis.horizontal).strideY, _yStrideHorizontal);
    });

    test('cellRect agrees with gridCellRect', () {
      for (final direction in Axis.values) {
        expect(
          metrics(direction).cellRect(2, 1, 2, 1),
          gridCellRect(
            x: 2,
            y: 1,
            w: 2,
            h: 1,
            slotWidth: _slot,
            slotHeight: _slot,
            mainAxisSpacing: _main,
            crossAxisSpacing: _cross,
            scrollDirection: direction,
          ),
        );
      }
    });
  });

  group('onDragUpdate resolves strides per axis', () {
    DashboardControllerImpl build(Axis direction) {
      final controller = DashboardController(
        initialSlotCount: 5,
        initialLayout: const [LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)],
      ) as DashboardControllerImpl;
      controller.setCompactionType(CompactType.none);
      controller.setScrollDirection(direction);
      return controller;
    }

    test('vertical: x uses crossAxisSpacing, y uses mainAxisSpacing', () {
      final controller = build(Axis.vertical);
      addTearDown(controller.dispose);

      controller.onDragStart('1');
      controller.onDragUpdate(
        '1',
        const Offset(3 * _xStrideVertical, 4 * _yStrideVertical), // (312, 496)
        slotWidth: _slot,
        slotHeight: _slot,
        mainAxisSpacing: _main,
        crossAxisSpacing: _cross,
      );

      final item = controller.layout.value.first;
      expect(item.x, 3);
      expect(item.y, 4);
    });

    test('horizontal: x uses mainAxisSpacing, y uses crossAxisSpacing', () {
      final controller = build(Axis.horizontal);
      addTearDown(controller.dispose);

      controller.onDragStart('1');
      controller.onDragUpdate(
        '1',
        const Offset(3 * _xStrideHorizontal, 4 * _yStrideHorizontal), // (372, 416)
        slotWidth: _slot,
        slotHeight: _slot,
        mainAxisSpacing: _main,
        crossAxisSpacing: _cross,
      );

      final item = controller.layout.value.first;
      // Pre-fix this landed on (4, 3): x was divided by 104 instead of 124,
      // and y by 124 instead of 104.
      expect(item.x, 3, reason: 'x is the MAIN axis in a horizontal grid');
      expect(item.y, 4, reason: 'y is the CROSS axis in a horizontal grid');
    });
  });

  group('onResizeUpdate resolves strides per axis', () {
    DashboardControllerImpl build(Axis direction) {
      final controller = DashboardController(
        initialSlotCount: 10,
        initialLayout: const [
          LayoutItem(id: 'a', x: 2, y: 2, w: 2, h: 2, minW: 1, minH: 1),
        ],
      ) as DashboardControllerImpl;
      controller.setScrollDirection(direction);
      return controller;
    }

    test('vertical: a 3-stride pull on x grows the item by exactly 3 columns', () {
      final controller = build(Axis.vertical);
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      controller.onResizeUpdate(
        'a',
        ResizeHandle.right,
        const Offset(3 * _xStrideVertical, 0),
        slotWidth: _slot,
        slotHeight: _slot,
        mainAxisSpacing: _main,
        crossAxisSpacing: _cross,
      );

      expect(controller.layout.value.firstWhere((i) => i.id == 'a').w, 5);
    });

    test('horizontal: a 3-stride pull on x grows the item by exactly 3 columns', () {
      final controller = build(Axis.horizontal);
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      controller.onResizeUpdate(
        'a',
        ResizeHandle.right,
        const Offset(3 * _xStrideHorizontal, 0), // 372
        slotWidth: _slot,
        slotHeight: _slot,
        mainAxisSpacing: _main,
        crossAxisSpacing: _cross,
      );

      // Pre-fix: 372 / 104 = 3.58 -> rounded to 4 -> w == 6.
      expect(controller.layout.value.firstWhere((i) => i.id == 'a').w, 5);
    });

    test('horizontal: a 4-stride pull on y grows the item by exactly 4 rows', () {
      final controller = build(Axis.horizontal);
      addTearDown(controller.dispose);

      controller.onResizeStart('a');
      controller.onResizeUpdate(
        'a',
        ResizeHandle.bottom,
        const Offset(0, 4 * _yStrideHorizontal), // 416
        slotWidth: _slot,
        slotHeight: _slot,
        mainAxisSpacing: _main,
        crossAxisSpacing: _cross,
      );

      // Pre-fix: 416 / 124 = 3.35 -> rounded to 3 -> h == 5.
      expect(controller.layout.value.firstWhere((i) => i.id == 'a').h, 6);
    });

    test('the fluid ghost uses the same strides as the snap it lands on', () {
      final controller = build(Axis.horizontal);
      addTearDown(controller.dispose);
      controller.setFluidResize(true);

      controller.onResizeStart('a');
      controller.onResizeUpdate(
        'a',
        ResizeHandle.right,
        const Offset(3 * _xStrideHorizontal, 0),
        slotWidth: _slot,
        slotHeight: _slot,
        mainAxisSpacing: _main,
        crossAxisSpacing: _cross,
      );

      final item = controller.layout.value.firstWhere((i) => i.id == 'a');
      final snapped = gridCellRect(
        x: item.x,
        y: item.y,
        w: item.w,
        h: item.h,
        slotWidth: _slot,
        slotHeight: _slot,
        mainAxisSpacing: _main,
        crossAxisSpacing: _cross,
        scrollDirection: Axis.horizontal,
      );

      // The delta was a whole number of strides, so raw and snapped coincide.
      // If the two paths ever used different conventions, this is where the
      // ghost would sit next to its own placeholder instead of on it.
      final ghost = controller.resizeGhostRect.value!;
      expect(ghost.left, closeTo(snapped.left, 0.001));
      expect(ghost.top, closeTo(snapped.top, 0.001));
      expect(ghost.width, closeTo(snapped.width, 0.001));
      expect(ghost.height, closeTo(snapped.height, 0.001));
    });
  });
}
