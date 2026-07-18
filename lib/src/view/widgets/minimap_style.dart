import 'package:flutter/material.dart';

/// Configuration for the visual appearance of the DashboardMinimap.
@immutable
class MinimapStyle {
  /// Creates a [MinimapStyle].
  const MinimapStyle({
    this.backgroundColor = const Color(0xFFE0E0E0),
    this.itemColor = const Color(0xFF9E9E9E),
    this.staticItemColor = const Color(0xFF616161),
    this.viewportColor = const Color(0x332196F3),
    this.viewportBorderColor = const Color(0xFF2196F3),
    this.itemBorderRadius = 2.0,
    this.viewportBorderWidth = 2.0,
  });

  /// The background color of the minimap area.
  final Color backgroundColor;

  /// The color of standard items in the minimap.
  final Color itemColor;

  /// The color of static items in the minimap.
  final Color staticItemColor;

  /// The fill color of the viewport rectangle (the visible area).
  final Color viewportColor;

  /// The border color of the viewport rectangle.
  final Color viewportBorderColor;

  /// The border radius for items in the minimap.
  final double itemBorderRadius;

  /// The width of the viewport border.
  final double viewportBorderWidth;

  // Reason: every CustomPainter parameter type must support value equality so
  // shouldRepaint can short-circuit (see the SlotMetrics rule). Without this,
  // a MinimapStyle constructed inline in build() re-rasterizes the item layer
  // on every scroll tick.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MinimapStyle &&
          runtimeType == other.runtimeType &&
          backgroundColor == other.backgroundColor &&
          itemColor == other.itemColor &&
          staticItemColor == other.staticItemColor &&
          viewportColor == other.viewportColor &&
          viewportBorderColor == other.viewportBorderColor &&
          itemBorderRadius == other.itemBorderRadius &&
          viewportBorderWidth == other.viewportBorderWidth;

  @override
  int get hashCode => Object.hash(
        backgroundColor,
        itemColor,
        staticItemColor,
        viewportColor,
        viewportBorderColor,
        itemBorderRadius,
        viewportBorderWidth,
      );
}

/// The geometric shape of a [MinimapMarker].
enum MinimapMarkerShape {
  /// A filled circle.
  circle,

  /// A filled square.
  square,

  /// A filled diamond (square rotated 45°).
  diamond,

  /// A filled upward-pointing triangle.
  triangle,
}

/// A custom overlay marker rendered over one item in the DashboardMinimap
/// (e.g. a status dot, an active-selection badge).
///
/// Immutable with value equality: unchanged marker lists short-circuit
/// `shouldRepaint` instantly, so the marker layer never re-rasterizes on
/// scroll or on unrelated rebuilds.
@immutable
class MinimapMarker {
  /// Creates a [MinimapMarker].
  const MinimapMarker({
    required this.itemId,
    required this.color,
    this.shape = MinimapMarkerShape.circle,
    this.alignment = Alignment.topRight,
    this.size = 6.0,
  });

  /// The LayoutItem.id this marker decorates. Unknown ids are ignored.
  final String itemId;

  /// The fill color of the marker.
  final Color color;

  /// The marker shape. All markers are batched into one [Path] per distinct
  /// color, so shapes are free — no per-marker canvas command.
  final MinimapMarkerShape shape;

  /// Where the marker sits within the item's minimap rectangle.
  final Alignment alignment;

  /// The marker's diameter/side, in minimap logical pixels.
  final double size;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MinimapMarker &&
          runtimeType == other.runtimeType &&
          itemId == other.itemId &&
          color == other.color &&
          shape == other.shape &&
          alignment == other.alignment &&
          size == other.size;

  @override
  int get hashCode => Object.hash(itemId, color, shape, alignment, size);
}

/// Configuration of one viewport indicator painted by the DashboardMinimap.
///
/// A single scroll view hosting several sibling `SliverDashboard`s produces
/// several scroll segments; each indicator maps the visible window of the
/// scroll view onto its own segment (`mainAxisLeadingExtent` /
/// `mainAxisContentExtent`), so a minimap can show which slice of *its* grid
/// is on screen — or several minimaps can each track their own grid.
@immutable
class ViewportIndicator {
  /// Creates a [ViewportIndicator].
  const ViewportIndicator({
    required this.scrollController,
    this.mainAxisLeadingExtent = 0.0,
    this.mainAxisContentExtent,
    this.color,
    this.borderColor,
    this.borderWidth,
  });

  /// The scroll controller whose position drives this indicator. The painter
  /// listens to all indicator controllers at once (merged listenable), so a
  /// scroll tick repaints only the viewport layer, never the item layer.
  final ScrollController scrollController;

  /// The scroll offset at which this grid's segment starts inside the scroll
  /// view (typically the sliver's `precedingScrollExtent`, i.e. the extent of
  /// every sliver before it — app bars, lists, other grids).
  final double mainAxisLeadingExtent;

  /// The scroll extent of the grid's segment. When null, the segment runs to
  /// the end of the scrollable.
  final double? mainAxisContentExtent;

  /// Overrides [MinimapStyle.viewportColor] for this indicator.
  final Color? color;

  /// Overrides [MinimapStyle.viewportBorderColor] for this indicator.
  final Color? borderColor;

  /// Overrides [MinimapStyle.viewportBorderWidth] for this indicator.
  final double? borderWidth;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewportIndicator &&
          runtimeType == other.runtimeType &&
          identical(scrollController, other.scrollController) &&
          mainAxisLeadingExtent == other.mainAxisLeadingExtent &&
          mainAxisContentExtent == other.mainAxisContentExtent &&
          color == other.color &&
          borderColor == other.borderColor &&
          borderWidth == other.borderWidth;

  @override
  int get hashCode => Object.hash(
        identityHashCode(scrollController),
        mainAxisLeadingExtent,
        mainAxisContentExtent,
        color,
        borderColor,
        borderWidth,
      );
}
