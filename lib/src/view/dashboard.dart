import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart' show ResizeBehavior;
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/dashboard_configuration.dart';
import 'package:sliver_dashboard/src/view/dashboard_overlay.dart';
import 'package:sliver_dashboard/src/view/dashboard_typedefs.dart';
import 'package:sliver_dashboard/src/view/guidance/dashboard_guidance.dart';
import 'package:sliver_dashboard/src/view/sliver_dashboard.dart';

/// The main dashboard widget.
///
/// This is a high-level wrapper that combines [DashboardOverlay] and [SliverDashboard]
/// into a single, easy-to-use widget. It creates a [CustomScrollView] internally
/// and manages the scrolling environment.
///
/// If you need to integrate the dashboard into an existing [CustomScrollView] (e.g.,
/// to use with [SliverAppBar]), use [DashboardOverlay] and [SliverDashboard] directly
/// instead of this widget.
class Dashboard<T extends Object> extends StatefulWidget {
  /// Creates a new Dashboard.
  const Dashboard({
    required this.controller,
    required this.itemBuilder,
    super.key,
    this.scrollDirection = Axis.vertical,
    this.slotAspectRatio = 1.0,
    this.mainAxisSpacing = 8.0,
    this.crossAxisSpacing = 8.0,
    this.padding,
    this.breakpoints,
    this.resizeHandleSide = 20.0,
    this.placeholderWidth = 1,
    this.placeholderHeight = 1,
    this.onDrop,
    this.gridStyle = const GridStyle(),
    this.itemStyle = DashboardItemStyle.defaultStyle,
    this.resizeBehavior = ResizeBehavior.push,
    this.showScrollbar = true,
    this.cacheExtent,
    this.guidance,
    this.physics,
    this.scrollBehavior,
    this.scrollController,
    this.itemGlobalKeySuffix = '',
    this.externalPlaceholderBuilder,
    this.itemFeedbackBuilder,
    this.onItemDragStart,
    this.onItemDragUpdate,
    this.onItemDragEnd,
    this.onItemResizeStart,
    this.onItemResizeEnd,
    this.trashLayout = TrashLayout.bottomCenter,
    this.trashBuilder,
    this.onWillDelete,
    this.onItemDeleted,
    this.trashHoverDelay = const Duration(milliseconds: 800),
  });

  /// The controller that manages the state of the dashboard.
  final DashboardController controller;

  /// A builder that creates the widgets for each dashboard item.
  final DashboardItemBuilder itemBuilder;

  /// The direction of scrolling for the dashboard.
  final Axis scrollDirection;

  /// The aspect ratio of each grid slot.
  final double slotAspectRatio;

  /// The spacing between items on the main axis (vertical).
  final double mainAxisSpacing;

  /// The spacing between items on the cross axis (horizontal).
  final double crossAxisSpacing;

  /// Optional padding for the entire dashboard.
  final EdgeInsets? padding;

  /// A map of breakpoints to automatically adjust the slot count based on width.
  final Map<double, int>? breakpoints;

  /// The size of the touch target on the corners and edges for resizing.
  final double resizeHandleSide;

  /// The width of the placeholder item in grid units when dragging from outside.
  final int placeholderWidth;

  /// The height of the placeholder item in grid units when dragging from outside.
  final int placeholderHeight;

  /// Callback when an external draggable is dropped onto the dashboard.
  final DashboardDropCallback<T>? onDrop;

  /// Styling options for the background grid in edit mode.
  final GridStyle gridStyle;

  /// Styling options for the item focus.
  final DashboardItemStyle itemStyle;

  /// The behavior to use when an item is resized and collides with another.
  final ResizeBehavior resizeBehavior;

  /// Whether to show the scrollbar.
  final bool showScrollbar;

  /// The cache extent for the underlying `CustomScrollView`.
  final double? cacheExtent;

  /// A set of customizable messages for user guidance. If null, guidance is disabled.
  final DashboardGuidance? guidance;

  /// Custom scroll physics for the dashboard.
  final ScrollPhysics? physics;

  /// Custom scroll behavior for the dashboard.
  final ScrollBehavior? scrollBehavior;

  /// An optional scroll controller for the dashboard.
  /// If not provided, a default one will be created and managed internally.
  final ScrollController? scrollController;

  /// A suffix to append to global keys for dashboard items.
  final String itemGlobalKeySuffix;

  /// Optional builder to customize the appearance of the external Placeholder.
  final Widget Function(BuildContext context, LayoutItem item)? externalPlaceholderBuilder;

  /// Optional builder to customize the appearance of the item while it is being dragged.
  final DashboardItemFeedbackBuilder? itemFeedbackBuilder;

  /// Called when a drag operation starts on an item.
  final void Function(LayoutItem item)? onItemDragStart;

  /// Called continuously when an item is being dragged.
  final void Function(LayoutItem item, Offset globalPosition)? onItemDragUpdate;

  /// Called when a drag operation ends.
  final void Function(LayoutItem item)? onItemDragEnd;

  /// Called when a resize operation starts on an item.
  final void Function(LayoutItem item)? onItemResizeStart;

  /// Called when a resize operation ends.
  final void Function(LayoutItem item)? onItemResizeEnd;

  /// The layout configuration for the trash bin.
  final TrashLayout trashLayout;

  /// A builder for the trash/delete area.
  final DashboardTrashBuilder? trashBuilder;

  /// Called when an item is dropped into the trash area.
  final Future<bool> Function(LayoutItem item)? onWillDelete;

  /// Called when an item is deleted.
  final void Function(LayoutItem item)? onItemDeleted;

  /// The duration the user must hover over the trash area before it becomes armed.
  final Duration trashHoverDelay;

  @override
  State<Dashboard<T>> createState() => _DashboardState<T>();
}

class _DashboardState<T extends Object> extends State<Dashboard<T>> {
  late ScrollController _scrollController;
  bool _isInternalScrollController = false;

  @override
  void initState() {
    super.initState();
    _isInternalScrollController = widget.scrollController == null;
    _scrollController = widget.scrollController ?? ScrollController();

    // Initialize controller settings based on widget parameters.
    widget.controller.setResizeBehavior(widget.resizeBehavior);
    (widget.controller as DashboardControllerImpl).setScrollDirection(widget.scrollDirection);
    widget.controller.setHandleColor(widget.gridStyle.handleColor);
    widget.controller.setResizeHandleSide(widget.resizeHandleSide);
    widget.controller.guidance = widget.guidance;
  }

  @override
  void dispose() {
    if (_isInternalScrollController) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant Dashboard<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync ScrollController if it changes
    if (widget.scrollController != oldWidget.scrollController) {
      if (_isInternalScrollController) {
        _scrollController.dispose();
      }
      _isInternalScrollController = widget.scrollController == null;
      _scrollController = widget.scrollController ?? ScrollController();
    }

    // Sync configuration changes to the controller
    if (widget.resizeBehavior != oldWidget.resizeBehavior) {
      widget.controller.setResizeBehavior(widget.resizeBehavior);
    }
    if (widget.scrollDirection != oldWidget.scrollDirection) {
      (widget.controller as DashboardControllerImpl).setScrollDirection(widget.scrollDirection);
    }
    if (widget.guidance != oldWidget.guidance) {
      widget.controller.guidance = widget.guidance;
    }
    if (widget.resizeHandleSide != oldWidget.resizeHandleSide) {
      widget.controller.setResizeHandleSide(widget.resizeHandleSide);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reasoning: The Dashboard widget acts as a high-level composer.
    // It wraps the content in a DashboardOverlay to handle interactions (drag, resize, trash)
    // and creates a CustomScrollView containing the SliverDashboard to render the grid.
    return DashboardOverlay<T>(
      controller: widget.controller,
      scrollController: _scrollController,
      itemBuilder: widget.itemBuilder,
      itemFeedbackBuilder: widget.itemFeedbackBuilder,
      trashBuilder: widget.trashBuilder,
      trashLayout: widget.trashLayout,
      trashHoverDelay: widget.trashHoverDelay,
      onWillDelete: widget.onWillDelete,
      onItemDeleted: widget.onItemDeleted,
      onItemDragStart: widget.onItemDragStart,
      onItemDragUpdate: widget.onItemDragUpdate,
      onItemDragEnd: widget.onItemDragEnd,
      onItemResizeStart: widget.onItemResizeStart,
      onItemResizeEnd: widget.onItemResizeEnd,
      onDrop: widget.onDrop,
      resizeHandleSide: widget.resizeHandleSide,
      placeholderWidth: widget.placeholderWidth,
      placeholderHeight: widget.placeholderHeight,
      itemGlobalKeySuffix: widget.itemGlobalKeySuffix,

      // Pass layout params directly to Overlay so it can render the background grid.
      gridStyle: widget.gridStyle,
      slotAspectRatio: widget.slotAspectRatio,
      mainAxisSpacing: widget.mainAxisSpacing,
      crossAxisSpacing: widget.crossAxisSpacing,
      padding: widget.padding ?? EdgeInsets.zero,
      scrollDirection: widget.scrollDirection,
      fillViewport: true,

      child: ScrollConfiguration(
        behavior: widget.scrollBehavior ??
            ScrollConfiguration.of(context).copyWith(scrollbars: widget.showScrollbar),
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: CustomScrollView(
            controller: _scrollController,
            physics: widget.physics,
            scrollDirection: widget.scrollDirection,
            cacheExtent: widget.cacheExtent,
            slivers: [
              SliverPadding(
                padding: widget.padding ?? EdgeInsets.zero,
                sliver: SliverDashboard(
                  itemBuilder: widget.itemBuilder,
                  itemStyle: widget.itemStyle,
                  scrollDirection: widget.scrollDirection,
                  slotAspectRatio: widget.slotAspectRatio,
                  mainAxisSpacing: widget.mainAxisSpacing,
                  crossAxisSpacing: widget.crossAxisSpacing,
                  breakpoints: widget.breakpoints,
                  itemGlobalKeySuffix: widget.itemGlobalKeySuffix,
                  // Reasoning: We pass null for gridStyle here because the grid is
                  // rendered by the DashboardOverlay (via DashboardGrid) in the background.
                  // This avoids painting the grid twice.
                  gridStyle: null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
