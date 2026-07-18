// ignore_for_files: specify_nonobvious_property_types
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart' as engine;
import 'package:sliver_dashboard/src/models/dashboard_policy.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/models/utility.dart';
import 'package:sliver_dashboard/src/view/a11y/dashboard_shortcuts.dart';
import 'package:sliver_dashboard/src/view/guidance/dashboard_guidance.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';
import 'package:state_beacon/state_beacon.dart';

/// Data payload for a scroll request.
typedef ScrollRequest = ({
  String itemId,
  double alignment,
  Duration duration,
  Curve curve,
  Completer<void> completer
});

/// The concrete implementation of [DashboardController].
/// Manages the state and interactions of the dashboard.
///
/// This controller is the single source of truth for the dashboard's layout.
/// It uses `state_beacon` for reactive state management, ensuring that UI
/// updates are efficient and predictable.
@internal
class DashboardControllerImpl with BeaconController implements DashboardController {
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

  @override
  DashboardPolicy? policy;

  // --- BEACONS (Public via Interface) ---

  @override
  late final handleColor = B.writable<Color?>(null);

  @override
  late final layout = B.writable<List<LayoutItem>>([]);

  @override
  late final scrollDirection = B.writable(Axis.vertical);

  @override
  late final isEditing = B.writable<bool>(false);

  @override
  late final slotCount = B.writable<int>(8);

  @override
  late final preventCollision = B.writable<bool>(true);

  @override
  late final compactionType = B.writable<engine.CompactType>(engine.CompactType.vertical);

  // Internal delegate reference
  engine.CompactorDelegate _compactor = const engine.FastVerticalCompactor();

  @override
  late final resizeHandleSide = B.writable<double>(20);

  @override
  late final resizeBehavior = B.writable<engine.ResizeBehavior>(
    engine.ResizeBehavior.push,
  );

  @override
  late final selectedItemIds = B.writable<Set<String>>({});

  // Internal state to track if we are actually moving items vs just selecting
  late final _isDraggingState = B.writable(false);

  @override
  ReadableBeacon<bool> get isDragging => _isDraggingState;

  // The item under the cursor that initiated the drag.
  // This is our reference point for calculating deltas.
  String? _pivotItemId;

  @override
  late final ReadableBeacon<String?> activeItemId = B.derived(() {
    // If dragging, the pivot is the active item.
    // If not dragging, the first selected item is "active" (for focus/properties).
    if (_isDraggingState.value) return _pivotItemId;
    return selectedItemIds.value.firstOrNull;
  });

  @override
  late final allowAutoShrink = B.writable<bool>(false);

  // --- INTERNAL STATE (Hidden from Interface) ---

  final _scrollToItemController = StreamController<ScrollRequest>.broadcast();

  /// Internal cache to store layouts for specific slot counts.
  /// Used to restore the layout when switching back to a previous breakpoint.
  final Map<int, List<LayoutItem>> _layoutsBySlotCount = {};

  /// Temporary placeholder item in the layout.
  @visibleForTesting
  late final placeholder = B.writable<LayoutItem?>(null);

  @override
  LayoutItem? get currentDragPlaceholder => placeholder.value;

  /// A reactive property that holds the pixel offset for the actively dragged item,
  /// enabling a smooth visual drag effect.
  late final dragOffset = B.writable<Offset>(Offset.zero);

  /// Indicates if the current interaction is a resize operation.
  late final isResizing = B.writable(false);

  /// Internal state to track the item being dragged or resized.
  @visibleForTesting
  late final activeItem = B.writable<LayoutItem?>(null);

  /// Internal state to store the layout at the beginning of an operation.
  @visibleForTesting
  late final originalLayoutOnStart = B.writable<List<LayoutItem>>([]);

  Stream<ScrollRequest> get scrollToItemRequest => _scrollToItemController.stream;

  int? _lastBBoxX;
  int? _lastBBoxY;

  int? _lastResizeW;
  int? _lastResizeH;
  int? _lastResizeX;
  int? _lastResizeY;

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
        _compactor = const engine.FastVerticalCompactor();
      case engine.CompactType.horizontal:
        _compactor = const engine.FastHorizontalCompactor();
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
    AutoPlacementStrategy strategy = AutoPlacementStrategy.appendBottom,
  }) {
    final currentLayout = List<LayoutItem>.from(layout.value);

    final placedLayout = engine.placeNewItems(
      existingLayout: currentLayout,
      newItems: items,
      cols: slotCount.value,
      strategy: strategy,
    );

    final compactorStrategy =
        overrideCompactType != null ? _getTempDelegate(overrideCompactType) : _compactor;

    layout.value = compactorStrategy.compact(
      placedLayout,
      slotCount.value,
    );

    onLayoutChanged?.call(layout.value, slotCount.value);
  }

  @override
  void addItem(
    LayoutItem newItem, {
    engine.CompactType? overrideCompactType,
    AutoPlacementStrategy strategy = AutoPlacementStrategy.appendBottom,
  }) {
    addItems(
      [newItem],
      overrideCompactType: overrideCompactType,
      strategy: strategy,
    );
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
  void updateItem(
    String itemId,
    LayoutItem Function(LayoutItem item) transform, {
    bool recompact = true,
  }) {
    final current = layout.value;

    // Locate the target once. No-op on unknown id (robustness guarantee).
    LayoutItem? original;
    for (final i in current) {
      if (i.id == itemId) {
        original = i;
        break;
      }
    }
    if (original == null) return;

    var updated = transform(original);

    // Enforce id identity: a transform must not repoint the item to a new id
    // (it would silently create a duplicate or orphan). In debug this is a
    // hard error; in release we defensively restore the id so the layout
    // cannot be corrupted by misuse.
    assert(
      updated.id == itemId,
      'updateItem: transform must not change the item id '
      '(expected "$itemId", got "${updated.id}").',
    );
    if (updated.id != itemId) {
      updated = updated.copyWith(id: itemId);
    }

    // Nothing changed: no mutation, no event (robustness guarantee).
    if (updated == original) return;

    // Correct bounds so a transform returning invalid geometry (w/h < 1, or an
    // out-of-grid position) cannot corrupt the cascade. correctBounds also
    // re-clamps against the current column count.
    final candidate = [
      for (final i in current)
        if (i.id == itemId) updated else i,
    ];
    final corrected = engine.correctBounds(candidate, slotCount.value);

    final List<LayoutItem> resolved;
    if (recompact) {
      // Size/position may have changed: run the full strategy.
      resolved = compactionType.value == engine.CompactType.none
          ? _compactor.resolveCollisions(corrected, slotCount.value)
          : _compactor.compact(corrected, slotCount.value);
    } else {
      // Metadata-only change: don't pull items back, only clear any overlap
      // the change might have introduced (usually none for a flag/title).
      resolved = _compactor.resolveCollisions(corrected, slotCount.value);
    }

    layout.value = resolved;

    // Write-through to the in-flight snapshots. Everything the engine
    // rebuilds from the pre-interaction snapshot — onDragUpdate recomputes,
    // the cross-grid exit base in [beginCrossGridExit], the canceled-drop
    // restore in [finishCrossGridExit] — would otherwise silently erase a
    // mid-interaction mutation. Concrete case: the same-grid subGridDynamic
    // conversion flips `hasNestedGrid` on a host while the drag is still in
    // flight; without this, the flag is lost the moment the session starts
    // and the freshly mounted nested grid unmounts with its content.
    // The transform is applied to the snapshot's own entry so the snapshot's
    // pristine positions are preserved. Limitation (unchanged): transforming
    // the actively dragged pivot itself mid-drag remains unsupported (the
    // cached pivot/cluster copies are not rewritten).
    final snapshot = originalLayoutOnStart.peek();
    if (snapshot.isNotEmpty) {
      final idx = snapshot.indexWhere((i) => i.id == itemId);
      if (idx != -1) {
        final next = List<LayoutItem>.from(snapshot);
        var patched = transform(next[idx]);
        if (patched.id != itemId) patched = patched.copyWith(id: itemId);
        next[idx] = patched;
        originalLayoutOnStart.value = next;
      }
    }
    final exitSnapshot = _crossGridExitSnapshot;
    if (exitSnapshot != null) {
      final idx = exitSnapshot.indexWhere((i) => i.id == itemId);
      if (idx != -1) {
        var patched = transform(exitSnapshot[idx]);
        if (patched.id != itemId) patched = patched.copyWith(id: itemId);
        exitSnapshot[idx] = patched;
      }
    }

    onLayoutChanged?.call(layout.value, slotCount.value);
  }

  @override
  void replaceItem(String oldItemId, LayoutItem newItem) {
    final current = layout.value;

    // 1. Locate the old item to ensure it exists
    LayoutItem? oldItem;
    for (final i in current) {
      if (i.id == oldItemId) {
        oldItem = i;
        break;
      }
    }
    if (oldItem == null) return;

    // 2. Correct bounds of the new item to match target columns
    final correctedNewItem = engine.correctBounds([newItem], slotCount.value).first;

    // 3. Build and sort the new layout (Index Stability Invariant)
    final nextLayout = [
      for (final i in current)
        if (i.id == oldItemId) correctedNewItem else i,
    ]..sort((a, b) => a.id.compareTo(b.id));

    layout.value = nextLayout;

    // 4. Invariant: Write-through to in-flight pre-drag snapshots to avoid erasing on pointer updates
    final snapshot = originalLayoutOnStart.peek();
    if (snapshot.isNotEmpty) {
      final nextSnapshot = [
        for (final i in snapshot)
          if (i.id == oldItemId) correctedNewItem else i,
      ]..sort((a, b) => a.id.compareTo(b.id));
      originalLayoutOnStart.value = nextSnapshot;
    }

    final exitSnapshot = _crossGridExitSnapshot;
    if (exitSnapshot != null) {
      final nextExitSnapshot = [
        for (final i in exitSnapshot)
          if (i.id == oldItemId) correctedNewItem else i,
      ]..sort((a, b) => a.id.compareTo(b.id));
      _crossGridExitSnapshot = nextExitSnapshot;
    }

    // 5. Notify layout changes
    onLayoutChanged?.call(layout.value, slotCount.value);
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
    _scrollToItemController.close().ignore();
    hoveredNestTargetId.dispose();
    super.dispose();
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

  @override
  void setAllowAutoShrink({required bool allow}) {
    allowAutoShrink.value = allow;
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

      policy: policy,
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
  // ===========================================================================
  // Nested grids / cross-grid drag & drop
  // ===========================================================================

  /// The item currently highlighted as a dynamic nested-grid host
  /// (`subGridDynamic` hover). Watched by the item shells for the visual ring;
  /// the heavy item content behind its RepaintBoundary never rebuilds.
  late final hoveredNestTargetId = B.writable<String?>(null);

  /// Sets or clears the nested-grid hover highlight.
  void setNestTargetHover(String? itemId) {
    if (hoveredNestTargetId.peek() == itemId) return;
    hoveredNestTargetId.value = itemId;
  }

  // Snapshot of the pre-drag layout taken when a cross-grid exit begins,
  // used to restore this grid if the drop is canceled or lands nowhere.
  List<LayoutItem>? _crossGridExitSnapshot;

  /// Whether a cross-grid temporary removal is pending resolution.
  bool get hasPendingCrossGridExit => _crossGridExitSnapshot != null;

  /// The pre-push layout snapshot to use for hover/hit detection while a
  /// foreign placeholder is active, or null when no placeholder is active.
  ///
  /// While an external/cross-grid placeholder is shown, the live [layout] is
  /// continuously reshuffled by collision pushes, which makes "what is under
  /// the cursor" unstable. This exposes the frozen [originalLayoutOnStart]
  /// snapshot for that purpose without leaking the test-only beacons.
  List<LayoutItem>? get placeholderHitTestSnapshot {
    if (placeholder.value == null) return null;
    final snapshot = originalLayoutOnStart.peek();
    return snapshot.isEmpty ? null : snapshot;
  }

  /// The pre-drag layout snapshot while an interactive in-grid drag is in
  /// progress, or null. Same-grid `subGridDynamic` uses it to hit-test the
  /// item under the pointer with the live collision pushes factored out —
  /// the pushed layout constantly lies about what is being hovered.
  List<LayoutItem>? get dragOriginSnapshot {
    if (!_isDraggingState.peek()) return null;
    final snapshot = originalLayoutOnStart.peek();
    return snapshot.isEmpty ? null : snapshot;
  }

  /// Reverts the visual collision pushes of the in-grid drag by restoring the
  /// pre-drag snapshot while keeping the drag itself alive (the same-grid
  /// `subGridDynamic` freeze). Also resets the drag-update boundary bypass so
  /// the next [onDragUpdate] re-applies the pushes instead of hitting the
  /// "bbox unchanged" fast path against a stale cache.
  void freezeDragPushes() {
    if (!_isDraggingState.peek()) return;
    final snapshot = originalLayoutOnStart.peek();
    if (snapshot.isEmpty) return;
    _lastBBoxX = null;
    _lastBBoxY = null;
    layout.value = List<LayoutItem>.from(snapshot);
  }

  /// Temporarily removes [itemIds] from this grid because they are being
  /// dragged over another grid.
  ///
  /// The removal is *silent*: `onLayoutChanged` is deliberately not fired —
  /// the move is not committed until [finishCrossGridExit]. The internal drag
  /// state is reset without the usual drop compaction/event.
  ///
  /// Returns the removed items with their pre-drag geometry (from the
  /// drag-start snapshot when available), so the receiving grid gets clean
  /// coordinates and constraints.
  List<LayoutItem> beginCrossGridExit(Set<String> itemIds) {
    if (_crossGridExitSnapshot != null) return const [];
    final current = layout.value;
    final base = originalLayoutOnStart.peek().isNotEmpty ? originalLayoutOnStart.peek() : current;
    final removed = base.where((i) => itemIds.contains(i.id)).toList();
    if (removed.isEmpty) return const [];

    _crossGridExitSnapshot = List<LayoutItem>.from(base);

    // Silently terminate the in-grid drag: no compaction event, no
    // onLayoutChanged — the gesture is still in flight.
    _isDraggingState.value = false;
    _pivotItemId = null;
    originalLayoutOnStart.value = [];
    dragOffset.value = Offset.zero;
    _dragPivotOriginal = null;
    _dragClusterItems = const [];
    _dragOriginalBBox = null;
    _lastMovedPivot = null;
    clearSelection();

    final remaining = base.where((i) => !itemIds.contains(i.id)).toList();
    layout.value = compactionType.value == engine.CompactType.none
        ? _compactor.resolveCollisions(remaining, slotCount.value)
        : _compactor.compact(remaining, slotCount.value);
    return removed;
  }

  /// Resolves a pending cross-grid exit (see [beginCrossGridExit]).
  ///
  /// * [CrossGridExitOutcome.movedAway] — the item landed in another grid:
  ///   the removal becomes definitive and `onLayoutChanged` fires once.
  /// * [CrossGridExitOutcome.returned] — the item was dropped back into this
  ///   grid via the external-drop path, which already emitted the final
  ///   layout: the snapshot is discarded silently.
  /// * [CrossGridExitOutcome.canceled] — the drop failed: the pre-drag layout
  ///   is restored silently, exactly like [cancelInteraction].
  void finishCrossGridExit({required CrossGridExitOutcome outcome}) {
    final snapshot = _crossGridExitSnapshot;
    if (snapshot == null) return;
    _crossGridExitSnapshot = null;
    switch (outcome) {
      case CrossGridExitOutcome.movedAway:
        onLayoutChanged?.call(layout.value, slotCount.value);
      case CrossGridExitOutcome.returned:
        break;
      case CrossGridExitOutcome.canceled:
        layout.value = snapshot;
    }
  }

  /// Finalizes a drop from another grid (or any caller holding a full
  /// [LayoutItem]), preserving the template's id, constraints and flags —
  /// unlike [onDropExternal], which only receives an id.
  ///
  /// Returns the placed item, or null when no placeholder is active.
  LayoutItem? onDropExternalItem({required LayoutItem template}) {
    final currentPlaceholder = placeholder.value;
    if (currentPlaceholder == null) return null;

    final finalPlaceholderPos =
        layout.value.firstWhereOrNull((e) => e.id == '__placeholder__') ?? currentPlaceholder;

    final newItem = template.copyWith(
      x: finalPlaceholderPos.x,
      y: finalPlaceholderPos.y,
      w: finalPlaceholderPos.w,
      h: finalPlaceholderPos.h,
      moved: false,
    );

    final finalLayout = layout.value.map((item) {
      if (item.id == '__placeholder__') return newItem;
      return item;
    }).toList();

    layout.value = _compactor.compact(
      finalLayout,
      slotCount.value,
      allowOverlap: false,
    );

    placeholder.value = null;
    originalLayoutOnStart.value = [];

    onLayoutChanged?.call(layout.value, slotCount.value);
    var placed = newItem;
    for (final i in layout.value) {
      if (i.id == newItem.id) {
        placed = i;
        break;
      }
    }
    return placed;
  }

  /// Programmatically resizes [itemId] to [w] x [h] slots (either may be
  /// null to keep the current value), clamped to the item's min/max
  /// constraints, then re-runs the current compaction strategy.
  ///
  /// Used by `NestedDashboard.sizeToContent` to grow/shrink the host item.
  /// Returns the updated item, or null when not found or unchanged.
  LayoutItem? setItemSize(String itemId, {int? w, int? h}) {
    final current = layout.value;
    LayoutItem? item;
    for (final i in current) {
      if (i.id == itemId) {
        item = i;
        break;
      }
    }
    if (item == null) return null;

    var newW = w ?? item.w;
    var newH = h ?? item.h;
    final maxW = item.maxW.isFinite ? item.maxW.toInt() : slotCount.value;
    final maxH = item.maxH.isFinite ? item.maxH.toInt() : 1 << 20;
    newW = newW.clamp(item.minW, maxW < item.minW ? item.minW : maxW);
    newH = newH.clamp(item.minH, maxH < item.minH ? item.minH : maxH);
    if (scrollDirection.value == Axis.vertical) {
      newW = newW.clamp(1, slotCount.value);
    } else {
      newH = newH.clamp(1, slotCount.value);
    }
    if (newW == item.w && newH == item.h) return item;

    final resized = item.copyWith(w: newW, h: newH, moved: false);
    final newLayout = [
      for (final i in current)
        if (i.id == itemId) resized else i,
    ];
    layout.value = compactionType.value == engine.CompactType.none
        ? _compactor.resolveCollisions(newLayout, slotCount.value)
        : _compactor.compact(newLayout, slotCount.value);
    onLayoutChanged?.call(layout.value, slotCount.value);
    for (final i in layout.value) {
      if (i.id == itemId) return i;
    }
    return resized;
  }

  // --- Per-drag cached invariants (computed once in onDragStart) ---
  // The original pivot, the cluster and its bounding box never change during
  // a drag; recomputing them on every pointer event (~60Hz) costs three O(N)
  // scans plus two list allocations per event at N=1000.
  LayoutItem? _dragPivotOriginal;
  List<LayoutItem> _dragClusterItems = const [];
  LayoutItem? _dragOriginalBBox;
  LayoutItem? _lastMovedPivot;

  /// Call when a drag gesture starts on a dashboard item.
  void onDragStart(String itemId) {
    final item = layout.value.firstWhere((i) => i.id == itemId);
    // Allow dragging section barriers even if they are marked static
    if (item.isStatic && !item.isSectionBarrier) return;

    if (policy != null && !policy!.canDrag(item)) return;

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

    // reset lock
    _lastBBoxX = null;
    _lastBBoxY = null;

    // Snapshot layout for anti-drift
    originalLayoutOnStart.value = layout.value;

    // Cache the per-drag invariants once (see field docs).
    final snapshot = originalLayoutOnStart.value;
    final ids = selectedItemIds.value;
    _dragPivotOriginal = snapshot.firstWhere((i) => i.id == itemId);
    _dragClusterItems = snapshot.where((i) => ids.contains(i.id)).toList();
    _dragOriginalBBox = engine.calculateBoundingBox(_dragClusterItems);
    _lastMovedPivot = _dragPivotOriginal;
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

    final pivotItem = _dragPivotOriginal;
    final originalBBox = _dragOriginalBBox;
    if (pivotItem == null || originalBBox == null) return;

    // 1. Calculate Pivot's new Grid Position
    final newGridX = (contentPosition.dx / (slotWidth + crossAxisSpacing)).round();
    final newGridY = (contentPosition.dy / (slotHeight + mainAxisSpacing)).round();

    if (policy != null &&
        !policy!.canMoveTo(pivotItem, newGridX, newGridY, originalLayoutOnStart.value)) {
      return; // Block move
    }

    // 2. Calculate Delta (Grid Units) from original position
    final dx = newGridX - pivotItem.x;
    final dy = newGridY - pivotItem.y;

    // 3. Target Bounding Box Position (cluster bbox cached at drag start)
    var targetBBoxX = originalBBox.x + dx;
    var targetBBoxY = originalBBox.y + dy;

    // 4. Clamping
    if (scrollDirection.value == Axis.vertical) {
      targetBBoxX = targetBBoxX.clamp(0, slotCount.value - originalBBox.w);
      targetBBoxY = max(0, targetBBoxY);
    } else {
      targetBBoxX = max(0, targetBBoxX);
      targetBBoxY = targetBBoxY.clamp(0, slotCount.value - originalBBox.h);
    }

    // Boundary Bypass.
    // If the logical grid coordinates of the moving bounding box have not
    // changed, the background grid is mathematically identical: only update
    // the lightweight overlay dragOffset. The pivot's logical position is
    // cached from the last moveCluster result instead of an O(N) firstWhere.
    if (_lastBBoxX == targetBBoxX && _lastBBoxY == targetBBoxY) {
      final movedPivot = _lastMovedPivot ?? pivotItem;
      final logicalItemPixelX = movedPivot.x * (slotWidth + crossAxisSpacing);
      final logicalItemPixelY = movedPivot.y * (slotHeight + mainAxisSpacing);

      dragOffset.value = Offset(
        contentPosition.dx - logicalItemPixelX,
        contentPosition.dy - logicalItemPixelY,
      );
      return;
    }

    _lastBBoxX = targetBBoxX;
    _lastBBoxY = targetBBoxY;

    // 5. Move Cluster
    final newLayout = engine.moveCluster(
      originalLayoutOnStart.value,
      selectedItemIds.value,
      targetBBoxX,
      targetBBoxY,
      cols: slotCount.value,
      compactType: compactionType.value,
      preventCollision: preventCollision.value,
      policy: policy,
      allowAutoShrink: allowAutoShrink.value,
    );

    layout.value = newLayout;

    // 6. Visual Offset (Smooth Drag)
    final movedPivot = newLayout.firstWhere((i) => i.id == itemId);
    _lastMovedPivot = movedPivot;

    final logicalItemPixelX = movedPivot.x * (slotWidth + crossAxisSpacing);
    final logicalItemPixelY = movedPivot.y * (slotHeight + mainAxisSpacing);

    dragOffset.value = Offset(
      contentPosition.dx - logicalItemPixelX,
      contentPosition.dy - logicalItemPixelY,
    );
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
    _dragPivotOriginal = null;
    _dragClusterItems = const [];
    _dragOriginalBBox = null;
    _lastMovedPivot = null;
  }

  /// Call when a resize gesture starts on a dashboard item.
  void onResizeStart(String itemId) {
    // Restriction: Multi-resize not supported yet.
    // If multiple items selected, we clear selection and select only this one.
    selectedItemIds.value = {itemId};

    final item = layout.value.firstWhere((i) => i.id == itemId);
    if (item.isStatic || item.isResizable == false) return;

    if (policy != null && !policy!.canResize(item)) return;

    isResizing.value = true;
    _pivotItemId = itemId;
    _isDraggingState.value = false;

    // reset lock
    _lastResizeW = null;
    _lastResizeH = null;
    _lastResizeX = null;
    _lastResizeY = null;

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

    // Anchored constraints resolver
    // Prevent counter-intuitive layout expansions when resizing top/left edges
    // against static obstacles, while preserving collision/jump behaviors
    // for bottom/right edge resizes.
    final statics = originalLayoutOnStart.value.where((i) => i.isStatic && i.id != itemId).toList();

    final isLeftResize = handle == ResizeHandle.left ||
        handle == ResizeHandle.topLeft ||
        handle == ResizeHandle.bottomLeft;

    final isTopResize = handle == ResizeHandle.top ||
        handle == ResizeHandle.topLeft ||
        handle == ResizeHandle.topRight;

    final maxW = originalItem.maxW.isFinite ? originalItem.maxW.toInt() : 10000;
    final maxH = originalItem.maxH.isFinite ? originalItem.maxH.toInt() : 10000;

    // Apply preliminary clamps to ensure minimum and maximum item constraints
    // are respected before applying geometric anchor boundaries.
    newW = newW.clamp(originalItem.minW, maxW);
    newH = newH.clamp(originalItem.minH, maxH);

    // Constrain Vertical Axis (Y, H)
    if (isTopResize) {
      final originalBottom = originalItem.y + originalItem.h;
      var limitY = 0;
      for (final s in statics) {
        if (s.x < (newX + newW) && (s.x + s.w) > newX) {
          if ((s.y + s.h) <= originalBottom) {
            limitY = max(limitY, s.y + s.h);
          }
        }
      }
      final minYClamp = max(limitY, originalBottom - maxH);
      final maxYClamp = originalBottom - originalItem.minH;
      newY = newY.clamp(minYClamp, maxYClamp);
      newH = originalBottom - newY;
    } else {
      // allows jumping/pushing obstacles below
      if (newY < 0) {
        newH += newY;
        newY = 0;
      }
      if (scrollDirection.value == Axis.horizontal) {
        if (newY + newH > slotCount.value) {
          newH = slotCount.value - newY;
        }
      }
    }

    // Constrain Horizontal Axis (X, W)
    if (isLeftResize) {
      final originalRight = originalItem.x + originalItem.w;
      var limitX = 0;
      for (final s in statics) {
        if (s.y < (newY + newH) && (s.y + s.h) > newY) {
          if ((s.x + s.w) <= originalRight) {
            limitX = max(limitX, s.x + s.w);
          }
        }
      }
      final minXClamp = max(limitX, originalRight - maxW);
      final maxXClamp = originalRight - originalItem.minW;
      newX = newX.clamp(minXClamp, maxXClamp);
      newW = originalRight - newX;
    } else {
      // allows jumping/pushing obstacles on the right
      if (newX < 0) {
        newW += newX;
        newX = 0;
      }
      if (scrollDirection.value == Axis.vertical) {
        if (newX + newW > slotCount.value) {
          newW = slotCount.value - newX;
        }
      }
    }

    // Boundary Bypass for resizing.
    // If the target dimensions and positions have not crossed a grid threshold,
    // bypass the entire layout reconstruction.
    if (_lastResizeW == newW &&
        _lastResizeH == newH &&
        _lastResizeX == newX &&
        _lastResizeY == newY) {
      return;
    }

    _lastResizeW = newW;
    _lastResizeH = newH;
    _lastResizeX = newX;
    _lastResizeY = newY;

    final resizedItem = originalItem.copyWith(w: newW, h: newH, x: newX, y: newY);

    final newLayout = engine.resizeItem(
      originalLayoutOnStart.value,
      resizedItem,
      behavior: resizeBehavior.value,
      cols: slotCount.value,
      preventCollision: preventCollision.value,
      compactType: compactionType.value,
      policy: policy,
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
    _dragPivotOriginal = null;
    _dragClusterItems = const [];
    _dragOriginalBBox = null;
    _lastMovedPivot = null;
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
    _dragPivotOriginal = null;
    _dragClusterItems = const [];
    _dragOriginalBBox = null;
    _lastMovedPivot = null;
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
        return const engine.FastVerticalCompactor();
      case engine.CompactType.horizontal:
        return const engine.FastHorizontalCompactor();
      case engine.CompactType.none:
        return const engine.NoCompactor();
    }
  }

  @override
  Future<void> scrollToItem(
    String itemId, {
    double alignment = 0.0,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    if (!layout.value.any((i) => i.id == itemId)) {
      return;
    }

    if (!_scrollToItemController.hasListener) {
      // No DashboardOverlay is attached (detached controller scenario):
      // completing immediately avoids a Future that never resolves.
      return;
    }

    final completer = Completer<void>();

    _scrollToItemController.add(
      (
        itemId: itemId,
        alignment: alignment,
        duration: duration,
        curve: curve,
        completer: completer,
      ),
    );

    return completer.future;
  }
}

/// How a pending cross-grid temporary removal is resolved.
/// See [DashboardControllerImpl.beginCrossGridExit].
enum CrossGridExitOutcome {
  /// The item was dropped into another grid: commit the removal.
  movedAway,

  /// The item came back into this grid through the external-drop path.
  returned,

  /// The drop failed: restore the pre-drag layout.
  canceled,
}
