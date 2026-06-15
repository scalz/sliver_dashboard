import 'package:flutter/widgets.dart';
import 'package:sliver_dashboard/src/view/dashboard_overlay.dart';

/// A widget that detects immediate touch gestures (like pointer down) on its child
/// and initiates a drag operation on the parent DashboardItem.
class DashboardDragStartListener extends StatelessWidget {
  /// Creates a [DashboardDragStartListener].
  const DashboardDragStartListener({
    required this.itemId,
    required this.child,
    super.key,
  });

  /// The unique identifier of the layout item to drag.
  final String itemId;

  /// The child widget representing the drag handle icon.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final overlay = DashboardOverlayProvider.maybeOf(context);
        if (overlay != null) {
          overlay.startDragging(itemId, event.position);
        }
      },
      child: child,
    );
  }
}

/// A widget that detects delayed touch gestures (like long press) on its child
/// and initiates a drag operation on the parent DashboardItem.
class DashboardDelayedDragStartListener extends StatelessWidget {
  /// Creates a [DashboardDelayedDragStartListener].
  const DashboardDelayedDragStartListener({
    required this.itemId,
    required this.child,
    super.key,
  });

  /// The unique identifier of the layout item to drag.
  final String itemId;

  /// The child widget representing the drag handle icon.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (details) {
        final overlay = DashboardOverlayProvider.maybeOf(context);
        if (overlay != null) {
          overlay.startDragging(itemId, details.globalPosition);
        }
      },
      child: child,
    );
  }
}
