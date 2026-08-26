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

/// Intent to cancel the current interaction (or clear selection when idle).
class DashboardCancelInteractionIntent extends Intent {
  /// Creates a [DashboardCancelInteractionIntent].
  const DashboardCancelInteractionIntent();
}

/// Intent to delete the selected item(s) or the currently focused item.
class DashboardDeleteItemIntent extends Intent {
  /// Creates a [DashboardDeleteItemIntent].
  const DashboardDeleteItemIntent();
}

/// Intent to select all non-static items in the grid.
class DashboardSelectAllIntent extends Intent {
  /// Creates a [DashboardSelectAllIntent].
  const DashboardSelectAllIntent();
}

/// Intent to duplicate the active / selected item(s).
class DashboardDuplicateItemIntent extends Intent {
  /// Creates a [DashboardDuplicateItemIntent].
  const DashboardDuplicateItemIntent();
}

/// Intent to undo the last layout transaction.
class DashboardUndoIntent extends Intent {
  /// Creates a [DashboardUndoIntent].
  const DashboardUndoIntent();
}

/// Intent to redo the last undone layout transaction.
class DashboardRedoIntent extends Intent {
  /// Creates a [DashboardRedoIntent].
  const DashboardRedoIntent();
}
