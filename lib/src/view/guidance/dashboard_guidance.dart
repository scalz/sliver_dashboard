// coverage:ignore-file

import 'package:flutter/material.dart';

/// A class that holds both a [MouseCursor] and a [String] message,
/// representing the guidance for a specific user interaction.
@immutable
class InteractionGuidance {
  /// Creates an [InteractionGuidance].
  const InteractionGuidance(this.cursor, this.message);

  /// The mouse cursor to display for the interaction.
  final MouseCursor cursor;

  /// The guidance message to display for the interaction.
  final String message;
}

/// A set of customizable messages for user guidance.
@immutable
class DashboardGuidance {
  /// Creates a set of guidance messages.
  const DashboardGuidance({
    this.move = const InteractionGuidance(
      SystemMouseCursors.grab,
      'Click and drag to move item',
    ),
    this.moving = const InteractionGuidance(
      SystemMouseCursors.grabbing,
      'Dragging item - release to place',
    ),
    this.resizeX = const InteractionGuidance(
      SystemMouseCursors.resizeLeftRight,
      'Drag to resize horizontally',
    ),
    this.resizeY = const InteractionGuidance(
      SystemMouseCursors.resizeUpDown,
      'Drag to resize vertically',
    ),
    this.resizeTopLeft = const InteractionGuidance(
      SystemMouseCursors.resizeUpLeftDownRight,
      'Drag to resize diagonally',
    ),
    this.resizeTopRight = const InteractionGuidance(
      SystemMouseCursors.resizeUpRightDownLeft,
      'Drag to resize diagonally',
    ),
    this.resizeXY = const InteractionGuidance(
      SystemMouseCursors.resizeUpLeftDownRight,
      'Drag to resize diagonally',
    ),
    this.tapToMove = 'Tap and hold to move item',
    this.tapToResize = 'Tap and hold to resize',
    this.longPressToMove = 'Drag to move item',
    this.longPressToResize = 'Drag to resize',
  });

  /// The default guidance messages.
  static const DashboardGuidance byDefault = DashboardGuidance();

  /// Message on hover for moving an item (desktop).
  final InteractionGuidance move;

  /// Message while an item is being moved (desktop).
  final InteractionGuidance moving;

  /// Message for resizing horizontally (desktop).
  final InteractionGuidance resizeX;

  /// Message for resizing vertically (desktop).
  final InteractionGuidance resizeY;

  /// Specific guidance for resizing from the top-left (desktop).
  final InteractionGuidance resizeTopLeft;

  /// Specific guidance for resizing from the top-right (desktop).
  final InteractionGuidance resizeTopRight;

  /// Specific guidance for resizing diagonally (desktop).
  final InteractionGuidance resizeXY;

  /// Message on tap for moving an item (mobile).
  final String tapToMove;

  /// Message on tap for resizing an item (mobile).
  final String tapToResize;

  /// Message on long-press for moving an item (mobile).
  final String longPressToMove;

  /// Message on long-press for resizing an item (mobile).
  final String longPressToResize;
}
