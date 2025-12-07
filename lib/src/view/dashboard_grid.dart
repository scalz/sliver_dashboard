import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/view/dashboard_configuration.dart';
import 'package:sliver_dashboard/src/view/grid_background_painter.dart';
import 'package:sliver_dashboard/src/view/sliver_dashboard.dart';
import 'package:state_beacon/state_beacon.dart';

/// A widget that paints the dashboard grid lines and the active item background.
///
/// This widget is designed to be placed in a [Stack] behind the scrollable content
/// within DashboardOverlay. It synchronizes with the [ScrollController] to
/// draw the grid lines as if they were part of the scroll view, while actually
/// residing in a static overlay.
class DashboardGrid extends StatefulWidget {
  /// Creates a [DashboardGrid].
  const DashboardGrid({
    required this.controller,
    required this.scrollController,
    required this.gridStyle,
    this.slotAspectRatio = 1.0,
    this.mainAxisSpacing = 8.0,
    this.crossAxisSpacing = 8.0,
    this.padding = EdgeInsets.zero,
    this.scrollDirection = Axis.vertical,
    this.fillViewport = false,
    super.key,
  });

  /// The controller managing the dashboard state.
  final DashboardController controller;

  /// The scroll controller used to synchronize the grid position.
  final ScrollController scrollController;

  /// Configuration for the grid's visual appearance.
  final GridStyle gridStyle;

  /// The aspect ratio of a single slot.
  final double slotAspectRatio;

  /// Spacing between items on the main axis.
  final double mainAxisSpacing;

  /// Spacing between items on the cross axis.
  final double crossAxisSpacing;

  /// Padding around the grid content.
  final EdgeInsets padding;

  /// The scroll direction of the dashboard.
  final Axis scrollDirection;

  /// If true, force grid to fill viewport
  final bool fillViewport;

  @override
  State<DashboardGrid> createState() => _DashboardGridState();
}

class _DashboardGridState extends State<DashboardGrid> {
  RenderSliverDashboard? _renderSliver;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.scrollController,
      builder: (context, child) {
        // Reasoning: We attempt to find the RenderSliverDashboard on every frame
        // (or rebuild) because the render object might have been detached/attached
        // or moved within the tree.
        _findRenderSliver();

        return LayoutBuilder(
          builder: (context, constraints) {
            // Watch for layout changes to repaint the placeholder/active item correctly.
            widget.controller.layout.watch(context);

            final metrics = SlotMetrics.fromConstraints(
              constraints,
              slotCount: widget.controller.slotCount.value,
              slotAspectRatio: widget.slotAspectRatio,
              mainAxisSpacing: widget.mainAxisSpacing,
              crossAxisSpacing: widget.crossAxisSpacing,
              padding: widget.padding,
              scrollDirection: widget.scrollDirection,
            );

            final isEditing = widget.controller.isEditing.watch(context);
            if (!isEditing) return const SizedBox.shrink();

            final activeItemId = widget.controller.activeItemId.watch(context);
            final activeItem = activeItemId != null
                ? widget.controller.layout.value.firstWhereOrNull((i) => i.id == activeItemId)
                : null;

            final placeholder = widget.controller.currentDragPlaceholder;

            // Extract positioning information from the actual Sliver RenderObject.
            var startOffset = 0.0;
            var contentExtent = 0.0;

            if (_renderSliver != null && _renderSliver!.geometry != null) {
              // Reasoning: The grid is drawn in an Overlay (Stack), which covers the
              // entire viewport. However, the actual Dashboard content might be
              // pushed down by a SliverAppBar or other slivers.
              // `precedingScrollExtent` tells us exactly where the dashboard starts
              // in the scroll view, allowing us to align the grid lines perfectly.
              startOffset = _renderSliver!.constraints.precedingScrollExtent;
              contentExtent = _renderSliver!.geometry!.scrollExtent;
            } else {
              // Fallback: If the sliver hasn't performed layout yet, assume full size.
              // This prevents visual glitches during the very first frame.
              contentExtent = widget.scrollDirection == Axis.vertical
                  ? constraints.maxHeight
                  : constraints.maxWidth;
            }

            return CustomPaint(
              size: constraints.biggest,
              painter: GridBackgroundPainter(
                metrics: metrics,
                scrollOffset:
                    widget.scrollController.hasClients ? widget.scrollController.offset : 0.0,
                activeItem: activeItem,
                placeholder: placeholder,
                lineColor: widget.gridStyle.lineColor,
                lineWidth: widget.gridStyle.lineWidth,
                fillColor: widget.gridStyle.fillColor,
                // Pass the calculated offsets to the painter for clipping and translation.
                sliverTop: startOffset,
                sliverHeight: contentExtent,
                fillViewport: widget.fillViewport,
              ),
            );
          },
        );
      },
    );
  }

  /// Locates the [RenderSliverDashboard] associated with this grid.
  ///
  /// This is necessary because the [DashboardGrid] (Overlay) and the
  /// [SliverDashboard] (Scroll View Content) are in different branches of the
  /// widget tree, but we need the RenderObject of the latter to get precise
  /// layout metrics.
  void _findRenderSliver() {
    // Optimization: If we already have a reference and it's still valid, return.
    if (_renderSliver != null && _renderSliver!.attached) return;

    void visitor(RenderObject child) {
      if (_renderSliver != null) return;
      if (child is RenderSliverDashboard) {
        _renderSliver = child;
        return;
      }
      child.visitChildren(visitor);
    }

    // Reasoning: We search for the RenderSliverDashboard by traversing the render tree.
    // We start from the nearest `RenderStack` ancestor. This `RenderStack` corresponds
    // to the Stack in `DashboardOverlay`, which is the common ancestor of both
    // this Grid and the CustomScrollView containing the Sliver.
    final overlayRender = context.findAncestorRenderObjectOfType<RenderStack>();
    overlayRender?.visitChildren(visitor);
  }
}
