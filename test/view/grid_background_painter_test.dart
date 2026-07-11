import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';

// A simple mock of RenderSliverDashboard using mocktail
class MockRenderSliverDashboard extends Mock implements RenderSliverDashboard {
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'MockRenderSliverDashboard';
  }
}

// A simple mock canvas to verify calls
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
      final sliverA = MockRenderSliverDashboard();
      final sliverB = MockRenderSliverDashboard();

      final oldPainter = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        renderSliver: sliverA,
      );

      // 1. Change Scroll Offset
      final newPainterScroll = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 10, // Changed
        renderSliver: sliverA,
      );
      expect(newPainterScroll.shouldRepaint(oldPainter), isTrue);

      // 2. Change Active Item
      final newPainterItem = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        draggedItems: const [LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)], // Changed
        renderSliver: sliverA,
      );
      expect(newPainterItem.shouldRepaint(oldPainter), isTrue);

      // 3. Change RenderSliver reference
      final newPainterSliver = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        renderSliver: sliverB, // Changed
      );
      expect(newPainterSliver.shouldRepaint(oldPainter), isTrue);

      // 4. Change fillViewport
      final newPainterViewport = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        renderSliver: sliverA,
        fillViewport: true, // Changed
      );
      expect(newPainterViewport.shouldRepaint(oldPainter), isTrue);
    });

    test('shouldRepaint detects changes in draggedItems content (Deep List Comparison)', () {
      const itemA = LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1);
      const itemB = LayoutItem(id: '2', x: 0, y: 0, w: 1, h: 1);
      final sliver = MockRenderSliverDashboard();

      final oldPainter = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        renderSliver: sliver,
        draggedItems: const [itemA], // List with Item A
      );

      // 1. Same list instance -> Should NOT repaint (covered by identical check)
      final sameListPainter = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        renderSliver: sliver,
        draggedItems: oldPainter.draggedItems,
      );
      expect(sameListPainter.shouldRepaint(oldPainter), isFalse);

      // 2. Different list instance, SAME content -> Should NOT repaint
      final sameContentPainter = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        renderSliver: sliver,
        draggedItems: const [itemA], // New list, same item
      );
      expect(sameContentPainter.shouldRepaint(oldPainter), isFalse);

      // 3. Different list instance, DIFFERENT content -> Should repaint
      final diffContentPainter = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        renderSliver: sliver,
        draggedItems: const [itemB], // New list, different item
      );
      expect(diffContentPainter.shouldRepaint(oldPainter), isTrue);
    });

    test('paint handles fillViewport: false (Clipping logic)', () {
      final renderSliver = MockRenderSliverDashboard();

      // Stubbing the renderSliver's layout properties
      when(() => renderSliver.attached).thenReturn(true);
      when(() => renderSliver.geometry).thenReturn(const SliverGeometry(scrollExtent: 500));
      when(() => renderSliver.constraints).thenReturn(
        const SliverConstraints(
          axisDirection: AxisDirection.down,
          growthDirection: GrowthDirection.forward,
          userScrollDirection: ScrollDirection.idle,
          scrollOffset: 0,
          precedingScrollExtent: 0,
          overlap: 0,
          remainingPaintExtent: 1000,
          crossAxisExtent: 400,
          crossAxisDirection: AxisDirection.right,
          viewportMainAxisExtent: 1000, // Fixed: 'viewportMainAxisExtent' is required
          remainingCacheExtent: 1000,
          cacheOrigin: 0,
        ),
      );

      final painter = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        renderSliver: renderSliver,
        fillViewport: false,
      );

      final canvas = MockCanvas();
      painter.paint(canvas, const Size(400, 1000));

      expect(canvas.clipRectCalls, 1);
    });

    test('paint draws placeholder if provided', () {
      final sliver = MockRenderSliverDashboard();
      when(() => sliver.attached).thenReturn(false);

      final painter = GridBackgroundPainter(
        metrics: metrics,
        scrollOffset: 0,
        renderSliver: sliver,
        placeholder: const LayoutItem(id: 'p', x: 1, y: 1, w: 1, h: 1),
      );

      final canvas = MockCanvas();
      painter.paint(canvas, const Size(400, 1000));

      expect(canvas.drawRectCalls, greaterThan(0));
    });
  });
}
