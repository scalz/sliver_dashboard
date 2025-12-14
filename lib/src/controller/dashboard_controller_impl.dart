// ignore_for_files: specify_nonobvious_property_types
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart' as engine;
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/models/utility.dart';
import 'package:sliver_dashboard/src/view/a11y/dashboard_shortcuts.dart';
import 'package:sliver_dashboard/src/view/guidance/dashboard_guidance.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';
import 'package:state_beacon/state_beacon.dart';

/// The concrete implementation of [DashboardController].
/// Manages the state and interactions of the dashboard.
///
/// This controller is the single source of truth for the dashboard's layout.
/// It uses `state_beacon` for reactive state management, ensuring that UI
/// updates are efficient and predictable.
@internal
class DashboardControllerImpl implements DashboardController {
  /// Creates a new [DashboardControllerImpl].
  DashboardControllerImpl({
    List<LayoutItem> initialLayout = const [],
    int initialSlotCount = 8,
    this.onInteractionStart,
    this.onLayoutChanged,
  }) {
    layout.value = initialLayout;
    slotCount.value = initialSlotCount;
  }

  @override
  final DashboardItemInteractionCallback? onInteractionStart;

  @override
  final DashboardLayoutChangeListener? onLayoutChanged;

  @override
  DashboardGuidance? guidance;

  @override
  DashboardShortcuts? shortcuts;

  // --- BEACONS (Public via Interface) ---

  @override
  final handleColor = Beacon.writable<Color?>(null);

  @override
  final layout = Beacon.writable<List<LayoutItem>>([]);

  @override
  final scrollDirection = Beacon.writable(Axis.vertical);

  @override
  final isEditing = Beacon.writable<bool>(false);

  @override
  final slotCount = Beacon.writable<int>(8);

  @override
  final preventCollision = Beacon.writable<bool>(true);

  @override
  final compactionType = Beacon.writable<engine.CompactType>(engine.CompactType.vertical);

  // Internal delegate reference
  engine.CompactorDelegate _compactor = const engine.VerticalCompactor();

  @override
  final resizeHandleSide = Beacon.writable<double>(20);

  @override
  final resizeBehavior = Beacon.writable<engine.ResizeBehavior>(
    engine.ResizeBehavior.push,
  );

  @override
  final selectedItemIds = Beacon.writable<Set<String>>({});

  // Internal state to track if we are actually moving items vs just selecting
  final _isDraggingState = Beacon.writable(false);

  @override
  ReadableBeacon<bool> get isDragging => _isDraggingState;

  // The item under the cursor that initiated the drag.
  // This is our reference point for calculating deltas.
  String? _pivotItemId;

  @override
  late final ReadableBeacon<String?> activeItemId = Beacon.derived(() {
    // If dragging, the pivot is the active item.
    // If not dragging, the first selected item is "active" (for focus/properties).
    if (_isDraggingState.value) return _pivotItemId;
    return selectedItemIds.value.firstOrNull;
  });

  // --- INTERNAL STATE (Hidden from Interface) ---

  /// Internal cache to store layouts for specific slot counts.
  /// Used to restore the layout when switching back to a previous breakpoint.
  final Map<int, List<LayoutItem>> _layoutsBySlotCount = {};

  /// Temporary placeholder item in the layout.
  @visibleForTesting
  final placeholder = Beacon.writable<LayoutItem?>(null);

  @override
  LayoutItem? get currentDragPlaceholder => placeholder.value;

  /// A reactive property that holds the pixel offset for the actively dragged item,
  /// enabling a smooth visual drag effect.
  final dragOffset = Beacon.writable<Offset>(Offset.zero);

  /// Indicates if the current interaction is a resize operation.
  final isResizing = Beacon.writable(false);

  /// Internal state to track the item being dragged or resized.
  @visibleForTesting
  final activeItem = Beacon.writable<LayoutItem?>(null);

  /// Internal state to store the layout at the beginning of an operation.
  @visibleForTesting
  final originalLayoutOnStart = Beacon.writable<List<LayoutItem>>([]);

  // --- PUBLIC METHODS IMPLEMENTATION ---

  @override
  void setResizeHandleSide(double side) {
    resizeHandleSide.value = side;
  }

  @override
  void setHandleColor(Color? color) {
    handleColor.value = color;
  }

  @override
  void setResizeBehavior(engine.ResizeBehavior behavior) {
    resizeBehavior.value = behavior;
  }

  @override
  void toggleEditing() {
    isEditing.value = !isEditing.value;
  }

  @override
  void setEditMode(bool editing) {
    isEditing.value = editing;
  }

  @override
  void setSlotCount(int newSlotCount) {
    if (slotCount.value == newSlotCount) return;

    final previousSlotCount = slotCount.value;
    final currentLayout = layout.value;

    // 1. Save the current layout state for the current slot count
    _layoutsBySlotCount[previousSlotCount] = List.from(currentLayout);

    List<LayoutItem> nextLayout;

    // 2. Check if we have a cached layout for the target slot count
    if (_layoutsBySlotCount.containsKey(newSlotCount)) {
      // 3a. Reconcile: Merge the cached layout with current changes (adds/removes)
      nextLayout = _reconcileLayouts(
        cachedLayout: _layoutsBySlotCount[newSlotCount]!,
        currentLayout: currentLayout,
        newSlotCount: newSlotCount,
      );
    } else {
      // 3b. Standard behavior: Calculate new layout from scratch
      final corrected = engine.correctBounds(currentLayout, newSlotCount);
      nextLayout = _compactor.compact(
        corrected,
        newSlotCount,
      );
    }

    slotCount.value = newSlotCount;
    layout.value = nextLayout;
  }

  /// Merges the [cachedLayout] (target state) with the [currentLayout] (source of truth for existence).
  ///
  /// - Items present in both are taken from [cachedLayout] (restoring position).
  /// - Items in [cachedLayout] but NOT in [currentLayout] are removed (sync deletion).
  /// - Items in [currentLayout] but NOT in [cachedLayout] are added (sync addition).
  List<LayoutItem> _reconcileLayouts({
    required List<LayoutItem> cachedLayout,
    required List<LayoutItem> currentLayout,
    required int newSlotCount,
  }) {
    final currentIds = currentLayout.map((e) => e.id).toSet();
    final cachedIds = cachedLayout.map((e) => e.id).toSet();

    // 1. Keep items that exist in both (Restoring their cached position)
    final result = cachedLayout.where((item) => currentIds.contains(item.id)).toList();

    // 2. Identify new items (Added while in the other breakpoint)
    final newItems = currentLayout.where((item) => !cachedIds.contains(item.id)).toList();

    // 3. Place new items
    // We append them to the bottom to avoid overlapping existing cached items.
    // The engine's placeNewItems logic is perfect for this.
    if (newItems.isNotEmpty) {
      // We reset their coordinates to -1 to force auto-placement at the bottom
      final itemsToPlace = newItems.map((e) => e.copyWith(x: -1, y: -1)).toList();

      final merged = engine.placeNewItems(
        existingLayout: result,
        newItems: itemsToPlace,
        cols: newSlotCount,
      );

      // Replace result with merged list
      result
        ..clear()
        ..addAll(merged);
    }

    // 4. Final compaction to ensure everything is tidy
    return _compactor.compact(
      result,
      newSlotCount,
    );
  }

  @override
  void setPreventCollision(bool prevent) {
    preventCollision.value = prevent;
  }

  @override
  void setCompactionType(engine.CompactType type) {
    compactionType.value = type;
    switch (type) {
      case engine.CompactType.vertical:
        _compactor = const engine.VerticalCompactor();
      case engine.CompactType.horizontal:
        _compactor = const engine.HorizontalCompactor();
      case engine.CompactType.none:
        _compactor = const engine.NoCompactor();
    }
    // Re-compact with new strategy
    layout.value = _compactor.compact(layout.value, slotCount.value);
    onLayoutChanged?.call(layout.value, slotCount.value);
  }

  @override
  void setCompactor(engine.CompactorDelegate compactor) {
    _compactor = compactor;
    // Note: We do not update the `compactionType` beacon here because custom
    // strategies might not map to the enum values.

    // Trigger an immediate re-layout using the new strategy.
    layout.value = _compactor.compact(layout.value, slotCount.value);
    onLayoutChanged?.call(layout.value, slotCount.value);
  }

  @override
  void addItems(
    List<LayoutItem> items, {
    engine.CompactType? overrideCompactType,
  }) {
    final currentLayout = List<LayoutItem>.from(layout.value);

    // We calculate the starting Y for auto-placed items to be at the bottom
    var autoPlacementY = engine.bottom(currentLayout);
    var autoPlacementX = 0;

    for (final item in items) {
      if (item.x == -1 || item.y == -1) {
        // Auto-placement logic: try to fit in the current "bottom" row
        if (autoPlacementX + item.w > slotCount.value) {
          autoPlacementX = 0;
          autoPlacementY++; // Move to next row (height 1 unit for safety)
        }

        currentLayout.add(
          item.copyWith(
            x: autoPlacementX,
            y: autoPlacementY,
          ),
        );

        // Advance cursor
        autoPlacementX += item.w;
      } else {
        // Fixed position
        currentLayout.add(item);
      }
    }

    // Use delegate (or temporary override)
    final strategy =
        overrideCompactType != null ? _getTempDelegate(overrideCompactType) : _compactor;

    // Run compaction.
    // This will pull the auto-placed items (which are at the bottom)
    // up into any available empty spaces above them.
    final newLayout = strategy.compact(
      currentLayout,
      slotCount.value,
    );

    layout.value = newLayout;
    onLayoutChanged?.call(layout.value, slotCount.value);
  }

  @override
  void addItem(LayoutItem newItem, {engine.CompactType? overrideCompactType}) {
    if (newItem.x == -1 || newItem.y == -1) {
      addItems([newItem], overrideCompactType: overrideCompactType);
      return;
    }
    final currentLayout = layout.value;

    final strategy =
        overrideCompactType != null ? _getTempDelegate(overrideCompactType) : _compactor;

    final newLayout = strategy.compact(
      [...currentLayout, newItem],
      slotCount.value,
    );
    layout.value = newLayout;

    onLayoutChanged?.call(layout.value, slotCount.value);
  }

  @override
  void removeItem(String itemId, {engine.CompactType? overrideCompactType}) {
    removeItems([itemId]);
  }

  @override
  void removeItems(List<String> itemIds) {
    final idsToRemove = itemIds.toSet();
    final currentLayout = layout.value;

    final newLayout = _compactor.compact(
      currentLayout.where((item) => !idsToRemove.contains(item.id)).toList(),
      slotCount.value,
    );

    layout.value = newLayout;
    onLayoutChanged?.call(layout.value, slotCount.value);

    clearSelection();
  }

  @override
  void toggleSelection(String itemId, {bool multi = false}) {
    final currentSet = selectedItemIds.value.toSet();
    if (multi) {
      if (currentSet.contains(itemId)) {
        currentSet.remove(itemId);
      } else {
        currentSet.add(itemId);
      }
    } else {
      currentSet
        ..clear()
        ..add(itemId);
    }
    selectedItemIds.value = currentSet;
  }

  @override
  void clearSelection() {
    selectedItemIds.value = {};
  }

  @override
  List<Map<String, dynamic>> exportLayout() {
    return layout.value.map((item) => item.toMap()).toList();
  }

  @override
  void importLayout(List<dynamic> jsonLayout) {
    final newLayout = jsonLayout.map((e) {
      if (e is Map<String, dynamic>) {
        return LayoutItem.fromMap(e);
      }
      if (e is Map) {
        return LayoutItem.fromMap(Map<String, dynamic>.from(e));
      }
      throw const FormatException('Invalid layout format: element is not a Map');
    }).toList();

    // Validate bounds and compact to ensure integrity
    final corrected = engine.correctBounds(newLayout, slotCount.value);

    // Apply compaction if configured, otherwise just resolve overlaps
    layout.value = _compactor.compact(
      corrected,
      slotCount.value,
      allowOverlap: false, // Ensure imported layout is clean
    );

    onLayoutChanged?.call(layout.value, slotCount.value);
  }

  @override
  void dispose() {
    layout.dispose();
    isEditing.dispose();
    slotCount.dispose();
    preventCollision.dispose();
    compactionType.dispose();
    activeItem.dispose();
    placeholder.dispose();
    resizeBehavior.dispose();
    dragOffset.dispose();
    originalLayoutOnStart.dispose();
    handleColor.dispose();
    scrollDirection.dispose();
    isResizing.dispose();
    resizeHandleSide.dispose();
    activeItemId.dispose();
  }

  // --- INTERNAL METHODS (Not in Interface) ---

  /// Sets the pixel offset for the actively dragged item.
  ///
  /// This is used internally by the `Dashboard` widget to create a smooth
  /// drag-and-drop effect.
  void setDragOffset(Offset offset) {
    dragOffset.value = offset;
  }

  /// Sets the scroll direction of the dashboard.
  ///
  /// This is used internally by the `Dashboard` widget and should not be
  /// called directly.
  void setScrollDirection(Axis direction) {
    if (scrollDirection.value == direction) return;
    scrollDirection.value = direction;
  }

  /// Adds or moves a temporary placeholder item in the layout.
  ///
  /// This is used during a drag-over operation from an external source.
  /// It avoids running a full compaction for better performance.
  void showPlaceholder({
    required int x,
    required int y,
    required int w,
    required int h,
  }) {
    final current = placeholder.value;
    if (current != null && current.x == x && current.y == y && current.w == w && current.h == h) {
      return;
    }

    if (placeholder.value == null) {
      originalLayoutOnStart.value = List.from(layout.peek());
    }

    final placeholderItem = LayoutItem(
      id: '__placeholder__',
      x: x,
      y: y,
      w: w,
      h: h,
      isStatic: false,
      isDraggable: true,
    );

    placeholder.value = placeholderItem;

    // Always operate on the clean layout from the start of the gesture.
    final baseLayout = List<LayoutItem>.from(originalLayoutOnStart.peek())

      // Clean just in case
      ..removeWhere((element) => element.id == '__placeholder__')

      // Create a layout that includes the placeholder for the engine to move.
      ..add(placeholderItem);

    final newLayout = engine.moveElement(
      baseLayout,
      placeholderItem,
      x,
      y,
      cols: slotCount.value,
      compactType: compactionType.value,

      // 1. Allow collisions so engine can push
      preventCollision: false,

      // 2. Notify user action to enable "Push" logic
      isUserAction: true,

      // 3. CRUCIAL : Force calculation even if item is already at x,y in baseLayout
      // Without it, engine returns immediately.
      force: true,
    );

    // If compaction is enabled, run it to fill gaps.
    // Otherwise, keep the result from `moveElement` (which only resolves collisions).
    final compactedLayout = compactionType.value != engine.CompactType.none
        ? _compactor.compact(newLayout, slotCount.value)
        : newLayout;

    layout.value = compactedLayout;
  }

  /// Removes the temporary placeholder item from the layout.
  void hidePlaceholder() {
    if (placeholder.value == null) return;
    // Revert to the clean layout from before the drag-over started.
    layout.value = List.from(originalLayoutOnStart.peek());
    placeholder.value = null;
    originalLayoutOnStart.value = []; // Clean up state
  }

  /// Finalizes a drop from an external source.
  void onDropExternal({
    required String newId,
  }) {
    final currentPlaceholder = placeholder.value;
    if (currentPlaceholder == null) return;

    // Search where placeholder is in current layout (which has already been "pushed")
    final finalPlaceholderPos =
        layout.value.firstWhereOrNull((e) => e.id == '__placeholder__') ?? currentPlaceholder;

    final newItem = finalPlaceholderPos.copyWith(
      id: newId,
      isStatic: false,
      moved: false,
    );

    //  Replace the placeholder with the actual item.
    final finalLayout = layout.value.map((item) {
      if (item.id == '__placeholder__') return newItem;
      return item;
    }).toList();

    // Run a final pass to ensure the layout is valid and stable after the drop.
    // This ensures no overlaps remain and respects the current compaction strategy.
    layout.value = _compactor.compact(
      finalLayout,
      slotCount.value,
      allowOverlap: false,
    );

    // Clean up all temporary state.
    placeholder.value = null;
    originalLayoutOnStart.value = [];

    onLayoutChanged?.call(layout.value, slotCount.value);
  }

  /// Call when a drag gesture starts on a dashboard item.
  void onDragStart(String itemId) {
    final item = layout.value.firstWhere((i) => i.id == itemId);
    if (item.isStatic) return;

    // Selection Logic at start of drag:
    // 1. If item is NOT in selection, it becomes the selection (clearing others).
    // 2. If item IS in selection, we keep the group to drag them all.
    final currentSelection = selectedItemIds.value;
    if (!currentSelection.contains(itemId)) {
      selectedItemIds.value = {itemId};
    }

    _isDraggingState.value = true;
    _pivotItemId = itemId;
    isResizing.value = false;

    // Snapshot layout for anti-drift
    originalLayoutOnStart.value = layout.value;
  }

  /// Call continuously while a drag gesture is updated.
  void onDragUpdate(
    String itemId,
    Offset contentPosition, {
    required double slotWidth,
    required double slotHeight,
    required double mainAxisSpacing,
    required double crossAxisSpacing,
  }) {
    // Safety check: ensure we are dragging the pivot
    if (_pivotItemId != itemId) return;

    final pivotItem = originalLayoutOnStart.value.firstWhere((i) => i.id == itemId);

    // 1. Calculate Pivot's new Grid Position
    final newGridX = (contentPosition.dx / (slotWidth + crossAxisSpacing)).round();
    final newGridY = (contentPosition.dy / (slotHeight + mainAxisSpacing)).round();

    // 2. Calculate Delta (Grid Units) from original position
    // Note: We don't clamp the pivot yet, we'll let moveCluster handle bounds via the BBox
    final dx = newGridX - pivotItem.x;
    final dy = newGridY - pivotItem.y;

    // 3. Calculate Target Bounding Box Position
    // We need the original BBox of the cluster
    final clusterIds = selectedItemIds.value;
    final clusterItems =
        originalLayoutOnStart.value.where((i) => clusterIds.contains(i.id)).toList();

    final originalBBox = engine.calculateBoundingBox(clusterItems);

    // Target BBox Position = Original BBox + Delta
    var targetBBoxX = originalBBox.x + dx;
    var targetBBoxY = originalBBox.y + dy;

    // 4. Clamping (Optional but recommended for visual sanity)
    // We clamp the BBox so it doesn't go out of grid bounds
    if (scrollDirection.value == Axis.vertical) {
      targetBBoxX = targetBBoxX.clamp(0, slotCount.value - originalBBox.w);
      targetBBoxY = max(0, targetBBoxY);
    } else {
      targetBBoxX = max(0, targetBBoxX);
      targetBBoxY = targetBBoxY.clamp(0, slotCount.value - originalBBox.h);
    }

    // 5. Move Cluster
    final newLayout = engine.moveCluster(
      originalLayoutOnStart.value,
      clusterIds,
      targetBBoxX,
      targetBBoxY,
      cols: slotCount.value,
      compactType: compactionType.value,
      preventCollision: preventCollision.value,
    );

    layout.value = newLayout;

    // 6. Visual Offset (Smooth Drag)
    // We calculate offset based on the Pivot Item's logical position in the NEW layout
    // to account for collision resolutions (pushes) performed by the engine.

    final movedPivot = newLayout.firstWhere((i) => i.id == itemId);

    final logicalItemPixelX = movedPivot.x * (slotWidth + crossAxisSpacing);
    final logicalItemPixelY = movedPivot.y * (slotHeight + mainAxisSpacing);

    final visualOffsetX = contentPosition.dx - logicalItemPixelX;
    final visualOffsetY = contentPosition.dy - logicalItemPixelY;

    dragOffset.value = Offset(visualOffsetX, visualOffsetY);
  }

  /// Call when a drag gesture ends.
  void onDragEnd(String itemId) {
    if (!_isDraggingState.value) return;

    List<LayoutItem> finalLayout;

    // Apply Compaction on Drop
    // Use delegate to resolve collisions or compact
    if (compactionType.value == engine.CompactType.none) {
      finalLayout = _compactor.resolveCollisions(layout.value, slotCount.value);
    } else {
      finalLayout = _compactor.compact(layout.value, slotCount.value);
    }

    layout.value = finalLayout;
    onLayoutChanged?.call(layout.value, slotCount.value);

    _isDraggingState.value = false;
    _pivotItemId = null;
    originalLayoutOnStart.value = [];
    dragOffset.value = Offset.zero;
  }

  /// Call when a resize gesture starts on a dashboard item.
  void onResizeStart(String itemId) {
    // Restriction: Multi-resize not supported yet.
    // If multiple items selected, we clear selection and select only this one.
    selectedItemIds.value = {itemId};

    final item = layout.value.firstWhere((i) => i.id == itemId);
    if (item.isStatic || item.isResizable == false) return;

    isResizing.value = true;
    _pivotItemId = itemId;
    _isDraggingState.value = false;
    originalLayoutOnStart.value = layout.value;
  }

  /// Call continuously while a resize gesture is updated.
  void onResizeUpdate(
    String itemId,
    ResizeHandle handle,
    Offset delta, {
    required double slotWidth,
    required double slotHeight,
    required double crossAxisSpacing,
    required double mainAxisSpacing,
  }) {
    // Use originalLayoutOnStart to get the item state before resize began
    final originalItem = originalLayoutOnStart.value.firstWhere((i) => i.id == itemId);

    final dW = delta.dx / (slotWidth + crossAxisSpacing);
    final dH = delta.dy / (slotHeight + mainAxisSpacing);

    var newX = originalItem.x;
    var newY = originalItem.y;
    var newW = originalItem.w;
    var newH = originalItem.h;

    switch (handle) {
      case ResizeHandle.bottomRight:
        newW = (originalItem.w + dW).round();
        newH = (originalItem.h + dH).round();
      case ResizeHandle.bottomLeft:
        newW = (originalItem.w - dW).round();
        newH = (originalItem.h + dH).round();
        newX = (originalItem.x + dW).round();
      case ResizeHandle.topRight:
        newW = (originalItem.w + dW).round();
        newH = (originalItem.h - dH).round();
        newY = (originalItem.y + dH).round();
      case ResizeHandle.topLeft:
        newW = (originalItem.w - dW).round();
        newH = (originalItem.h - dH).round();
        newX = (originalItem.x + dW).round();
        newY = (originalItem.y + dH).round();
      case ResizeHandle.top:
        newH = (originalItem.h - dH).round();
        newY = (originalItem.y + dH).round();
      case ResizeHandle.bottom:
        newH = (originalItem.h + dH).round();
      case ResizeHandle.left:
        newW = (originalItem.w - dW).round();
        newX = (originalItem.x + dW).round();
      case ResizeHandle.right:
        newW = (originalItem.w + dW).round();
    }

    final maxW = originalItem.maxW.isFinite ? originalItem.maxW.toInt() : 10000;
    final maxH = originalItem.maxH.isFinite ? originalItem.maxH.toInt() : 10000;
    newW = newW.clamp(originalItem.minW, maxW);
    newH = newH.clamp(originalItem.minH, maxH);

    if (scrollDirection.value == Axis.vertical) {
      if (newX < 0) {
        newW += newX;
        newX = 0;
      }
      if (newX + newW > slotCount.value) {
        newW = slotCount.value - newX;
      }
    } else {
      if (newY < 0) {
        newH += newY;
        newY = 0;
      }
      if (newY + newH > slotCount.value) {
        newH = slotCount.value - newY;
      }
    }

    final resizedItem = originalItem.copyWith(w: newW, h: newH, x: newX, y: newY);

    final newLayout = engine.resizeItem(
      originalLayoutOnStart.value,
      resizedItem,
      behavior: resizeBehavior.value,
      cols: slotCount.value,
      preventCollision: preventCollision.value,
    );

    layout.value = newLayout;
  }

  /// Call when a resize gesture ends.
  void onResizeEnd(String itemId) {
    if (!isResizing.value) return;

    final finalLayout = _compactor.resolveCollisions(
      layout.value,
      slotCount.value,
    );

    layout.value = finalLayout;

    onLayoutChanged?.call(layout.value, slotCount.value);

    isResizing.value = false;
    _pivotItemId = null;
    activeItem.value = null;
    originalLayoutOnStart.value = [];
    dragOffset.value = Offset.zero;
  }

  @override
  void moveActiveItemBy(int dx, int dy) {
    final clusterIds = selectedItemIds.value;
    if (clusterIds.isEmpty) return;

    // For keyboard moves, we work incrementally from the CURRENT layout.
    // This allows step-by-step movement.
    final currentLayout = layout.value;
    final clusterItems = currentLayout.where((i) => clusterIds.contains(i.id)).toList();

    // Calculate current BBox
    final bbox = engine.calculateBoundingBox(clusterItems);

    // Calculate target BBox position
    var targetX = bbox.x + dx;
    var targetY = bbox.y + dy;

    // Clamp BBox to grid
    if (scrollDirection.value == Axis.vertical) {
      targetX = targetX.clamp(0, slotCount.value - bbox.w);
      targetY = max(0, targetY);
    } else {
      targetX = max(0, targetX);
      targetY = targetY.clamp(0, slotCount.value - bbox.h);
    }

    // Check if movement is valid (e.g. not moving onto a static item)
    // We create a virtual item representing the target BBox
    final targetBBoxItem = bbox.copyWith(x: targetX, y: targetY);
    final statics = engine.getStatics(currentLayout);

    // If the BBox collides with a static item, we block the move.
    // Note: This is a simplified check. Ideally we should check individual items,
    // but checking the BBox is safer and faster for A11y.
    if (engine.getFirstCollision(statics, targetBBoxItem) != null) {
      return;
    }

    // Move the cluster using the engine
    final newLayout = engine.moveCluster(
      currentLayout,
      clusterIds,
      targetX,
      targetY,
      cols: slotCount.value,
      compactType: compactionType.value,
      preventCollision: preventCollision.value,
    );

    layout.value = newLayout;
    dragOffset.value = Offset.zero;
  }

  @override
  void cancelInteraction() {
    if (originalLayoutOnStart.value.isNotEmpty) {
      layout.value = List.from(originalLayoutOnStart.value);
    }

    _isDraggingState.value = false;
    isResizing.value = false;
    _pivotItemId = null;
    originalLayoutOnStart.value = [];
    dragOffset.value = Offset.zero;
  }

  @override
  void optimizeLayout() {
    final currentLayout = layout.value;
    final cols = slotCount.value;

    // Call the pure engine function
    final optimized = engine.optimizeLayout(currentLayout, cols);

    layout.value = optimized;
    onLayoutChanged?.call(layout.value, slotCount.value);
  }

  // Helper to get temporary delegate for overrides
  engine.CompactorDelegate _getTempDelegate(engine.CompactType type) {
    switch (type) {
      case engine.CompactType.vertical:
        return const engine.VerticalCompactor();
      case engine.CompactType.horizontal:
        return const engine.HorizontalCompactor();
      case engine.CompactType.none:
        return const engine.NoCompactor();
    }
  }
}
