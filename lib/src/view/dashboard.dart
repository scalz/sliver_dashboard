import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_provider.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart' show ResizeBehavior;
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/dashboard_configuration.dart';
import 'package:sliver_dashboard/src/view/dashboard_feedback_widget.dart';
import 'package:sliver_dashboard/src/view/dashboard_item_widget.dart';
import 'package:sliver_dashboard/src/view/dashboard_typedefs.dart';
import 'package:sliver_dashboard/src/view/grid_background_painter.dart';
import 'package:sliver_dashboard/src/view/guidance/dashboard_guidance.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';
import 'package:sliver_dashboard/src/view/sliver_dashboard.dart';
import 'package:state_beacon/state_beacon.dart';

/// Provides access to the internal implementation of [DashboardController].
///
/// This extension is intended for internal use within the package (e.g., inside
/// [Dashboard] or [SliverDashboard]) to access logic and state that are hidden
/// from the public API (such as `onDragUpdate`, `dragOffset`, etc.).
extension ControllerInternalAccess on DashboardController {
  /// Casts this controller to [DashboardControllerImpl] to access internal members.
  DashboardControllerImpl get internal => this as DashboardControllerImpl;
}

/// The main dashboard widget.
///
/// A scrollable, grid-based layout that uses a sliver for high-performance
/// rendering. It is controlled by a [DashboardController].
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

  /// Optional padding for the entire dashboard, the spacing between items and Dashboard outer edges.
  final EdgeInsets? padding;

  /// A map of breakpoints where the key is the minimum width and the value
  /// is the number of columns (slotCount).
  ///
  /// If provided, the dashboard will automatically update the controller.slotCount
  /// when the available width changes.
  ///
  /// Example:
  /// ```dart
  /// {
  ///   0: 4,    // Mobile (0px - 599px) -> 4 cols
  ///   600: 8,  // Tablet (600px - 1199px) -> 8 cols
  ///   1200: 12 // Desktop (1200px+) -> 12 cols
  /// }
  /// ```
  final Map<double, int>? breakpoints;

  /// The size of the touch target on the corners and edges for resizing.
  final double resizeHandleSide;

  /// The width of the placeholder item in grid units when dragging from outside.
  final int placeholderWidth;

  /// The height of the placeholder item in grid units when dragging from outside.
  final int placeholderHeight;

  /// Callback when an external draggable is dropped onto the dashboard.
  /// The user is responsible for creating a new unique ID for the item.
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
  /// If one is provided, the user is responsible for disposing it.
  final ScrollController? scrollController;

  /// A suffix to append to global keys for dashboard items.
  /// Use it for edge case like displaying same dashboard
  /// from two difference places (main page+pushed page or dialog)
  final String itemGlobalKeySuffix;

  /// Optional builder to customize the appearance of the external Placeholder
  final Widget Function(BuildContext context, LayoutItem item)? externalPlaceholderBuilder;

  /// Optional builder to customize the appearance of the item while it is being dragged.
  /// If null, the original item widget is used.
  final DashboardItemFeedbackBuilder? itemFeedbackBuilder;

  /// Called when a drag operation starts on an item.
  final void Function(LayoutItem item)? onItemDragStart;

  /// Called continuously when an item is being dragged.
  /// Provides the item and the global position of the pointer.
  final void Function(LayoutItem item, Offset globalPosition)? onItemDragUpdate;

  /// Called when a drag operation ends.
  final void Function(LayoutItem item)? onItemDragEnd;

  /// Called when a resize operation starts on an item.
  final void Function(LayoutItem item)? onItemResizeStart;

  /// Called when a resize operation ends.
  final void Function(LayoutItem item)? onItemResizeEnd;

  /// The layout configuration for the trash bin (visible and hidden positions).
  /// Defaults to [TrashLayout.bottomCenter].
  final TrashLayout trashLayout;

  /// A builder for the trash/delete area.
  /// If provided, a trash zone will be displayed when dragging an item.
  /// You should usually wrap your widget in an [Align] or [Positioned] to place it correctly.
  final DashboardTrashBuilder? trashBuilder;

  /// Called when an item is dropped into the trash area.
  /// Return `true` to confirm deletion, `false` to cancel.
  /// If null, deletion is immediate.
  final Future<bool> Function(LayoutItem item)? onWillDelete;

  /// Called when an item is dropped into the trash area defined by [trashBuilder].
  /// The item is automatically removed from the controller BEFORE this callback is called.
  final void Function(LayoutItem item)? onItemDeleted;

  /// The duration the user must hover over the trash area before it becomes armed.
  /// Defaults to 400ms.
  /// This prevents accidental deletions when dragging items across the trash area.
  final Duration trashHoverDelay;

  @override
  State<Dashboard<T>> createState() => _DashboardState<T>();
}

class _DashboardState<T extends Object> extends State<Dashboard<T>> {
  late final ScrollController _scrollController;
  bool _isInternalScrollController = false;

  final GlobalKey<State<StatefulWidget>> _scrollKey = GlobalKey();
  final GlobalKey _dashboardStackKey = GlobalKey();

  // Key to detect the trash bin area
  final GlobalKey _trashKey = GlobalKey();

  // State for tracking the active drag/resize operation
  String? _activeItemId;
  LayoutItem? _activeItemInitialLayout;
  Offset _operationStartPosition = Offset.zero;
  ResizeHandle? _activeResizeHandle;

  // State variables for scroll-aware resizing
  double _initialScrollOffset = 0;
  Offset? _lastGlobalPosition;

  Timer? _trashTimer;
  // Internal reactive state for trash
  final _isHoveringTrash = Beacon.writable(false);
  final _isTrashActive = Beacon.writable(false); // Is Trash ready for delete ?

  // The offset from the item's top-left corner to the cursor at the start of a drag.
  // This ensures the item doesn't "jump" to the cursor position when dragging starts.
  Offset? _dragGrabOffset;

  // State for auto-scroll
  Timer? _scrollTimer;
  double _scrollSpeed = 0;

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  // Helper to get metrics
  SlotMetrics _getMetrics(BoxConstraints constraints) {
    return SlotMetrics.fromConstraints(
      constraints,
      slotCount: widget.controller.slotCount.value,
      slotAspectRatio: widget.slotAspectRatio,
      mainAxisSpacing: widget.mainAxisSpacing,
      crossAxisSpacing: widget.crossAxisSpacing,
      padding: widget.padding ?? EdgeInsets.zero,
      scrollDirection: widget.scrollDirection,
    );
  }

  @override
  void initState() {
    super.initState();

    _isInternalScrollController = widget.scrollController == null;
    _scrollController = widget.scrollController ?? ScrollController();

    // Pass the initial resize behavior to the controller
    widget.controller.setResizeBehavior(widget.resizeBehavior);
    widget.controller.internal.setScrollDirection(widget.scrollDirection);
    widget.controller.setHandleColor(widget.gridStyle.handleColor);
    widget.controller.setResizeHandleSide(widget.resizeHandleSide);
    widget.controller.guidance = widget.guidance;
  }

  @override
  void dispose() {
    if (_isInternalScrollController) {
      _scrollController.dispose();
    }
    _scrollTimer?.cancel();
    _isHoveringTrash.dispose();
    _isTrashActive.dispose();
    _trashTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant Dashboard<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scrollController != oldWidget.scrollController) {
      if (_isInternalScrollController) {
        _scrollController.dispose();
      }
      _isInternalScrollController = widget.scrollController == null;
      _scrollController = widget.scrollController ?? ScrollController();
    }

    if (widget.resizeBehavior != oldWidget.resizeBehavior) {
      widget.controller.setResizeBehavior(widget.resizeBehavior);
    }
    if (widget.scrollDirection != oldWidget.scrollDirection) {
      widget.controller.internal.setScrollDirection(widget.scrollDirection);
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
    // Listen to layout changes to trigger rebuilds.
    widget.controller.layout.watch(context);
    final isEditing = widget.controller.isEditing.watch(context);

    return DashboardControllerProvider(
      controller: widget.controller,
      // Use a LayoutBuilder to get the constraints for the painter.
      child: LayoutBuilder(
        builder: (context, constraints) {
          // --- RESPONSIVE LOGIC ---
          if (widget.breakpoints != null) {
            final width = constraints.maxWidth;
            final targetSlots = _calculateSlots(width, widget.breakpoints!);

            // Only update if the slot count actually changes to avoid loops.
            if (targetSlots != widget.controller.slotCount.value) {
              // 1. Schedule the update for the next frame.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  widget.controller.setSlotCount(targetSlots);
                }
              });

              // 2. OPTIMIZATION: Return nothing for this frame.
              // Since the slotCount is incorrect, there is no need to build the heavy grid
              // which will be discarded immediately in the next frame.
              return const SizedBox.shrink();
            }
          }
          // ------------------------

          final metrics = _getMetrics(constraints);

          return DragTarget<T>(
            // Called once when entering the target
            onWillAcceptWithDetails: (DragTargetDetails<T> details) {
              _updatePlaceholderPosition(details.offset);
              return true;
            },
            // Called continuously while dragging over the target
            onMove: (DragTargetDetails<T> details) {
              // Update last known position for external drag
              _lastGlobalPosition = details.offset;

              _updatePlaceholderPosition(details.offset);
              _handleAutoScroll(details.offset); // Trigger auto-scroll
            },
            onLeave: (data) {
              _lastGlobalPosition = null;
              widget.controller.internal.hidePlaceholder();
              _stopScrollTimer(); // Stop auto-scroll when leaving
            },
            onAcceptWithDetails: (DragTargetDetails<T> details) async {
              _stopScrollTimer();
              _lastGlobalPosition = null;
              final placeholder = widget.controller.currentDragPlaceholder;

              if (placeholder != null) {
                // The controller knows about the placeholder internally.
                // We just need to provide the data and layoutItem from the drop.
                final newId = await widget.onDrop?.call(details.data, placeholder);
                if (newId != null) {
                  widget.controller.internal.onDropExternal(newId: newId);
                } else {
                  // If user doesn't provide an ID, just hide the placeholder
                  widget.controller.internal.hidePlaceholder();
                }
              } else {
                // rare : if no placeholder, cancel
                widget.controller.internal.hidePlaceholder();
              }
            },
            builder: (context, candidateData, rejectedData) {
              return Stack(
                key: _dashboardStackKey,
                children: [
                  // Conditionally build the grid background if in edit mode.
                  Builder(
                    builder: (context) {
                      final isEditing = widget.controller.isEditing.watch(context);
                      final currentActiveId = widget.controller.activeItemId.watch(context);

                      LayoutItem? itemToHighlight;
                      if (currentActiveId != null) {
                        // Find the full LayoutItem from the public layout list.
                        // Item is not in layout, ignore.
                        itemToHighlight = widget.controller.layout.value
                            .firstWhereOrNull((item) => item.id == currentActiveId);
                      }

                      if (isEditing) {
                        return _buildGridBackground(constraints, itemToHighlight);
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  GestureDetector(
                    // Desktop uses onPan for more direct mouse interaction
                    onPanStart:
                        _isMobile ? null : (details) => _onPointerDown(details.globalPosition),
                    onPanUpdate:
                        _isMobile ? null : (details) => _onPointerMove(details.globalPosition),
                    onPanEnd: _isMobile ? null : (details) => _onPointerUp(),
                    onPanCancel: _isMobile ? null : _onPointerUp,
                    // Whereas mobile uses onLongPress
                    onLongPressStart:
                        !_isMobile ? null : (details) => _onPointerDown(details.globalPosition),
                    onLongPressMoveUpdate:
                        !_isMobile ? null : (details) => _onPointerMove(details.globalPosition),
                    onLongPressEnd: !_isMobile ? null : (details) => _onPointerUp(),
                    //onLongPressUp: !_isMobile ? null : _onPointerUp,
                    child: ScrollConfiguration(
                      behavior: widget.scrollBehavior ??
                          ScrollConfiguration.of(context)
                              .copyWith(scrollbars: widget.showScrollbar),
                      child: FocusTraversalGroup(
                        policy: OrderedTraversalPolicy(),
                        child: CustomScrollView(
                          key: _scrollKey,
                          controller: _scrollController,
                          physics: widget.physics,
                          scrollDirection: widget.scrollDirection,
                          cacheExtent: widget.cacheExtent,
                          slivers: [
                            SliverPadding(
                              padding: widget.padding ?? EdgeInsets.zero,
                              sliver: SliverDashboard(
                                scrollDirection: widget.scrollDirection,
                                slotCount: widget.controller.slotCount.value,
                                slotAspectRatio: widget.slotAspectRatio,
                                mainAxisSpacing: widget.mainAxisSpacing,
                                crossAxisSpacing: widget.crossAxisSpacing,
                                items: widget.controller.layout.value,
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    // Watch active item ID to know when to show feedback
                                    final activeItemId =
                                        widget.controller.activeItemId.watch(context);
                                    final item = widget.controller.layout.value[index];
                                    final isBeingDragged = item.id == activeItemId;
                                    if (isBeingDragged && item.id != '__placeholder__') {
                                      return const SizedBox.shrink();
                                    }

                                    return KeyedSubtree(
                                      // Use ValueKey for better performance in Slivers
                                      key: ValueKey('${item.id}${widget.itemGlobalKeySuffix}'),
                                      // Use the Stateful wrapper that handles caching internally
                                      child: DashboardItem(
                                        item: item,
                                        isEditing: isEditing,
                                        itemStyle: widget.itemStyle,
                                        builder: widget.itemBuilder,
                                      ),
                                    );
                                  },
                                  childCount: widget.controller.layout.value.length,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      final activeItemId = widget.controller.activeItemId.watch(context);
                      if (activeItemId == null || activeItemId == '__placeholder__') {
                        return const SizedBox.shrink();
                      }

                      // If item not found, use initial layout as fallback
                      // or return empty box
                      final activeItem = widget.controller.layout.value
                              .firstWhereOrNull((i) => i.id == activeItemId) ??
                          _activeItemInitialLayout;

                      if (activeItem == null) return const SizedBox.shrink();

                      return DashboardFeedbackItem(
                        item: activeItem,
                        builder: widget.itemBuilder,
                        feedbackBuilder: widget.itemFeedbackBuilder,
                        controller: widget.controller,
                        scrollController: _scrollController,
                        slotWidth: metrics.slotWidth,
                        slotHeight: metrics.slotHeight,
                        mainAxisSpacing: widget.mainAxisSpacing,
                        crossAxisSpacing: widget.crossAxisSpacing,
                        scrollDirection: widget.scrollDirection,
                        itemGlobalKeySuffix: widget.itemGlobalKeySuffix,
                        isEditing: isEditing,
                      );
                    },
                  ),
                  // --- TRASH BIN INTEGRATION ---
                  if (widget.trashBuilder != null)
                    Builder(
                      builder: (context) {
                        // Only show trash when dragging an item (and not resizing)
                        final activeItemId = widget.controller.activeItemId.watch(context);
                        final isResizing = widget.controller.internal.isResizing.watch(context);
                        final showTrash = activeItemId != null && !isResizing;

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
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  int _calculateSlots(double width, Map<double, int> breakpoints) {
    // Sort keys to ensure we find the correct range
    final sortedBreakpoints = breakpoints.keys.toList()..sort();

    var slots = widget.controller.slotCount.value; // Fallback

    for (final breakpoint in sortedBreakpoints) {
      if (width >= breakpoint) {
        slots = breakpoints[breakpoint]!;
      } else {
        // Since it's sorted, if width < breakpoint, we are in the previous range
        break;
      }
    }
    return slots;
  }

  void _updatePlaceholderPosition(Offset globalPosition) {
    final scrollBox = _scrollKey.currentContext?.findRenderObject() as RenderBox?;
    if (scrollBox == null) return;

    final localPosition = scrollBox.globalToLocal(globalPosition);
    final gridCoords = _pixelToGrid(localPosition);

    widget.controller.internal.showPlaceholder(
      x: gridCoords.x,
      y: gridCoords.y,
      w: widget.placeholderWidth,
      h: widget.placeholderHeight,
    );
  }

  ({int x, int y}) _pixelToGrid(Offset localPosition) {
    final scrollContext = _scrollKey.currentContext;
    if (scrollContext == null || !scrollContext.mounted) return (x: 0, y: 0);

    final renderObject = scrollContext.findRenderObject();
    if (renderObject is! RenderBox) return (x: 0, y: 0);
    final scrollBox = renderObject;

    final metrics = _getMetrics(BoxConstraints.tight(scrollBox.size));
    final scrollOffset = _scrollController.offset;

    final gridPos = metrics.pixelToGrid(localPosition, scrollOffset);

    // Clamping on drag (placeholder)
    final int clampedX;
    final int clampedY;

    if (widget.scrollDirection == Axis.vertical) {
      clampedX = gridPos.x.clamp(0, metrics.slotCount - widget.placeholderWidth);
      clampedY = gridPos.y; // No limit for Y
    } else {
      clampedX = gridPos.x; // No limit for X
      clampedY = gridPos.y.clamp(0, metrics.slotCount - widget.placeholderHeight);
    }

    return (x: max(0, clampedX), y: max(0, clampedY));
  }

  ({double slotWidth, double slotHeight}) _calculateSlotSize() {
    final scrollContext = _scrollKey.currentContext;
    if (scrollContext == null || !scrollContext.mounted) {
      return (slotWidth: 0, slotHeight: 0);
    }

    final renderObject = scrollContext.findRenderObject();
    if (renderObject is! RenderBox) return (slotWidth: 0, slotHeight: 0);

    final metrics = _getMetrics(BoxConstraints.tight(renderObject.size));
    return (slotWidth: metrics.slotWidth, slotHeight: metrics.slotHeight);
  }

  void _onPointerDown(Offset position) {
    if (!widget.controller.isEditing.value) return;

    final scrollRenderBox = _scrollKey.currentContext?.findRenderObject() as RenderBox?;
    if (scrollRenderBox == null) return;

    // Capture initial scroll offset
    if (_scrollController.hasClients) {
      _initialScrollOffset = _scrollController.offset;
    }

    final localPosition = scrollRenderBox.globalToLocal(position);

    final result = BoxHitTestResult();
    LayoutItem? foundItem;
    RenderBox? itemRenderBox;

    // Use hitTest to find the specific RenderBox of the item under the cursor.
    if (scrollRenderBox.hitTest(result, position: localPosition)) {
      // Traverse from the END of the path to find the item's RenderBox
      for (var i = result.path.length - 1; i >= 0; i--) {
        final entry = result.path.elementAt(i);
        final target = entry.target;

        if (target is RenderBox) {
          final parentData = target.parentData;

          // We look for the parent data that our RenderSliverDashboard sets.
          if (parentData is SliverMultiBoxAdaptorParentData && parentData.index != null) {
            final index = parentData.index!;

            if (index < widget.controller.layout.value.length) {
              foundItem = widget.controller.layout.value[index];
              itemRenderBox = target;
              break;
            }
          }
        }
      }
    }

    if (foundItem != null && itemRenderBox != null) {
      if (foundItem.isStatic) return;

      widget.controller.onInteractionStart?.call(foundItem);

      // Get the item's paint offset from parent data
      final parentData = itemRenderBox.parentData;
      if (parentData is! SliverDashboardParentData) return;
      final itemPaintOffset = parentData.paintOffset;

      // Calculate the scroll offset
      final scrollOffset = _scrollController.offset;

      // Calculate item's position in scroll view coordinates
      final Offset itemPositionInScrollView;
      if (widget.scrollDirection == Axis.vertical) {
        itemPositionInScrollView = Offset(
          itemPaintOffset.dx,
          itemPaintOffset.dy - scrollOffset,
        );
      } else {
        itemPositionInScrollView = Offset(
          itemPaintOffset.dx - scrollOffset,
          itemPaintOffset.dy,
        );
      }

      // Calculate local position within the item
      final itemLocalPosition = localPosition - itemPositionInScrollView;

      // Store the grab offset to prevent visual jumping
      _dragGrabOffset = itemLocalPosition;

      // Now that we have the correct RenderBox, we can accurately convert the
      // global pointer position to the item's local coordinates to find the handle.
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

      // Trigger Callbacks
      if (handle != null) {
        widget.onItemResizeStart?.call(foundItem);
        widget.controller.internal.onResizeStart(foundItem.id);
      } else {
        widget.onItemDragStart?.call(foundItem);
        widget.controller.internal.onDragStart(foundItem.id);
      }
    }
  }

  void _handleAutoScroll(Offset globalPosition) {
    final scrollContext = _scrollKey.currentContext;
    if (scrollContext == null || !scrollContext.mounted) return;

    final renderObject = scrollContext.findRenderObject();
    if (renderObject is! RenderBox) return;
    final scrollBox = renderObject;
    final localPosition = scrollBox.globalToLocal(globalPosition);

    const hotZoneExtent = 50.0;
    const maxScrollSpeed = 15.0;

    final isVertical = widget.scrollDirection == Axis.vertical;
    if (isVertical) {
      if (localPosition.dy < hotZoneExtent) {
        // Top hot zone
        final proximity = (hotZoneExtent - localPosition.dy) / hotZoneExtent;
        _scrollSpeed = -maxScrollSpeed * proximity;
        _startScrollTimer();
      } else if (localPosition.dy > scrollBox.size.height - hotZoneExtent) {
        // Bottom hot zone
        final proximity =
            (localPosition.dy - (scrollBox.size.height - hotZoneExtent)) / hotZoneExtent;
        _scrollSpeed = maxScrollSpeed * proximity;
        _startScrollTimer();
      } else {
        // Not in a hot zone
        _stopScrollTimer();
      }
    } else {
      // Horizontal
      if (localPosition.dx < hotZoneExtent) {
        // Left hot zone
        final proximity = (hotZoneExtent - localPosition.dx) / hotZoneExtent;
        _scrollSpeed = -maxScrollSpeed * proximity;
        _startScrollTimer();
      } else if (localPosition.dx > scrollBox.size.width - hotZoneExtent) {
        // Right hot zone
        final proximity =
            (localPosition.dx - (scrollBox.size.width - hotZoneExtent)) / hotZoneExtent;
        _scrollSpeed = maxScrollSpeed * proximity;
        _startScrollTimer();
      } else {
        // Not in a hot zone
        _stopScrollTimer();
      }
    }
  }

  void _startScrollTimer() {
    // If timer is already active, do nothing.
    if (_scrollTimer?.isActive ?? false) return;

    _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!_scrollController.hasClients) return;

      final newOffset = _scrollController.offset + _scrollSpeed;
      _scrollController.jumpTo(
        newOffset.clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        ),
      );

      // Force update of drag/resize logic during auto-scroll
      if (_lastGlobalPosition != null) {
        _performUpdate(_lastGlobalPosition!);
      }
    });
  }

  void _stopScrollTimer() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _scrollSpeed = 0.0;
  }

  void _onPointerMove(Offset position) {
    if (_activeItemId == null || _activeItemInitialLayout == null) return;

    // Update last known position for the timer
    _lastGlobalPosition = position;

    _handleAutoScroll(position);
    _performUpdate(position);
  }

  void _performUpdate(Offset position) {
    final scrollContext = _scrollKey.currentContext;
    if (scrollContext == null || !scrollContext.mounted) return;

    final slotSizes = _calculateSlotSize();
    if (slotSizes.slotWidth <= 0 || slotSizes.slotHeight <= 0) return;

    // Case: External Drag (No active internal item)
    if (_activeItemId == null) {
      _updatePlaceholderPosition(position);
      return;
    }

    // Case: Internal Resize
    if (_activeResizeHandle != null) {
      // Calculate delta adjusted for scroll
      final currentScrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
      final scrollDelta = currentScrollOffset - _initialScrollOffset;

      // The delta passed to the controller must account for the fact that the
      // content has moved under the pointer.
      final effectiveScrollDelta =
          widget.scrollDirection == Axis.vertical ? Offset(0, scrollDelta) : Offset(scrollDelta, 0);

      final totalDragDelta = (position - _operationStartPosition) + effectiveScrollDelta;

      widget.controller.internal.onResizeUpdate(
        _activeItemId!,
        _activeResizeHandle!,
        totalDragDelta,
        slotWidth: slotSizes.slotWidth,
        slotHeight: slotSizes.slotHeight,
        crossAxisSpacing: widget.crossAxisSpacing,
        mainAxisSpacing: widget.mainAxisSpacing,
      );
    }
    // Case: Internal Drag
    else {
      // Convert global cursor position to a scroll-aware content position.
      final scrollRenderBox = scrollContext.findRenderObject();
      if (scrollRenderBox is! RenderBox) return;
      final localPosition = scrollRenderBox.globalToLocal(position);
      var contentPosition = widget.scrollDirection == Axis.vertical
          ? Offset(localPosition.dx, localPosition.dy + _scrollController.offset)
          : Offset(localPosition.dx + _scrollController.offset, localPosition.dy);

      // Adjust the content position by the initial grab offset.
      // This effectively passes the item's top-left position to the controller,
      // rather than the cursor position.
      if (_dragGrabOffset != null) {
        contentPosition -= _dragGrabOffset!;
      }

      // Let the controller handle all drag update logic.
      widget.controller.internal.onDragUpdate(
        _activeItemId!,
        contentPosition,
        slotWidth: slotSizes.slotWidth,
        slotHeight: slotSizes.slotHeight,
        crossAxisSpacing: widget.crossAxisSpacing,
        mainAxisSpacing: widget.mainAxisSpacing,
      );

      // --- TRASH DETECTION LOGIC ---
      if (widget.trashBuilder != null) {
        final trashRenderBox = _trashKey.currentContext?.findRenderObject() as RenderBox?;
        if (trashRenderBox != null) {
          final localTrashPos = trashRenderBox.globalToLocal(position);
          final result = BoxHitTestResult();
          final isHovering = trashRenderBox.hitTest(result, position: localTrashPos);

          if (isHovering) {
            if (!_isHoveringTrash.value) {
              // Enter trash area
              _isHoveringTrash.value = true;
              _isTrashActive.value = false;

              // Start timer to arm the trash
              _trashTimer?.cancel();
              _trashTimer = Timer(widget.trashHoverDelay, () {
                if (mounted && _isHoveringTrash.value) {
                  _isTrashActive.value = true;
                }
              });
            }
          } else {
            if (_isHoveringTrash.value) {
              // Leave trash area
              _trashTimer?.cancel();
              _isHoveringTrash.value = false;
              _isTrashActive.value = false;
            }
          }
        }
      }

      // Trigger drag update callback
      if (widget.onItemDragUpdate != null) {
        // Get current item (which may have changed in layout)
        final currentItem =
            widget.controller.layout.value.firstWhereOrNull((i) => i.id == _activeItemId) ??
                _activeItemInitialLayout!;
        widget.onItemDragUpdate!(currentItem, position);
      }
    }
  }

  Future<void> _onPointerUp() async {
    // Stop scrolling when drag ends
    _stopScrollTimer();

    // Stop trash timer when drag ends
    _trashTimer?.cancel();

    if (_activeItemId == null) return;

    // Trigger Callbacks
    // Retrieve the current item state to pass to the callback
    // Handle edge cases where item might have been removed (unlikely during drag)
    // Fallback if item is not current layout anymore
    final currentItem =
        widget.controller.layout.value.firstWhereOrNull((i) => i.id == _activeItemId) ??
            _activeItemInitialLayout;

    // Safety : if item is lost (this should not happen), stop.
    if (currentItem == null) {
      _resetOperationState();
      return;
    }

    if (_activeResizeHandle != null) {
      widget.controller.internal.onResizeEnd(_activeItemId!);
      widget.onItemResizeEnd?.call(currentItem);
    } else {
      // --- TRASH DROP LOGIC ---
      // Only delete if the trash is ARMED (timer elapsed)
      if (widget.trashBuilder != null && _isTrashActive.value) {
        var shouldDelete = true;
        if (widget.onWillDelete != null) {
          shouldDelete = await widget.onWillDelete!(currentItem);
        }

        if (shouldDelete) {
          // Automatic removal from controller
          widget.controller.removeItem(currentItem.id);
          // Notify user
          widget.onItemDeleted?.call(currentItem);
          // Ensure controller state is cleaned up even after deletion
          // We call onDragEnd with the deleted ID. The controller will handle the cleanup
          // of activeItem and originalLayout, even if the item is no longer in the layout list.
          widget.controller.internal.onDragEnd(currentItem.id);
        } else {
          // Cancel : end dragging which will release the item on the dashboard.
          widget.controller.internal.onDragEnd(currentItem.id);
        }
      } else {
        widget.controller.internal.onDragEnd(_activeItemId!);
      }
      widget.onItemDragEnd?.call(currentItem);
    }
    _resetOperationState();
  }

  void _resetOperationState() {
    if (!mounted) return;

    _activeItemId = null;
    _activeItemInitialLayout = null;
    _operationStartPosition = Offset.zero;
    _activeResizeHandle = null;
    _dragGrabOffset = null;
    _lastGlobalPosition = null; // Reset last position

    // Reset trash state
    _isHoveringTrash.value = false;
    _isTrashActive.value = false;
    _trashTimer?.cancel();

    // Also reset the visual offset
    widget.controller.internal.setDragOffset(Offset.zero);
  }

  Widget _buildGridBackground(BoxConstraints constraints, LayoutItem? activeItem) {
    return AnimatedBuilder(
      animation: _scrollController,
      builder: (context, child) {
        final metrics = _getMetrics(constraints);

        return CustomPaint(
          size: constraints.biggest,
          painter: GridBackgroundPainter(
            metrics: metrics,
            scrollOffset: _scrollController.hasClients ? _scrollController.offset : 0.0,
            activeItem: activeItem,
            lineColor: widget.gridStyle.lineColor,
            lineWidth: widget.gridStyle.lineWidth,
            fillColor: widget.gridStyle.fillColor,
          ),
        );
      },
    );
  }
}
