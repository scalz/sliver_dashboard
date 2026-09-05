import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/dashboard_configuration.dart' show DashboardItemStyle;
import 'package:sliver_dashboard/src/view/dashboard_item_widget.dart';
import 'package:sliver_dashboard/src/view/dashboard_typedefs.dart';
import 'package:state_beacon/state_beacon.dart';

/// A widget that renders the visual feedback for an item being dragged — or,
/// with [isResizeGhost], for the item being resized.
///
/// Both gestures share this widget on purpose: the composition (grid hole +
/// overlay copy + sliver clip band) is identical, only the source of the
/// rectangle differs — `dragOffset` translates the tile's snapped rect for a
/// drag, `resizeGhostRect` replaces it outright for a fluid resize.
class DashboardFeedbackItem extends StatelessWidget {
  /// Creates a [DashboardFeedbackItem].
  const DashboardFeedbackItem({
    required this.item,
    required this.controller,
    required this.slotWidth,
    required this.slotHeight,
    required this.mainAxisSpacing,
    required this.crossAxisSpacing,
    required this.scrollDirection,
    required this.isEditing,
    required this.sliverStartPos,
    this.isResizeGhost = false,
    this.isSettling = false,
    this.settleDuration = Duration.zero,
    this.onSettleEnd,
    this.itemBuilder,
    this.itemLayoutBuilder,
    this.itemBreakpointBuilder,
    this.breakpointResolver,
    this.itemGlobalKeySuffix = '',
    this.feedbackBuilder,
    this.sliverBounds,
    this.itemStyle = DashboardItemStyle.defaultStyle,
    super.key,
  }) : assert(
          (itemBuilder != null ? 1 : 0) +
                  (itemLayoutBuilder != null ? 1 : 0) +
                  (itemBreakpointBuilder != null && breakpointResolver != null ? 1 : 0) ==
              1,
          'Provide exactly one builder configuration.',
        );

  /// The layout item currently being dragged.
  final LayoutItem item;

  /// A static builder that creates the widget for a dashboard item.
  ///
  /// Highly optimized; completely prevents widget subtree rebuilds during window resizing
  /// or visual dragging when grid coordinates remain unchanged.
  final DashboardItemBuilder? itemBuilder;

  /// A layout-aware builder that provides live physical pixel dimensions.
  ///
  /// Rebuilds continuously as the physical bounds are adjusted, enabling sub-pixel responsiveness
  /// and continuous visual updates during resizing.
  final DashboardItemLayoutBuilder? itemLayoutBuilder;

  /// A breakpoint-aware builder that reconstructs its subtree selectively based on a resolved state.
  ///
  /// Rebuilds only when the layout state returned by [breakpointResolver] transitions,
  /// shielding complex downstream subtrees from redundant build passes during resizing.
  final DashboardItemBreakpointBuilder? itemBreakpointBuilder;

  /// Maps the item's live physical pixel dimensions to a developer-defined layout state.
  ///
  /// Evaluated continuously during resizing when [itemBreakpointBuilder] is provided.
  final DashboardBreakpointResolver? breakpointResolver;

  /// The controller managing the drag state and offsets.
  final DashboardController controller;

  /// The width of a single grid slot in pixels.
  final double slotWidth;

  /// The height of a single grid slot in pixels.
  final double slotHeight;

  /// The spacing between items on the main axis.
  final double mainAxisSpacing;

  /// The spacing between items on the cross axis.
  final double crossAxisSpacing;

  /// The scroll direction of the dashboard.
  final Axis scrollDirection;

  /// A suffix appended to the item's key to ensure uniqueness.
  final String itemGlobalKeySuffix;

  /// Whether the dashboard is currently in edit mode.
  final bool isEditing;

  /// An optional builder to customize the appearance of the item while dragging.
  final DashboardItemFeedbackBuilder? feedbackBuilder;

  /// The visual position of the grid's (0,0) coordinate relative to the Overlay.
  final Offset sliverStartPos;

  /// The bounds of the sliver to clip the feedback item.
  final Rect? sliverBounds;

  /// The visual style of the item focus and active borders.
  final DashboardItemStyle itemStyle;

  /// Whether this copy is the fluid-resize ghost rather than a drag feedback.
  ///
  /// The ghost reads its rectangle from `resizeGhostRect` (raw pixels,
  /// already clamped by the controller) instead of deriving it from the
  /// item's grid coordinates.
  final bool isResizeGhost;

  /// Whether the ghost is settling into its snapped slot after the release.
  ///
  /// Derived state, not stored anywhere: a ghost is settling exactly when it
  /// is still armed while `isResizing` has gone false.
  final bool isSettling;

  /// Duration of the settle animation. Only read while [isSettling].
  final Duration settleDuration;

  /// Invoked once the settle animation lands, so the owner can drop the ghost.
  final VoidCallback? onSettleEnd;

  @override
  Widget build(BuildContext context) {
    final impl = controller as DashboardControllerImpl;

    // The tile's own slot, in content pixels. Single geometry site shared with
    // the sliver, the background painter and the settle target.
    final snapped = gridCellRect(
      x: item.x,
      y: item.y,
      w: item.w,
      h: item.h,
      slotWidth: slotWidth,
      slotHeight: slotHeight,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      scrollDirection: scrollDirection,
    );

    if (isResizeGhost) {
      // Raw rect published by onResizeUpdate on every pointer event. Null
      // until the first move: the ghost then sits exactly on the tile it
      // replaced, so arming the preview is visually a no-op.
      final raw = impl.resizeGhostRect.watch(context) ?? snapped;

      if (isSettling) {
        // Implicit animation rather than a ticker on the overlay: it retargets
        // in flight for free (ImplicitlyAnimatedWidgetState restarts from the
        // interpolated value when the end changes), it costs nothing while no
        // resize is settling, and it writes no state — the drop already
        // committed, this is pure paint.
        return TweenAnimationBuilder<Rect?>(
          tween: RectTween(begin: raw, end: snapped),
          duration: settleDuration,
          curve: Curves.easeOutCubic,
          onEnd: onSettleEnd,
          builder: (context, value, _) => _buildPositioned(context, value ?? snapped),
        );
      }

      return _buildPositioned(context, raw);
    }

    // Watch the drag offset specifically here.
    final dragOffset = impl.dragOffset.watch(context);
    return _buildPositioned(context, snapped.shift(dragOffset));
  }

  /// Places the tile at [contentRect], translated to overlay coordinates and
  /// clipped to the sliver's visible band.
  Widget _buildPositioned(BuildContext context, Rect contentRect) {
    // Apply the sliver start position (which accounts for scroll, padding, appbars)
    final left = contentRect.left + sliverStartPos.dx;
    final top = contentRect.top + sliverStartPos.dy;
    final width = contentRect.width;
    final height = contentRect.height;

    // Use _DashboardItem to get the cached content widget
    final content = DashboardItem(
      item: item,
      isEditing: isEditing,
      isFeedback: true,
      itemStyle: itemStyle,
      itemWidth: width,
      itemHeight: height,
      slotCount: controller.slotCount.value,
      itemBuilder: itemBuilder,
      itemLayoutBuilder: itemLayoutBuilder,
      itemBreakpointBuilder: itemBreakpointBuilder,
      breakpointResolver: breakpointResolver,
    );

    // Apply custom feedback builder if provided, otherwise use the content directly
    final feedbackWidget =
        feedbackBuilder != null ? feedbackBuilder!(context, item, content) : content;

    // Apply clipping if sliver bounds are provided.
    // Reason: This ensures the dragged item appears to be "inside" the scrollable area
    // and gets cut off correctly when sliding under pinned headers (like SliverAppBar).
    var child = feedbackWidget;
    if (sliverBounds != null) {
      child = ClipRect(
        clipper: _SliverBoundsClipper(
          sliverBounds: sliverBounds!,
          itemOffset: Offset(left, top),
        ),
        child: child,
      );
    }

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: child,
    );
  }
}

class _SliverBoundsClipper extends CustomClipper<Rect> {
  _SliverBoundsClipper({required this.sliverBounds, required this.itemOffset});

  final Rect sliverBounds;
  final Offset itemOffset;

  @override
  Rect getClip(Size size) {
    // The item's rectangle in global (Overlay) coordinates.
    final itemRect = itemOffset & size;
    // Calculate the intersection with the visible sliver bounds.
    final intersection = itemRect.intersect(sliverBounds);

    if (intersection.isEmpty) return Rect.zero;

    // Convert the intersection rectangle back to the item's local coordinate system.
    return intersection.shift(-itemOffset);
  }

  @override
  bool shouldReclip(_SliverBoundsClipper oldClipper) {
    return oldClipper.sliverBounds != sliverBounds || oldClipper.itemOffset != itemOffset;
  }
}
