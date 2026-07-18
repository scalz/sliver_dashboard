import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_provider.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart' show ResizeBehavior;
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/dashboard.dart';
import 'package:sliver_dashboard/src/view/dashboard_configuration.dart';
import 'package:sliver_dashboard/src/view/dashboard_overlay.dart';
import 'package:sliver_dashboard/src/view/dashboard_typedefs.dart';
import 'package:sliver_dashboard/src/view/guidance/dashboard_guidance.dart';
import 'package:sliver_dashboard/src/view/nested/dashboard_nested_scope.dart';
import 'package:state_beacon/state_beacon.dart';

/// A dashboard embedded inside an item of another dashboard.
///
/// Place a [NestedDashboard] in the content you build for a parent item, and — when a
/// [DashboardNestedScope] wraps the tree — items can be dragged seamlessly
/// between the parent grid, this grid, and any sibling or deeper grids.
///
/// ```dart
/// Dashboard(
///   controller: root,
///   itemBuilder: (context, item) {
///     if (item.id == 'group-1') {
///       return NestedDashboard(
///         controller: group1Controller,
///         parentItemId: item.id,
///         itemBuilder: buildLeafItem,
///       );
///     }
///     return buildLeafItem(context, item);
///   },
/// )
/// ```
///
///
/// * **[autoSlotCount]** (default true): the child
///   grid's slot count follows the parent item's width in slots, so inner and
///   outer cells keep the same visual width while the host item is resized.
/// * **[sizeToContent]** (default false): the host
///   item's height grows/shrinks so the child grid never scrolls internally.
/// * Registration with the enclosing [DashboardNestedScope] happens
///   automatically; a layout stashed by `loadNestedTree` for [parentItemId]
///   is applied on first mount.
class NestedDashboard extends StatefulWidget {
  /// Creates a nested dashboard hosted by the parent item [parentItemId].
  const NestedDashboard({
    required this.controller,
    required this.parentItemId,
    this.itemBuilder,
    this.itemLayoutBuilder,
    this.itemBreakpointBuilder,
    this.breakpointResolver,
    this.autoSlotCount = true,
    this.sizeToContent = false,
    this.sizeToContentMax,
    this.chromeExtent = 0.0,
    this.slotAspectRatio = 1.0,
    this.mainAxisSpacing = 8.0,
    this.crossAxisSpacing = 8.0,
    this.padding,
    this.resizeHandleSide = 20.0,
    this.gridStyle = const GridStyle(),
    this.itemStyle = DashboardItemStyle.defaultStyle,
    this.resizeBehavior = ResizeBehavior.push,
    this.guidance,
    this.itemGlobalKeySuffix = '',
    this.itemFeedbackBuilder,
    this.onItemDragStart,
    this.onItemDragUpdate,
    this.onItemDragEnd,
    this.onItemResizeStart,
    this.onItemResizeEnd,
    this.dragStartGesture = DragStartGesture.longPress,
    this.sectionHeaderBuilder,
    this.crossGridDragOut = true,
    this.acceptCrossGridItems = true,
    super.key,
  }) : assert(
          (itemBuilder != null ? 1 : 0) +
                  (itemLayoutBuilder != null ? 1 : 0) +
                  (itemBreakpointBuilder != null && breakpointResolver != null ? 1 : 0) ==
              1,
          'Provide exactly one builder configuration: itemBuilder, itemLayoutBuilder, or both itemBreakpointBuilder and breakpointResolver.',
        );

  /// The controller of the nested grid. Owned by the application.
  final DashboardController controller;

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

  /// The id of the parent grid item hosting this nested dashboard.
  ///
  /// Required to link the grids in the [DashboardNestedScope] tree (export,
  /// `subGridDynamic` detection, [sizeToContent]).
  final String parentItemId;

  /// When true (default), the child slot count follows the parent item's
  /// width in slots.
  final bool autoSlotCount;

  /// When true, the parent item's height is adjusted automatically so the
  /// whole child grid is visible without internal scrolling.
  ///
  /// While enabled, **`sizeToContent` owns the host item's height**: it is
  /// derived from the child content on every layout change. Manually resizing
  /// the host vertically therefore has no lasting effect — the height snaps
  /// back to fit the content on the next frame (the manual resize is not
  /// fought *during* the gesture, only reconciled after it).
  /// A`sizeToContent` sub-grid's height is content-driven,
  /// not user-driven. To let users set the host height by hand, disable
  /// `sizeToContent` for that host (it may be toggled at runtime).
  final bool sizeToContent;

  /// Optional soft cap (in parent slots) for [sizeToContent] growth.
  final int? sizeToContentMax;

  /// Extra vertical pixels occupied by chrome around the nested grid inside
  /// the host item (header, paddings) that [sizeToContent] must account for.
  final double chromeExtent;

  /// See [Dashboard.slotAspectRatio].
  final double slotAspectRatio;

  /// See [Dashboard.mainAxisSpacing].
  final double mainAxisSpacing;

  /// See [Dashboard.crossAxisSpacing].
  final double crossAxisSpacing;

  /// See [Dashboard.padding].
  final EdgeInsets? padding;

  /// See [Dashboard.resizeHandleSide].
  final double resizeHandleSide;

  /// See [Dashboard.gridStyle].
  final GridStyle gridStyle;

  /// See [Dashboard.itemStyle].
  final DashboardItemStyle itemStyle;

  /// See [Dashboard.resizeBehavior].
  final ResizeBehavior resizeBehavior;

  /// See [Dashboard.guidance].
  final DashboardGuidance? guidance;

  /// See [Dashboard.itemGlobalKeySuffix]. Defaults to a value derived from
  /// [parentItemId] to keep item global keys unique across grids.
  final String itemGlobalKeySuffix;

  /// See [Dashboard.itemFeedbackBuilder].
  final DashboardItemFeedbackBuilder? itemFeedbackBuilder;

  /// See [Dashboard.onItemDragStart].
  final void Function(LayoutItem item)? onItemDragStart;

  /// See [Dashboard.onItemDragUpdate].
  final void Function(LayoutItem item, Offset globalPosition)? onItemDragUpdate;

  /// See [Dashboard.onItemDragEnd].
  final void Function(LayoutItem item)? onItemDragEnd;

  /// See [Dashboard.onItemResizeStart].
  final void Function(LayoutItem item)? onItemResizeStart;

  /// See [Dashboard.onItemResizeEnd].
  final void Function(LayoutItem item)? onItemResizeEnd;

  /// See [Dashboard.dragStartGesture].
  final DragStartGesture dragStartGesture;

  /// See [Dashboard.sectionHeaderBuilder].
  final DashboardSectionHeaderBuilder? sectionHeaderBuilder;

  /// Whether items may be dragged out of this nested grid into other grids
  /// of the same [DashboardNestedScope].
  final bool crossGridDragOut;

  /// Whether this nested grid accepts items dragged from other grids of the
  /// same [DashboardNestedScope].
  final bool acceptCrossGridItems;

  @override
  State<NestedDashboard> createState() => _NestedDashboardState();
}

class _NestedDashboardState extends State<NestedDashboard> {
  DashboardNestedCoordinator? _coordinator;
  DashboardController? _parentController;

  // Last slot count pushed via autoSlotCount; avoids redundant setSlotCount.
  int? _appliedSlotCount;

  // Last host height pushed via sizeToContent; breaks feedback loops.
  int? _appliedHostH;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final coordinator = DashboardNestedScope.maybeOf(context);
    final parent = DashboardControllerProvider.of(context);

    if (!identical(coordinator, _coordinator) || !identical(parent, _parentController)) {
      _coordinator = coordinator;
      _parentController = parent;
      coordinator?.linkChildGrid(
        parent: parent,
        parentItemId: widget.parentItemId,
        child: widget.controller,
      );
      // Apply grid data stashed by a tree load before this grid mounted.
      // Deferred to after the frame: didChangeDependencies runs during build,
      // and importLayout mutates beacons that other widgets may be watching.
      final stashed = coordinator?.takeStashedChildGrid(widget.parentItemId);
      if (stashed != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!widget.autoSlotCount && stashed.slotCount != null && stashed.slotCount! > 0) {
            widget.controller.setSlotCount(stashed.slotCount!);
          }
          widget.controller.importLayout([for (final i in stashed.items) i.toMap()]);
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant NestedDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller) ||
        widget.parentItemId != oldWidget.parentItemId) {
      _appliedSlotCount = null;
      _appliedHostH = null;
      if (!identical(widget.controller, oldWidget.controller)) {
        _coordinator?.unlinkChildGrid(oldWidget.controller);
      }
      final parent = _parentController;
      if (parent != null) {
        _coordinator?.linkChildGrid(
          parent: parent,
          parentItemId: widget.parentItemId,
          child: widget.controller,
        );
      }
    }
  }

  @override
  void dispose() {
    // Deliberately NOT unlinking here: sliver virtualization unmounts this
    // widget whenever the host item leaves the viewport, and the parent link
    // must survive so exports, subGridDynamic detection and tree loads keep
    // seeing the (still alive) child controller. Call
    // `coordinator.unlinkChildGrid(controller)` from application code when a
    // nested grid is removed permanently and its controller disposed.
    super.dispose();
  }

  LayoutItem? _hostItem(List<LayoutItem> parentLayout) {
    for (final i in parentLayout) {
      if (i.id == widget.parentItemId) return i;
    }
    return null;
  }

  /// column:'auto' — child slot count follows the host item's width in slots.
  void _syncSlotCount(LayoutItem host) {
    final wanted = host.w;
    if (wanted < 1 || _appliedSlotCount == wanted) return;
    if (widget.controller.slotCount.peek() == wanted) {
      _appliedSlotCount = wanted;
      return;
    }
    _appliedSlotCount = wanted;
    // Mutating a beacon during build is illegal; defer to after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.controller.slotCount.peek() != wanted) {
        widget.controller.setSlotCount(wanted);
      }
    });
  }

  /// sizeToContent — grow/shrink the host item so the child grid fits.
  void _syncSizeToContent({
    required LayoutItem host,
    required List<LayoutItem> childLayout,
    required BoxConstraints constraints,
  }) {
    final parentReg = _coordinator?.registrationOf(_parentController!);
    final parentMetrics = parentReg?.target.currentSlotMetrics();
    if (parentMetrics == null) return;

    // Rows needed by the child layout.
    var rows = 0;
    for (final i in childLayout) {
      final bottom = i.y + i.h;
      if (bottom > rows) rows = bottom;
    }
    if (rows == 0) rows = 1;

    // Child pixel height for those rows, using the child's own metrics
    // derived from the width this widget actually occupies.
    final childMetrics = SlotMetrics.fromConstraints(
      constraints,
      slotCount: widget.controller.slotCount.peek(),
      slotAspectRatio: widget.slotAspectRatio,
      mainAxisSpacing: widget.mainAxisSpacing,
      crossAxisSpacing: widget.crossAxisSpacing,
      padding: widget.padding ?? EdgeInsets.zero,
      scrollDirection: Axis.vertical,
    );
    final padding = widget.padding ?? EdgeInsets.zero;
    final neededChildPx = rows * (childMetrics.slotHeight + widget.mainAxisSpacing) -
        widget.mainAxisSpacing +
        padding.vertical +
        widget.chromeExtent;

    // Parent slots needed: h*(slotH+spacing)-spacing >= neededChildPx.
    final parentStride = parentMetrics.slotHeight + parentMetrics.mainAxisSpacing;
    if (parentStride <= 0) return;
    var wantedH = ((neededChildPx + parentMetrics.mainAxisSpacing) / parentStride).ceil();
    if (wantedH < 1) wantedH = 1;
    final cap = widget.sizeToContentMax;
    if (cap != null && wantedH > cap) wantedH = cap;

    if (wantedH == host.h) {
      // Already at the right height: remember it and stop.
      _appliedHostH = wantedH;
      return;
    }
    // Only skip if we already REQUESTED this exact height and the host has not
    // yet caught up (avoids re-posting the same callback every frame). If the
    // host settled at a different height than we last asked for, recompute:
    // the previous request may have been based on transient metrics (during
    // autoSlotCount / host-resize churn) and must be allowed to re-converge.
    if (_appliedHostH == wantedH && _appliedHostH == host.h) return;
    _appliedHostH = wantedH;

    final parent = _parentController!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Never fight an interactive gesture. This must cover BOTH grids and
      // BOTH gesture kinds:
      //  - a drag/resize on the parent grid (the user is moving/sizing the
      //    host itself — e.g. dragging the host's resize handle downward);
      //  - a drag/resize on the child grid (its layout is mid-change).
      final parentImpl = parent.internal;
      final childImpl = widget.controller.internal;
      if (parentImpl.isDragging.peek() ||
          parentImpl.isResizing.peek() ||
          childImpl.isDragging.peek() ||
          childImpl.isResizing.peek()) {
        return;
      }
      parentImpl.setItemSize(widget.parentItemId, h: wantedH);
    });
  }

  @override
  Widget build(BuildContext context) {
    final parent = _parentController;

    // Watch the parent layout only for this item's geometry.
    LayoutItem? host;
    if (parent != null) {
      final parentLayout = parent.layout.watch(context);
      host = _hostItem(parentLayout);
      if (host != null && widget.autoSlotCount) {
        _syncSlotCount(host);
      }
    }

    // Watch the child layout when sizeToContent needs to react to it.
    final childLayout = widget.sizeToContent ? widget.controller.layout.watch(context) : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.sizeToContent &&
            host != null &&
            childLayout != null &&
            constraints.hasBoundedWidth) {
          _syncSizeToContent(
            host: host,
            childLayout: childLayout,
            constraints: constraints,
          );
        }

        return Dashboard<Object>(
          controller: widget.controller,
          itemBuilder: widget.itemBuilder,
          itemLayoutBuilder: widget.itemLayoutBuilder,
          itemBreakpointBuilder: widget.itemBreakpointBuilder,
          breakpointResolver: widget.breakpointResolver,
          slotAspectRatio: widget.slotAspectRatio,
          mainAxisSpacing: widget.mainAxisSpacing,
          crossAxisSpacing: widget.crossAxisSpacing,
          padding: widget.padding,
          resizeHandleSide: widget.resizeHandleSide,
          gridStyle: widget.gridStyle,
          itemStyle: widget.itemStyle,
          resizeBehavior: widget.resizeBehavior,
          // The parent scroll view owns scrolling when sizeToContent is on;
          // otherwise the nested grid scrolls internally like any Dashboard.
          physics: widget.sizeToContent ? const NeverScrollableScrollPhysics() : null,
          showScrollbar: !widget.sizeToContent,
          // With sizeToContent the host is sized to the content, so grid lines
          // must stop at the content extent instead of filling the (equal)
          // host height, which would paint empty trailing rows.
          fillViewport: !widget.sizeToContent,
          guidance: widget.guidance,
          itemGlobalKeySuffix: widget.itemGlobalKeySuffix.isEmpty
              ? '-nested-${widget.parentItemId}'
              : widget.itemGlobalKeySuffix,
          itemFeedbackBuilder: widget.itemFeedbackBuilder,
          onItemDragStart: widget.onItemDragStart,
          onItemDragUpdate: widget.onItemDragUpdate,
          onItemDragEnd: widget.onItemDragEnd,
          onItemResizeStart: widget.onItemResizeStart,
          onItemResizeEnd: widget.onItemResizeEnd,
          dragStartGesture: widget.dragStartGesture,
          sectionHeaderBuilder: widget.sectionHeaderBuilder,
          crossGridDragOut: widget.crossGridDragOut,
          acceptCrossGridItems: widget.acceptCrossGridItems,
        );
      },
    );
  }
}
