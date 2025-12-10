// coverage:ignore-file

import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/view/dashboard_typedefs.dart';

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

    // Accessibility (Screen Readers)
    this.a11yGrab = _defaultA11yGrab,
    this.a11yDrop = _defaultA11yDrop,
    this.a11yMove = _defaultA11yMove,
    this.a11yCancel = 'Interaction cancelled. Item returned to original position.',
    this.semanticsHintGrab = 'Press Space to grab',
    this.semanticsHintDrop = 'Press Space to drop, Arrows to move',
  });

  /// The default guidance messages.
  static const DashboardGuidance byDefault = DashboardGuidance();

  // --- Default Implementations ---
  static String _defaultA11yGrab(String id) =>
      'Item $id grabbed. Use arrow keys to move, Space to drop, Escape to cancel.';

  static String _defaultA11yDrop(int x, int y) => 'Item dropped at Row $y, Column $x.';

  static String _defaultA11yMove(int x, int y) => 'Row $y, Column $x';

  // --- Visual Properties ---

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

  // --- Accessibility Properties ---

  /// Message announced when an item is grabbed via keyboard.
  final A11yItemMessageBuilder a11yGrab;

  /// Message announced when an item is dropped.
  final A11yPositionMessageBuilder a11yDrop;

  /// Message announced when an item moves (feedback for arrow keys).
  final A11yPositionMessageBuilder a11yMove;

  /// Message announced when interaction is cancelled (Esc or focus loss).
  final String a11yCancel;

  /// Semantic hint when the item is idle (not grabbed).
  final String semanticsHintGrab;

  /// Semantic hint when the item is grabbed.
  final String semanticsHintDrop;
}
