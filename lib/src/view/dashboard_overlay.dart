import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:sliver_dashboard/src/view/dashboard_typedefs.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';
import 'package:sliver_dashboard/src/view/sliver_dashboard.dart';
import 'package:state_beacon/state_beacon.dart';

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
    required this.itemBuilder,
    super.key,
    this.gridStyle,
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
  });

  /// The controller that manages the state of the dashboard.
  final DashboardController controller;

  /// The scroll controller of the child scroll view.
  /// Required for auto-scrolling and feedback positioning.
  final ScrollController scrollController;

  /// The child widget, typically a [CustomScrollView].
  final Widget child;

  /// A builder that creates the widgets for each dashboard item.
  /// Used for rendering the feedback item during drag.
  final DashboardItemBuilder itemBuilder;

  /// Styling options for the background grid in edit mode.
  /// If null, no grid is painted unless [backgroundBuilder] is provided.
  final GridStyle? gridStyle;

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

  @override
  State<DashboardOverlay<T>> createState() => _DashboardOverlayState<T>();
}

class _DashboardOverlayState<T extends Object> extends State<DashboardOverlay<T>> {
  final GlobalKey _overlayStackKey = GlobalKey();

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

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _leaveTimer?.cancel();
    _isHoveringTrash.dispose();
    _isTrashActive.dispose();
    _trashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DashboardControllerProvider(
      controller: widget.controller,
      child: DragTarget<T>(
        onWillAcceptWithDetails: (DragTargetDetails<T> details) {
          _updatePlaceholderPosition(details.offset);
          return true;
        },
        onMove: (DragTargetDetails<T> details) {
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
        onAcceptWithDetails: (DragTargetDetails<T> details) async {
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
                    if (!_isMobile) _onPointerDown(event.position);
                  },
                  // On Mobile, we leave 'Move' to the GestureDetector/ScrollView to avoid conflicts.
                  onPointerMove: _isMobile ? null : (event) => _onPointerMove(event.position),
                  onPointerUp: (event) {
                    if (_isMobile) {
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
                    if (!_isMobile) {
                      // Desktop only
                      // On Mobile, onLongPressEnd is in charge, else it's called twice (Listener + GestureDetector).
                      _onPointerUp().ignore();
                    }
                    _pointerDownPosition = null; // Cleanup
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onLongPressStart: _isMobile
                        ? (details) {
                            // Sur mobile, le LongPress déclenche tout :
                            // 1. Identification (HitTest + Sélection)
                            _onPointerDown(details.globalPosition);
                          }
                        : null,
                    onLongPressMoveUpdate:
                        _isMobile ? (details) => _onPointerMove(details.globalPosition) : null,
                    onLongPressEnd: _isMobile ? (details) => _onPointerUp() : null,
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
              builder: widget.itemBuilder,
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
      for (final entry in result.path) {
        final target = entry.target;
        if (target is RenderBox) {
          final parentData = target.parentData;
          if (parentData is SliverDashboardParentData && parentData.index != null) {
            final parent = target.parent;
            if (parent is RenderSliverDashboard) {
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
    return found;
  }

  void _onPointerDown(Offset position) {
    if (!widget.controller.isEditing.value) return;

    final hit = _hitTest(position);
    final foundItem = hit.item;
    final itemRenderBox = hit.itemRenderBox;
    final renderSliver = hit.renderSliver;

    if (foundItem != null && itemRenderBox != null && renderSliver != null) {
      if (foundItem.isStatic) return;

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

    // If it starts tp move, this is not a "clic", so we won't unselect group at the end.
    if ((position - _operationStartPosition).distance > 2.0) {
      // Tolerance threshold
      _shouldClearSelectionOnUp = false;
    }

    _lastGlobalPosition = position;
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

  void _checkTrash(Offset position) {
    if (widget.trashBuilder == null) return;
    final trashRenderBox = _trashKey.currentContext?.findRenderObject() as RenderBox?;
    if (trashRenderBox != null) {
      final localTrashPos = trashRenderBox.globalToLocal(position);
      final result = BoxHitTestResult();
      final isHovering = trashRenderBox.hitTest(result, position: localTrashPos);

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
    _stopScrollTimer();
    _trashTimer?.cancel();

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
      _resetOperationState();
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
    _resetOperationState();
  }

  void _resetOperationState() {
    if (!mounted) return;
    _activeItemId = null;
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
    widget.controller.internal.setDragOffset(Offset.zero);
  }

  // Auto Scroll

  void _handleAutoScroll(Offset globalPosition) {
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
        } else {
          _updatePlaceholderPosition(_lastGlobalPosition!);
        }
      }
    });
  }

  void _stopScrollTimer() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _scrollSpeed = 0.0;
  }

  void _updatePlaceholderPosition(Offset globalPosition) {
    final renderSliver = _findRenderSliver();
    if (renderSliver == null) return;

    final metrics = _getMetricsFromSliver(renderSliver);
    _activeSliverMetrics = metrics;

    // Reason: We use the Overlay's RenderBox as the global coordinate reference.
    // This is safer than using the child's render box, as the Overlay is guaranteed
    // to cover the entire interactive area.
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;
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

    final x = (dx /
            (metrics.slotWidth +
                (metrics.scrollDirection == Axis.vertical
                    ? metrics.crossAxisSpacing
                    : metrics.mainAxisSpacing)))
        .floor();
    final y = (dy /
            (metrics.slotHeight +
                (metrics.scrollDirection == Axis.vertical
                    ? metrics.mainAxisSpacing
                    : metrics.crossAxisSpacing)))
        .floor();

    final clampedX = max(
      0,
      metrics.scrollDirection == Axis.vertical
          ? x.clamp(0, metrics.slotCount - widget.placeholderWidth)
          : x,
    );
    final clampedY = max(
      0,
      metrics.scrollDirection == Axis.vertical
          ? y
          : y.clamp(0, metrics.slotCount - widget.placeholderHeight),
    );

    widget.controller.internal.showPlaceholder(
      x: clampedX,
      y: clampedY,
      w: widget.placeholderWidth,
      h: widget.placeholderHeight,
    );

    _lastValidPlaceholder = widget.controller.currentDragPlaceholder;
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
