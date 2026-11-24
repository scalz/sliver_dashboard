import 'package:sliver_dashboard/src/models/layout_item.dart';

/// A declarative policy interface to validate and customize grid interactions at runtime.
///
/// Implement this class to enforce business logic rules such as locked zones,
/// collision filters, and dynamic drag/resize permissions without writing a
/// custom compaction delegate from scratch.
abstract class DashboardPolicy {
  /// Default constructor to satisfy static code analysis.
  const DashboardPolicy();

  /// Whether the specific [item] is allowed to be dragged.
  bool canDrag(LayoutItem item) => true;

  /// Whether the specific [item] is allowed to be resized.
  bool canResize(LayoutItem item) => true;

  /// Whether the [item] is allowed to be moved to the target coordinates ([targetX], [targetY]).
  ///
  /// Returning `false` will block the movement, keeping the item at its previous position.
  bool canMoveTo(LayoutItem item, int targetX, int targetY, List<LayoutItem> currentLayout) => true;

  /// Whether [itemA] is allowed to collide with or push [itemB] during interactions.
  ///
  /// Returning `false` will treat [itemB] as an immoveable static obstacle for [itemA],
  /// forcing [itemA] to slide or jump past it instead of pushing it.
  bool canCollide(LayoutItem itemA, LayoutItem itemB) => true;

  /// Whether [item] may take the size [w] x [h] (in grid slots).
  ///
  /// Restricts a grid to a set of tile sizes (e.g. only 1x1, 2x2 and 4x2 on a
  /// fixed wall panel). An item's current size is always accepted, so an item
  /// stored with a size this policy no longer allows can still be moved.
  /// Consulted by `DashboardController.canPlace`, resizes and cross-grid
  /// projection. Must be pure and cheap: it may be called once per candidate
  /// size while a resize crosses a slot boundary.
  bool isSizeAllowed(LayoutItem item, int w, int h) => true;
}
