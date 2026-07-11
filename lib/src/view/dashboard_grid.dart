import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
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
    final isEditing = widget.controller.isEditing.watch(context);
    if (!isEditing) {
      _renderSliver = null; // Free up the reference to avoid memory leaks
      return const SizedBox.shrink();
    }

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
            final layout = widget.controller.layout.watch(context);

            final metrics = SlotMetrics.fromConstraints(
              constraints,
              slotCount: widget.controller.slotCount.value,
              slotAspectRatio: widget.slotAspectRatio,
              mainAxisSpacing: widget.mainAxisSpacing,
              crossAxisSpacing: widget.crossAxisSpacing,
              padding: widget.padding,
              scrollDirection: widget.scrollDirection,
            );

            final isDragging = widget.controller.isDragging.watch(context);
            final selectedIds = widget.controller.selectedItemIds.watch(context);
            var draggedItems = <LayoutItem>[];

            // Only show shadows if we are actively dragging (or resizing)
            if (isDragging || widget.controller.internal.isResizing.value) {
              draggedItems = layout.where((i) => selectedIds.contains(i.id)).toList();
            }

            final placeholder = widget.controller.currentDragPlaceholder;

            return CustomPaint(
              size: constraints.biggest,
              painter: GridBackgroundPainter(
                metrics: metrics,
                scrollOffset:
                    widget.scrollController.hasClients ? widget.scrollController.offset : 0.0,
                draggedItems: draggedItems,
                placeholder: placeholder,
                lineColor: widget.gridStyle.lineColor,
                lineWidth: widget.gridStyle.lineWidth,
                fillColor: widget.gridStyle.fillColor,
                renderSliver: _renderSliver,
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
