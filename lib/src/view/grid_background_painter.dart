import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/sliver_dashboard.dart' show RenderSliverDashboard;

/// A custom painter that draws the background grid lines and the highlight
/// for the currently active item (or placeholder) within a Sliver context.
///
/// This painter handles the complex coordinate transformations required to
/// align the grid correctly within a [CustomScrollView], accounting for
/// scroll offsets, sliver positioning, and padding.
class GridBackgroundPainter extends CustomPainter {
  /// Creates a [GridBackgroundPainter].
  const GridBackgroundPainter({
    required this.metrics,
    required this.scrollOffset,
    required this.renderSliver,
    this.draggedItems = const [],
    this.placeholder,
    this.lineColor = Colors.black12,
    this.lineWidth = 1.0,
    this.fillColor = Colors.black12,
    this.fillViewport = false,
  });

  /// The layout metrics containing slot sizes, spacing, and padding.
  final SlotMetrics metrics;

  /// The current scroll offset of the viewport.
  final double scrollOffset;

  /// Reference to the RenderObject
  final RenderSliverDashboard? renderSliver;

  /// The items currently being dragged/resized by the user (internal).
  /// These represent the "shadows" on the grid.
  final List<LayoutItem> draggedItems;

  /// The placeholder item representing an external drag entering the grid.
  final LayoutItem? placeholder;

  /// The color of the grid lines.
  final Color lineColor;

  /// The width of the grid lines.
  final double lineWidth;

  /// The color used to fill the area of the active item or placeholder.
  final Color fillColor;

  /// If true, ignore sliverHeight for clipping
  final bool fillViewport;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = lineWidth;

    final viewportRect = Offset.zero & size;

    final isVertical = metrics.scrollDirection == Axis.vertical;

    var sliverTop = 0.0;
    var sliverHeight = 0.0;

    if (renderSliver != null && renderSliver!.attached && renderSliver!.geometry != null) {
      sliverTop = renderSliver!.constraints.precedingScrollExtent;
      sliverHeight = renderSliver!.geometry!.scrollExtent;
    } else {
      // Fallback si le sliver n'a pas encore de géométrie calculée
      sliverHeight = isVertical ? size.height : size.width;
    }

    final visualStart = sliverTop - scrollOffset;

    canvas.save();

    // Clipping Extent:
    final double clipExtent;
    if (fillViewport) {
      // Reasoning: When fillViewport is true, the grid must cover the entire visible
      // area of the sliver, which is the viewport size minus the visual start offset.
      clipExtent = isVertical ? size.height - visualStart : size.width - visualStart;
    } else {
      // Reasoning: When fillViewport is false, the grid must stop strictly at the
      // end of the content (sliverHeight) to allow the next sliver to be visible.
      clipExtent = sliverHeight;
    }

    if (isVertical) {
      final clipRect = Rect.fromLTWH(
        0,
        visualStart,
        size.width,
        clipExtent,
      ).intersect(viewportRect);

      canvas
        ..clipRect(clipRect)
        ..translate(metrics.padding.left, visualStart);
    } else {
      final clipRect = Rect.fromLTWH(
        visualStart,
        0,
        clipExtent,
        size.height,
      ).intersect(viewportRect);

      canvas
        ..clipRect(clipRect)
        ..translate(visualStart, metrics.padding.top);
    }

    // 2. Draw Item Highlights (Shadows)
    // We combine the internal dragged items and the external placeholder
    final itemsToHighlight = [...draggedItems];
    if (placeholder != null) {
      itemsToHighlight.add(placeholder!);
    }

    if (itemsToHighlight.isNotEmpty) {
      final fillPaint = Paint()..color = fillColor;
      for (final item in itemsToHighlight) {
        final double left;
        final double top;
        final double width;
        final double height;

        if (isVertical) {
          left = item.x * (metrics.slotWidth + metrics.crossAxisSpacing);
          top = item.y * (metrics.slotHeight + metrics.mainAxisSpacing);
          width =
              item.w * (metrics.slotWidth + metrics.crossAxisSpacing) - metrics.crossAxisSpacing;
          height =
              item.h * (metrics.slotHeight + metrics.mainAxisSpacing) - metrics.mainAxisSpacing;
        } else {
          left = item.x * (metrics.slotWidth + metrics.mainAxisSpacing);
          top = item.y * (metrics.slotHeight + metrics.crossAxisSpacing);
          width = item.w * (metrics.slotWidth + metrics.mainAxisSpacing) - metrics.mainAxisSpacing;
          height =
              item.h * (metrics.slotHeight + metrics.crossAxisSpacing) - metrics.crossAxisSpacing;
        }

        canvas.drawRect(Rect.fromLTWH(left, top, width, height), fillPaint);
      }
    }

    // 3. Draw Grid Lines
    // We draw the grid over the entire content extent (`sliverHeight`),
    // relying on the `clipRect` applied earlier to hide lines that are off-screen.
    final contentWidth = size.width - metrics.padding.horizontal;
    final contentHeight = size.height - metrics.padding.vertical;

    // Reasoning: The drawing bounds must be large enough to cover the entire
    // scrollable content, which is why we use a large arbitrary number.
    const largeExtent = 10000.0;

    final drawBounds =
        isVertical ? Size(contentWidth, largeExtent) : Size(largeExtent, contentHeight);

    if (isVertical) {
      _paintVerticalGrid(canvas, drawBounds, linePaint, visualStart, size.height, sliverHeight);
    } else {
      _paintHorizontalGrid(canvas, drawBounds, linePaint, visualStart, size.width, sliverHeight);
    }

    canvas.restore();
  }

  void _paintVerticalGrid(
    Canvas canvas,
    Size size,
    Paint paint,
    double visualStart,
    double viewportHeight,
    double sliverHeight,
  ) {
    // Limit drawing range of vertical grid columns on the cross-axis.
    for (var i = 1; i < metrics.slotCount; i++) {
      final x = i * metrics.slotWidth +
          (i - 1) * metrics.crossAxisSpacing +
          (metrics.crossAxisSpacing / 2);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, fillViewport ? viewportHeight - visualStart : sliverHeight),
        paint,
      );
    }

    // Prevent painting infinite off-screen horizontal rows. Calculate the exact intersection
    // of the scrollOffset, visual viewport boundaries, and content height, cutting down repaints
    // to only the visible lines (usually 10-20 lines instead of 150+).
    final spacing = metrics.slotHeight + metrics.mainAxisSpacing;
    if (spacing <= 0) return;

    final firstLineY = metrics.slotHeight + (metrics.mainAxisSpacing / 2);
    final minY = max(0, -visualStart);
    final maxY = min(
      fillViewport ? viewportHeight - visualStart : sliverHeight,
      -visualStart + viewportHeight,
    );

    if (minY >= maxY) return;

    final double startY;
    if (minY <= firstLineY) {
      startY = firstLineY;
    } else {
      startY = firstLineY + ((minY - firstLineY) / spacing).ceil() * spacing;
    }

    for (var y = startY; y < maxY; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintHorizontalGrid(
    Canvas canvas,
    Size size,
    Paint paint,
    double visualStart,
    double viewportWidth,
    double sliverHeight,
  ) {
    // Limit drawing range of horizontal grid rows on the cross-axis.
    for (var i = 1; i < metrics.slotCount; i++) {
      final y = i * metrics.slotHeight +
          (i - 1) * metrics.mainAxisSpacing +
          (metrics.mainAxisSpacing / 2);
      canvas.drawLine(
        Offset(0, y),
        Offset(fillViewport ? viewportWidth - visualStart : sliverHeight, y),
        paint,
      );
    }

    // Clip vertical columns to the visible viewport boundaries on the horizontal main-axis.
    final spacing = metrics.slotWidth + metrics.crossAxisSpacing;
    if (spacing <= 0) return;

    final firstLineX = metrics.slotWidth + (metrics.crossAxisSpacing / 2);
    final minX = max(0, -visualStart);
    final maxX = min(
      fillViewport ? viewportWidth - visualStart : sliverHeight,
      -visualStart + viewportWidth,
    );

    if (minX >= maxX) return;

    final double startX;
    if (minX <= firstLineX) {
      startX = firstLineX;
    } else {
      startX = firstLineX + ((minX - firstLineX) / spacing).ceil() * spacing;
    }

    for (var x = startX; x < maxX; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GridBackgroundPainter oldDelegate) {
    return oldDelegate.metrics != metrics ||
        oldDelegate.scrollOffset != scrollOffset ||
        !listEquals(oldDelegate.draggedItems, draggedItems) ||
        oldDelegate.placeholder != placeholder ||
        oldDelegate.renderSliver != renderSliver ||
        oldDelegate.fillViewport != fillViewport ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.lineWidth != lineWidth ||
        oldDelegate.fillColor != fillColor;
  }

  /// Helper for list comparison if you don't have foundation imported
  bool listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    if (identical(a, b)) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
