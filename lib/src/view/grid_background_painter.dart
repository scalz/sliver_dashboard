import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';

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
    this.activeItem,
    this.placeholder,
    this.lineColor = Colors.black12,
    this.lineWidth = 1.0,
    this.fillColor = Colors.black12,
    this.sliverTop = 0.0,
    this.sliverHeight = 0.0,
    this.fillViewport = false,
  });

  /// The layout metrics containing slot sizes, spacing, and padding.
  final SlotMetrics metrics;

  /// The current scroll offset of the viewport.
  final double scrollOffset;

  /// The item currently being dragged/resized by the user (internal).
  final LayoutItem? activeItem;

  /// The placeholder item representing an external drag entering the grid.
  final LayoutItem? placeholder;

  /// The color of the grid lines.
  final Color lineColor;

  /// The width of the grid lines.
  final double lineWidth;

  /// The color used to fill the area of the active item or placeholder.
  final Color fillColor;

  /// The layout offset of the sliver within the scroll view (e.g., `precedingScrollExtent`).
  /// This accounts for widgets placed before this dashboard (like SliverAppBars).
  final double sliverTop;

  /// The total extent (height/width) of the sliver's content.
  final double sliverHeight;

  /// If true, ignore sliverHeight for clipping
  final bool fillViewport;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = lineWidth;

    final viewportRect = Offset.zero & size;

    final isVertical = metrics.scrollDirection == Axis.vertical;

    // Calculate the screen coordinate where the sliver content physically begins.
    // Reason: `sliverTop` is the layout offset in the scroll view. Subtracting
    // `scrollOffset` gives us the visual position relative to the viewport top.
    // This value implicitly includes the main-axis padding (e.g., SliverPadding.top).
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

    // 2. Draw Item Highlight (Shadow/Placeholder)
    // Prioritize the active item (internal drag), otherwise use placeholder (external drag).
    final itemToHighlight = activeItem ?? placeholder;

    if (itemToHighlight != null) {
      final fillPaint = Paint()..color = fillColor;
      final item = itemToHighlight;

      final double left;
      final double top;
      final double width;
      final double height;

      // Calculate exact pixel coordinates based on grid slots.
      // Reason: Since we translated the canvas origin to the grid's start,
      // we can calculate positions purely based on slot index * size,
      // without worrying about scroll offsets here.
      if (isVertical) {
        left = item.x * (metrics.slotWidth + metrics.crossAxisSpacing);
        top = item.y * (metrics.slotHeight + metrics.mainAxisSpacing);
        width = item.w * (metrics.slotWidth + metrics.crossAxisSpacing) - metrics.crossAxisSpacing;
        height = item.h * (metrics.slotHeight + metrics.mainAxisSpacing) - metrics.mainAxisSpacing;
      } else {
        left = item.x * (metrics.slotWidth + metrics.mainAxisSpacing);
        top = item.y * (metrics.slotHeight + metrics.crossAxisSpacing);
        width = item.w * (metrics.slotWidth + metrics.mainAxisSpacing) - metrics.mainAxisSpacing;
        height =
            item.h * (metrics.slotHeight + metrics.crossAxisSpacing) - metrics.crossAxisSpacing;
      }

      canvas.drawRect(Rect.fromLTWH(left, top, width, height), fillPaint);
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
      _paintVerticalGrid(canvas, drawBounds, linePaint);
    } else {
      _paintHorizontalGrid(canvas, drawBounds, linePaint);
    }

    canvas.restore();
  }

  void _paintVerticalGrid(Canvas canvas, Size size, Paint paint) {
    // Draw vertical lines (Columns)
    for (var i = 1; i < metrics.slotCount; i++) {
      final x = i * metrics.slotWidth +
          (i - 1) * metrics.crossAxisSpacing +
          (metrics.crossAxisSpacing / 2);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal lines (Rows)
    final slotHeightWithSpacing = metrics.slotHeight + metrics.mainAxisSpacing;
    if (slotHeightWithSpacing <= 0) return;

    // Start drawing from the first slot boundary.
    final firstLineY = metrics.slotHeight + (metrics.mainAxisSpacing / 2);

    for (var y = firstLineY; y < size.height; y += slotHeightWithSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintHorizontalGrid(Canvas canvas, Size size, Paint paint) {
    // Draw horizontal lines (Rows/Cross-axis columns)
    for (var i = 1; i < metrics.slotCount; i++) {
      final y = i * metrics.slotHeight +
          (i - 1) * metrics.mainAxisSpacing +
          (metrics.mainAxisSpacing / 2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Draw vertical lines (Main-axis columns)
    final slotWidthWithSpacing = metrics.slotWidth + metrics.crossAxisSpacing;
    if (slotWidthWithSpacing <= 0) return;

    final firstLineX = metrics.slotWidth + (metrics.crossAxisSpacing / 2);

    for (var x = firstLineX; x < size.width; x += slotWidthWithSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GridBackgroundPainter oldDelegate) {
    return oldDelegate.metrics != metrics ||
        oldDelegate.scrollOffset != scrollOffset ||
        oldDelegate.activeItem != activeItem ||
        oldDelegate.placeholder != placeholder ||
        oldDelegate.sliverTop != sliverTop ||
        oldDelegate.sliverHeight != sliverHeight;
  }
}
