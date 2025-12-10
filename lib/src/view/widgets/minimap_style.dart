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
}
