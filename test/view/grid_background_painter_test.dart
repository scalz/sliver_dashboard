import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';

// A simple mock canvas to verify calls (optional, but good for verifying paint logic)
class MockCanvas extends Fake implements Canvas {
  int drawRectCalls = 0;
  int clipRectCalls = 0;
  int saveCalls = 0;
  int restoreCalls = 0;
  int translateCalls = 0;
  int drawLineCalls = 0;

  @override
  void drawRect(Rect rect, Paint paint) => drawRectCalls++;

  @override
  void clipRect(Rect rect, {ClipOp clipOp = ClipOp.intersect, bool doAntiAlias = true}) =>
      clipRectCalls++;

  @override
  void save() => saveCalls++;

  @override
  void restore() => restoreCalls++;

  @override
  void translate(double dx, double dy) => translateCalls++;

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => drawLineCalls++;
}

void main() {
  group('GridBackgroundPainter', () {
    const metrics = SlotMetrics(
      slotWidth: 100,
      slotHeight: 100,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      padding: EdgeInsets.zero,
      scrollDirection: Axis.vertical,
      slotCount: 4,
    );

    test('shouldRepaint returns true when properties change', () {
      const oldPainter = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        sliverTop: 0,
        sliverHeight: 1000,
      );

      // 1. Change Scroll Offset
      const newPainterScroll = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 10, // Changed
        sliverTop: 0,
        sliverHeight: 1000,
      );
      expect(newPainterScroll.shouldRepaint(oldPainter), isTrue);

      // 2. Change Active Item
      const newPainterItem = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        draggedItems: [LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)], // Changed
        sliverTop: 0,
        sliverHeight: 1000,
      );
      expect(newPainterItem.shouldRepaint(oldPainter), isTrue);

      // 3. Change Sliver Top
      const newPainterTop = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        sliverTop: 50, // Changed
        sliverHeight: 1000,
      );
      expect(newPainterTop.shouldRepaint(oldPainter), isTrue);

      // 4. Change Sliver Height
      const newPainterHeight = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        sliverTop: 0,
        sliverHeight: 2000, // Changed
      );
      expect(newPainterHeight.shouldRepaint(oldPainter), isTrue);
    });

    test('shouldRepaint detects changes in draggedItems content (Deep List Comparison)', () {
      const itemA = LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1);
      const itemB = LayoutItem(id: '2', x: 0, y: 0, w: 1, h: 1);

      const oldPainter = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        draggedItems: [itemA], // List with Item A
      );

      // 1. Same list instance -> Should NOT repaint (covered by identical check)
      final sameListPainter = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        draggedItems: oldPainter.draggedItems,
      );
      expect(sameListPainter.shouldRepaint(oldPainter), isFalse);

      // 2. Different list instance, SAME content -> Should NOT repaint
      // This covers the loop where a[i] == b[i]
      const sameContentPainter = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        draggedItems: [itemA], // New list, same item
      );
      expect(sameContentPainter.shouldRepaint(oldPainter), isFalse);

      // 3. Different list instance, DIFFERENT content -> Should repaint
      // This covers the loop where a[i] != b[i]
      const diffContentPainter = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        draggedItems: [itemB], // New list, different item
      );
      expect(diffContentPainter.shouldRepaint(oldPainter), isTrue);
    });

    test('paint handles fillViewport: false (Clipping logic)', () {
      const painter = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        sliverTop: 0,
        sliverHeight: 500, // Content is smaller than screen
        fillViewport: false,
      );

      final canvas = MockCanvas();
      // Screen size is 1000, but content is 500.
      painter.paint(canvas, const Size(400, 1000));

      // We just verify it runs without error and calls clipRect.
      // The logic inside paint uses sliverHeight (500) for clipping instead of size.height.
      expect(canvas.clipRectCalls, 1);
    });

    test('paint draws placeholder if provided', () {
      const painter = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        placeholder: LayoutItem(id: 'p', x: 1, y: 1, w: 1, h: 1),
      );

      final canvas = MockCanvas();
      painter.paint(canvas, const Size(400, 1000));

      // drawRect is called for:
      // 1. The placeholder highlight
      // 2. The grid lines (if implemented via drawLine, this count might vary,
      //    but we ensure the highlight logic is triggered).
      expect(canvas.drawRectCalls, greaterThan(0));
    });
  });
}
