import 'package:flutter/widgets.dart';
import 'package:sliver_dashboard/src/view/a11y/dashboard_intents.dart';

/// Marks [child] as an interactive island inside a tile: a press on it never
/// starts a grid drag, a resize, a selection change or a lasso, so a button
/// placed in a tile receives its tap and nothing else happens.
///
/// Only the area where [child] is actually hit is excluded
/// ([HitTestBehavior.deferToChild]): a button in a corner leaves the rest of
/// the tile draggable. Widgets built by `Dashboard.editOverlayBuilder` are
/// wrapped automatically.
class DashboardGestureExclusion extends StatelessWidget {
  /// Creates a [DashboardGestureExclusion].
  const DashboardGestureExclusion({required this.child, super.key});

  /// The interactive content whose presses the grid ignores.
  final Widget child;

  /// The marker the grid overlay looks for on the hit path.
  static const Object marker = _GestureExclusionMarker();

  @override
  Widget build(BuildContext context) => MetaData(
        metaData: marker,
        behavior: HitTestBehavior.deferToChild,
        child: child,
      );
}

class _GestureExclusionMarker {
  const _GestureExclusionMarker();
}

/// Actions a tile's edit overlay (`Dashboard.editOverlayBuilder`) can trigger.
///
/// Each one goes through the grid's own pipeline, exactly like its keyboard
/// shortcut, but always targets THIS tile only (never the rest of the
/// selection): a delete button on a tile deletes that tile. Calls on a tile
/// that is no longer mounted, or on which the action does not apply (a static
/// tile, edit mode off), do nothing.
class DashboardTileActions {
  /// Binds the actions to a context inside the tile.
  DashboardTileActions(this._context);

  final BuildContext _context;

  /// Deletes this tile: `onWillDelete` (may veto), `removeItems` (one undo
  /// entry), `onItemsDeleted`, and the screen-reader announcement.
  void delete() {
    if (!_context.mounted) return;
    Actions.maybeInvoke(_context, const DashboardDeleteItemIntent(onlyThisItem: true));
  }

  /// Duplicates this tile through `onCloneRequested` (no-op without it), next
  /// to the original, and selects the copy.
  void duplicate() {
    if (!_context.mounted) return;
    Actions.maybeInvoke(_context, const DashboardDuplicateItemIntent(onlyThisItem: true));
  }
}
