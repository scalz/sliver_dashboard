import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';

/// A custom painter that draws the background grid lines and the highlight
/// for the currently active item (or placeholder) within a Sliver context.
///
/// ## Coordinate contract (INVARIANT)
///
/// [sliverLayoutStart] is the grid content's origin along the MAIN axis, in
/// scroll coordinates. It is `RenderSliverDashboard.constraints.precedingScrollExtent`,
/// which **already includes the enclosing `SliverPadding`'s leading extent** —
/// `RenderSliverEdgeInsetsPadding` forwards `precedingScrollExtent: beforePadding +
/// constraints.precedingScrollExtent` to its child. The main-axis padding must
/// therefore NEVER be added on top of it. The CROSS axis is not part of the scroll
/// extent and IS added manually ([SlotMetrics.padding]).
///
/// Every parameter is value-typed on purpose: [shouldRepaint] can only be sound
/// if the painted output is a pure function of value-typed inputs.
class GridBackgroundPainter extends CustomPainter {
  /// Creates a [GridBackgroundPainter].
  const GridBackgroundPainter({
    required this.metrics,
    required this.scrollOffset,
    required this.sliverLayoutStart,
    required this.sliverContentExtent,
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

  /// Main-axis origin of the grid content, in scroll coordinates.
  /// See the coordinate contract on [GridBackgroundPainter].
  final double sliverLayoutStart;

  /// Main-axis extent actually occupied by the grid content
  /// (`SliverGeometry.scrollExtent`).
  final double sliverContentExtent;

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

  /// If true, ignore [sliverContentExtent] for clipping.
  final bool fillViewport;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = lineWidth;

    final viewportRect = Offset.zero & size;
    final isVertical = metrics.scrollDirection == Axis.vertical;
    final visualStart = sliverLayoutStart - scrollOffset;

    canvas.save();

    // Reason: When fillViewport is true, the grid covers the entire visible viewport.
    // Otherwise, it stops strictly at the content extent to leave space for subsequent slivers.
    final double clipExtent;
    if (fillViewport) {
      clipExtent = isVertical ? size.height - visualStart : size.width - visualStart;
    } else {
      clipExtent = sliverContentExtent;
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

    // Draw Item Highlights (Shadows)
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

    // Draw Grid Lines
    final contentWidth = size.width - metrics.padding.horizontal;
    final contentHeight = size.height - metrics.padding.vertical;

    // Reason: Large extent to cover all potential scrollable content within clipRect bounds.
    const largeExtent = 10000.0;

    final drawBounds =
        isVertical ? Size(contentWidth, largeExtent) : Size(largeExtent, contentHeight);

    if (isVertical) {
      _paintVerticalGrid(canvas, drawBounds, linePaint, visualStart, size.height);
    } else {
      _paintHorizontalGrid(canvas, drawBounds, linePaint, visualStart, size.width);
    }

    canvas.restore();
  }

  void _paintVerticalGrid(
    Canvas canvas,
    Size size,
    Paint paint,
    double visualStart,
    double viewportHeight,
  ) {
    for (var i = 1; i < metrics.slotCount; i++) {
      final x = i * metrics.slotWidth +
          (i - 1) * metrics.crossAxisSpacing +
          (metrics.crossAxisSpacing / 2);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, fillViewport ? viewportHeight - visualStart : sliverContentExtent),
        paint,
      );
    }

    // Reason: Bound drawing loop to visible lines within the viewport, skipping off-screen rows.
    final spacing = metrics.slotHeight + metrics.mainAxisSpacing;
    if (spacing <= 0) return;

    final firstLineY = metrics.slotHeight + (metrics.mainAxisSpacing / 2);
    final minY = max(0, -visualStart);
    final maxY = min(
      fillViewport ? viewportHeight - visualStart : sliverContentExtent,
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
  ) {
    for (var i = 1; i < metrics.slotCount; i++) {
      final y = i * metrics.slotHeight +
          (i - 1) * metrics.mainAxisSpacing +
          (metrics.mainAxisSpacing / 2);
      canvas.drawLine(
        Offset(0, y),
        Offset(fillViewport ? viewportWidth - visualStart : sliverContentExtent, y),
        paint,
      );
    }

    final spacing = metrics.slotWidth + metrics.crossAxisSpacing;
    if (spacing <= 0) return;

    final firstLineX = metrics.slotWidth + (metrics.crossAxisSpacing / 2);
    final minX = max(0, -visualStart);
    final maxX = min(
      fillViewport ? viewportWidth - visualStart : sliverContentExtent,
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
        oldDelegate.sliverLayoutStart != sliverLayoutStart ||
        oldDelegate.sliverContentExtent != sliverContentExtent ||
        !listEquals(oldDelegate.draggedItems, draggedItems) ||
        oldDelegate.placeholder != placeholder ||
        oldDelegate.fillViewport != fillViewport ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.lineWidth != lineWidth ||
        oldDelegate.fillColor != fillColor;
  }

  /// Helper for deep list comparison.
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
