import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
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
    this.markers = const <MinimapMarker>[],
    this.viewportIndicators,
    this.mainAxisLeadingExtent,
    this.mainAxisContentExtent,
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

  /// Custom overlay markers (status dots, selection badges…) rendered over
  /// specific items. Painted in a dedicated cached layer: all markers are
  /// batched into one [Path] per distinct color, and the layer only
  /// re-rasterizes when this list changes by value (`listEquals`), never on
  /// scroll.
  final List<MinimapMarker> markers;

  /// The scroll offset at which the grid's segment starts inside the
  /// scrollable (extent of every sliver before it: app bars, headers…).
  /// When null (default), the exact `precedingScrollExtent` published by the
  /// grid sliver at each layout pass is used. Used by the default viewport
  /// indicator and by tap/drag-to-scroll.
  /// Ignored when [viewportIndicators] is provided.
  final double? mainAxisLeadingExtent;

  /// The scroll extent of the grid's segment. When null (default), it is
  /// derived from the layout and the live slot metrics — an approximation
  /// that excludes any `SliverPadding` wrapped around the grid sliver; pass
  /// the exact extent here if that approximation is off for your tree.
  /// Ignored when [viewportIndicators] is provided.
  final double? mainAxisContentExtent;

  /// The viewport indicators to paint. When null (default), one indicator is
  /// derived from [scrollController], mapped onto the *grid's own scroll
  /// segment* ([mainAxisLeadingExtent] / [mainAxisContentExtent]) rather
  /// than the whole scrollable. The two spaces only coincide for a bare grid
  /// alone in its scroll view; with section headers, a `fillViewport`
  /// filler, or preceding slivers, mapping the whole scrollable draws the
  /// indicator at the wrong place/size (degenerate case: a non-scrolling
  /// scrollable covers the entire minimap).
  ///
  /// Provide several [ViewportIndicator]s when multiple sibling
  /// `SliverDashboard`s share the scroll view: each indicator maps the
  /// visible window onto its own scroll segment. All indicators are painted
  /// by the single viewport layer, whose `repaint` listenable merges every
  /// indicator's controller — scroll ticks still never touch the item or
  /// marker layers.
  final List<ViewportIndicator>? viewportIndicators;

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

        // Main-axis pixel extent of the grid content (rows/columns +
        // spacings), derived from the live slot metrics. Drives the default
        // viewport-indicator segment and tap-to-scroll so both live in the
        // SAME coordinate space as the painted items — not the whole
        // scrollable. 0 when metrics are unavailable (no clients yet).
        var derivedGridExtent = 0.0;

        // Exact metrics published by RenderSliverDashboard at each layout
        // pass (preceding extent, own scroll extent, real slot sizes).
        // Preferred over any local derivation: the historical approximation
        // used position.viewportDimension — the SCROLL-axis size — as the
        // cross-axis width, which skews every derived pixel value.
        final internal = controller.internal;
        final pubSlotW = internal.viewSlotWidth;
        final pubSlotH = internal.viewSlotHeight;
        final pubExtent = internal.viewMainAxisContentExtent;
        final pubLeading = internal.viewMainAxisLeadingExtent;

        if (pubSlotW != null && pubSlotH != null && pubSlotW > 0 && pubSlotH > 0) {
          if (isVertical) {
            spacingRatioCross = crossAxisSpacing / pubSlotW;
            spacingRatioMain = mainAxisSpacing / pubSlotH;
          } else {
            spacingRatioCross = crossAxisSpacing / pubSlotH;
            spacingRatioMain = mainAxisSpacing / pubSlotW;
          }
        } else if (scrollController.hasClients && scrollController.position.haveDimensions) {
          // Fallback before the first layout: legacy approximation.
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
              derivedGridExtent = maxY * realSlotHeight + max(0, maxY - 1) * mainAxisSpacing;
            }
          } else {
            // Horizontal logic
            final realSlotHeight = (viewportSize - padding.vertical) / slotCount;
            if (realSlotHeight > 0) {
              final realSlotWidth = realSlotHeight * slotAspectRatio;
              spacingRatioCross = crossAxisSpacing / realSlotHeight;
              spacingRatioMain = mainAxisSpacing / realSlotWidth;
              derivedGridExtent = maxX * realSlotWidth + max(0, maxX - 1) * mainAxisSpacing;
            }
          }
        }

        // Segment of the scrollable depicted by this minimap. Precedence:
        // explicit widget values > exact published metrics > legacy
        // approximation (which excludes any SliverPadding around the grid).
        final segmentExtent = mainAxisContentExtent ??
            pubExtent ??
            (derivedGridExtent > 0 ? derivedGridExtent : null);
        final segmentLeading = mainAxisLeadingExtent ?? pubLeading ?? 0.0;

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
                segmentExtent: segmentExtent,
                segmentLeading: segmentLeading,
              ),
              onPanUpdate: (details) => _handleInteraction(
                details.localPosition,
                isVertical ? drawnHeight : drawnWidth,
                isVertical,
                segmentExtent: segmentExtent,
                segmentLeading: segmentLeading,
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
                    if (markers.isNotEmpty)
                      RepaintBoundary(
                        child: CustomPaint(
                          size: Size(drawnWidth, drawnHeight),
                          painter: _MinimapMarkersPainter(
                            layout: layout,
                            markers: markers,
                            scale: scale,
                            unitWidth: unitWidth,
                            unitHeight: unitHeight,
                            spacingRatioMain: spacingRatioMain,
                            spacingRatioCross: spacingRatioCross,
                            isVertical: isVertical,
                          ),
                        ),
                      ),
                    CustomPaint(
                      size: Size(drawnWidth, drawnHeight),
                      painter: _MinimapViewportPainter(
                        indicators: viewportIndicators ??
                            <ViewportIndicator>[
                              ViewportIndicator(
                                scrollController: scrollController,
                                mainAxisLeadingExtent: segmentLeading,
                                mainAxisContentExtent: segmentExtent,
                              ),
                            ],
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
    bool isVertical, {
    double? segmentExtent,
    double? segmentLeading,
  }) {
    if (!scrollController.hasClients || !scrollController.position.haveDimensions) return;

    final position = scrollController.position;
    final viewportDimension = position.viewportDimension;
    final maxScroll = position.maxScrollExtent;
    final totalContentSize = maxScroll + viewportDimension;

    if (totalContentSize <= 0 || minimapMainAxisSize <= 0) return;

    // Same coordinate space as the painted items and the default viewport
    // indicator: the minimap depicts the grid's scroll segment
    // [leading, leading + segmentLen], not the whole scrollable.
    final leading = segmentLeading ?? mainAxisLeadingExtent ?? 0.0;
    final segmentLen = segmentExtent ?? (totalContentSize - leading);
    if (segmentLen <= 0) return;

    final ratio = segmentLen / minimapMainAxisSize;
    final touchPos = isVertical ? localPosition.dy : localPosition.dx;
    final targetCenter = leading + touchPos * ratio;
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

/// Paints one or several viewport indicators.
///
/// Bound via `super(repaint: ...)` to every indicator's scroll controller, so
/// scroll ticks repaint only this thin layer — never the item or marker
/// layers (the two-layer invariant, extended).
class _MinimapViewportPainter extends CustomPainter {
  _MinimapViewportPainter({
    required this.indicators,
    required this.style,
    required this.isVertical,
    required this.minimapContentMainAxis,
    // Repaint automatically on every scroll notification without rebuilding
    // or re-rasterizing the item layer. A single indicator listens to its
    // controller directly (no merge allocation on the common path).
  }) : super(
          repaint: indicators.length == 1
              ? indicators.first.scrollController
              : Listenable.merge(
                  <Listenable>[for (final i in indicators) i.scrollController],
                ),
        );

  final List<ViewportIndicator> indicators;
  final MinimapStyle style;
  final bool isVertical;
  final double minimapContentMainAxis;

  @override
  void paint(Canvas canvas, Size size) {
    // Reason: two Paint objects for the whole layer regardless of the number
    // of indicators; fill/stroke settings are mutated per indicator.
    final fill = Paint();
    final stroke = Paint()..style = PaintingStyle.stroke;

    for (final indicator in indicators) {
      final controller = indicator.scrollController;
      if (!controller.hasClients || !controller.position.haveDimensions) continue;

      final position = controller.position;
      final viewportSize = position.viewportDimension;
      final totalContentSize = position.maxScrollExtent + viewportSize;
      if (totalContentSize <= 0) continue;

      // Map the visible window [pixels, pixels + viewport] onto this
      // indicator's segment [leading, leading + segmentLen].
      final segmentStart = indicator.mainAxisLeadingExtent;
      final segmentLen = indicator.mainAxisContentExtent ?? (totalContentSize - segmentStart);

      final mapped = mapViewportToSegment(
        pixels: position.pixels,
        viewportDimension: viewportSize,
        segmentLeading: segmentStart,
        segmentExtent: segmentLen,
        minimapMainAxis: minimapContentMainAxis,
      );
      if (mapped == null) continue; // segment empty or fully off-screen

      final indicatorStart = mapped.$1;
      final indicatorLength = mapped.$2;

      final viewportRect = isVertical
          ? Rect.fromLTWH(0, indicatorStart, size.width, indicatorLength)
          : Rect.fromLTWH(indicatorStart, 0, indicatorLength, size.height);

      fill.color = indicator.color ?? style.viewportColor;
      stroke
        ..color = indicator.borderColor ?? style.viewportBorderColor
        ..strokeWidth = indicator.borderWidth ?? style.viewportBorderWidth;

      canvas
        ..drawRect(viewportRect, fill)
        ..drawRect(viewportRect, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapViewportPainter oldDelegate) {
    return !listEquals(oldDelegate.indicators, indicators) ||
        oldDelegate.style != style ||
        oldDelegate.isVertical != isVertical ||
        oldDelegate.minimapContentMainAxis != minimapContentMainAxis;
  }
}

/// Maps the scrollable's visible window onto a minimap of one scroll
/// segment. Returns `(indicatorStart, indicatorLength)` in minimap logical
/// pixels, or null when nothing of the segment is visible.
///
/// Contract (unit-tested — the anti-"gauge" invariant): as long as the
/// window stays strictly inside the segment, the indicator LENGTH is the
/// constant `viewportDimension / segmentExtent * minimapMainAxis` and only
/// its START moves with `pixels`. Length may only shrink by clamping at the
/// segment's edges.
@visibleForTesting
(double, double)? mapViewportToSegment({
  required double pixels,
  required double viewportDimension,
  required double segmentLeading,
  required double segmentExtent,
  required double minimapMainAxis,
}) {
  if (segmentExtent <= 0 || minimapMainAxis <= 0) return null;
  final visibleStart = (pixels - segmentLeading).clamp(0.0, segmentExtent);
  final visibleEnd = (pixels + viewportDimension - segmentLeading).clamp(0.0, segmentExtent);
  if (visibleEnd <= visibleStart) return null;
  final ratio = minimapMainAxis / segmentExtent;
  return (visibleStart * ratio, (visibleEnd - visibleStart) * ratio);
}

/// Paints the custom overlay markers in an isolated cached layer.
///
/// Performance contract:
///  * all markers of a given color are batched into ONE [Path] — the number
///    of canvas commands is the number of distinct colors, not of markers;
///  * one reusable [Paint] for the whole layer, mutated per color group;
///  * the layer is behind its own `RepaintBoundary` and `shouldRepaint`
///    short-circuits on value equality, so scroll ticks and unrelated
///    rebuilds cost zero raster work here.
class _MinimapMarkersPainter extends CustomPainter {
  _MinimapMarkersPainter({
    required this.layout,
    required this.markers,
    required this.scale,
    required this.unitWidth,
    required this.unitHeight,
    required this.spacingRatioMain,
    required this.spacingRatioCross,
    required this.isVertical,
  });

  final List<LayoutItem> layout;
  final List<MinimapMarker> markers;
  final double scale;
  final double unitWidth;
  final double unitHeight;
  final double spacingRatioMain;
  final double spacingRatioCross;
  final bool isVertical;

  @override
  void paint(Canvas canvas, Size size) {
    if (markers.isEmpty || layout.isEmpty) return;

    // One path per distinct color; typical marker sets use 1-3 colors so the
    // map stays tiny. Built only when the layer actually re-rasterizes
    // (markers or layout changed) — never on scroll.
    final pathsByColor = <Color, Path>{};

    for (final marker in markers) {
      LayoutItem? item;
      for (final candidate in layout) {
        if (candidate.id == marker.itemId) {
          item = candidate;
          break;
        }
      }
      if (item == null) continue; // unknown id: ignore silently

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

      // Cap the marker to the item's minimap rectangle: a 24 px marker on a
      // 15 px 1x1 tile would otherwise invert the clamp bounds below
      // (min > max throws ArgumentError). The declared size is a maximum.
      final effSize = min(marker.size, min(w, h));
      if (effSize <= 0) continue;
      final half = effSize / 2;
      // Resolve the alignment inside the item's rect, keeping the marker
      // fully inside it.
      final cx = x + (marker.alignment.x + 1) / 2 * w;
      final cy = y + (marker.alignment.y + 1) / 2 * h;
      final mx = cx.clamp(x + half, x + w - half);
      final my = cy.clamp(y + half, y + h - half);

      final path = pathsByColor.putIfAbsent(marker.color, Path.new);
      switch (marker.shape) {
        case MinimapMarkerShape.circle:
          path.addOval(Rect.fromCircle(center: Offset(mx, my), radius: half));
        case MinimapMarkerShape.square:
          path.addRect(
            Rect.fromCenter(
              center: Offset(mx, my),
              width: effSize,
              height: effSize,
            ),
          );
        case MinimapMarkerShape.diamond:
          path
            ..moveTo(mx, my - half)
            ..lineTo(mx + half, my)
            ..lineTo(mx, my + half)
            ..lineTo(mx - half, my)
            ..close();
        case MinimapMarkerShape.triangle:
          path
            ..moveTo(mx, my - half)
            ..lineTo(mx + half, my + half)
            ..lineTo(mx - half, my + half)
            ..close();
      }
    }

    final paint = Paint();
    pathsByColor.forEach((color, path) {
      paint.color = color;
      canvas.drawPath(path, paint);
    });
  }

  @override
  bool shouldRepaint(covariant _MinimapMarkersPainter oldDelegate) {
    return !identical(oldDelegate.layout, layout) ||
        !listEquals(oldDelegate.markers, markers) ||
        oldDelegate.scale != scale ||
        oldDelegate.unitWidth != unitWidth ||
        oldDelegate.unitHeight != unitHeight ||
        oldDelegate.spacingRatioMain != spacingRatioMain ||
        oldDelegate.spacingRatioCross != spacingRatioCross ||
        oldDelegate.isVertical != isVertical;
  }
}
