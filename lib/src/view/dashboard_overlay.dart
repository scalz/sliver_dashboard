import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart'
    show DashboardControllerImpl, ScrollRequest;
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_provider.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/models/utility.dart';
import 'package:sliver_dashboard/src/view/a11y/dashboard_shortcuts.dart';
import 'package:sliver_dashboard/src/view/dashboard_configuration.dart';
import 'package:sliver_dashboard/src/view/dashboard_feedback_widget.dart';
import 'package:sliver_dashboard/src/view/dashboard_grid.dart';
import 'package:sliver_dashboard/src/view/dashboard_item_widget.dart';
import 'package:sliver_dashboard/src/view/dashboard_typedefs.dart';
import 'package:sliver_dashboard/src/view/nested/dashboard_nested_scope.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';
import 'package:sliver_dashboard/src/view/sliver_dashboard.dart';
import 'package:state_beacon/state_beacon.dart';

/// Internal flag to allow overriding kIsWeb during unit tests
/// to safely execute and cover the Web throttle mechanism.
@visibleForTesting
bool debugOverrideIsWeb = false;

/// The gesture used to trigger a drag operation on mobile platforms.
enum DragStartGesture {
  /// Dragging is initiated by holding/long-pressing an item.
  longPress,

  /// Dragging is initiated by a simple pointer down / tap on the item.
  tap,

  /// Dragging on the item's main body is disabled. Drags can only be
  /// initiated using handles (e.g. DashboardDragStartListener).
  none,
}

/// An interface to control [DashboardOverlay] programmatically.
class DashboardOverlayController {
  /// Creates a [DashboardOverlayController].
  const DashboardOverlayController();

  /// Starts a drag operation programmatically on the item with the given [itemId]
  /// using the provided [globalPosition] as the start coordinate.
  void startDragging(String itemId, Offset globalPosition) {}
}

/// An InheritedWidget that provides a [DashboardOverlayController] to its descendants.
class DashboardOverlayProvider extends InheritedWidget {
  /// Creates a [DashboardOverlayProvider].
  const DashboardOverlayProvider({
    required this.overlayController,
    required super.child,
    super.key,
  });

  /// The overlay controller instance to provide.
  final DashboardOverlayController overlayController;

  /// Retrieves the closest [DashboardOverlayController] instance from the widget tree.
  static DashboardOverlayController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<DashboardOverlayProvider>()
        ?.overlayController;
  }

  @override
  bool updateShouldNotify(DashboardOverlayProvider oldWidget) {
    return overlayController != oldWidget.overlayController;
  }
}

/// A widget that provides interaction capabilities (drag, resize, auto-scroll)
/// for [SliverDashboard]s embedded within its [child].
///
/// This widget must wrap the [CustomScrollView] (or similar scrollable) that
/// contains the [SliverDashboard]. It handles gestures globally and performs
/// hit-testing to find the underlying dashboard items.
class DashboardOverlay<T extends Object> extends StatefulWidget {
  /// Creates a [DashboardOverlay].
  const DashboardOverlay({
    required this.controller,
    required this.scrollController,
    required this.child,
    this.sliverKey,
    this.itemBuilder,
    this.itemLayoutBuilder,
    this.itemBreakpointBuilder,
    this.breakpointResolver,
    this.gridStyle,
    this.itemStyle = DashboardItemStyle.defaultStyle,
    this.slotAspectRatio = 1.0,
    this.mainAxisSpacing = 8.0,
    this.crossAxisSpacing = 8.0,
    this.padding = EdgeInsets.zero,
    this.scrollDirection = Axis.vertical,
    this.itemFeedbackBuilder,
    this.onItemDragStart,
    this.onItemDragUpdate,
    this.onItemDragEnd,
    this.onItemResizeStart,
    this.onItemResizeEnd,
    this.trashLayout = TrashLayout.bottomCenter,
    this.trashBuilder,
    this.onWillDelete,
    this.onItemsDeleted,
    this.trashHoverDelay = const Duration(milliseconds: 800),
    this.resizeHandleSide = 20.0,
    this.placeholderWidth = 1,
    this.placeholderHeight = 1,
    this.onDrop,
    this.itemGlobalKeySuffix = '',
    this.backgroundBuilder,
    this.fillViewport = false,
    this.dragStartGesture = DragStartGesture.longPress,
    this.crossGridDragOut = true,
    this.acceptCrossGridItems = true,
    super.key,
  }) : assert(
          (itemBuilder != null ? 1 : 0) +
                  (itemLayoutBuilder != null ? 1 : 0) +
                  (itemBreakpointBuilder != null && breakpointResolver != null ? 1 : 0) ==
              1,
          'Provide exactly one builder configuration.',
        );

  /// The controller that manages the state of the dashboard.
  final DashboardController controller;

  /// Whether items may be dragged out of this grid into another grid of the
  /// same [DashboardNestedScope]. Only relevant when such a scope is present.
  final bool crossGridDragOut;

  /// Whether this grid accepts items dragged from other grids of the same [DashboardNestedScope].
  /// Only relevant when such a scope is present.
  final bool acceptCrossGridItems;

  /// The scroll controller of the child scroll view.
  /// Required for auto-scrolling and feedback positioning.
  final ScrollController scrollController;

  /// The child widget, typically a [CustomScrollView].
  final Widget child;

  /// A specific GlobalKey bound to the SliverDashboard to resolve hit-test
  /// and geometry target metrics in multi-sliver viewport layouts.
  final GlobalKey? sliverKey;

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

  /// Styling options for the background grid in edit mode.
  /// If null, no grid is painted unless [backgroundBuilder] is provided.
  final GridStyle? gridStyle;

  /// The visual style of the focus/selection borders.
  final DashboardItemStyle itemStyle;

  /// The aspect ratio of each grid slot.
  final double slotAspectRatio;

  /// The spacing between items on the main axis (vertical).
  final double mainAxisSpacing;

  /// The spacing between items on the cross axis (horizontal).
  final double crossAxisSpacing;

  /// Optional padding for the dashboard grid.
  final EdgeInsets padding;

  /// The direction of scrolling for the dashboard.
  final Axis scrollDirection;

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
  final DashboardWillDeleteCallback? onWillDelete;

  /// Called when items are deleted.
  final DashboardItemsDeletedCallback? onItemsDeleted;

  /// The duration the user must hover over the trash area before it becomes armed.
  final Duration trashHoverDelay;

  /// The size of the touch target for resizing handles.
  final double resizeHandleSide;

  /// The width of the placeholder item in grid units when dragging from outside.
  final int placeholderWidth;

  /// The height of the placeholder item in grid units when dragging from outside.
  final int placeholderHeight;

  /// Callback when an external draggable is dropped onto the dashboard.
  final DashboardDropCallback<T>? onDrop;

  /// A suffix to append to global keys for dashboard items.
  final String itemGlobalKeySuffix;

  /// Optional builder for a background widget (e.g. custom grid lines).
  /// This is placed behind the [child]. If provided, [gridStyle] is ignored.
  final WidgetBuilder? backgroundBuilder;

  /// If true, force grid to fill viewport
  final bool fillViewport;

  /// The gesture used to trigger a drag operation on mobile platforms
  final DragStartGesture dragStartGesture;

  @override
  State<DashboardOverlay<T>> createState() => _DashboardOverlayState<T>();
}

class _DashboardOverlayState<T extends Object> extends State<DashboardOverlay<T>>
    implements DashboardOverlayController, CrossGridDragTarget {
  final GlobalKey _overlayStackKey = GlobalKey();

  // Cache target for the RenderObject to prevent expensive tree traversals on pointer moves
  RenderSliverDashboard? _renderSliver;

  // --- Nested grids / cross-grid drag & drop ---
  // Resolved from the nearest DashboardNestedScope; null outside a scope, in
  // which case every cross-grid code path is a single null-check no-op.
  DashboardNestedCoordinator? _nestedCoordinator;
  // Whether this overlay owns the active cross-grid session (the drag started
  // here and the item currently lives as a placeholder in another grid).
  bool _ownsCrossGridSession = false;
  // The foreign item currently hovering this grid (cross-grid target side).
  // Lets the auto-scroll tick re-anchor the placeholder with the right size.
  LayoutItem? _foreignDragItem;
  // Parent grid overlay currently scrolled on our behalf (sizeToContent
  // nested grids delegate edge auto-scroll to their parent).
  CrossGridDragTarget? _delegatedAutoScroll;
  // --- Same-grid subGridDynamic (subGridDynamicSameGrid) ---
  // In-grid drags push neighbours continuously, so a hovered sibling is
  // shoved away before the pointer can rest on it. When the option is on, a
  // stationary pointer freezes the pushes (pre-drag snapshot restored while
  // the drag stays alive), highlights the item under the pointer and arms the
  // nested-grid request — the in-grid twin of the cross-grid arming.
  static const Duration _sameGridPauseDelay = Duration(milliseconds: 350);
  static const double _sameGridMoveTolerance = 8;
  Timer? _sameGridPauseTimer;
  Timer? _sameGridArmTimer;
  String? _sameGridArmedHostId;

  /// The id of the child-grid host the pointer is currently traveling over
  /// during an in-grid drag, while collision pushes are frozen (see the
  /// existing-host approach freeze in the drag branch of _performUpdate).
  String? _frozenOverChildHostId;

  /// Number of enclosing dashboards (0 = a root grid). Cached at
  /// registration; drives the nested-grid containment extension in
  /// [_isInsideSliver].
  int _nestedDepth = 0;
  Offset? _sameGridFreezePosition;
  Offset? _sameGridPauseAnchor;
  StreamSubscription<ScrollRequest>? _scrollSubscription;

  // State for tracking the active drag/resize operation
  String? _activeItemId;
  LayoutItem? _activeItemInitialLayout;
  Offset _operationStartPosition = Offset.zero;
  ResizeHandle? _activeResizeHandle;

  // State variables for scroll-aware resizing
  double _initialScrollOffset = 0;
  Offset? _lastGlobalPosition;

  // Track the visual start of the sliver (grid 0,0) relative to overlay
  Offset? _initialSliverStartLocal;

  // Trash state
  Timer? _trashTimer;
  final _isHoveringTrash = Beacon.writable(false);
  final _isTrashActive = Beacon.writable(false);
  final GlobalKey _trashKey = GlobalKey();

  // Drag offset
  Offset? _dragGrabOffset;

  // Auto-scroll
  Timer? _scrollTimer;
  double _scrollSpeed = 0;

  // Cached metrics for the active sliver
  SlotMetrics? _activeSliverMetrics;

  // Timer to debounce the onLeave call
  Timer? _leaveTimer;
  // Store last valid placeholder to restore it on drop
  LayoutItem? _lastValidPlaceholder;

  // Flag for defering selection to PointerUp if we clic on an already selected item
  bool _shouldClearSelectionOnUp = false;

  bool _isProcessingPointerUp = false;
  final _throttleStopwatch = Stopwatch()..start();
  Offset? _pendingThrottledPosition;
  Timer? _throttleFlushScheduled;

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void startDragging(String itemId, Offset globalPosition) {
    if (!widget.controller.isEditing.value) return;
    _onPointerDown(globalPosition);
  }

  @override
  void initState() {
    super.initState();
    _setupScrollListener();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final coordinator = DashboardNestedScope.maybeOf(context);
    if (!identical(coordinator, _nestedCoordinator)) {
      _nestedCoordinator?.unregister(this);
      _nestedCoordinator = coordinator;
      _nestedDepth = 0;
      if (coordinator != null) {
        // Depth = number of enclosing dashboards. Computed once per
        // registration; used to resolve the deepest grid under the pointer.
        var depth = 0;
        context.visitAncestorElements((element) {
          if (element.widget is DashboardOverlayProvider) depth++;
          return true;
        });
        _nestedDepth = depth;
        coordinator.register(this, depth: depth);
      }
    }
  }

  @override
  void didUpdateWidget(covariant DashboardOverlay<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sliverKey != oldWidget.sliverKey) {
      // The cached render object may still be attached (it belongs to
      // another grid); only the key swap tells us it is no longer ours.
      _renderSliver = null;
    }
    if (widget.controller != oldWidget.controller) {
      _renderSliver = null;
      _hoverIndex = null; // Reason: retains a layout list of the old controller.
      _scrollSubscription?.cancel().ignore();
      _setupScrollListener();
    }
  }

  void _setupScrollListener() {
    if (widget.controller is DashboardControllerImpl) {
      _scrollSubscription = (widget.controller as DashboardControllerImpl)
          .scrollToItemRequest
          .listen(_handleScrollRequest);
    }
  }

  Future<void> _handleScrollRequest(ScrollRequest request) async {
    final renderSliver = _findRenderSliver();
    if (renderSliver == null) {
      if (!request.completer.isCompleted) request.completer.complete();
      return;
    }

    final item = widget.controller.layout.value.firstWhereOrNull((i) => i.id == request.itemId);
    if (item == null) {
      if (!request.completer.isCompleted) request.completer.complete();
      return;
    }

    final metrics = _getMetricsFromSliver(renderSliver);

    // 1. Calculate Item Position relative to the Sliver start
    final double itemStart;
    final double itemSize;

    if (metrics.scrollDirection == Axis.vertical) {
      itemStart = item.y * (metrics.slotHeight + metrics.mainAxisSpacing) + metrics.padding.top;
      itemSize = item.h * (metrics.slotHeight + metrics.mainAxisSpacing) - metrics.mainAxisSpacing;
    } else {
      itemStart = item.x * (metrics.slotWidth + metrics.mainAxisSpacing) + metrics.padding.left;
      itemSize = item.w * (metrics.slotWidth + metrics.mainAxisSpacing) - metrics.mainAxisSpacing;
    }

    // 2. Calculate Absolute Scroll Position
    // precedingScrollExtent is the space taken by slivers BEFORE the dashboard (e.g. AppBar)
    final sliverStart = renderSliver.constraints.precedingScrollExtent;
    final targetOffset = sliverStart + itemStart;

    // 3. Apply Alignment
    // alignment 0.0 = Top of item at Top of viewport
    // alignment 1.0 = Bottom of item at Bottom of viewport
    final viewportSize = widget.scrollController.position.viewportDimension;

    // We want: targetOffset - (viewportSize * alignment) + (itemSize * alignment)
    // Example: Align 0.5 (Center)
    // Scroll to: ItemTop - (ViewHeight/2) + (ItemHeight/2)
    final alignedOffset =
        targetOffset - (viewportSize * request.alignment) + (itemSize * request.alignment);

    // 4. Clamp
    try {
      final clampedOffset = alignedOffset.clamp(
        widget.scrollController.position.minScrollExtent,
        widget.scrollController.position.maxScrollExtent,
      );

      if (request.duration == Duration.zero) {
        widget.scrollController.jumpTo(clampedOffset);
      } else {
        await widget.scrollController.animateTo(
          clampedOffset,
          duration: request.duration,
          curve: request.curve,
        );
      }

      if (!request.completer.isCompleted) {
        request.completer.complete();
      }
    } catch (e, s) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(e, s);
      }
    }
  }

  @override
  void dispose() {
    _scrollSubscription?.cancel().ignore();
    _scrollTimer?.cancel();
    _leaveTimer?.cancel();
    _isHoveringTrash.dispose();
    _isTrashActive.dispose();
    _trashTimer?.cancel();
    _throttleFlushScheduled?.cancel();
    _sameGridPauseTimer?.cancel();
    _sameGridArmTimer?.cancel();
    _nestedCoordinator?.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DashboardControllerProvider(
      controller: widget.controller,
      child: DashboardOverlayProvider(
        overlayController: this,
        child: DragTarget<T>(
          onWillAcceptWithDetails: (details) {
            _updatePlaceholderPosition(details.offset);
            return true;
          },
          onMove: (details) {
            _lastGlobalPosition = details.offset;
            _updatePlaceholderPosition(details.offset);
            _handleAutoScroll(details.offset);
          },
          onLeave: (data) {
            _lastGlobalPosition = null;
            _stopScrollTimer();

            // Reason: Debounce hiding to prevent race condition with onAccept.
            // Sometimes onLeave is called just before onAccept when dropping,
            // causing the placeholder to disappear prematurely.
            _leaveTimer?.cancel();
            _leaveTimer = Timer(const Duration(milliseconds: 50), () {
              widget.controller.internal.hidePlaceholder();
              _lastValidPlaceholder = null;
            });
          },
          onAcceptWithDetails: (details) async {
            _leaveTimer?.cancel(); // Cancel any pending hide
            _stopScrollTimer();
            _lastGlobalPosition = null;

            // Reason: Use last valid placeholder if controller's is null.
            // This ensures we have a valid drop target even if onLeave cleared it.
            final placeholder = widget.controller.currentDragPlaceholder ?? _lastValidPlaceholder;

            if (placeholder != null) {
              final newId = await widget.onDrop?.call(details.data, placeholder);
              if (newId != null) {
                widget.controller.internal.onDropExternal(newId: newId);
              } else {
                widget.controller.internal.hidePlaceholder();
              }
            } else {
              widget.controller.internal.hidePlaceholder();
            }

            _lastValidPlaceholder = null;
          },
          builder: (context, candidateData, rejectedData) {
            // Watching isDragging here guarantees that the overlay re-evaluates
            // gesture handling and activates raw pointer movement tracing on mobile immediately.
            widget.controller.isDragging.watch(context);

            return Stack(
              key: _overlayStackKey,
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                // 1. Background (Grid)
                if (widget.backgroundBuilder != null)
                  Positioned.fill(child: widget.backgroundBuilder!(context))
                else if (widget.gridStyle != null)
                  Positioned.fill(
                    child: DashboardGrid(
                      controller: widget.controller,
                      scrollController: widget.scrollController,
                      gridStyle: widget.gridStyle!,
                      slotAspectRatio: widget.slotAspectRatio,
                      mainAxisSpacing: widget.mainAxisSpacing,
                      crossAxisSpacing: widget.crossAxisSpacing,
                      padding: widget.padding,
                      scrollDirection: widget.scrollDirection,
                      fillViewport: widget.fillViewport,
                    ),
                  ),

                // 2. Content
                Positioned.fill(
                  // We use a Listener to handle raw pointer events.
                  // This is necessary for two reasons:
                  // 1. Desktop: To provide immediate feedback (selection) on pointer down,
                  //    bypassing the delay introduced by GestureDetector's tap/long-press logic.
                  // 2. Mobile: To implement a manual "Tap" detection. Since we disable
                  //    onPanStart to allow native scrolling, we need a way to detect
                  //    selection taps that might otherwise be consumed by child widgets.
                  child: Listener(
                    // DESKTOP LOGIC: Raw Pointer Events
                    // On Desktop, we want instant reaction. We handle selection on 'Down'
                    // and drag initiation on 'Move' (with a threshold).
                    onPointerDown: (event) {
                      // 1. Store the initial position to calculate distance later (for Mobile Tap detection).
                      _pointerDownPosition = event.position;

                      // 2. On Desktop, trigger selection logic immediately.
                      // If tap to drag is enabled, we trigger drag start immediately on touch down
                      if (!_isMobile || widget.dragStartGesture == DragStartGesture.tap) {
                        _onPointerDown(event.position);
                      }
                    },
                    // On Mobile, we leave 'Move' to the GestureDetector/ScrollView to avoid conflicts.
                    onPointerMove: (!_isMobile || widget.controller.isDragging.value)
                        ? (event) => _onPointerMove(event.position)
                        : null,
                    onPointerUp: (event) {
                      if (_isMobile && !widget.controller.isDragging.value) {
                        // MOBILE TAP DETECTION
                        // Since onPanStart is null on mobile (to favor scrolling),
                        // standard onTap might be lost if children (like buttons) capture the gesture.
                        // We manually detect a "Tap" if the pointer went Down and Up
                        // without moving more than a small threshold (10px).
                        if (_pointerDownPosition != null &&
                            (event.position - _pointerDownPosition!).distance < 10.0) {
                          _handleMobileTap(event.position);
                        }
                      } else {
                        // Desktop only
                        // On Mobile, onLongPressEnd is in charge, else it's called twice (Listener + GestureDetector).
                        _onPointerUp().ignore();
                      }
                      _pointerDownPosition = null; // Cleanup
                    },
                    onPointerCancel: (event) {
                      _onPointerUp().ignore();
                      _pointerDownPosition = null; // Cleanup
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onLongPressStart:
                          _isMobile && widget.dragStartGesture == DragStartGesture.longPress
                              ? (details) => _onPointerDown(details.globalPosition)
                              : null,
                      onLongPressMoveUpdate:
                          _isMobile && widget.dragStartGesture == DragStartGesture.longPress
                              ? (details) => _onPointerMove(details.globalPosition)
                              : null,
                      onLongPressEnd:
                          _isMobile && widget.dragStartGesture == DragStartGesture.longPress
                              ? (details) => _onPointerUp()
                              : null,
                      onLongPressCancel:
                          _isMobile && widget.dragStartGesture == DragStartGesture.longPress
                              ? _onPointerUp
                              : null,
                      child: widget.child,
                    ),
                  ),
                ),
                // 3. Feedback & Trash
                _buildFeedbackLayer(),
                _buildTrashLayer(),
              ],
            );
          },
        ),
      ),
    );
  }

  Offset? _pointerDownPosition;

  /// Handles simple tap on Mobile to toggle selection.
  void _handleMobileTap(Offset globalPosition) {
    if (!widget.controller.isEditing.value) return;

    final hit = _hitTest(globalPosition);
    final foundItem = hit.item;

    if (foundItem != null && !foundItem.isStatic) {
      widget.controller.toggleSelection(foundItem.id, multi: true);
    } else {
      widget.controller.clearSelection();
    }
  }

  Widget _buildFeedbackLayer() {
    return AnimatedBuilder(
      animation: widget.scrollController,
      builder: (context, _) {
        widget.controller.layout.watch(context);

        final isDragging = widget.controller.isDragging.watch(context);
        if (!isDragging) return const SizedBox.shrink();

        // Get Selected Items
        final selectedIds = widget.controller.selectedItemIds.watch(context);
        final activeItemId = widget.controller.activeItemId.watch(context); // The Pivot

        if (selectedIds.isEmpty || activeItemId == null) {
          return const SizedBox.shrink();
        }

        // Find Pivot Item (The reference for positioning)
        final layout = widget.controller.layout.value;
        final pivotItem = layout.firstWhereOrNull((i) => i.id == activeItemId);

        // Find All Cluster Items
        final clusterItems = layout.where((i) => selectedIds.contains(i.id)).toList();

        final renderSliver = _findRenderSliver();
        if (renderSliver != null) {
          _activeSliverMetrics = _getMetricsFromSliver(renderSliver);
        }

        if (pivotItem == null ||
            clusterItems.isEmpty ||
            _activeSliverMetrics == null ||
            renderSliver == null ||
            !renderSliver.attached) {
          return const SizedBox.shrink();
        }

        final isEditing = widget.controller.isEditing.watch(context);
        final metrics = _activeSliverMetrics!;
        final isVertical = metrics.scrollDirection == Axis.vertical;

        // Position & Clipping (Same robust logic as before)

        final sliverLayoutStart = renderSliver.constraints.precedingScrollExtent;
        final scrollOffset =
            widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;
        final visualStart = sliverLayoutStart - scrollOffset;

        final Offset currentSliverStart;
        if (isVertical) {
          currentSliverStart = Offset(metrics.padding.left, visualStart + metrics.padding.top);
        } else {
          currentSliverStart = Offset(visualStart + metrics.padding.left, metrics.padding.top);
        }

        Rect? sliverBounds;
        final overlayBox = _overlayStackKey.currentContext?.findRenderObject() as RenderBox?;

        if (overlayBox != null) {
          final overlaySize = overlayBox.size;
          final overlap = renderSliver.constraints.overlap;
          final clipStart = max(visualStart, overlap);

          if (isVertical) {
            sliverBounds = Rect.fromLTRB(0, clipStart, overlaySize.width, overlaySize.height);
          } else {
            sliverBounds = Rect.fromLTRB(clipStart, 0, overlaySize.width, overlaySize.height);
          }
          sliverBounds = sliverBounds.intersect(Offset.zero & overlaySize);
        }

        // RENDER CLUSTER
        return Stack(
          children: clusterItems.map((item) {
            return DashboardFeedbackItem(
              key: ValueKey('feedback_${item.id}'),
              item: item,
              itemBuilder: widget.itemBuilder,
              itemLayoutBuilder: widget.itemLayoutBuilder,
              itemBreakpointBuilder: widget.itemBreakpointBuilder,
              breakpointResolver: widget.breakpointResolver,
              feedbackBuilder: widget.itemFeedbackBuilder,
              controller: widget.controller,
              slotWidth: metrics.slotWidth,
              slotHeight: metrics.slotHeight,
              mainAxisSpacing: metrics.mainAxisSpacing,
              crossAxisSpacing: metrics.crossAxisSpacing,
              scrollDirection: metrics.scrollDirection,
              itemGlobalKeySuffix: widget.itemGlobalKeySuffix,
              isEditing: isEditing,
              sliverStartPos: currentSliverStart,
              sliverBounds: sliverBounds,
              itemStyle: widget.itemStyle,
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildTrashLayer() {
    if (widget.trashBuilder == null) return const SizedBox.shrink();

    return Builder(
      builder: (context) {
        final activeItemId = widget.controller.activeItemId.watch(context);
        final isDragging = widget.controller.isDragging.watch(context);
        final showTrash = activeItemId != null && isDragging;

        final layout = widget.trashLayout;
        final targetPos = showTrash ? layout.visible : layout.hidden;

        return AnimatedPositioned(
          left: targetPos.left,
          right: targetPos.right,
          top: targetPos.top,
          bottom: targetPos.bottom,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !showTrash,
            child: KeyedSubtree(
              key: _trashKey,
              child: Builder(
                builder: (context) {
                  final isHoveringTrash = _isHoveringTrash.watch(context);
                  final isTrashActive = _isTrashActive.watch(context);
                  return widget.trashBuilder!(
                    context,
                    isHoveringTrash,
                    isTrashActive,
                    activeItemId,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // Interaction Logic

  ({LayoutItem? item, RenderSliverDashboard? renderSliver, RenderBox? itemRenderBox}) _hitTest(
    Offset globalPosition,
  ) {
    final overlayRenderBox = context.findRenderObject() as RenderBox?;
    if (overlayRenderBox == null) return (item: null, renderSliver: null, itemRenderBox: null);

    final localPosition = overlayRenderBox.globalToLocal(globalPosition);
    final result = BoxHitTestResult();

    if (overlayRenderBox.hitTest(result, position: localPosition)) {
      // Nested grids: the hit-test path is deepest-first, so without an
      // ownership check the first SliverDashboardParentData found under the
      // pointer may belong to a *nested* dashboard's item, and this overlay
      // would try to drag a foreign item (crashing onDragStart on an unknown
      // id). Only entries whose sliver is our own are considered; deeper
      // entries are skipped and the walk naturally reaches our host item.
      final ownSliver = _findRenderSliver();
      for (final entry in result.path) {
        final target = entry.target;
        if (target is RenderBox) {
          final parentData = target.parentData;
          if (parentData is SliverDashboardParentData && parentData.index != null) {
            final parent = target.parent;
            if (parent is RenderSliverDashboard) {
              if (!identical(parent, ownSliver)) continue;
              final index = parentData.index!;
              if (index < parent.items.length) {
                return (
                  item: parent.items[index],
                  renderSliver: parent,
                  itemRenderBox: target,
                );
              }
            }
          }
        }
      }
    }
    return (item: null, renderSliver: null, itemRenderBox: null);
  }

  RenderSliverDashboard? _findRenderSliver() {
    if (_renderSliver != null && _renderSliver!.attached) return _renderSliver;

    // In multi-sliver environments, resolve the exact targeted render object
    // by searching strictly within the localized subtree of the sliver's GlobalKey.
    if (widget.sliverKey != null) {
      final sliverContext = widget.sliverKey!.currentContext;
      if (sliverContext != null) {
        final rootObject = sliverContext.findRenderObject();
        if (rootObject != null) {
          RenderSliverDashboard? found;
          void visitor(RenderObject child) {
            if (found != null) return;
            if (child is RenderSliverDashboard) {
              found = child;
              return;
            }
            child.visitChildren(visitor);
          }

          if (rootObject is RenderSliverDashboard) {
            _renderSliver = rootObject;
          } else {
            // Localized search inside specific SliverDashboard subtree only
            rootObject.visitChildren(visitor);
            _renderSliver = found;
          }

          if (_renderSliver != null) {
            return _renderSliver;
          }
        }
      }
    }

    RenderSliverDashboard? found;
    void visitor(RenderObject child) {
      if (found != null) return;
      if (child is RenderSliverDashboard) {
        found = child;
        return;
      }
      child.visitChildren(visitor);
    }

    final root = context.findRenderObject();
    root?.visitChildren(visitor);
    _renderSliver = found;
    return found;
  }

  void _onPointerDown(Offset position) {
    if (!widget.controller.isEditing.value) return;

    // A deeper nested grid already handles this pointer (its Listener runs
    // first in the dispatch order): do not steal the drag.
    if (_nestedCoordinator?.isPointerClaimedByOther(this) ?? false) return;

    final hit = _hitTest(position);
    final foundItem = hit.item;
    final itemRenderBox = hit.itemRenderBox;
    final renderSliver = hit.renderSliver;

    if (foundItem != null && itemRenderBox != null && renderSliver != null) {
      // Prevent dragging static items, unless the item is an interactive section barrier
      if (foundItem.isStatic && !foundItem.isSectionBarrier) return;

      // MULTI-SELECTION LOGIC
      final shortcuts = widget.controller.shortcuts ?? DashboardShortcuts.defaultShortcuts;
      final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;
      final isMultiSelect = shortcuts.multiSelectKeys.any(pressedKeys.contains);
      final isAlreadySelected = widget.controller.selectedItemIds.peek().contains(foundItem.id);
      _shouldClearSelectionOnUp = false;

      if (isMultiSelect) {
        // Case 1: Shift pressed -> Toggle immediately
        widget.controller.toggleSelection(foundItem.id, multi: true);

        // If we just unselected item, don't start drag
        if (!widget.controller.selectedItemIds.peek().contains(foundItem.id)) {
          return;
        }
      } else {
        // Case 2: No Shift
        if (isAlreadySelected) {
          // Case 2a: Already selected -> Perhaps a Group Drag.
          // Do NOT change selection now.
          // Cleanup others if this is a simple clic (PointerUp).
          _shouldClearSelectionOnUp = true;
        } else {
          // Case 2b: Not selected -> Single selection immediately (replace others).
          widget.controller.toggleSelection(foundItem.id, multi: false);
        }
      }

      widget.controller.onInteractionStart?.call(foundItem);

      _activeSliverMetrics = _getMetricsFromSliver(renderSliver);

      if (widget.scrollController.hasClients) {
        _initialScrollOffset = widget.scrollController.offset;
      }

      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox) return;
      final overlayBox = renderObject;

      final itemLocalPosition = itemRenderBox.globalToLocal(position);

      final itemVisualPos = itemRenderBox.localToGlobal(Offset.zero, ancestor: overlayBox);

      final isVertical = _activeSliverMetrics!.scrollDirection == Axis.vertical;
      final spacingX = isVertical
          ? _activeSliverMetrics!.crossAxisSpacing
          : _activeSliverMetrics!.mainAxisSpacing;
      final spacingY = isVertical
          ? _activeSliverMetrics!.mainAxisSpacing
          : _activeSliverMetrics!.crossAxisSpacing;

      final itemLogicalX = foundItem.x * (_activeSliverMetrics!.slotWidth + spacingX);
      final itemLogicalY = foundItem.y * (_activeSliverMetrics!.slotHeight + spacingY);

      _initialSliverStartLocal = itemVisualPos - Offset(itemLogicalX, itemLogicalY);

      _dragGrabOffset = itemLocalPosition;

      final handle = calculateResizeHandle(
        localPosition: itemLocalPosition,
        size: itemRenderBox.size,
        handleSide: widget.resizeHandleSide,
        isResizable: foundItem.isResizable ?? true,
      );

      _activeItemId = foundItem.id;
      _activeItemInitialLayout = foundItem;
      _operationStartPosition = position;
      _activeResizeHandle = handle;

      // Claim the pointer so ancestor overlays skip it (see _onPointerDown).
      _nestedCoordinator?.claimPointer(this);

      if (handle != null) {
        widget.onItemResizeStart?.call(foundItem);
        widget.controller.internal.onResizeStart(foundItem.id);
      } else {
        widget.onItemDragStart?.call(foundItem);
        widget.controller.internal.onDragStart(foundItem.id);
      }
    }
  }

  void _onPointerMove(Offset position) {
    if (_activeItemId == null) return;

    // Stopwatch Throttling.
    // To prevent event queue flooding from high-polling mice, we throttle updates on Web.
    // Using a Stopwatch avoids allocating garbage (DateTime.now() objects) while remaining
    // completely independent of Flutter's frame rendering cycles, avoiding visual lockups
    // when sub-slot moves are bypassed.
    if (kIsWeb || debugOverrideIsWeb) {
      if (_throttleStopwatch.elapsedMilliseconds < 16) {
        // Keep the freshest position and flush it after the throttle window,
        // otherwise the item settles one event behind the cursor when the
        // burst ends exactly inside the window.
        _pendingThrottledPosition = position;
        _throttleFlushScheduled ??= Timer(const Duration(milliseconds: 17), () {
          _throttleFlushScheduled = null;
          final pending = _pendingThrottledPosition;
          _pendingThrottledPosition = null;
          if (pending != null && _activeItemId != null && mounted) {
            _onPointerMove(pending);
          }
        });
        return; // Skip intermediate events (approx. 60fps) to keep browser responsive
      }
      _throttleStopwatch.reset();
      _pendingThrottledPosition = null;
    }

    // If it starts tp move, this is not a "clic", so we won't unselect group at the end.
    if ((position - _operationStartPosition).distance > 2.0) {
      // Tolerance threshold
      _shouldClearSelectionOnUp = false;
    }

    _lastGlobalPosition = position;

    // Active cross-grid session: the item no longer lives in this grid; every
    // move is routed to the coordinator (proxy + hovered grid placeholder +
    // that grid's auto-scroll). Our own auto-scroll and drag math are skipped.
    if (_ownsCrossGridSession) {
      _nestedCoordinator?.updateSession(position);
      return;
    }

    // Same-grid dynamic nesting: while frozen, jitter within the tolerance is
    // swallowed (no pushes, no auto-scroll — the pause IS the intent); a real
    // move disarms and falls through, resuming the normal drag below.
    if (_handleSameGridNestPause(position)) return;

    _handleAutoScroll(position);
    _performUpdate(position);
  }

  void _performUpdate(Offset position) {
    final metrics = _activeSliverMetrics!;

    if (_activeResizeHandle != null) {
      final currentScrollOffset =
          widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;
      final scrollDelta = currentScrollOffset - _initialScrollOffset;
      final effectiveScrollDelta = metrics.scrollDirection == Axis.vertical
          ? Offset(0, scrollDelta)
          : Offset(scrollDelta, 0);

      final totalDragDelta = (position - _operationStartPosition) + effectiveScrollDelta;

      widget.controller.internal.onResizeUpdate(
        _activeItemId!,
        _activeResizeHandle!,
        totalDragDelta,
        slotWidth: metrics.slotWidth,
        slotHeight: metrics.slotHeight,
        crossAxisSpacing: metrics.crossAxisSpacing,
        mainAxisSpacing: metrics.mainAxisSpacing,
      );
    } else {
      // Cross-grid handoff: when the pointer enters another grid of the same
      // DashboardNestedScope (a nested grid inside one of our items, an
      // ancestor grid, or a sibling), the drag leaves this grid and becomes a
      // coordinator-driven session.
      if (_maybeStartCrossGridSession(position)) return;

      // Reason: We calculate the position relative to the Overlay's render box.
      // We assume the Overlay wraps the entire scrollable area.
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox) return;
      final overlayBox = renderObject;

      final overlayLocalPos = overlayBox.globalToLocal(position);

      final currentScroll =
          widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;
      final scrollDelta = currentScroll - _initialScrollOffset;
      final isVertical = metrics.scrollDirection == Axis.vertical;
      final visualDelta = isVertical ? Offset(0, -scrollDelta) : Offset(-scrollDelta, 0);

      final currentSliverStart = _initialSliverStartLocal! + visualDelta;

      var relativePos = overlayLocalPos - currentSliverStart;

      if (_dragGrabOffset != null) {
        relativePos -= _dragGrabOffset!;
      }

      // Existing-host approach freeze. While the pointer travels over an
      // item that ALREADY hosts a child grid, revert the collision pushes so
      // the host — and the child grid mounted inside it — stays put long
      // enough for the pointer to actually enter the child's sliver bounds
      // and hand the drag over (_maybeStartCrossGridSession above). Without
      // this, the in-grid push preview shoves the host away from the
      // approaching pointer, and reaching the child grid takes several
      // attempts of luck and speed. Complements the cross-grid exit hole,
      // which only protects the window AFTER the session has started.
      // Disjoint from the subGridDynamic arm flow, which only handles hosts
      // WITHOUT a grid.
      final approachCoordinator = _nestedCoordinator;
      if (approachCoordinator != null) {
        final impl = widget.controller.internal;
        final snapshot = impl.dragOriginSnapshot;
        final host =
            snapshot == null ? null : _itemAtGlobalIn(snapshot, position, excludeId: _activeItemId);
        final hostsGrid = host != null &&
            !host.isStatic &&
            (host.hasNestedGrid || approachCoordinator.hasChildGrid(widget.controller, host.id));
        if (hostsGrid) {
          if (_frozenOverChildHostId != host.id) {
            _frozenOverChildHostId = host.id;
            impl.freezeDragPushes();
          }
          // Keep the dragged tile glued to the pointer: with the pushes
          // frozen, the pivot sits at its snapshot position, so the visual
          // offset is relative to that.
          final pivot = snapshot!.firstWhereOrNull((i) => i.id == _activeItemId);
          if (pivot != null) {
            // Mirrors onDragUpdate's own offset convention exactly
            // (x stride uses crossAxisSpacing, y stride uses mainAxisSpacing,
            // in both scroll directions).
            impl.setDragOffset(
              relativePos -
                  Offset(
                    pivot.x * (metrics.slotWidth + metrics.crossAxisSpacing),
                    pivot.y * (metrics.slotHeight + metrics.mainAxisSpacing),
                  ),
            );
          }
          _checkTrash(position);
          return; // hold: no pushes while approaching a child grid
        }
        // Left the host without entering its grid: resume normal pushes
        // (freezeDragPushes reset the bbox cache, so the next onDragUpdate
        // re-applies them).
        _frozenOverChildHostId = null;
      }

      widget.controller.internal.onDragUpdate(
        _activeItemId!,
        relativePos,
        slotWidth: metrics.slotWidth,
        slotHeight: metrics.slotHeight,
        crossAxisSpacing: metrics.crossAxisSpacing,
        mainAxisSpacing: metrics.mainAxisSpacing,
      );

      _checkTrash(position);

      if (widget.onItemDragUpdate != null) {
        final currentItem =
            widget.controller.layout.value.firstWhereOrNull((i) => i.id == _activeItemId) ??
                _activeItemInitialLayout!;
        widget.onItemDragUpdate!(currentItem, position);
      }
    }
  }

  /// Whether [position] currently hits the trash zone (if any). Shared by
  /// [_checkTrash] and by the cross-grid exit gating in
  /// [_maybeStartCrossGridSession].
  bool _isPointerOverTrash(Offset position) {
    if (widget.trashBuilder == null) return false;
    final trashRenderBox = _trashKey.currentContext?.findRenderObject() as RenderBox?;
    if (trashRenderBox == null || !trashRenderBox.attached) return false;
    final localTrashPos = trashRenderBox.globalToLocal(position);
    final result = BoxHitTestResult();
    return trashRenderBox.hitTest(result, position: localTrashPos);
  }

  void _checkTrash(Offset position) {
    if (widget.trashBuilder == null) return;
    final trashRenderBox = _trashKey.currentContext?.findRenderObject() as RenderBox?;
    if (trashRenderBox != null) {
      final isHovering = _isPointerOverTrash(position);

      if (isHovering) {
        if (!_isHoveringTrash.value) {
          _isHoveringTrash.value = true;
          _isTrashActive.value = false;
          _trashTimer?.cancel();
          _trashTimer = Timer(widget.trashHoverDelay, () {
            if (mounted && _isHoveringTrash.value) {
              _isTrashActive.value = true;
            }
          });
        }
      } else {
        if (_isHoveringTrash.value) {
          _trashTimer?.cancel();
          _isHoveringTrash.value = false;
          _isTrashActive.value = false;
        }
      }
    }
  }

  Future<void> _onPointerUp() async {
    if (_isProcessingPointerUp) return;
    _isProcessingPointerUp = true;
    final hadActiveDrag = _activeItemId != null;

    try {
      _stopScrollTimer();
      _trashTimer?.cancel();

      // Same-grid nest arming: releasing while frozen drops at the pointer —
      // one final update re-applies the move and, if the armed host was just
      // converted, hands the item over to the freshly mounted nested grid
      // (the regular cross-grid session start inside _performUpdate), which
      // the _ownsCrossGridSession branch below then finalizes as a drop.
      if (_sameGridArmedHostId != null) {
        _cancelSameGridNest();
        if (_activeItemId != null && _lastGlobalPosition != null) {
          _performUpdate(_lastGlobalPosition!);
        }
      } else {
        _sameGridPauseTimer?.cancel();
        _sameGridPauseTimer = null;
      }

      // Clic management for group
      if (_shouldClearSelectionOnUp && _activeItemId != null) {
        // User clicked on an item without moving (without Shift).
        // Keep only this item selected.
        widget.controller.toggleSelection(_activeItemId!, multi: false);
        _shouldClearSelectionOnUp = false;
      }

      if (_activeItemId == null) return;

      final currentItem =
          widget.controller.layout.value.firstWhereOrNull((i) => i.id == _activeItemId) ??
              _activeItemInitialLayout;

      if (currentItem == null) {
        return;
      }

      if (_ownsCrossGridSession) {
        // The item was dragged into another grid (or back): finalize there.
        // A drop over no grid restores this grid's pre-drag layout.
        final placed =
            _nestedCoordinator?.dropSession(_lastGlobalPosition ?? _operationStartPosition);
        widget.onItemDragEnd?.call(placed ?? currentItem);
        return;
      }

      if (_activeResizeHandle != null) {
        widget.controller.internal.onResizeEnd(_activeItemId!);
        widget.onItemResizeEnd?.call(currentItem);
      } else {
        if (widget.trashBuilder != null && _isTrashActive.value) {
          // Identify all items to delete (Pivot + Selection)
          final selectedIds = widget.controller.selectedItemIds.value;

          // Safety: If selection is empty (rare edge case), take the current dragged item
          final idsToDelete = selectedIds.isEmpty ? {currentItem.id} : selectedIds;

          // Retrieve LayoutItem objects
          final itemsToDelete =
              widget.controller.layout.value.where((i) => idsToDelete.contains(i.id)).toList();

          // Fallback safety
          if (itemsToDelete.isEmpty) {
            itemsToDelete.add(currentItem);
          }

          var shouldDelete = true;

          if (widget.onWillDelete != null) {
            shouldDelete = await widget.onWillDelete!(itemsToDelete);
          }
          if (shouldDelete) {
            widget.controller.removeItems(itemsToDelete.map((e) => e.id).toList());

            // Notify for each deleted item
            widget.onItemsDeleted?.call(itemsToDelete);

            widget.controller.internal.onDragEnd(currentItem.id);
          } else {
            widget.controller.internal.onDragEnd(currentItem.id);
          }
        } else {
          widget.controller.internal.onDragEnd(_activeItemId!);
        }
        widget.onItemDragEnd?.call(currentItem);
      }
    } finally {
      // Resolve any fired-but-unconfirmed nested-grid request. A session
      // drop has already resolved it inside dropSession (no-op here); a
      // plain in-grid release resolves it as abandoned. Guarded so a stray
      // pointer-up on a non-dragging overlay can't steal another grid's
      // pending request.
      if (hadActiveDrag) _nestedCoordinator?.resolveNestRequest(null);
      _resetOperationState();
      _isProcessingPointerUp = false;
    }
  }

  void _resetOperationState() {
    if (!mounted) return;
    _activeItemId = null;
    _frozenOverChildHostId = null;
    _activeItemInitialLayout = null;
    _operationStartPosition = Offset.zero;
    _activeResizeHandle = null;
    _dragGrabOffset = null;
    _lastGlobalPosition = null;
    _activeSliverMetrics = null;
    _initialSliverStartLocal = null;
    _isHoveringTrash.value = false;
    _isTrashActive.value = false;
    _trashTimer?.cancel();
    _throttleFlushScheduled?.cancel();
    _throttleFlushScheduled = null;
    _pendingThrottledPosition = null;
    _cancelSameGridNest();
    // Cross-grid cleanup: release the pointer claim and, if a session we own
    // is somehow still alive (exception path), cancel it so the source grid
    // is restored instead of silently losing the item.
    _ownsCrossGridSession = false;
    final coordinator = _nestedCoordinator;
    if (coordinator != null) {
      if (coordinator.isSessionOwner(this)) coordinator.cancelSession();
      coordinator.releasePointer(this);
    }
    widget.controller.internal.setDragOffset(Offset.zero);
  }

  // Auto Scroll

  void _handleAutoScroll(Offset globalPosition) {
    // Auto-scroll for a grid whose own scroll view cannot scroll (typically a
    // sizeToContent nested grid on NeverScrollableScrollPhysics) is delegated
    // to its parent grid, which owns the real viewport. This covers both a
    // foreign cross-grid hover near the bottom edge and an internal child-tile
    // drag that grows the host: in either case the parent must scroll to keep
    // the relevant tile in view. See the delegation block below.
    final scrollPosition =
        widget.scrollController.hasClients ? widget.scrollController.position : null;
    final canScrollSelf =
        scrollPosition != null && scrollPosition.maxScrollExtent > scrollPosition.minScrollExtent;
    // A non-scrollable grid (sizeToContent) delegates edge auto-scroll to its
    // parent in BOTH cases:
    //  - foreign hover: the parent reveals the grid's growing content;
    //  - internal drag: dragging a child tile toward the bottom grows the host
    //    (sizeToContent) and the parent must scroll to keep the tile in view.
    // The difference is handled by the caller: for an internal drag the caller
    // still runs the local _performUpdate afterwards (the tile is ours), while
    // a foreign hover returns here. In both cases we do NOT run this grid's own
    // hot-zone math (it cannot scroll).
    if (!canScrollSelf) {
      final coordinator = _nestedCoordinator;
      final parentController = coordinator?.registrationOf(widget.controller)?.parentController;
      final parentTarget =
          parentController == null ? null : coordinator!.registrationOf(parentController)?.target;
      if (parentTarget != null) {
        // The parent decides start/stop from its own hot zones on every call.
        _delegatedAutoScroll = parentTarget;
        parentTarget.autoScrollAt(globalPosition);
      } else {
        // No parent to delegate to: release any prior delegation.
        _delegatedAutoScroll?.stopAutoScroll();
        _delegatedAutoScroll = null;
      }
      // Nothing to scroll locally regardless; stop only this grid's own timer
      // (must NOT cancel the delegation we just requested above).
      _scrollTimer?.cancel();
      _scrollTimer = null;
      _scrollSpeed = 0.0;
      return;
    }

    final overlayBox = _overlayStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;

    final localPosition = overlayBox.globalToLocal(globalPosition);
    final size = overlayBox.size;

    const hotZoneExtent = 50.0;
    const maxScrollSpeed = 15.0;

    final isVertical = _activeSliverMetrics?.scrollDirection != Axis.horizontal;

    if (isVertical) {
      if (localPosition.dy < hotZoneExtent) {
        final proximity = (hotZoneExtent - localPosition.dy) / hotZoneExtent;
        _scrollSpeed = -maxScrollSpeed * proximity;
        _startScrollTimer();
      } else if (localPosition.dy > size.height - hotZoneExtent) {
        final proximity = (localPosition.dy - (size.height - hotZoneExtent)) / hotZoneExtent;
        _scrollSpeed = maxScrollSpeed * proximity;
        _startScrollTimer();
      } else {
        _stopScrollTimer();
      }
    } else {
      if (localPosition.dx < hotZoneExtent) {
        final proximity = (hotZoneExtent - localPosition.dx) / hotZoneExtent;
        _scrollSpeed = -maxScrollSpeed * proximity;
        _startScrollTimer();
      } else if (localPosition.dx > size.width - hotZoneExtent) {
        final proximity = (localPosition.dx - (size.width - hotZoneExtent)) / hotZoneExtent;
        _scrollSpeed = maxScrollSpeed * proximity;
        _startScrollTimer();
      } else {
        _stopScrollTimer();
      }
    }
  }

  void _startScrollTimer() {
    if (_scrollTimer?.isActive ?? false) return;
    // A non-scrollable grid (e.g. sizeToContent on NeverScrollableScrollPhysics)
    // has nothing to auto-scroll on its own. A foreign hover has already been
    // delegated to the parent in _handleAutoScroll; an internal drag simply
    // grows the host via sizeToContent, and the parent scrolls itself. Starting
    // a timer here would tick jumpTo() against a pinned position every 16ms for
    // no effect, so skip it.
    if (widget.scrollController.hasClients) {
      final p = widget.scrollController.position;
      if (p.maxScrollExtent <= p.minScrollExtent) return;
    }
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!widget.scrollController.hasClients) return;
      final newOffset = widget.scrollController.offset + _scrollSpeed;
      widget.scrollController.jumpTo(
        newOffset.clamp(
          widget.scrollController.position.minScrollExtent,
          widget.scrollController.position.maxScrollExtent,
        ),
      );
      if (_lastGlobalPosition != null) {
        if (_activeItemId != null) {
          _performUpdate(_lastGlobalPosition!);
        } else if (_foreignDragItem != null) {
          // Cross-grid hover: re-anchor with the dragged item's size, not the
          // DragTarget placeholder size.
          _showPlaceholderAt(
            _lastGlobalPosition!,
            w: _foreignDragItem!.w,
            h: _foreignDragItem!.h,
          );
        } else if (widget.controller.currentDragPlaceholder != null) {
          // External DragTarget hover only; never resurrect a placeholder
          // from a stale position (e.g. when scrolled by delegation).
          _updatePlaceholderPosition(_lastGlobalPosition!);
        }
      }
    });
  }

  void _stopScrollTimer() {
    // Also stop a parent grid scrolled on our behalf (delegation).
    _delegatedAutoScroll?.stopAutoScroll();
    _delegatedAutoScroll = null;

    _scrollTimer?.cancel();
    _scrollTimer = null;
    _scrollSpeed = 0.0;
  }

  void _updatePlaceholderPosition(Offset globalPosition) {
    _showPlaceholderAt(
      globalPosition,
      w: widget.placeholderWidth,
      h: widget.placeholderHeight,
    );
  }

  /// Converts [globalPosition] into grid-content coordinates (pixels relative
  /// to the sliver's (0,0), scroll- and padding-corrected), together with the
  /// current slot metrics. Returns null when the sliver is not attached.
  ({SlotMetrics metrics, double dx, double dy})? _gridPointAtGlobal(Offset globalPosition) {
    final renderSliver = _findRenderSliver();
    if (renderSliver == null) return null;

    final metrics = _getMetricsFromSliver(renderSliver);

    // Reason: We use the Overlay's RenderBox as the global coordinate reference.
    // This is safer than using the child's render box, as the Overlay is guaranteed
    // to cover the entire interactive area.
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return null;
    final overlayBox = renderObject;

    final localPos = overlayBox.globalToLocal(globalPosition);

    final scrollOffset = widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;

    final sliverStart = renderSliver.constraints.precedingScrollExtent;

    final double dx;
    final double dy;

    if (metrics.scrollDirection == Axis.vertical) {
      // Reason: Subtract cross-axis padding (left) because the grid logic assumes (0,0)
      // starts after the padding.
      dx = localPos.dx - metrics.padding.left;
      // Reason: Calculate Y relative to the sliver's content start.
      // (Mouse Y) + (Scroll Offset) - (Sliver Start Position) gives the Y inside the sliver.
      dy = localPos.dy + scrollOffset - sliverStart;
    } else {
      dx = localPos.dx + scrollOffset - sliverStart;
      // Reason: Subtract cross-axis padding (top) for horizontal scroll.
      dy = localPos.dy - metrics.padding.top;
    }

    return (metrics: metrics, dx: dx, dy: dy);
  }

  /// Shows (or moves) the external/foreign placeholder of size [w] x [h] at
  /// the grid cell under [globalPosition]. Shared by the [DragTarget] path
  /// (`widget.placeholderWidth/Height`) and by cross-grid drags (dragged item size).
  void _showPlaceholderAt(Offset globalPosition, {required int w, required int h}) {
    final point = _gridPointAtGlobal(globalPosition);
    if (point == null) return;

    final metrics = point.metrics;
    _activeSliverMetrics = metrics;

    // Defensive clamp — a foreign/projected item wider than this grid
    // would invert the x/y clamp range below (`x.clamp(0, slotCount - w)`
    // throws ArgumentError when the upper bound is negative). The coordinator
    // sanitizes projections, but this method is also reachable via the public
    // DragTarget path with caller-provided dimensions.
    final clampedW = metrics.scrollDirection == Axis.vertical ? min(w, metrics.slotCount) : w;
    final clampedH = metrics.scrollDirection != Axis.vertical ? min(h, metrics.slotCount) : h;

    final x = (point.dx /
            (metrics.slotWidth +
                (metrics.scrollDirection == Axis.vertical
                    ? metrics.crossAxisSpacing
                    : metrics.mainAxisSpacing)))
        .floor();
    final y = (point.dy /
            (metrics.slotHeight +
                (metrics.scrollDirection == Axis.vertical
                    ? metrics.mainAxisSpacing
                    : metrics.crossAxisSpacing)))
        .floor();

    final clampedX = max(
      0,
      metrics.scrollDirection == Axis.vertical ? x.clamp(0, metrics.slotCount - clampedW) : x,
    );
    final clampedY = max(
      0,
      metrics.scrollDirection == Axis.vertical ? y : y.clamp(0, metrics.slotCount - clampedH),
    );

    widget.controller.internal.showPlaceholder(
      x: clampedX,
      y: clampedY,
      w: clampedW,
      h: clampedH,
    );

    _lastValidPlaceholder = widget.controller.currentDragPlaceholder;
  }

  @override
  bool isPointInsideSliver(Offset globalPosition) => _isInsideSliver(globalPosition, tolerance: 0);

  /// Core of [isPointInsideSliver] with an optional symmetric [tolerance]
  /// (pixels) inflating the accepted bounds.
  ///
  /// Reason — hot-path shape: this runs once per registered grid per pointer
  /// event during a cross-grid drag (see `DashboardNestedCoordinator.targetAt`,
  /// budget: O(G) point-in-rect tests). It therefore reads the sliver
  /// constraints/geometry directly instead of going through
  /// [_gridPointAtGlobal], which would allocate one SlotMetrics and one record
  /// per grid per event (~2·G·120 short-lived objects/s on a 120 Hz pointer).
  bool _isInsideSliver(Offset globalPosition, {required double tolerance}) {
    final sliver = _findRenderSliver();
    if (sliver == null || !sliver.attached || sliver.geometry == null) return false;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return false;
    final localPos = renderObject.globalToLocal(globalPosition);

    final viewportScroll =
        widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;
    final constraints = sliver.constraints;
    final crossAxisExtent = constraints.crossAxisExtent;
    // Position along the scroll axis relative to the first *visible* pixel of
    // this sliver: (pointer main-axis) + (viewport scroll) - (extent of the
    // slivers before this one) - (part of this sliver already scrolled away).
    final mainLead = constraints.precedingScrollExtent + constraints.scrollOffset;

    var mainEnd = sliver.geometry!.paintExtent;
    if (_nestedDepth > 0) {
      // A nested grid owns its WHOLE internal viewport: NestedDashboard
      // builds a scroll view containing only this grid, so the host strip
      // below the painted content still belongs to it. Without this, the
      // main-axis growth cap can shrink the painted extent below the host
      // height mid-drag, and the strip under the content gets misattributed
      // to the PARENT grid: a session starts against the parent while the
      // pointer is visually inside the nested grid, and the parent's
      // placeholder pushes the host around (top-placeholder + flicker).
      // Root grids (depth 0) keep strict bounds — several sibling slivers
      // may share their scroll view, and inflating one would shadow the
      // others.
      final viewportEnd = constraints.viewportMainAxisExtent + viewportScroll - mainLead;
      if (viewportEnd > mainEnd) mainEnd = viewportEnd;
    }

    if (constraints.axis == Axis.vertical) {
      final dx = localPos.dx - widget.padding.left;
      if (dx < -tolerance || dx > crossAxisExtent + tolerance) return false;
      final dyLocal = localPos.dy + viewportScroll - mainLead;
      return dyLocal >= -tolerance && dyLocal <= mainEnd + tolerance;
    } else {
      final dy = localPos.dy - widget.padding.top;
      if (dy < -tolerance || dy > crossAxisExtent + tolerance) return false;
      final dxLocal = localPos.dx + viewportScroll - mainLead;
      return dxLocal >= -tolerance && dxLocal <= mainEnd + tolerance;
    }
  }
  // ===========================================================================
  // CrossGridDragTarget — how the DashboardNestedScope coordinator drives this
  // grid during a cross-grid drag (see dashboard_nested_scope.dart).
  // ===========================================================================

  @override
  DashboardController get controller => widget.controller;

  @override
  bool get canAcceptCrossGridItems =>
      widget.acceptCrossGridItems && widget.controller.isEditing.value;

  @override
  bool get canDragItemsOut => widget.crossGridDragOut;

  @override
  RenderBox? get overlayRenderBox =>
      _overlayStackKey.currentContext?.findRenderObject() as RenderBox?;

  @override
  SlotMetrics? currentSlotMetrics() {
    final sliver = _findRenderSliver();
    return sliver == null ? null : _getMetricsFromSliver(sliver);
  }

  @override
  void foreignDragOver(LayoutItem item, Offset globalPosition) {
    _foreignDragItem = item;
    // Keep the freshest position so the auto-scroll tick can re-anchor the
    // placeholder while the content moves under a stationary pointer.
    _lastGlobalPosition = globalPosition;
    _showPlaceholderAt(globalPosition, w: item.w, h: item.h);
    _handleAutoScroll(globalPosition);
  }

  @override
  void foreignDragLeave() {
    _foreignDragItem = null;
    _stopScrollTimer();
    widget.controller.internal.hidePlaceholder();
  }

  @override
  LayoutItem? foreignDrop(LayoutItem item) {
    _foreignDragItem = null;
    _stopScrollTimer();
    return widget.controller.internal.onDropExternalItem(template: item);
  }

  @override
  void autoScrollAt(Offset globalPosition) => _handleAutoScroll(globalPosition);

  @override
  void stopAutoScroll() => _stopScrollTimer();

  @override
  LayoutItem? itemAtGlobal(Offset globalPosition, {String? excludeId}) {
    // When a foreign placeholder is active, its collision pushes constantly
    // move items away from the cursor; hover detection is therefore done
    // against the pre-push snapshot so the hovered item is stable.
    final base =
        widget.controller.internal.placeholderHitTestSnapshot ?? widget.controller.layout.peek();
    return _itemAtGlobalIn(base, globalPosition, excludeId: excludeId);
  }

  /// Resolves the item whose cell contains [globalPosition] within [base] —
  /// which may be the live layout or a pre-push snapshot, depending on why
  /// the caller needs hover stability (foreign placeholder vs same-grid drag).
  LayoutItem? _itemAtGlobalIn(
    List<LayoutItem> base,
    Offset globalPosition, {
    String? excludeId,
  }) {
    final point = _gridPointAtGlobal(globalPosition);
    if (point == null) return null;
    final metrics = point.metrics;
    final isVertical = metrics.scrollDirection == Axis.vertical;
    final strideX =
        metrics.slotWidth + (isVertical ? metrics.crossAxisSpacing : metrics.mainAxisSpacing);
    final strideY =
        metrics.slotHeight + (isVertical ? metrics.mainAxisSpacing : metrics.crossAxisSpacing);
    final cx = (point.dx / strideX).floor();
    final cy = (point.dy / strideY).floor();
    if (cx < 0 || cy < 0) return null;

    // Dense-layout fast path: above the threshold, hover resolution goes
    // through a coordinate-bucket index (O(1) per event) instead of the
    // linear scan (O(N) per event). At 100+ small items under a fast desktop
    // pointer (120 Hz), the linear scan costs 12k+ rect tests per second;
    // the bucket lookup costs one hash probe. The index is built once per
    // *base list instance*: the hot callers (nest-hover, same-grid pause)
    // resolve against stable snapshots, so a whole gesture reuses one index.
    if (base.length >= _kHoverIndexThreshold) {
      final index = _hoverIndexFor(base);
      final hit = index.buckets[_hoverCellKey(cx, cy)];
      if (hit == null || hit.id == '__placeholder__' || hit.id == excludeId) {
        return null;
      }
      return hit;
    }

    for (final candidate in base) {
      if (candidate.id == '__placeholder__' || candidate.id == excludeId) continue;
      if (cx >= candidate.x &&
          cx < candidate.x + candidate.w &&
          cy >= candidate.y &&
          cy < candidate.y + candidate.h) {
        return candidate;
      }
    }
    return null;
  }

  /// Below this item count the plain linear scan wins (no index build, no
  /// map memory); above it, the bucket index amortizes within a few events.
  static const int _kHoverIndexThreshold = 16;

  _HoverGridIndex? _hoverIndex;

  /// Packs a grid cell into one int key. `x` is bounded by the slot count
  /// (< 2^20 by construction); `y` grows with content but stays far below
  /// 2^32, keeping the packed key inside the 2^53 safe-integer range on
  /// dart2js.
  static int _hoverCellKey(int cx, int cy) => (cy << 20) | cx;

  /// Returns the bucket index for [base], rebuilding it only when the list
  /// *instance* changed. Build cost is O(total covered cells); the
  /// overlap-free invariant guarantees at most one non-static item per cell,
  /// and first-in-list wins on any residual collision — matching the linear
  /// scan's semantics exactly.
  _HoverGridIndex _hoverIndexFor(List<LayoutItem> base) {
    final cached = _hoverIndex;
    if (cached != null && identical(cached.source, base)) return cached;

    final buckets = <int, LayoutItem>{};
    for (final item in base) {
      if (item.id == '__placeholder__') continue;
      for (var dy = 0; dy < item.h; dy++) {
        final rowBase = (item.y + dy) << 20;
        for (var dx = 0; dx < item.w; dx++) {
          final key = rowBase | (item.x + dx);
          // First-in-list wins, like the linear scan (no closure allocation).
          buckets[key] ??= item;
        }
      }
    }
    final built = _HoverGridIndex(source: base, buckets: buckets);
    _hoverIndex = built;
    return built;
  }

  // ===========================================================================
  // Same-grid subGridDynamic (subGridDynamicSameGrid)
  // ===========================================================================

  /// Called on every internal-drag pointer move. Returns true while the drag
  /// is frozen (armed) and the move is within the jitter tolerance — the
  /// caller must then skip its drag math so the freeze holds. A real move
  /// disarms and returns false, letting the normal drag resume.
  bool _handleSameGridNestPause(Offset position) {
    final coordinator = _nestedCoordinator;
    // Note: deliberately independent of subGridDynamic — the two are
    // orthogonal surfaces (cross-grid hover vs in-grid pause).
    if (coordinator == null ||
        !coordinator.subGridDynamicSameGrid ||
        coordinator.onNestedGridRequested == null ||
        _activeResizeHandle != null ||
        _ownsCrossGridSession) {
      return false;
    }
    // Same rule as cross-grid: dynamic nesting carries exactly one item.
    if (widget.controller.selectedItemIds.peek().length != 1) return false;

    if (_sameGridArmedHostId != null) {
      final anchor = _sameGridFreezePosition;
      if (anchor != null && (position - anchor).distance <= _sameGridMoveTolerance) {
        return true; // frozen: swallow jitter, keep the pushes reverted
      }
      // Real movement: disarm. The caller falls through to _performUpdate,
      // which re-applies the pushes (freezeDragPushes reset the bbox cache)
      // or hands the drag over to a freshly mounted nested grid.
      _cancelSameGridNest();
      return false;
    }

    // Not armed: (re)start pause detection. Pointer events stop arriving when
    // the pointer stops, so the pause can only be observed with a timer —
    // but one restarted only on REAL movement: trackpads and touch screens
    // emit sub-pixel jitter continuously, and restarting on every event
    // would keep the pause forever out of reach on those devices.
    final anchor = _sameGridPauseAnchor;
    if (anchor == null || (position - anchor).distance > _sameGridMoveTolerance) {
      _sameGridPauseAnchor = position;
      _sameGridPauseTimer?.cancel();
      _sameGridPauseTimer = Timer(_sameGridPauseDelay, _armSameGridNest);
    }
    return false;
  }

  /// Pause-timer callback: the pointer has been stationary for
  /// [_sameGridPauseDelay] during an in-grid drag. Freezes the pushes,
  /// highlights the hovered item (resolved against the pre-drag snapshot,
  /// since the pushed layout lies about what is under the pointer) and arms
  /// the nested-grid request after [DashboardNestedCoordinator.nestHoverDelay].
  void _armSameGridNest() {
    if (!mounted) return;
    final coordinator = _nestedCoordinator;
    final itemId = _activeItemId;
    final position = _lastGlobalPosition;
    if (coordinator == null || itemId == null || position == null) return;
    if (_ownsCrossGridSession || _activeResizeHandle != null) return;
    // Pausing over the trash is a delete intent, not a nest intent.
    if (_isHoveringTrash.peek()) return;

    final impl = widget.controller.internal;
    final snapshot = impl.dragOriginSnapshot;
    if (snapshot == null) return;

    final host = _itemAtGlobalIn(snapshot, position, excludeId: itemId);
    final myReg = coordinator.registrationOf(widget.controller);
    final hostable = host != null &&
        !host.isStatic &&
        !host.isSectionBarrier &&
        !host.hasNestedGrid &&
        !coordinator.hasChildGrid(widget.controller, host.id) &&
        (myReg == null || coordinator.canHostAtDepth(myReg.depth));
    if (!hostable) return;

    // Freeze: revert the collision pushes so the hovered item is visually
    // back under the pointer — the in-grid equivalent of the cross-grid
    // freeze (foreignDragLeave before arming). Stop the edge auto-scroll
    // first: its periodic tick re-runs _performUpdate and would fight the
    // freeze every 16ms.
    _stopScrollTimer();
    impl
      ..freezeDragPushes()
      ..setNestTargetHover(host.id);
    _sameGridArmedHostId = host.id;
    _sameGridFreezePosition = position;

    _sameGridArmTimer?.cancel();
    _sameGridArmTimer = Timer(coordinator.nestHoverDelay, () {
      if (!mounted) return;
      if (_sameGridArmedHostId != host.id || _activeItemId != itemId) return;
      final dragged = snapshot.firstWhereOrNull((i) => i.id == itemId) ?? _activeItemInitialLayout;
      if (dragged == null) return;
      coordinator.notifyNestRequestFired(host, widget.controller);
      coordinator.onNestedGridRequested?.call(host, dragged, widget.controller);
      // Stay frozen: the app converts the host and the nested grid mounts
      // under the (stationary) pointer. The next pointer move — or the
      // release itself — hands the drag over to it through the regular
      // cross-grid session start in _performUpdate.
    });
  }

  /// Cancels any same-grid pause/arming state and clears the highlight.
  /// Idempotent; never touches the drag itself (the caller decides whether
  /// to resume it, drop it, or reset the whole operation).
  void _cancelSameGridNest() {
    _sameGridPauseTimer?.cancel();
    _sameGridPauseTimer = null;
    _sameGridArmTimer?.cancel();
    _sameGridArmTimer = null;
    _sameGridPauseAnchor = null;
    if (_sameGridArmedHostId != null) {
      _sameGridArmedHostId = null;
      _sameGridFreezePosition = null;
      widget.controller.internal.setNestTargetHover(null);
    }
  }

  @override
  void setNestHoverHighlight(String? itemId) {
    widget.controller.internal.setNestTargetHover(itemId);
  }

  /// Starts a cross-grid session when the pointer, during a plain item drag,
  /// enters another grid of the same scope. Returns true when the session
  /// started (the caller must skip its local drag math from now on).
  bool _maybeStartCrossGridSession(Offset position) {
    final coordinator = _nestedCoordinator;
    if (coordinator == null || !widget.crossGridDragOut) return false;
    if (coordinator.sessionActive) return false;
    // a cross-grid drag carries exactly one node. Cluster drags stay within their grid.
    if (widget.controller.selectedItemIds.peek().length != 1) return false;

    final itemId = _activeItemId;
    if (itemId == null) return false;
    final item = widget.controller.layout.peek().firstWhereOrNull((i) => i.id == itemId) ??
        _activeItemInitialLayout;
    if (item == null || item.isStatic || item.isSectionBarrier) return false;

    final metrics = _activeSliverMetrics;
    if (metrics == null) return false;
    final isVertical = metrics.scrollDirection == Axis.vertical;
    final spacingX = isVertical ? metrics.crossAxisSpacing : metrics.mainAxisSpacing;
    final spacingY = isVertical ? metrics.mainAxisSpacing : metrics.crossAxisSpacing;
    final itemPixelSize = Size(
      item.w * (metrics.slotWidth + spacingX) - spacingX,
      item.h * (metrics.slotHeight + spacingY) - spacingY,
    );

    // Exit-by-void detection ("the pointer left this sliver's bounds") uses a
    // hysteresis margin of half a slot (min 24 px): the common in-grid
    // gestures — appending past the current last row, skimming through a
    // SliverPadding ring — overshoot the exact paint bounds by a few pixels
    // every drag, and triggering an exit there makes the tile visibly pop
    // into the proxy and back. Entering another *registered grid* is still
    // immediate (no tolerance), so adjacent slivers hand over instantly.
    final double exitTolerance = max(
      24,
      0.5 * (isVertical ? metrics.slotHeight : metrics.slotWidth),
    );
    final isOutside = !_isInsideSliver(position, tolerance: exitTolerance) &&
        // Exiting into the void is only meaningful if some other grid
        // could receive the item; a single-grid scope (e.g. opened purely for
        // subGridDynamicSameGrid) keeps the native drag, which also keeps the
        // trash flow alive.
        coordinator.hasAnyTargetBesides(this) &&
        // The trash zone lives outside the sliver's paint bounds by
        // construction; starting an exit session there would cancel the trash
        // timers and make deletion unreachable (_checkTrash runs after this
        // method in _performUpdate, and never again once a session owns the
        // pointer).
        !_isPointerOverTrash(position);

    // Same probe as the session updates, so entering and placing agree.
    final probePoint = coordinator.probePointFor(
      position,
      grabOffset: _dragGrabOffset ?? Offset.zero,
      itemPixelSize: itemPixelSize,
    );
    final reg = coordinator.targetAt(
      probePoint,
      excludeSourceController: widget.controller,
      excludeItemId: itemId,
    );

    // Start cross-grid session immediately if the pointer exits our overlay bounds,
    // or if it enters another valid registered target.
    if (isOutside || (reg != null && !identical(reg.target, this))) {
      _stopScrollTimer();
      _trashTimer?.cancel();
      _isHoveringTrash.value = false;
      _isTrashActive.value = false;

      coordinator.beginSession(
        source: this,
        item: item,
        globalPosition: position,
        grabOffset: _dragGrabOffset ?? Offset.zero,
        itemPixelSize: itemPixelSize,
        overlayContext: context,
        proxyChild: _buildCrossGridProxy(item, itemPixelSize, metrics.slotCount),
      );
      if (!coordinator.isSessionOwner(this)) return false;
      _ownsCrossGridSession = true;
      coordinator.updateSession(position);
      return true;
    }
    return false;
  }

  /// Builds the floating proxy content that visually carries the item between
  /// grids. Honors [DashboardOverlay.itemFeedbackBuilder] like the in-grid
  /// drag feedback does.
  Widget _buildCrossGridProxy(LayoutItem item, Size itemPixelSize, int slotCount) {
    final base = Material(
      type: MaterialType.transparency,
      child: DashboardControllerProvider(
        controller: widget.controller,
        child: DashboardItem(
          item: item,
          isEditing: false,
          isFeedback: true,
          itemBuilder: widget.itemBuilder,
          itemLayoutBuilder: widget.itemLayoutBuilder,
          itemBreakpointBuilder: widget.itemBreakpointBuilder,
          breakpointResolver: widget.breakpointResolver,
          itemWidth: itemPixelSize.width,
          itemHeight: itemPixelSize.height,
          slotCount: slotCount,
        ),
      ),
    );
    final feedbackBuilder = widget.itemFeedbackBuilder;
    if (feedbackBuilder == null) return base;
    return feedbackBuilder(context, item, base);
  }

  SlotMetrics _getMetricsFromSliver(RenderSliverDashboard sliver) {
    final constraints = sliver.constraints;
    final crossAxisExtent = constraints.crossAxisExtent;
    final slotCount = sliver.slotCount;
    final crossAxisSpacing = sliver.crossAxisSpacing;
    final mainAxisSpacing = sliver.mainAxisSpacing;
    final aspectRatio = sliver.slotAspectRatio;
    final direction = sliver.scrollDirection;

    final double slotWidth;
    final double slotHeight;

    if (direction == Axis.vertical) {
      slotWidth = (crossAxisExtent - (slotCount - 1) * crossAxisSpacing) / slotCount;
      slotHeight = slotWidth / aspectRatio;
    } else {
      slotHeight = (crossAxisExtent - (slotCount - 1) * mainAxisSpacing) / slotCount;
      slotWidth = slotHeight * aspectRatio;
    }

    return SlotMetrics(
      slotWidth: slotWidth,
      slotHeight: slotHeight,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      padding: widget.padding, // Reason: Use the padding passed to Overlay
      scrollDirection: direction,
      slotCount: slotCount,
    );
  }
}

/// Immutable coordinate-bucket index over one layout list instance, mapping a
/// packed grid cell to the item covering it. See `_hoverIndexFor`.
class _HoverGridIndex {
  const _HoverGridIndex({required this.source, required this.buckets});

  /// The exact list instance this index was built from (identity-cached).
  final List<LayoutItem> source;

  /// Packed cell key -> covering item.
  final Map<int, LayoutItem> buckets;
}
