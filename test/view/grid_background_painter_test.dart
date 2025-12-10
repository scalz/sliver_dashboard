import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';

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
        activeItem: LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1), // Changed
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
  });
}
