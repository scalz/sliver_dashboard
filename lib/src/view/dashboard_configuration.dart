import 'package:flutter/material.dart';

/// A class to hold styling properties for the background grid.
@immutable
class GridStyle {
  /// Creates a [GridStyle].
  const GridStyle({
    this.lineColor = Colors.black12,
    this.lineWidth = 1.0,
    this.fillColor = Colors.black12,
    this.handleColor,
  });

  /// The color of the grid lines.
  final Color lineColor;

  /// The stroke width of the grid lines.
  final double lineWidth;

  /// The color of the fill that highlights the active item's area.
  final Color fillColor;

  /// The color of the "L" shaped resize handles.
  /// If null, defaults to `Theme.of(context).primaryColor`.
  final Color? handleColor;
}

/// Configuration for the visual appearance of dashboard items.
@immutable
class DashboardItemStyle {
  /// Creates a [DashboardItemStyle].
  const DashboardItemStyle({
    this.focusDecoration,
    this.focusColor,
    this.borderRadius,
  });

  /// The decoration to paint behind the child when the item has focus.
  /// If null, a default border will be used if [focusColor] is provided.
  final BoxDecoration? focusDecoration;

  /// A convenience color for a default focus border.
  /// Ignored if [focusDecoration] is provided.
  final Color? focusColor;

  /// Border radius for the focus highlight.
  final BorderRadius? borderRadius;

  /// Default style
  static const DashboardItemStyle defaultStyle = DashboardItemStyle(
    focusColor: Colors.blueAccent,
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );
}

/// Defines the position of the Trash bin in the Stack.
@immutable
class TrashPosition {
  /// Creates a [TrashPosition].
  const TrashPosition({
    this.left,
    this.top,
    this.right,
    this.bottom,
  });

  /// The position from the left edge of the dashboard.
  final double? left;

  /// The position from the top edge of the dashboard.
  final double? top;

  /// The position from the right edge of the dashboard.
  final double? right;

  /// The position from the bottom edge of the dashboard.
  final double? bottom;

  /// Creates a new [TrashPosition] with updated properties.
  TrashPosition copyWith({
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) {
    return TrashPosition(
      left: left ?? this.left,
      top: top ?? this.top,
      right: right ?? this.right,
      bottom: bottom ?? this.bottom,
    );
  }
}

/// Defines the layout and animation behavior of the Trash bin.
/// It contains both the [visible] position (when dragging) and the [hidden] position.
@immutable
class TrashLayout {
  /// Creates a [TrashPosition].
  const TrashLayout({
    required this.visible,
    required this.hidden,
  });

  /// The position of the Trash bin when it is visible.
  final TrashPosition visible;

  /// The position of the Trash bin when it is hidden.
  final TrashPosition hidden;

  /// Slides up from the bottom center.
  static const TrashLayout bottomCenter = TrashLayout(
    visible: TrashPosition(bottom: 0, left: 0, right: 0),
    hidden: TrashPosition(bottom: -100, left: 0, right: 0),
  );

  /// Slides down from the top center.
  static const TrashLayout topCenter = TrashLayout(
    visible: TrashPosition(top: 0, left: 0, right: 0),
    hidden: TrashPosition(top: -100, left: 0, right: 0),
  );

  /// Slides up from the bottom right (FAB style).
  static const TrashLayout bottomRight = TrashLayout(
    visible: TrashPosition(bottom: 20, right: 20),
    hidden: TrashPosition(bottom: -100, right: 20),
  );

  /// Slides in from the left side.
  static const TrashLayout centerLeft = TrashLayout(
    visible: TrashPosition(left: 0, top: 0, bottom: 0),
    hidden: TrashPosition(left: -200, top: 0, bottom: 0),
  );
}
