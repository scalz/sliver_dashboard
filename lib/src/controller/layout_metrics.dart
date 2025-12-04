import 'package:flutter/material.dart';

/// layout_metrics

/// A utility class to calculate and hold layout metrics for the dashboard.
///
/// This class encapsulates the logic for determining slot sizes based on
/// constraints, spacing, and aspect ratios, as well as converting pixel
/// coordinates to grid coordinates.
class SlotMetrics {
  /// Creates a [SlotMetrics] instance with pre-calculated values.
  const SlotMetrics({
    required this.slotWidth,
    required this.slotHeight,
    required this.mainAxisSpacing,
    required this.crossAxisSpacing,
    required this.padding,
    required this.scrollDirection,
    required this.slotCount,
  });

  /// Calculates layout metrics from the given [BoxConstraints].
  ///
  /// This factory computes the [slotWidth] and [slotHeight] based on the
  /// available space within [constraints] and the provided configuration.
  factory SlotMetrics.fromConstraints(
    BoxConstraints constraints, {
    required int slotCount,
    required double slotAspectRatio,
    required double mainAxisSpacing,
    required double crossAxisSpacing,
    required EdgeInsets padding,
    required Axis scrollDirection,
  }) {
    final isVertical = scrollDirection == Axis.vertical;
    final double slotWidth;
    final double slotHeight;

    if (isVertical) {
      final availableWidth = constraints.maxWidth - padding.horizontal;
      slotWidth = (availableWidth - (slotCount - 1) * crossAxisSpacing) / slotCount;
      slotHeight = slotWidth / slotAspectRatio;
    } else {
      final availableHeight = constraints.maxHeight - padding.vertical;
      slotHeight = (availableHeight - (slotCount - 1) * mainAxisSpacing) / slotCount;
      slotWidth = slotHeight * slotAspectRatio;
    }

    return SlotMetrics(
      slotWidth: slotWidth,
      slotHeight: slotHeight,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      padding: padding,
      scrollDirection: scrollDirection,
      slotCount: slotCount,
    );
  }

  /// The calculated width of a single grid slot.
  final double slotWidth;

  /// The calculated height of a single grid slot.
  final double slotHeight;

  /// The spacing between items on the main axis.
  final double mainAxisSpacing;

  /// The spacing between items on the cross axis.
  final double crossAxisSpacing;

  /// The padding around the dashboard.
  final EdgeInsets padding;

  /// The scroll direction of the dashboard.
  final Axis scrollDirection;

  /// The number of slots (columns or rows depending on direction).
  final int slotCount;

  /// Converts a local pixel position to grid coordinates (x, y).
  ///
  /// [localPosition] is the touch position relative to the dashboard's origin.
  /// [scrollOffset] is the current scroll position of the viewport.
  ///
  /// Returns a record containing the `x` and `y` grid indices.
  ({int x, int y}) pixelToGrid(Offset localPosition, double scrollOffset) {
    final double dx;
    final double dy;

    if (scrollDirection == Axis.vertical) {
      dx = localPosition.dx - padding.left;
      dy = localPosition.dy + scrollOffset - padding.top;

      final x = (dx / (slotWidth + crossAxisSpacing)).floor();
      final y = (dy / (slotHeight + mainAxisSpacing)).floor();
      return (x: x, y: y);
    } else {
      dx = localPosition.dx + scrollOffset - padding.left;
      dy = localPosition.dy - padding.top;

      final x = (dx / (slotWidth + mainAxisSpacing)).floor();
      final y = (dy / (slotHeight + crossAxisSpacing)).floor();
      return (x: x, y: y);
    }
  }
}
