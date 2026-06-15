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
}
