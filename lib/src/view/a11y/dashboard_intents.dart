import 'package:flutter/widgets.dart';

/// Intent to grab (start dragging) the focused item.
class DashboardGrabItemIntent extends Intent {
  /// Creates a [DashboardGrabItemIntent].
  const DashboardGrabItemIntent();
}

/// Intent to drop (stop dragging) the currently grabbed item.
class DashboardDropItemIntent extends Intent {
  /// Creates a [DashboardDropItemIntent].
  const DashboardDropItemIntent();
}

/// Intent to move the grabbed item by a specific grid delta.
class DashboardMoveItemIntent extends Intent {
  /// Creates a [DashboardMoveItemIntent].
  const DashboardMoveItemIntent(this.dx, this.dy);

  /// The horizontal change in grid columns (e.g., -1 for left, 1 for right).
  final int dx;

  /// The vertical change in grid rows (e.g., -1 for up, 1 for down).
  final int dy;
}

/// Intent to cancel the current interaction and revert changes.
class DashboardCancelInteractionIntent extends Intent {
  /// Creates a [DashboardCancelInteractionIntent].
  const DashboardCancelInteractionIntent();
}
