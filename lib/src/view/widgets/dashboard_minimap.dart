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
              child: SizedBox(
                width: drawnWidth,
                height: drawnHeight,
                child: Stack(
                  children: [
                    // Item layer: repaints ONLY when the layout instance
                    // changes. Isolated behind a RepaintBoundary so scroll
                    // ticks never re-rasterize 1,000 item rects.
                    RepaintBoundary(
                      child: CustomPaint(
                        size: Size(drawnWidth, drawnHeight),
                        painter: _MinimapItemsPainter(
                          layout: layout,
                          style: style,
                          scale: scale,
                          unitWidth: unitWidth,
                          unitHeight: unitHeight,
                          spacingRatioMain: spacingRatioMain,
                          spacingRatioCross: spacingRatioCross,
                          isVertical: isVertical,
                        ),
                      ),
                    ),
                    // Viewport layer: repaints on every scroll tick via the
                    // `repaint` listenable (fixes the stale indicator bug —
                    // the old shouldRepaint ignored scroll entirely).
                    CustomPaint(
                      size: Size(drawnWidth, drawnHeight),
                      painter: _MinimapViewportPainter(
                        scrollController: scrollController,
                        style: style,
                        isVertical: isVertical,
                        minimapContentMainAxis: isVertical ? drawnHeight : drawnWidth,
                      ),
                    ),
                  ],
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

class _MinimapItemsPainter extends CustomPainter {
  _MinimapItemsPainter({
    required this.layout,
    required this.style,
    required this.scale,
    required this.unitWidth,
    required this.unitHeight,
    required this.spacingRatioMain,
    required this.spacingRatioCross,
    required this.isVertical,
  });

  final List<LayoutItem> layout;
  final MinimapStyle style;
  final double scale;
  final double unitWidth;
  final double unitHeight;
  final double spacingRatioMain;
  final double spacingRatioCross;
  final bool isVertical;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = style.backgroundColor);

    // Batch all item rounded-rects into two paths: two drawPath commands
    // instead of one drawRRect per item (1,000 canvas commands at N=1000),
    // which dominates minimap paint time on the web renderers.
    final dynamicPath = Path();
    final staticPath = Path();
    final radius = Radius.circular(style.itemBorderRadius);

    for (final item in layout) {
      final double x;
      final double y;
      final double w;
      final double h;

      if (isVertical) {
        x = (item.x * unitWidth + item.x * spacingRatioCross) * scale;
        y = (item.y * unitHeight + item.y * spacingRatioMain) * scale;
        w = (item.w * unitWidth + (max(0, item.w - 1) * spacingRatioCross)) * scale;
        h = (item.h * unitHeight + (max(0, item.h - 1) * spacingRatioMain)) * scale;
      } else {
        x = (item.x * unitWidth + item.x * spacingRatioMain) * scale;
        y = (item.y * unitHeight + item.y * spacingRatioCross) * scale;
        w = (item.w * unitWidth + (max(0, item.w - 1) * spacingRatioMain)) * scale;
        h = (item.h * unitHeight + (max(0, item.h - 1) * spacingRatioCross)) * scale;
      }

      final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), radius);
      (item.isStatic ? staticPath : dynamicPath).addRRect(rrect);
    }

    canvas
      ..drawPath(dynamicPath, Paint()..color = style.itemColor)
      ..drawPath(staticPath, Paint()..color = style.staticItemColor);
  }

  @override
  bool shouldRepaint(covariant _MinimapItemsPainter oldDelegate) {
    return !identical(oldDelegate.layout, layout) ||
        oldDelegate.style != style ||
        oldDelegate.scale != scale ||
        oldDelegate.unitWidth != unitWidth ||
        oldDelegate.unitHeight != unitHeight ||
        oldDelegate.spacingRatioMain != spacingRatioMain ||
        oldDelegate.spacingRatioCross != spacingRatioCross ||
        oldDelegate.isVertical != isVertical;
  }
}

class _MinimapViewportPainter extends CustomPainter {
  _MinimapViewportPainter({
    required this.scrollController,
    required this.style,
    required this.isVertical,
    required this.minimapContentMainAxis,
    // Repaint automatically on every scroll notification without rebuilding
    // or re-rasterizing the item layer.
  }) : super(repaint: scrollController);

  final ScrollController scrollController;
  final MinimapStyle style;
  final bool isVertical;
  final double minimapContentMainAxis;

  @override
  void paint(Canvas canvas, Size size) {
    if (!scrollController.hasClients || !scrollController.position.haveDimensions) return;

    final position = scrollController.position;
    final viewportSize = position.viewportDimension;
    final totalContentSize = position.maxScrollExtent + viewportSize;
    if (totalContentSize <= 0) return;

    final ratio = minimapContentMainAxis / totalContentSize;
    final viewportStart = position.pixels * ratio;
    final viewportLength = viewportSize * ratio;
    final clampedStart = viewportStart.clamp(0.0, minimapContentMainAxis);

    final viewportRect = isVertical
        ? Rect.fromLTWH(0, clampedStart, size.width, viewportLength)
        : Rect.fromLTWH(clampedStart, 0, viewportLength, size.height);

    canvas
      ..drawRect(viewportRect, Paint()..color = style.viewportColor)
      ..drawRect(
        viewportRect,
        Paint()
          ..color = style.viewportBorderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.viewportBorderWidth,
      );
  }

  @override
  bool shouldRepaint(covariant _MinimapViewportPainter oldDelegate) {
    return oldDelegate.scrollController != scrollController ||
        oldDelegate.style != style ||
        oldDelegate.isVertical != isVertical ||
        oldDelegate.minimapContentMainAxis != minimapContentMainAxis;
  }
}
