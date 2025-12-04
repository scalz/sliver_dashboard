import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';

/// A custom painter that draws a grid background for the dashboard.
///
/// It's designed to be used within a CustomPaint widget and repaints
/// on scroll to create the illusion of a static, infinite grid.
class GridBackgroundPainter extends CustomPainter {
  /// Creates a [GridBackgroundPainter].
  const GridBackgroundPainter({
    required this.metrics,
    required this.scrollOffset,
    this.activeItem,
    this.lineColor = Colors.black12,
    this.lineWidth = 1.0,
    this.fillColor = Colors.black12,
  });

  /// The layout metrics containing slot sizes and spacing.
  final SlotMetrics metrics;

  /// The current scroll offset of the dashboard.
  final double scrollOffset;

  /// The currently active (being dragged or resized) item.
  final LayoutItem? activeItem;

  /// The color of the grid lines.
  final Color lineColor;

  /// The width of the grid lines.
  final double lineWidth;

  /// The color used to fill the area of the [activeItem].
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = lineWidth;

    canvas
      ..save()
      ..translate(metrics.padding.left, metrics.padding.top);

    final paddedSize = Size(
      size.width - metrics.padding.horizontal,
      size.height - metrics.padding.vertical,
    );

    // Paint the active item's background fill ---
    if (activeItem != null) {
      final fillPaint = Paint()..color = fillColor;
      final item = activeItem!;
      final isVertical = metrics.scrollDirection == Axis.vertical;

      final double left;
      final double top;
      final double width;
      final double height;

      if (isVertical) {
        left = item.x * (metrics.slotWidth + metrics.crossAxisSpacing);
        top = item.y * (metrics.slotHeight + metrics.mainAxisSpacing) - scrollOffset;
        width = item.w * (metrics.slotWidth + metrics.crossAxisSpacing) - metrics.crossAxisSpacing;
        height = item.h * (metrics.slotHeight + metrics.mainAxisSpacing) - metrics.mainAxisSpacing;
      } else {
        left = item.x * (metrics.slotWidth + metrics.mainAxisSpacing) - scrollOffset;
        top = item.y * (metrics.slotHeight + metrics.crossAxisSpacing);
        width = item.w * (metrics.slotWidth + metrics.mainAxisSpacing) - metrics.mainAxisSpacing;
        height =
            item.h * (metrics.slotHeight + metrics.crossAxisSpacing) - metrics.crossAxisSpacing;
      }

      canvas.drawRect(Rect.fromLTWH(left, top, width, height), fillPaint);
    }

    // Paint the grid lines ---
    if (metrics.scrollDirection == Axis.vertical) {
      _paintVerticalGrid(canvas, paddedSize, linePaint);
    } else {
      _paintHorizontalGrid(canvas, paddedSize, linePaint);
    }

    canvas.restore();
  }

  void _paintVerticalGrid(Canvas canvas, Size paddedSize, Paint paint) {
    // Draw vertical lines (cross-axis)
    for (var i = 1; i < metrics.slotCount; i++) {
      final x = i * metrics.slotWidth +
          (i - 1) * metrics.crossAxisSpacing +
          (metrics.crossAxisSpacing / 2);
      canvas.drawLine(Offset(x, 0), Offset(x, paddedSize.height), paint);
    }

    // Draw horizontal lines (main-axis)
    final slotHeightWithSpacing = metrics.slotHeight + metrics.mainAxisSpacing;
    if (slotHeightWithSpacing <= 0) return;

    final startOffset = (scrollOffset + metrics.padding.top) % slotHeightWithSpacing;
    final firstLineY = metrics.slotHeight - startOffset + (metrics.mainAxisSpacing / 2);

    for (var y = firstLineY; y < paddedSize.height; y += slotHeightWithSpacing) {
      canvas.drawLine(Offset(0, y), Offset(paddedSize.width, y), paint);
    }
  }

  void _paintHorizontalGrid(Canvas canvas, Size paddedSize, Paint paint) {
    // Draw horizontal lines (cross-axis)
    for (var i = 1; i < metrics.slotCount; i++) {
      final y = i * metrics.slotHeight +
          (i - 1) * metrics.mainAxisSpacing +
          (metrics.mainAxisSpacing / 2);
      canvas.drawLine(Offset(0, y), Offset(paddedSize.width, y), paint);
    }

    // Draw vertical lines (main-axis)
    final slotWidthWithSpacing = metrics.slotWidth + metrics.crossAxisSpacing;
    if (slotWidthWithSpacing <= 0) return;

    final startOffset = (scrollOffset + metrics.padding.left) % slotWidthWithSpacing;
    final firstLineX = metrics.slotWidth - startOffset + (metrics.crossAxisSpacing / 2);

    for (var x = firstLineX; x < paddedSize.width; x += slotWidthWithSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, paddedSize.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GridBackgroundPainter oldDelegate) {
    return oldDelegate.metrics.scrollDirection != metrics.scrollDirection ||
        oldDelegate.scrollOffset != scrollOffset ||
        oldDelegate.metrics.slotCount != metrics.slotCount ||
        oldDelegate.metrics.slotHeight != metrics.slotHeight ||
        oldDelegate.metrics.slotWidth != metrics.slotWidth ||
        oldDelegate.metrics.mainAxisSpacing != metrics.mainAxisSpacing ||
        oldDelegate.metrics.crossAxisSpacing != metrics.crossAxisSpacing ||
        oldDelegate.metrics.padding != metrics.padding ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.lineWidth != lineWidth ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.activeItem != activeItem;
  }
}
