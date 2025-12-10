import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/widgets/minimap_style.dart';
import 'package:state_beacon/state_beacon.dart';

/// A widget that displays a miniature representation of the dashboard layout
/// and the current viewport (visible area).
///
/// It allows navigation by clicking or dragging the viewport indicator.
class DashboardMinimap extends StatelessWidget {
  /// Creates a [DashboardMinimap].
  const DashboardMinimap({
    required this.controller,
    required this.scrollController,
    super.key,
    this.style = const MinimapStyle(),
    this.width = 100.0,
    this.slotAspectRatio = 1.0,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
    this.padding = EdgeInsets.zero,
  });

  /// The dashboard controller containing the layout data.
  final DashboardController controller;

  /// The scroll controller of the dashboard.
  /// Used to calculate and draw the viewport indicator (visible range).
  final ScrollController scrollController;

  /// The visual style configuration (colors, borders, radius).
  final MinimapStyle style;

  /// The desired width of the minimap.
  /// The height will be calculated automatically based on the content aspect ratio.
  final double width;

  /// The aspect ratio of the dashboard slots (width / height).
  /// Used to calculate relative heights in the minimap.
  final double slotAspectRatio;

  /// The main axis spacing used in the real dashboard.
  final double mainAxisSpacing;

  /// The cross axis spacing used in the real dashboard.
  final double crossAxisSpacing;

  /// The padding used in the real dashboard.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final layout = controller.layout.watch(context);
    final slotCount = controller.slotCount.watch(context);
    final scrollDirection = controller.scrollDirection.watch(context);

    // --- 1. Pre-calculate Metrics ---
    final isVertical = scrollDirection == Axis.vertical;

    // Calculate logical grid dimensions
    var maxMainAxis = 0;
    for (final item in layout) {
      final end = isVertical ? item.y + item.h : item.x + item.w;
      if (end > maxMainAxis) maxMainAxis = end;
    }
    maxMainAxis = max(maxMainAxis, 1);

    // Virtual slot dimensions (normalized)
    const virtualSlotCrossAxis = 1.0;
    final virtualSlotMainAxis = virtualSlotCrossAxis / slotAspectRatio;

    double totalRealCrossAxisExtent;
    double totalRealMainAxisExtent;

    if (isVertical) {
      totalRealCrossAxisExtent = slotCount * virtualSlotCrossAxis;
      totalRealMainAxisExtent = maxMainAxis * virtualSlotMainAxis;
    } else {
      totalRealCrossAxisExtent = slotCount * virtualSlotMainAxis;
      totalRealMainAxisExtent = maxMainAxis * virtualSlotCrossAxis;
    }

    // Calculate scale to fit the width
    final scale = width / totalRealCrossAxisExtent;

    // Calculate the drawn height of the content in the minimap
    final minimapContentSize = totalRealMainAxisExtent * scale;

    return AnimatedBuilder(
      animation: scrollController,
      builder: (context, _) {
        return GestureDetector(
          // Handle Click (Jump)
          onTapUp: (details) => _handleInteraction(
            details.localPosition,
            minimapContentSize,
            isVertical,
          ),
          // Handle Drag (Scrub)
          onPanUpdate: (details) => _handleInteraction(
            details.localPosition,
            minimapContentSize,
            isVertical,
          ),
          child: CustomPaint(
            size: Size(width, minimapContentSize),
            painter: _MinimapPainter(
              layout: layout,
              slotCount: slotCount,
              scrollController: scrollController,
              style: style,
              slotAspectRatio: slotAspectRatio,
              scrollDirection: scrollDirection,
              padding: padding,
              scale: scale,
              virtualSlotCrossAxis: virtualSlotCrossAxis,
              virtualSlotMainAxis: virtualSlotMainAxis,
              minimapContentSize: minimapContentSize,
            ),
          ),
        );
      },
    );
  }

  void _handleInteraction(
    Offset localPosition,
    double minimapSize,
    bool isVertical,
  ) {
    if (!scrollController.hasClients) return;

    final position = scrollController.position;
    final viewportDimension = position.viewportDimension;
    final maxScroll = position.maxScrollExtent;
    final totalContentSize = maxScroll + viewportDimension;

    if (totalContentSize <= 0 || minimapSize <= 0) return;

    // Ratio: 1 pixel on minimap = X pixels on scroll view
    final ratio = totalContentSize / minimapSize;

    // Position touched on the minimap axis
    final touchPos = isVertical ? localPosition.dy : localPosition.dx;

    // Convert to scroll offset
    final targetCenter = touchPos * ratio;

    // We want the touched point to be the CENTER of the viewport, not the top.
    final targetStart = targetCenter - (viewportDimension / 2);

    // Clamp to valid scroll range
    final clampedOffset = targetStart.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    scrollController.jumpTo(clampedOffset);
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.layout,
    required this.slotCount,
    required this.scrollController,
    required this.style,
    required this.slotAspectRatio,
    required this.scrollDirection,
    required this.padding,
    required this.scale,
    required this.virtualSlotCrossAxis,
    required this.virtualSlotMainAxis,
    required this.minimapContentSize,
  });

  final List<LayoutItem> layout;
  final int slotCount;
  final ScrollController scrollController;
  final MinimapStyle style;
  final double slotAspectRatio;
  final Axis scrollDirection;
  final EdgeInsets padding;
  final double scale;
  final double virtualSlotCrossAxis;
  final double virtualSlotMainAxis;
  final double minimapContentSize;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = style.backgroundColor;
    final isVertical = scrollDirection == Axis.vertical;

    // Draw Background
    canvas.drawRect(Offset.zero & size, bgPaint);

    // --- Draw Items ---
    final itemPaint = Paint()..color = style.itemColor;
    final staticItemPaint = Paint()..color = style.staticItemColor;

    for (final item in layout) {
      double x;
      double y;
      double w;
      double h;

      if (isVertical) {
        x = item.x * virtualSlotCrossAxis;
        y = item.y * virtualSlotMainAxis;
        w = item.w * virtualSlotCrossAxis;
        h = item.h * virtualSlotMainAxis;
      } else {
        x = item.x * virtualSlotMainAxis;
        y = item.y * virtualSlotCrossAxis;
        w = item.w * virtualSlotMainAxis;
        h = item.h * virtualSlotCrossAxis;
      }

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x * scale, y * scale, w * scale, h * scale),
        Radius.circular(style.itemBorderRadius),
      );

      canvas.drawRRect(
        rect,
        item.isStatic ? staticItemPaint : itemPaint,
      );
    }

    // --- Draw Viewport ---
    if (scrollController.hasClients) {
      final position = scrollController.position;
      final viewportSize = position.viewportDimension;
      final maxScroll = position.maxScrollExtent;
      final currentScroll = position.pixels;

      final totalContentSize = maxScroll + viewportSize;

      if (totalContentSize > 0) {
        // Ratio: Minimap / Real
        final ratio = minimapContentSize / totalContentSize;

        final viewportY = currentScroll * ratio;
        final viewportH = viewportSize * ratio;

        // Clamp visual drawing to bounds
        final clampedY = viewportY.clamp(0.0, minimapContentSize);

        final viewportRect = Rect.fromLTWH(
          0,
          clampedY,
          size.width,
          viewportH,
        );

        canvas.drawRect(viewportRect, Paint()..color = style.viewportColor);

        final borderPaint = Paint()
          ..color = style.viewportBorderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.viewportBorderWidth;
        canvas.drawRect(viewportRect, borderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.slotCount != slotCount ||
        oldDelegate.style != style ||
        oldDelegate.scrollController != scrollController ||
        oldDelegate.scale != scale ||
        oldDelegate.minimapContentSize != minimapContentSize;
  }
}
