import 'package:flutter/material.dart';

/// Defines what arms a rubberband ("lasso") selection on desktop and web.
///
/// The lasso is always armed on a press over **empty grid space** — a press on
/// a tile is a drag or a resize, never a selection rectangle. This enum only
/// decides whether that press additionally requires a modifier key
/// (DashboardShortcuts.lassoModifier), or nothing at all.
enum LassoSelectionMode {
  /// A press on empty grid space arms the lasso; the rectangle appears as
  /// soon as the pointer travels past the drag threshold. Matches the
  /// behaviour of file managers and design tools, and is the default.
  emptySpace,

  /// The lasso is armed only when one of DashboardShortcuts.lassoModifier
  /// is held **at the moment of the press**. A plain press on empty space
  /// keeps its historical behaviour (nothing happens).
  ///
  /// Use this when the grid shares its scroll view with other slivers, or
  /// when the application already binds empty-space drags to something else.
  modifierRequired,

  /// No rubberband selection at all. Empty-space drags behave exactly as
  /// they did before the feature existed.
  disabled,
}

/// Behaviour and appearance of the rubberband ("lasso") selection.
///
/// Configured on the controller — `controller.lassoStyle = ...` — like
/// DashboardShortcuts and `DashboardGuidance`, so every grid in a nested
/// tree carries its own policy without any prop drilling.
@immutable
class LassoStyle {
  /// Creates a [LassoStyle].
  const LassoStyle({
    this.mode = LassoSelectionMode.emptySpace,
    this.fillColor = const Color(0x332196F3),
    this.borderColor = Colors.blue,
    this.borderWidth = 1.0,
  });

  /// What arms the selection rectangle.
  ///
  /// The lasso is a pointer-device feature: whatever the mode, it is never
  /// armed on Android or iOS, where an empty-space drag scrolls the grid.
  final LassoSelectionMode mode;

  /// Fill of the selection rectangle.
  final Color fillColor;

  /// Border color of the selection rectangle.
  final Color borderColor;

  /// Border stroke width of the selection rectangle.
  final double borderWidth;

  /// The default configuration: an empty-space drag draws the rectangle.
  static const LassoStyle byDefault = LassoStyle();

  /// Turns the feature off entirely.
  static const LassoStyle off = LassoStyle(mode: LassoSelectionMode.disabled);

  /// Whether a press over empty space can arm a lasso at all.
  bool get isEnabled => mode != LassoSelectionMode.disabled;

  /// Creates a copy of this [LassoStyle] with the given fields replaced.
  LassoStyle copyWith({
    LassoSelectionMode? mode,
    Color? fillColor,
    Color? borderColor,
    double? borderWidth,
  }) {
    return LassoStyle(
      mode: mode ?? this.mode,
      fillColor: fillColor ?? this.fillColor,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LassoStyle &&
        other.mode == mode &&
        other.fillColor == fillColor &&
        other.borderColor == borderColor &&
        other.borderWidth == borderWidth;
  }

  @override
  int get hashCode => Object.hash(mode, fillColor, borderColor, borderWidth);
}

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

  /// Creates a copy of this [GridStyle] with the given fields replaced.
  GridStyle copyWith({
    Color? lineColor,
    double? lineWidth,
    Color? fillColor,
    Color? handleColor,
  }) {
    return GridStyle(
      lineColor: lineColor ?? this.lineColor,
      lineWidth: lineWidth ?? this.lineWidth,
      fillColor: fillColor ?? this.fillColor,
      handleColor: handleColor ?? this.handleColor,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GridStyle &&
        other.lineColor == lineColor &&
        other.lineWidth == lineWidth &&
        other.fillColor == fillColor &&
        other.handleColor == handleColor;
  }

  @override
  int get hashCode => Object.hash(lineColor, lineWidth, fillColor, handleColor);
}

/// Configuration for the visual appearance of dashboard items.
@immutable
class DashboardItemStyle {
  /// Creates a [DashboardItemStyle].
  const DashboardItemStyle({
    this.focusDecoration,
    this.focusColor,
    this.activeColor,
    this.borderRadius,
    this.nestTargetColor,
    this.nestTargetDecoration,
    this.displacedColor,
    this.displacedDecoration,
  });

  /// The decoration to paint behind the child when the item has focus.
  /// If null, a default border will be used if [focusColor] is provided.
  final BoxDecoration? focusDecoration;

  /// A convenience color for a default focus border.
  /// Ignored if [focusDecoration] is provided.
  final Color? focusColor;

  /// A convenience color for the focus border when the item is being actively dragged.
  /// If null, defaults to [Colors.deepOrange].
  final Color? activeColor;

  /// Border radius for the focus highlight.
  final BorderRadius? borderRadius;

  /// Ring color used while this item is the hovered nest / drop target.
  /// Ignored if [nestTargetDecoration] is provided. Defaults to
  /// [activeColor], then to [Colors.deepOrange].
  final Color? nestTargetColor;

  /// Full decoration used while this item is the hovered nest / drop
  /// target. Takes precedence over [nestTargetColor].
  final BoxDecoration? nestTargetDecoration;

  /// Convenience color for border highlight when this item is displaced by a push cascade.
  /// Ignored if [displacedDecoration] is provided.
  final Color? displacedColor;

  /// Full decoration used when this item is displaced by a push cascade.
  /// Takes precedence over [displacedColor].
  final BoxDecoration? displacedDecoration;

  /// Default style
  static const DashboardItemStyle defaultStyle = DashboardItemStyle(
    focusColor: Colors.blueAccent,
    activeColor: Colors.deepOrange,
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );

  /// Creates a copy of this [DashboardItemStyle] with the given fields replaced.
  DashboardItemStyle copyWith({
    BoxDecoration? focusDecoration,
    Color? focusColor,
    Color? activeColor,
    BorderRadius? borderRadius,
    Color? nestTargetColor,
    BoxDecoration? nestTargetDecoration,
    Color? displacedColor,
    BoxDecoration? displacedDecoration,
  }) {
    return DashboardItemStyle(
      focusDecoration: focusDecoration ?? this.focusDecoration,
      focusColor: focusColor ?? this.focusColor,
      activeColor: activeColor ?? this.activeColor,
      borderRadius: borderRadius ?? this.borderRadius,
      nestTargetColor: nestTargetColor ?? this.nestTargetColor,
      nestTargetDecoration: nestTargetDecoration ?? this.nestTargetDecoration,
      displacedColor: displacedColor ?? this.displacedColor,
      displacedDecoration: displacedDecoration ?? this.displacedDecoration,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DashboardItemStyle &&
        other.focusDecoration == focusDecoration &&
        other.focusColor == focusColor &&
        other.activeColor == activeColor &&
        other.borderRadius == borderRadius &&
        other.nestTargetColor == nestTargetColor &&
        other.nestTargetDecoration == nestTargetDecoration &&
        other.displacedColor == displacedColor &&
        other.displacedDecoration == displacedDecoration;
  }

  @override
  int get hashCode => Object.hash(
        focusDecoration,
        focusColor,
        activeColor,
        borderRadius,
        nestTargetColor,
        nestTargetDecoration,
        displacedColor,
        displacedDecoration,
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrashPosition &&
          runtimeType == other.runtimeType &&
          left == other.left &&
          top == other.top &&
          right == other.right &&
          bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrashLayout &&
          runtimeType == other.runtimeType &&
          visible == other.visible &&
          hidden == other.hidden;

  @override
  int get hashCode => Object.hash(visible, hidden);
}
