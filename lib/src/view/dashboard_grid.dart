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
    this.sliverKey,
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

  /// A specific GlobalKey bound to the `SliverDashboard` this background
  /// belongs to.
  ///
  /// Required in multi-sliver trees (several dashboards sharing one
  /// `CustomScrollView`): without it the render-tree walk below returns the
  /// FIRST `RenderSliverDashboard` under the shared overlay stack, so every
  /// grid would paint the background of the same sliver. Mirrors
  /// `DashboardOverlay.sliverKey`.
  final GlobalKey? sliverKey;

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

  /// Guards the one-shot post-frame retry below. Set when a resolution
  /// attempt failed and a retry is already queued; cleared as soon as a
  /// resolution succeeds. Bounds the self-heal to a single extra build per
  /// failure episode — it can never turn into a rebuild loop.
  bool _resolveRetryScheduled = false;

  @override
  void dispose() {
    _renderSliver = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DashboardGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sliverKey != oldWidget.sliverKey || widget.controller != oldWidget.controller) {
      // The cached render object may still be attached (it belongs to another
      // grid); only the key/controller swap tells us it is no longer ours.
      _renderSliver = null;
      _resolveRetryScheduled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.controller.isEditing.watch(context);
    if (!isEditing) {
      _renderSliver = null; // Free up the reference to avoid memory leaks
      _resolveRetryScheduled = false;
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
    // Optimization: keep the cached reference while it is still usable.
    //
    // Reason — `geometry != null` matters as much as `attached`: the painter
    // reads `constraints.precedingScrollExtent` and `geometry.scrollExtent`.
    // A render object that is attached but not laid out yet would silently
    // send it down its fallback path.
    final cached = _renderSliver;
    if (cached != null && cached.attached && cached.geometry != null) {
      _resolveRetryScheduled = false;
      return;
    }

    // Reason — the search state MUST be local (`found`), never the field.
    // Reading the field as the "already found" guard made the whole walk a
    // no-op the moment the field held a STALE (detached) render object: the
    // guard fired on the very first visitor call and the reference could
    // never be refreshed again.
    //
    // This is not a corner case. `SliverDashboard` keys its
    // `SliverLayoutBuilder` on the slot count, so ANY slot-count change
    // rebuilds a brand-new `RenderSliverDashboard`, while this State — which
    // lives in the overlay's Stack, outside that subtree — survives with a
    // dead reference. `NestedDashboard(autoSlotCount: true)` hits it on its
    // very first frame (post-frame `setSlotCount(host.w)`).
    //
    // Consequence before the fix: `GridBackgroundPainter` fell back to
    // `sliverTop = 0` permanently, painting the background grid `padding.top`
    // too high — invisible at `padding: EdgeInsets.zero` (0 happens to be the
    // right value there), blatant on a padded nested grid. `shouldRepaint`
    // could not recover it either: it compares the renderSliver *reference*,
    // which never changed again.
    RenderSliverDashboard? found;
    void visitor(RenderObject child) {
      if (found != null) return;
      if (child is RenderSliverDashboard) {
        found = child;
        return;
      }
      child.visitChildren(visitor);
    }

    // Multi-sliver trees: restrict the walk to the subtree of the sliver this
    // background belongs to. Same contract as
    // `DashboardOverlay._findRenderSliver`.
    final scopedRoot = widget.sliverKey?.currentContext?.findRenderObject();
    if (scopedRoot != null) {
      if (scopedRoot is RenderSliverDashboard) {
        found = scopedRoot;
      } else {
        scopedRoot.visitChildren(visitor);
      }
    } else {
      // Reasoning: We search for the RenderSliverDashboard by traversing the
      // render tree, starting from the nearest `RenderStack` ancestor. This
      // `RenderStack` corresponds to the Stack in `DashboardOverlay`, which is
      // the common ancestor of both this Grid and the CustomScrollView
      // containing the Sliver.
      context.findAncestorRenderObjectOfType<RenderStack>()?.visitChildren(visitor);
    }

    // A stale reference is worse than none: the painter's fallback is exact
    // for a single-grid composition, a detached render object is not.
    _renderSliver = found;

    if (found != null && found!.geometry != null) {
      _resolveRetryScheduled = false;
      return;
    }

    // Self-heal: the sliver exists but has not been laid out yet (first frame
    // of a freshly mounted grid). Nothing else would necessarily rebuild this
    // subtree — a nested grid that never scrolls emits no scroll notification
    // — so schedule exactly ONE retry. Guarded so a permanently unresolvable
    // sliver costs one extra build, not a loop.
    if (!_resolveRetryScheduled) {
      _resolveRetryScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {});
      });
    }
  }
}
