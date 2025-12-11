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
    this.width,
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
  final double? width;

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

    // Rebuild when scroll controller attaches/detaches to get viewport dimensions
    return AnimatedBuilder(
      animation: scrollController,
      builder: (context, _) {
        final isVertical = scrollDirection == Axis.vertical;

        // Calculate logical grid dimensions
        var maxX = 0;
        var maxY = 0;
        for (final item in layout) {
          if (item.x + item.w > maxX) maxX = item.x + item.w;
          if (item.y + item.h > maxY) maxY = item.y + item.h;
        }
        maxX = max(maxX, 1);
        maxY = max(maxY, 1);

        // Calculate Unit Sizes & Spacing Ratio ---
        double unitWidth;
        double unitHeight;

        // We need to convert pixel spacing (e.g. 10px) into "Grid Units".
        // To do this, we need the size of 1 slot in pixels.
        var spacingRatioMain = 0.0;
        var spacingRatioCross = 0.0;

        if (scrollController.hasClients && scrollController.position.haveDimensions) {
          final viewportSize = scrollController.position.viewportDimension;
          if (isVertical) {
            // Real Width of 1 slot in pixels
            final realSlotWidth = (viewportSize - padding.horizontal) / slotCount;
            if (realSlotWidth > 0) {
              final realSlotHeight = realSlotWidth / slotAspectRatio;
              // How many "Units" is the spacing?
              // UnitWidth is 1.0. Spacing is X pixels.
              // Ratio = SpacingPx / SlotWidthPx
              spacingRatioCross = crossAxisSpacing / realSlotWidth;
              spacingRatioMain = mainAxisSpacing / realSlotHeight;
            }
          } else {
            // Horizontal logic
            final realSlotHeight = (viewportSize - padding.vertical) / slotCount;
            if (realSlotHeight > 0) {
              final realSlotWidth = realSlotHeight * slotAspectRatio;
              spacingRatioCross = crossAxisSpacing / realSlotHeight;
              spacingRatioMain = mainAxisSpacing / realSlotWidth;
            }
          }
        }

        double logicalGridWidth;
        double logicalGridHeight;

        if (isVertical) {
          unitWidth = 1.0;
          unitHeight = 1.0 / slotAspectRatio;

          // Total Width = Slots + Spacings
          logicalGridWidth = slotCount * unitWidth + (max(0, slotCount - 1) * spacingRatioCross);
          // Total Height = Rows + Spacings
          logicalGridHeight = maxY * unitHeight + (max(0, maxY - 1) * spacingRatioMain);
        } else {
          unitHeight = 1.0;
          unitWidth = 1.0 * slotAspectRatio;

          logicalGridHeight = slotCount * unitHeight + (max(0, slotCount - 1) * spacingRatioCross);
          logicalGridWidth = maxX * unitWidth + (max(0, maxX - 1) * spacingRatioMain);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = width ?? constraints.maxWidth;
            final availableHeight = constraints.maxHeight;

            if (availableWidth == double.infinity && width == null) {
              return const SizedBox();
            }

            // Calculate Scale to FIT
            final scaleX = availableWidth / logicalGridWidth;

            var scale = scaleX;
            if (availableHeight.isFinite) {
              final scaleY = availableHeight / logicalGridHeight;
              scale = min(scaleX, scaleY);
            }

            final drawnWidth = logicalGridWidth * scale;
            final drawnHeight = logicalGridHeight * scale;

            return GestureDetector(
              onTapUp: (details) => _handleInteraction(
                details.localPosition,
                isVertical ? drawnHeight : drawnWidth,
                isVertical,
              ),
              onPanUpdate: (details) => _handleInteraction(
                details.localPosition,
                isVertical ? drawnHeight : drawnWidth,
                isVertical,
              ),
              child: CustomPaint(
                size: Size(drawnWidth, drawnHeight),
                painter: _MinimapPainter(
                  layout: layout,
                  scrollController: scrollController,
                  style: style,
                  padding: padding,
                  scale: scale,
                  unitWidth: unitWidth,
                  unitHeight: unitHeight,
                  spacingRatioMain: spacingRatioMain,
                  spacingRatioCross: spacingRatioCross,
                  scrollDirection: scrollDirection,
                  minimapContentMainAxis: isVertical ? drawnHeight : drawnWidth,
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _handleInteraction(
    Offset localPosition,
    double minimapMainAxisSize,
    bool isVertical,
  ) {
    if (!scrollController.hasClients || !scrollController.position.haveDimensions) return;

    final position = scrollController.position;
    final viewportDimension = position.viewportDimension;
    final maxScroll = position.maxScrollExtent;
    final totalContentSize = maxScroll + viewportDimension;

    if (totalContentSize <= 0 || minimapMainAxisSize <= 0) return;

    final ratio = totalContentSize / minimapMainAxisSize;
    final touchPos = isVertical ? localPosition.dy : localPosition.dx;
    final targetCenter = touchPos * ratio;
    final targetStart = targetCenter - (viewportDimension / 2);

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
    required this.scrollController,
    required this.style,
    required this.padding,
    required this.scale,
    required this.unitWidth,
    required this.unitHeight,
    required this.spacingRatioMain,
    required this.spacingRatioCross,
    required this.scrollDirection,
    required this.minimapContentMainAxis,
  });

  final List<LayoutItem> layout;
  final ScrollController scrollController;
  final MinimapStyle style;
  final EdgeInsets padding;
  final double scale;
  final double unitWidth;
  final double unitHeight;
  final double spacingRatioMain;
  final double spacingRatioCross;
  final Axis scrollDirection;
  final double minimapContentMainAxis;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = style.backgroundColor;
    final isVertical = scrollDirection == Axis.vertical;

    canvas.drawRect(Offset.zero & size, bgPaint);

    final itemPaint = Paint()..color = style.itemColor;
    final staticItemPaint = Paint()..color = style.staticItemColor;

    for (final item in layout) {
      // Apply spacing to coordinates
      // Position = (Index * UnitSize) + (Index * SpacingSize)
      // Size = (Size * UnitSize) + ((Size - 1) * SpacingSize)

      double x;
      double y;
      double w;
      double h;

      if (isVertical) {
        // Vertical: X is Cross, Y is Main
        x = (item.x * unitWidth + item.x * spacingRatioCross) * scale;
        y = (item.y * unitHeight + item.y * spacingRatioMain) * scale;

        // Width includes internal spacings if item spans multiple slots
        w = (item.w * unitWidth + (max(0, item.w - 1) * spacingRatioCross)) * scale;
        h = (item.h * unitHeight + (max(0, item.h - 1) * spacingRatioMain)) * scale;
      } else {
        // Horizontal: X is Main, Y is Cross
        x = (item.x * unitWidth + item.x * spacingRatioMain) * scale;
        y = (item.y * unitHeight + item.y * spacingRatioCross) * scale;

        w = (item.w * unitWidth + (max(0, item.w - 1) * spacingRatioMain)) * scale;
        h = (item.h * unitHeight + (max(0, item.h - 1) * spacingRatioCross)) * scale;
      }

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        Radius.circular(style.itemBorderRadius),
      );

      canvas.drawRRect(
        rect,
        item.isStatic ? staticItemPaint : itemPaint,
      );
    }

    if (scrollController.hasClients && scrollController.position.haveDimensions) {
      final position = scrollController.position;
      final viewportSize = position.viewportDimension;
      final maxScroll = position.maxScrollExtent;
      final currentScroll = position.pixels;
      final totalContentSize = maxScroll + viewportSize;

      if (totalContentSize > 0) {
        final ratio = minimapContentMainAxis / totalContentSize;
        final viewportStart = currentScroll * ratio;
        final viewportLength = viewportSize * ratio;
        final clampedStart = viewportStart.clamp(0.0, minimapContentMainAxis);

        final Rect viewportRect;
        if (isVertical) {
          viewportRect = Rect.fromLTWH(0, clampedStart, size.width, viewportLength);
        } else {
          viewportRect = Rect.fromLTWH(clampedStart, 0, viewportLength, size.height);
        }

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
        oldDelegate.style != style ||
        oldDelegate.scrollController != scrollController ||
        oldDelegate.scale != scale ||
        oldDelegate.scrollDirection != scrollDirection ||
        oldDelegate.spacingRatioMain != spacingRatioMain ||
        oldDelegate.spacingRatioCross != spacingRatioCross;
  }
}
