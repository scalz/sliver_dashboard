import 'package:flutter/foundation.dart' show kDebugMode;
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
  /// `CustomScrollView`): without it the render-tree walk
  /// would returns the FIRST `RenderSliverDashboard` under the
  /// shared overlay stack, so every grid would paint the background of the same
  /// sliver. Mirrors `DashboardOverlay.sliverKey`, which must be given the same
  /// key.
  final GlobalKey? sliverKey;

  /// The aspect ratio of a single slot.
  final double slotAspectRatio;

  /// Spacing between items on the main axis.
  final double mainAxisSpacing;

  /// Spacing between items on the cross axis.
  final double crossAxisSpacing;

  /// Padding around the grid content.
  ///
  /// Must match the `SliverPadding` surrounding the `SliverDashboard`: the
  /// cross-axis component is applied to the painted origin, and the main-axis
  /// component is the last-resort fallback when the sliver cannot be resolved.
  final EdgeInsets padding;

  /// The scroll direction of the dashboard.
  final Axis scrollDirection;

  /// If true, force grid to fill viewport.
  final bool fillViewport;

  @override
  State<DashboardGrid> createState() => _DashboardGridState();
}

class _DashboardGridState extends State<DashboardGrid> {
  RenderSliverDashboard? _renderSliver;

  /// One-shot post-frame retry guard for two-pass Stack sibling resolution.
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
        final sliver = _findRenderSliver();

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
            // Reason: watched (not peeked) so the snap-target fill paints immediately on
// resize start, before the first cell crossing (two rebuilds per gesture).
            final isResizing = widget.controller.internal.isResizing.watch(context);
            final selectedIds = widget.controller.selectedItemIds.watch(context);
            var draggedItems = <LayoutItem>[];

            if (isDragging || isResizing) {
              draggedItems = layout.where((i) => selectedIds.contains(i.id)).toList();
            }

            final placeholder = widget.controller.currentDragPlaceholder;
            final geometry = _resolveSliverGeometry(constraints, sliver);

            return CustomPaint(
              size: constraints.biggest,
              painter: GridBackgroundPainter(
                metrics: metrics,
                scrollOffset:
                    widget.scrollController.hasClients ? widget.scrollController.offset : 0.0,
                sliverLayoutStart: geometry.layoutStart,
                sliverContentExtent: geometry.contentExtent,
                draggedItems: draggedItems,
                placeholder: placeholder,
                lineColor: widget.gridStyle.lineColor,
                lineWidth: widget.gridStyle.lineWidth,
                fillColor: widget.gridStyle.fillColor,
                fillViewport: widget.fillViewport,
              ),
            );
          },
        );
      },
    );
  }

  /// Resolves the two main-axis scalars in 3 decreasing precision tiers:
  /// 1) live sliver geometry, 2) published controller metrics, 3) leading padding.
  ///
  /// Reason — why scalars: CustomPainter.shouldRepaint compares value parameters.
  /// Passing plain doubles guarantees repaints on geometry changes.
  ({double layoutStart, double contentExtent}) _resolveSliverGeometry(
    BoxConstraints constraints,
    RenderSliverDashboard? sliver,
  ) {
    final isVertical = widget.scrollDirection == Axis.vertical;

    if (sliver != null && sliver.attached && sliver.geometry != null) {
      _recordGeometrySource(GridGeometrySource.liveSliver);
      return (
        layoutStart: sliver.constraints.precedingScrollExtent,
        contentExtent: sliver.geometry!.scrollExtent,
      );
    }

    final internal = widget.controller.internal;
    final publishedStart = internal.viewMainAxisLeadingExtent;
    final publishedExtent = internal.viewMainAxisContentExtent;
    if (publishedStart != null && publishedExtent != null) {
      _recordGeometrySource(GridGeometrySource.publishedMetrics);
      return (layoutStart: publishedStart, contentExtent: publishedExtent);
    }

    _recordGeometrySource(GridGeometrySource.padding);
    return (
      layoutStart: isVertical ? widget.padding.top : widget.padding.left,
      contentExtent: isVertical ? constraints.maxHeight : constraints.maxWidth,
    );
  }

  static void _recordGeometrySource(GridGeometrySource source) {
    if (kDebugMode) debugLastGridGeometrySource = source;
  }

  /// Locates the [RenderSliverDashboard] associated with this grid.
  ///
  /// This is necessary because the [DashboardGrid] (Overlay) and the
  /// `SliverDashboard` (Scroll View Content) are in different branches of the
  /// widget tree, but we need the RenderObject of the latter to get precise
  /// layout metrics.
  RenderSliverDashboard? _findRenderSliver() {
    // Optimization: keep the cached reference while it is still usable.
    //
    // Reason — `geometry != null` matters as much as `attached`: the caller
    // reads `constraints.precedingScrollExtent` and `geometry.scrollExtent`, so
    // a render object that is attached but not laid out yet must not satisfy the
    // cache and silently send the caller down its fallback tiers.
    final cached = _renderSliver;
    if (cached != null && cached.attached && cached.geometry != null) {
      _resolveRetryScheduled = false;
      return cached;
    }

    // Reason: Search state MUST be local (`found`) to prevent stale detached references
    // from permanently blocking the walk.
    RenderSliverDashboard? found;
    void visitor(RenderObject child) {
      if (found != null) return;
      if (child is RenderSliverDashboard) {
        found = child;
        return;
      }
      child.visitChildren(visitor);
    }

    final key = widget.sliverKey;
    if (key != null) {
      // Reason: Scoped walk without fallback. An unscoped fallback when context is null on frame 1
      // would latch a sibling grid's sliver permanently.
      final scopedRoot = key.currentContext?.findRenderObject();
      if (scopedRoot is RenderSliverDashboard) {
        found = scopedRoot;
      } else {
        scopedRoot?.visitChildren(visitor);
      }
    } else {
      context.findAncestorRenderObjectOfType<RenderStack>()?.visitChildren(visitor);
    }

    final resolved = found;
    _renderSliver = resolved;

    if (resolved != null && resolved.geometry != null) {
      _resolveRetryScheduled = false;
      return resolved;
    }

    // Reason: Stack children are built in order (background = 0, scroll view = 1).
    // On frame 1, child 1 has not laid out yet. One post-frame retry ensures resolution on frame 2.
    //
    // Bounded to ONE extra build per failure episode (the flag is cleared only
    // on success), so it can never loop — a composition with no
    // `SliverDashboard` at all settles after exactly one retry. A grid that is
    // off-screen at mount needs no further retry either: scrolling it into view
    // rebuilds this subtree through the AnimatedBuilder anyway.
    if (!_resolveRetryScheduled) {
      _resolveRetryScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }

    return resolved;
  }
}

/// Which tier `_resolveSliverGeometry` used on its last run (test hook).
@visibleForTesting
enum GridGeometrySource {
  /// Resolved directly from the attached [RenderSliverDashboard].
  liveSliver,

  /// Resolved from the exact metrics published on the controller.
  publishedMetrics,

  /// Resolved from the fallback leading padding.
  padding,
}

/// The tier `_resolveSliverGeometry` used on its last run (test hook).
@visibleForTesting
GridGeometrySource? debugLastGridGeometrySource;
