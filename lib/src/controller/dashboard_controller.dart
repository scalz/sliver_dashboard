// ignore_for_files: specify_nonobvious_property_types
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart' as engine;
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/guidance/dashboard_guidance.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';
import 'package:state_beacon/state_beacon.dart';

/// A callback that is fired when a user starts a drag or resize interaction
/// on a dashboard item.
///
/// The [LayoutItem] that is being interacted with is passed as an argument.
typedef DashboardItemInteractionCallback = void Function(LayoutItem item);

/// A callback that is fired when the layout of the dashboard changes.
///
/// The new layout, represented as a list of [LayoutItem]s, is passed as an argument.
typedef DashboardLayoutChangeListener = void Function(List<LayoutItem> items);
/*
typedef DashboardItemAddedListener = void Function(LayoutItem item, List<LayoutItem> fullLayout);
typedef DashboardItemRemovedListener = void Function(String item, List<LayoutItem> fullLayout);
typedef DashboardItemMovedListener = void Function(LayoutItem item, List<LayoutItem> fullLayout);
typedef DashboardItemResizedListener = void Function(LayoutItem item, List<LayoutItem> fullLayout);
 */

/// Manages the state and interactions of the dashboard.
///
/// This controller is the single source of truth for the dashboard's layout.
/// It uses `state_beacon` for reactive state management, ensuring that UI
/// updates are efficient and predictable.
class DashboardController {
  /// Creates a new [DashboardController].
  ///
  /// - [initialLayout]: The starting layout for the dashboard.
  /// - [initialSlotCount]: The number of columns in the grid.
  DashboardController({
    List<LayoutItem> initialLayout = const [],
    int initialSlotCount = 8,
    this.onInteractionStart,
    this.onLayoutChanged,
  }) {
    layout.value = initialLayout;
    slotCount.value = initialSlotCount;
  }

  /// An optional callback that is fired when a user starts a drag or resize
  /// gesture on an item.
  ///
  /// This can be used to trigger haptic feedback, logging, or other custom
  /// actions. The specific [LayoutItem] being interacted with is provided.
  final DashboardItemInteractionCallback? onInteractionStart;

  /// The set of messages to display for user guidance. Can be null if disabled.
  DashboardGuidance? guidance;

  // --- PUBLIC API ---
  /// Default Handles color style
  final handleColor = Beacon.writable<Color?>(null);

  /// The reactive state of the dashboard layout.
  ///
  /// Widgets can listen to this beacon to rebuild whenever the layout changes.
  final layout = Beacon.writable<List<LayoutItem>>([]);

  /// A callback that is fired whenever the layout changes.
  final DashboardLayoutChangeListener? onLayoutChanged;

  /// The scroll direction of the dashboard.
  final scrollDirection = Beacon.writable(Axis.vertical);

  /// The reactive state for the dashboard's edit mode.
  final isEditing = Beacon.writable<bool>(false);

  /// The number of columns in the dashboard grid.
  ///
  /// Changing this value will trigger a relayout.
  final slotCount = Beacon.writable<int>(8);

  /// A reactive property to control collision behavior.
  /// If `true` (default), items will push each other on drag/resize.
  /// If `false`, items will be allowed to overlap.
  final preventCollision = Beacon.writable<bool>(true);

  /// This controls "push" direction.
  /// If null, no compaction for precise placement.
  final compactionType = Beacon.writable<engine.CompactType>(engine.CompactType.vertical);

  /// Temporary placeholder item in the layout.
  @visibleForTesting
  final placeholder = Beacon.writable<LayoutItem?>(null);

  /// Returns the current placeholder item.
  /// Used by the view to determine the drop position.
  LayoutItem? get currentDragPlaceholder => placeholder.value;

  /// A reactive property that holds the pixel offset for the actively dragged item,
  /// enabling a smooth visual drag effect.
  final dragOffset = Beacon.writable<Offset>(Offset.zero);

  /// Indicates if the current interaction is a resize operation.
  final isResizing = Beacon.writable(false);

  /// The size of the touch target for resizing handles.
  final resizeHandleSide = Beacon.writable<double>(20);

  /// Sets the resize handle side length.
  void setResizeHandleSide(double side) {
    resizeHandleSide.value = side;
  }

  /// Sets the default color of handles.
  void setHandleColor(Color? color) {
    handleColor.value = color;
  }

  /// Sets the pixel offset for the actively dragged item.
  ///
  /// This is used internally by the `Dashboard` widget to create a smooth
  /// drag-and-drop effect.
  @internal
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
  @internal
  void showPlaceholder({required int x, required int y, required int w, required int h}) {
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

    // When no compaction, do not compact final result, keep result from moveElement
    // which potentially has already pushed items.
    final compactedLayout = compactionType.value != engine.CompactType.none
        ? engine.compact(newLayout, compactionType.value, slotCount.value)
        : newLayout;

    layout.value = compactedLayout;
  }

  /// Removes the temporary placeholder item from the layout.
  @internal
  void hidePlaceholder() {
    if (placeholder.value == null) return;
    // Revert to the clean layout from before the drag-over started.
    layout.value = List.from(originalLayoutOnStart.peek());
    placeholder.value = null;
    originalLayoutOnStart.value = []; // Clean up state
  }

  /// Finalizes a drop from an external source.
  @internal
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

    // Simply replace placeholder with real item
    final finalLayout = layout.value.map((item) {
      if (item.id == '__placeholder__') return newItem;
      return item;
    }).toList();

    // No need to call again moveElement or compaction if showPlaceholder
    // already did its job on last frame.
    // For safety, eg. compact is none, ALWAYS call compact.
    // If compactionType is null, this won't compact,
    // But this will prevent collision (overlaps) by pushing items.
    layout.value = engine.compact(
      finalLayout,
      compactionType.value,
      slotCount.value,
      allowOverlap: false,
    );

    // Clean up all temporary state.
    placeholder.value = null;
    originalLayoutOnStart.value = [];

    onLayoutChanged?.call(layout.value);
  }

  /// Adds multiple items to the dashboard.
  ///
  /// If an item has x = -1 or y = -1, it will be automatically placed
  /// at the bottom of the layout.
  ///
  /// [overrideCompactType] allows you to force a specific compaction strategy
  /// for this operation (e.g. force vertical compaction even if the controller is in 'none').
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

    // Run compaction.
    // This will pull the auto-placed items (which are at the bottom)
    // up into any available empty spaces above them.
    final newLayout = engine.compact(
      currentLayout,
      overrideCompactType ?? compactionType.value,
      slotCount.value,
    );

    layout.value = newLayout;
    onLayoutChanged?.call(layout.value);
  }

  /// Adds a new item to the dashboard.
  ///
  /// The new item is added, and the layout is re-compacted to find a suitable
  /// position for it.
  void addItem(LayoutItem newItem, {engine.CompactType? overrideCompactType}) {
    if (newItem.x == -1 || newItem.y == -1) {
      addItems([newItem], overrideCompactType: overrideCompactType);
      return;
    }
    final currentLayout = layout.value;
    final newLayout = engine.compact(
      [...currentLayout, newItem],
      overrideCompactType ?? compactionType.value,
      slotCount.value,
    );
    layout.value = newLayout;

    onLayoutChanged?.call(layout.value);
  }

  /// Removes an item from the dashboard by its ID.
  ///
  /// After removal, the layout is re-compacted to fill any empty space.
  void removeItem(String itemId, {engine.CompactType? overrideCompactType}) {
    final currentLayout = layout.value;
    final newLayout = engine.compact(
      currentLayout.where((item) => item.id != itemId).toList(),
      overrideCompactType ?? compactionType.value,
      slotCount.value,
    );
    layout.value = newLayout;
    onLayoutChanged?.call(layout.value);
  }

  /// Toggles the edit mode for the dashboard.
  void toggleEditing() {
    isEditing.value = !isEditing.value;
  }

  /// Sets the edit mode for the dashboard.
  // ignore: avoid_positional_boolean_parameters
  void setEditMode(bool editing) {
    isEditing.value = editing;
  }

  /// Sets the number of columns for the grid and triggers a relayout.
  void setSlotCount(int newSlotCount) {
    if (slotCount.value == newSlotCount) return;

    slotCount.value = newSlotCount;
    // Correct bounds and re-compact for the new column count
    final corrected = engine.correctBounds(layout.value, newSlotCount);
    layout.value = engine.compact(corrected, engine.CompactType.vertical, newSlotCount);
  }

  /// Sets the collision behavior for the dashboard.
  // ignore: avoid_positional_boolean_parameters
  void setPreventCollision(bool prevent) {
    preventCollision.value = prevent;
  }

  /// Sets the compaction behavior for the dashboard.
  void setCompactionType(engine.CompactType type) {
    compactionType.value = type;
  }

  // --- DRAG AND RESIZE LOGIC ---

  /// A readable beacon that exposes the ID of the currently active
  /// (dragged or resized) item.
  ///
  /// Returns `null` if no item is active.
  late final ReadableBeacon<String?> activeItemId = Beacon.derived(() => activeItem.value?.id);

  /// Internal state to track the item being dragged or resized.
  @visibleForTesting
  final activeItem = Beacon.writable<LayoutItem?>(null);

  /// Internal state to store the layout at the beginning of an operation.
  @visibleForTesting
  final originalLayoutOnStart = Beacon.writable<List<LayoutItem>>([]);

  /// Call when a drag gesture starts on a dashboard item.
  @internal
  void onDragStart(String itemId) {
    final item = layout.value.firstWhere((i) => i.id == itemId);
    if (item.isStatic) return;
    isResizing.value = false;
    originalLayoutOnStart.value = layout.value;
    activeItem.value = item;
  }

  /// Call continuously while a drag gesture is updated.
  @internal
  void onDragUpdate(
    String itemId,
    Offset contentPosition, {
    required double slotWidth,
    required double slotHeight,
    required double mainAxisSpacing,
    required double crossAxisSpacing,
  }) {
    final item = activeItem.value;
    if (item == null || item.id != itemId) return;

    // 1. Calculate the new logical grid position from the scroll-aware contentPosition.
    final newGridX = (contentPosition.dx / (slotWidth + crossAxisSpacing)).round();
    final newGridY = (contentPosition.dy / (slotHeight + mainAxisSpacing)).round();

    final int clampedX;
    final int clampedY;

    if (scrollDirection.value == Axis.vertical) {
      clampedX = newGridX.clamp(0, slotCount.value - item.w);
      clampedY = max(0, newGridY);
    } else {
      clampedX = max(0, newGridX);
      clampedY = newGridY.clamp(0, slotCount.value - item.h);
    }

    // 2. Update the layout by moving the element to the new logical position.
    final newLayout = engine.moveElement(
      originalLayoutOnStart.value,
      item,
      clampedX,
      clampedY,
      cols: slotCount.value,
      compactType: compactionType.value,
      preventCollision: preventCollision.value,
    );
    layout.value = newLayout;

    // 3. Calculate the smooth visual offset.
    final logicalItemPixelX = clampedX * (slotWidth + crossAxisSpacing);
    final logicalItemPixelY = clampedY * (slotHeight + mainAxisSpacing);

    final visualOffsetX = contentPosition.dx - logicalItemPixelX;
    final visualOffsetY = contentPosition.dy - logicalItemPixelY;

    // 4. Update the drag offset beacon.
    dragOffset.value = Offset(visualOffsetX, visualOffsetY);
  }

  /// Call when a drag gesture ends.
  @internal
  void onDragEnd(String itemId) {
    if (activeItem.value == null) return;

    // For safety, eg. compact is none, ALWAYS call compact.
    // If compactionType is null, this won't compact,
    // But this will prevent collision (overlaps) by pushing items.
    final finalLayout = engine.compact(
      layout.value,
      compactionType.value,
      slotCount.value,
      allowOverlap: false,
    );

    layout.value = finalLayout;

    onLayoutChanged?.call(layout.value);

    activeItem.value = null;
    originalLayoutOnStart.value = [];
    dragOffset.value = Offset.zero;
  }

  /// A reactive property to control resize behavior.
  final WritableBeacon<engine.ResizeBehavior> resizeBehavior =
      Beacon.writable<engine.ResizeBehavior>(
    engine.ResizeBehavior.push,
  );

  /// Sets the resize behavior for the dashboard.
  void setResizeBehavior(engine.ResizeBehavior behavior) {
    resizeBehavior.value = behavior;
  }

  /// Call when a resize gesture starts on a dashboard item.
  @internal
  void onResizeStart(String itemId) {
    final item = layout.value.firstWhere((i) => i.id == itemId);
    if (item.isStatic || item.isResizable == false) return;
    isResizing.value = true;
    originalLayoutOnStart.value = layout.value;
    activeItem.value = item;
  }

  /// Call continuously while a resize gesture is updated.
  @internal
  void onResizeUpdate(
    String itemId,
    ResizeHandle handle,
    Offset delta, {
    required double slotWidth,
    required double slotHeight,
    required double crossAxisSpacing,
    required double mainAxisSpacing,
  }) {
    final item = activeItem.value;
    if (item == null || item.id != itemId) return;

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
        newW = (originalItem.w - dW).round(); // Dragging left (-dx) should increase width
        newH = (originalItem.h + dH).round();
        newX = (originalItem.x + dW).round();
      case ResizeHandle.topRight:
        newW = (originalItem.w + dW).round();
        newH = (originalItem.h - dH).round(); // Dragging up (-dy) should increase height
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

    // Clamp dimensions to min/max
    final maxW = originalItem.maxW.isFinite ? originalItem.maxW.toInt() : 10000;
    final maxH = originalItem.maxH.isFinite ? originalItem.maxH.toInt() : 10000;
    newW = newW.clamp(originalItem.minW, maxW);
    newH = newH.clamp(originalItem.minH, maxH);

    // Clamp position and dimensions to grid boundaries
    if (scrollDirection.value == Axis.vertical) {
      if (newX < 0) {
        newW += newX; // Reduce width by the amount it went off-screen
        newX = 0;
      }
      if (newX + newW > slotCount.value) {
        newW = slotCount.value - newX; // Clamp width to the right edge
      }
    } else {
      // Horizontal scroll
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
  @internal
  void onResizeEnd(String itemId) {
    if (activeItem.value == null) return;

    // For safety, eg. compact is none, ALWAYS call compact.
    // If compactionType is null, this won't compact,
    // But this will prevent collision (overlaps) by pushing items.
    final finalLayout = engine.compact(
      layout.value,
      compactionType.value,
      slotCount.value,
      allowOverlap: false,
    );

    layout.value = finalLayout;

    onLayoutChanged?.call(layout.value);

    activeItem.value = null;
    originalLayoutOnStart.value = [];
    dragOffset.value = Offset.zero;
  }

  /// Exports the current layout state to a list of maps (JSON-ready).
  List<Map<String, dynamic>> exportLayout() {
    return layout.value.map((item) => item.toMap()).toList();
  }

  /// Imports a layout from a list of maps.
  ///
  /// This replaces the current layout.
  /// [jsonLayout] is the list of maps (e.g. from JSON decode).
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
    layout.value = engine.compact(
      corrected,
      compactionType.value,
      slotCount.value,
      allowOverlap: false, // Ensure imported layout is clean
    );

    onLayoutChanged?.call(layout.value);
  }

  /// Disposes all the beacons to prevent memory leaks.
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
}
