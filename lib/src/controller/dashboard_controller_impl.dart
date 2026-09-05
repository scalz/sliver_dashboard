// ignore_for_files: specify_nonobvious_property_types
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart' as engine;
import 'package:sliver_dashboard/src/models/dashboard_policy.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/models/utility.dart';
import 'package:sliver_dashboard/src/view/a11y/dashboard_shortcuts.dart';
import 'package:sliver_dashboard/src/view/dashboard_configuration.dart';
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

/// Internal flag to allow bypassing the ID assertion during unit tests
/// to cover the defensive ID restoration logic.
@visibleForTesting
bool debugBypassUpdateItemIdAssert = false;

/// One transactional snapshot of the dashboard's spatial state.
///
/// The column count travels with the items on purpose. A snapshot recorded
/// under 12 columns is not replayable verbatim on a 4-column grid, and
/// restoring one without that information would silently push items out of
/// the grid. [DashboardControllerImpl._restoreSnapshot] branches on it.
typedef LayoutSnapshot = ({List<LayoutItem> items, int slotCount});

/// The default number of states kept on the layout history stack.
///
/// The current state counts as one entry, so this allows 29 consecutive
/// undos.
const int kDefaultMaxHistoryLength = 30;

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
    this.onUndo,
    this.onRedo,
    this.onWillUndo,
    this.onWillRedo,
    int maxHistoryLength = kDefaultMaxHistoryLength,
  }) {
    if (maxHistoryLength < 0) {
      throw ArgumentError.value(
        maxHistoryLength,
        'maxHistoryLength',
        'must be >= 0 (0 disables the layout history entirely)',
      );
    }
    _maxHistoryLength = maxHistoryLength;
    layout.value = initialLayout;
    slotCount.value = initialSlotCount;
    // The history must be seeded AFTER the two beacons above, because
    // a snapshot carries the column count it was recorded under. With
    // `maxHistoryLength: 0` nothing is created at all.
    if (_historyEnabled) _rebuildHistory([_snapshotNow()]);
  }

  @override
  final DashboardItemInteractionCallback? onInteractionStart;

  @override
  final DashboardLayoutChangeListener? onLayoutChanged;

  @override
  final DashboardHistoryRestoreListener? onUndo;

  @override
  final DashboardHistoryRestoreListener? onRedo;

  @override
  final DashboardHistoryVeto? onWillUndo;

  @override
  final DashboardHistoryVeto? onWillRedo;

  @override
  DashboardGuidance? guidance;

  @override
  DashboardShortcuts? shortcuts;

  @override
  LassoStyle lassoStyle = LassoStyle.byDefault;

  @override
  late final dragMode = B.writable<engine.DragMode>(engine.DragMode.cascade);

  @override
  late final swapModifierHeld = B.writable<bool>(false);

  @override
  late final lassoModifierHeld = B.writable<bool>(false);

  /// Effective mode of the frame the boundary bypass last computed.
  ///
  /// Part of the bypass key, not just bookkeeping: without it, flipping the
  /// modifier mid-drag without moving the pointer leaves the target box
  /// unchanged, the bypass returns early and the mode change is silently
  /// swallowed — the one failure the view's re-trigger cannot fix on its own.
  engine.DragMode? _lastDragMode;

  @override
  DashboardPolicy? policy;

  // --- BEACONS (Public via Interface) ---

  @override
  late final handleColor = B.writable<Color?>(null);

  @override
  late final layout = B.writable<List<LayoutItem>>([]);

  @override
  late final scrollDirection = B.writable(Axis.vertical);

  /// Non-reactive read of [scrollDirection], for the pointer hot paths.
  bool get _isVerticalScroll => scrollDirection.peek() == Axis.vertical;

  @override
  late final isEditing = B.writable<bool>(false);

  @override
  late final slotCount = B.writable<int>(8);

  /// Optional cap on the grid's main-axis extent, in rows (vertical
  /// scrolling) or columns (horizontal scrolling). Null (default) keeps the
  /// classic unbounded grid. Enforced where USER-driven placement is
  /// decided — drag targets, interactive and programmatic resizes, and
  /// auto-placement of new items (which falls back past the limit rather
  /// than losing data when the bounded area is full). Collision pushes are
  /// deliberately not truncated: rejecting a whole push cascade would need
  /// speculative simulation on every pointer event.
  @override
  late final maxRows = B.writable<int?>(null);

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
  late final fluidResize = B.writable<bool>(false);

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

  // --- LAYOUT HISTORY (UNDO / REDO) ---

  /// The transactional history stack, or null when the history is disabled.
  ///
  /// Recreated (never mutated in place) by [_rebuildHistory], because
  /// `UndoRedoBeacon.historyLimit` is `final`.
  ///
  /// INVARIANT: non-null exactly when [_historyEnabled] is true.
  UndoRedoBeacon<LayoutSnapshot>? _layoutHistory;

  int _maxHistoryLength = kDefaultMaxHistoryLength;

  /// Whether any history is kept at all.
  bool get _historyEnabled => _maxHistoryLength > 0;

  /// Mirror of `UndoRedoBeacon`'s private cursor and stack length.
  ///
  /// The beacon exposes `canUndo` / `canRedo` (plain, NON-reactive
  /// getters) and `history`, but not its index — so the entry an undo *would*
  /// restore cannot be read, and [onWillUndo] could not be handed a candidate
  /// layout without this mirror. Every mutation below reproduces the beacon's
  /// own bookkeeping step for step; [_syncHistoryFlags] asserts the two agree
  /// on every transition, so a divergence (e.g. after a `state_beacon`
  /// upgrade) fails a test instead of silently mis-restoring.
  ///
  /// Both are 0 while the history is disabled.
  int _historyIndex = 0;
  int _historyLength = 0;

  /// True while [undo] / [redo] is writing to [layout]; suppresses recording.
  bool _isRestoringHistory = false;

  /// True while an async veto hook is awaited; makes undo/redo non-reentrant.
  bool _historyOperationInFlight = false;

  late final _canUndoState = B.writable<bool>(false);
  late final _canRedoState = B.writable<bool>(false);

  @override
  ReadableBeacon<bool> get canUndo => _canUndoState;

  @override
  ReadableBeacon<bool> get canRedo => _canRedoState;

  @override
  int get maxHistoryLength => _maxHistoryLength;

  /// Number of entries currently on the stack (current state included).
  /// 0 when the history is disabled.
  @visibleForTesting
  int get debugHistoryLength => _historyLength;

  /// Position of the cursor on the stack, 0-based.
  @visibleForTesting
  int get debugHistoryIndex => _historyIndex;

  UndoRedoBeacon<LayoutSnapshot> _createHistoryBeacon(LayoutSnapshot seed) {
    return Beacon.undoRedo<LayoutSnapshot>(
      seed,
      historyLimit: _maxHistoryLength,
      name: 'DashboardLayoutHistory',
    );
  }

  /// An immutable snapshot of the live state.
  ///
  /// [updateItem] patches
  /// `_crossGridExitSnapshot` **in place**, and `finishCrossGridExit` can hand
  /// that very list back to [layout]. Storing the live instance would let a
  /// later mutation rewrite recorded history.
  LayoutSnapshot _snapshotNow() => (
        items: List<LayoutItem>.unmodifiable(layout.peek()),
        slotCount: slotCount.peek(),
      );

  static bool _layoutsEqual(List<LayoutItem> a, List<LayoutItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Notifies [onLayoutChanged] with an unmodifiable copy of the current layout.
  ///
  /// INVARIANT: Every emission of [onLayoutChanged] must pass through this method.
  /// Handing out an unmodifiable list prevents external listeners (persistence,
  /// sorting, debug logging) from corrupting the controller's internal layout state
  /// or breaking the ascending ID order invariant in place.
  void _notifyLayoutChanged([List<LayoutItem>? unmodifiableItems]) {
    final listener = onLayoutChanged;
    if (listener == null) return;
    listener(
      unmodifiableItems ?? List<LayoutItem>.unmodifiable(layout.value),
      slotCount.value,
    );
  }

  /// Records the live state as a new history entry.
  ///
  /// INVARIANT — transactional boundaries only. This is called exclusively at
  /// the end of a completed operation (`onDragEnd`, `onResizeEnd`, `addItems`,
  /// `removeItems`, `importLayout`, `optimizeLayout`, and
  /// `updateItem(recompact: true)` outside a gesture). It must NEVER be called
  /// from `onDragUpdate` / `onResizeUpdate`: at 60 Hz a two-second drag would
  /// push 120 full layout copies, blowing the stack away and allocating
  /// 120 x N `LayoutItem` references on the hot path.
  ///
  /// A transaction whose result is content-equal to the cursor entry records
  /// nothing. This is what keeps the very common "press, jiggle, drop where it
  /// started" gesture — and any compaction that turns out to be a no-op — from
  /// filling the stack with entries that undo to themselves.
  void _recordHistory() {
    // Zero-cost opt-out, deliberately the very first statement: with
    // `maxHistoryLength: 0` a transaction costs one integer comparison — no
    // `_layoutsEqual` scan over N items, no list copy, and no `LayoutItem`
    // (nor its `extra` map) retained past its own removal.
    if (_maxHistoryLength == 0) return;
    if (_isRestoringHistory) return;

    final history = _layoutHistory!;
    final current = history.peek();
    final liveItems = layout.peek();
    final liveSlots = slotCount.peek();
    if (current.slotCount == liveSlots && _layoutsEqual(current.items, liveItems)) {
      return;
    }

    history.value = (
      items: List<LayoutItem>.unmodifiable(liveItems),
      slotCount: liveSlots,
    );

    // Mirror `UndoRedoBeacon._addValueToHistory` + `_trimHistoryIfNeeded`.
    _historyIndex++;
    if (_historyIndex < _historyLength) {
      // A new transaction after an undo truncates the redo branch.
      _historyLength = _historyIndex;
    }
    _historyLength++;
    if (_historyLength > _maxHistoryLength) {
      _historyLength = _maxHistoryLength;
      _historyIndex = _maxHistoryLength - 1;
    }

    _syncHistoryFlags();
  }

  /// Publishes the non-reactive beacon getters onto our own beacons.
  void _syncHistoryFlags() {
    final history = _layoutHistory!;
    assert(
      history.history.length == _historyLength &&
          history.canUndo == (_historyIndex > 0) &&
          history.canRedo == (_historyIndex < _historyLength - 1),
      'Layout history bookkeeping desynchronised from UndoRedoBeacon '
      '(mirror: index=$_historyIndex length=$_historyLength, '
      'beacon: length=${history.history.length} '
      'canUndo=${history.canUndo} canRedo=${history.canRedo}).',
    );
    _canUndoState.value = history.canUndo;
    _canRedoState.value = history.canRedo;
  }

  /// Replaces the history beacon with one seeded from [entries].
  ///
  /// [entries] is the full retained stack, oldest first; its last element is
  /// the current state and becomes the cursor. Used by [clearHistory] and
  /// [setMaxHistoryLength] — `historyLimit` is `final` on `UndoRedoBeacon`, so
  /// there is no in-place path.
  void _rebuildHistory(List<LayoutSnapshot> entries) {
    assert(entries.isNotEmpty, 'History must retain at least the current state.');
    _layoutHistory?.dispose();
    final history = _layoutHistory = _createHistoryBeacon(entries.first);
    for (var i = 1; i < entries.length; i++) {
      history.value = entries[i];
    }
    _historyLength = entries.length;
    _historyIndex = entries.length - 1;
    _syncHistoryFlags();
  }

  @override
  void clearHistory() {
    if (!_historyEnabled) return;
    _rebuildHistory([_snapshotNow()]);
  }

  @override
  void setMaxHistoryLength(int length) {
    // A plain `assert` would leave the release-mode clamp permanently
    // unexecutable by any test.
    // Throwing makes both outcomes observable and the misuse loud.
    if (length < 0) {
      throw ArgumentError.value(
        length,
        'length',
        'maxHistoryLength must be >= 0 (0 disables the layout history)',
      );
    }
    if (length == _maxHistoryLength) return;

    final wasEnabled = _historyEnabled;
    _maxHistoryLength = length;

    if (length == 0) {
      // Disabling frees the stack and everything it retained. The flags are
      // published explicitly: an app watching them must see the transition,
      // not silently keep a `canUndo: true` button that no longer works.
      _layoutHistory?.dispose();
      _layoutHistory = null;
      _historyIndex = 0;
      _historyLength = 0;
      _canUndoState.value = false;
      _canRedoState.value = false;
      return;
    }

    if (!wasEnabled) {
      // Re-enabling starts a fresh stack seeded with the live layout. The
      // states that occurred while disabled were never recorded and cannot be
      // invented — this is a documented consequence, not an omission.
      _rebuildHistory([_snapshotNow()]);
      return;
    }

    // Keep the cursor entry plus as many predecessors as the new cap allows.
    // The redo branch is dropped: replaying it would need to re-seed a cursor
    // in the middle of the stack, which the beacon's API cannot express.
    final stack = _layoutHistory!.history;
    final end = _historyIndex + 1;
    final start = end - length < 0 ? 0 : end - length;
    _rebuildHistory(stack.sublist(start, end));
  }

  @override
  Future<bool> undo() => _travelHistory(isUndo: true);

  @override
  Future<bool> redo() => _travelHistory(isUndo: false);

  /// Shared undo/redo implementation. See [undo] for the contract.
  Future<bool> _travelHistory({required bool isUndo}) async {
    // An undo mid-gesture would fight `originalLayoutOnStart` — the
    // next `onDragUpdate` rebuilds `layout` from that snapshot and would erase
    // the restored state one frame later. Gestures are transactions; you can
    // only undo a committed one.
    final history = _layoutHistory;
    if (history == null) return false;
    if (_historyOperationInFlight) return false;
    if (_isDraggingState.peek() || isResizing.peek()) return false;
    if (isUndo ? !history.canUndo : !history.canRedo) return false;

    final targetIndex = isUndo ? _historyIndex - 1 : _historyIndex + 1;
    final candidate = history.history[targetIndex];

    final veto = isUndo ? onWillUndo : onWillRedo;
    if (veto != null) {
      final cursorAtEntry = _historyIndex;
      _historyOperationInFlight = true;
      final bool approved;
      try {
        approved = await veto(candidate.items);
      } finally {
        _historyOperationInFlight = false;
      }
      if (!approved) return false;

      // Awaiting yields control, so re-validate everything the decision was
      // based on rather than trusting it. Four things can have moved:
      //  1. a gesture may have started;
      //  2. the stack instance may have been swapped or dropped
      //     (`clearHistory`, `setMaxHistoryLength`, including a disable);
      //  3. the cursor may have moved (a transaction was recorded);
      //  4. AT CAPACITY, the stack contents may have shifted under an
      //     UNCHANGED cursor — a trim drops the oldest entry and pins the
      //     index at `_maxHistoryLength - 1`, so `targetIndex` silently points
      //     at a different snapshot. Comparing the entry itself is the only
      //     check that catches this one.
      if (_isDraggingState.peek() || isResizing.peek()) return false;
      final live = _layoutHistory;
      if (live == null || !identical(live, history)) return false;
      if (_historyIndex != cursorAtEntry) return false;
      if (live.history[targetIndex] != candidate) return false;
    }

    _isRestoringHistory = true;
    try {
      if (isUndo) {
        history.undo();
        _historyIndex--;
      } else {
        history.redo();
        _historyIndex++;
      }
      layout.value = _restoreSnapshot(history.peek());
    } finally {
      _isRestoringHistory = false;
    }

    _syncHistoryFlags();
    _pruneSelection();

    final unmodifiableItems = List<LayoutItem>.unmodifiable(layout.value);
    _notifyLayoutChanged(unmodifiableItems);
    (isUndo ? onUndo : onRedo)?.call(unmodifiableItems, slotCount.value);
    return true;
  }

  /// Projects [snapshot] onto the live grid.
  List<LayoutItem> _restoreSnapshot(LayoutSnapshot snapshot) {
    final cols = slotCount.peek();
    final items = List<LayoutItem>.from(snapshot.items);
    if (snapshot.slotCount == cols) {
      // Exact restoration — deliberately NOT recompacted. An undo must be the
      // exact inverse of the transaction it reverts; running the compactor
      // here would make undo -> redo -> undo drift away from the recorded
      // states.
      return items;
    }
    // `setSlotCount` archives the live layout under the count it is
    // leaving and REPLAYS that archive when the grid returns to a count it has
    // already visited. The entry for `snapshot.slotCount` was frozen before
    // this restoration, so without the write-through below the reverted
    // arrangement silently comes back the next time the window is resized to
    // that width — the undo appears to undo itself. Symmetric for redo.
    // The write is unconditional: a snapshot can only carry a count the grid
    // was actually at, and leaving a count always archives it, so the entry
    // exists in every flow reachable through `setSlotCount`. Creating one for
    // a count reached by writing `slotCount` directly is the correct outcome
    // too, which is why there is no `containsKey` guard to leave dead.
    _layoutsBySlotCount[snapshot.slotCount] = List<LayoutItem>.from(snapshot.items);

    // A breakpoint change happened since the snapshot was taken. Replaying it
    // verbatim would leave items outside the grid, so it is re-projected.
    return _compactor.resolveCollisions(
      engine.correctBounds(items, cols),
      cols,
    );
  }

  /// Drops selection ids that the restored layout no longer contains.
  ///
  /// Undoing an `addItem` deletes the item that is very likely still
  /// selected. A dangling id keeps `activeItemId` pointing at nothing, and the
  /// next `onDragStart` / `moveActiveItemBy` throws on `firstWhere`.
  void _pruneSelection() {
    final selected = selectedItemIds.peek();
    if (selected.isEmpty) return;
    final liveIds = <String>{for (final i in layout.peek()) i.id};
    if (selected.every(liveIds.contains)) return;
    selectedItemIds.value = {
      for (final id in selected)
        if (liveIds.contains(id)) id,
    };
  }

  /// Test-only hook to verify that [_syncHistoryFlags] throws when corrupted.
  @visibleForTesting
  void debugForceDesyncHistoryIndex(int index) {
    _historyIndex = index;
    _syncHistoryFlags();
  }

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

  /// Id of the tile currently rendered as a fluid-resize ghost, or null.
  ///
  /// **Coarse on purpose.** Every item shell watches this beacon to decide
  /// whether it must render as a hole, so it may only transition when a
  /// gesture starts or ends — never per pointer event. The per-event value is
  /// [resizeGhostRect], which only the overlay's ghost reads. This is the
  /// exact split `isDragging` / `dragOffset` already uses for drags.
  ///
  /// Non-null spans the whole preview, INCLUDING the settle animation that
  /// outlives [isResizing]: `ghost armed && !isResizing` IS the settle phase,
  /// which is why it needs no state of its own.
  late final resizeGhostId = B.writable<String?>(null);

  /// Raw, unsnapped pixel rect of the resizing tile, in grid-CONTENT pixels
  /// (no padding, no scroll — see [gridCellRect]).
  ///
  /// Null while [resizeGhostId] is armed but no pointer movement has been
  /// applied yet: the ghost then paints on the tile's own snapped rect, which
  /// is what makes the first frame of a resize a no-op visually.
  late final resizeGhostRect = B.writable<Rect?>(null);

  /// Arms or updates the fluid-resize ghost.
  ///
  /// Called by the controller on gesture start/update, and by the view once
  /// more at release to hand the frozen rect over to the settle animation.
  void setResizeGhost(String itemId, Rect? rect) {
    resizeGhostId.value = itemId;
    resizeGhostRect.value = rect;
  }

  /// Drops the fluid-resize ghost: the tile becomes visible again in the grid.
  ///
  /// Idempotent and allocation-free when no ghost is armed (both beacons
  /// dedupe on `==`), so callers on the pointer-up path need no guard.
  void clearResizeGhost() {
    resizeGhostId.value = null;
    resizeGhostRect.value = null;
  }

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
  void setFluidResize(bool value) {
    fluidResize.value = value;
    if (!value) clearResizeGhost();
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
        maxRows: maxRows.value,
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
    _notifyLayoutChanged();
  }

  @override
  void setCompactor(engine.CompactorDelegate compactor) {
    _compactor = compactor;
    // Note: We do not update the `compactionType` beacon here because custom
    // strategies might not map to the enum values.

    // Trigger an immediate re-layout using the new strategy.
    layout.value = _compactor.compact(layout.value, slotCount.value);
    _notifyLayoutChanged();
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
      maxRows: maxRows.value,
    );

    final compactorStrategy =
        overrideCompactType != null ? _getTempDelegate(overrideCompactType) : _compactor;

    layout.value = compactorStrategy.compact(
      placedLayout,
      slotCount.value,
    );

    _recordHistory();
    _notifyLayoutChanged();
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
    _recordHistory();
    _notifyLayoutChanged();

    clearSelection();
  }

  @override
  void updateItem(
    String itemId,
    LayoutItem Function(LayoutItem item) transform, {
    bool recompact = true,
  }) {
    // See replaceItem: geometry/flag changes on the ACTIVE pivot are not
    // propagated to the per-gesture caches. Changing a non-pivot item
    // mid-gesture is supported (that is what the snapshot write-through below
    // is for).
    assert(
      !(_isDraggingState.peek() || isResizing.peek()) || itemId != _pivotItemId,
      'updateItem: cannot transform the item of the active gesture '
      '("$itemId" is the current pivot).',
    );
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
    //
    // The check is bypassed during unit tests when debugBypassUpdateItemIdAssert is true
    // to allow coverage of the defensive ID restoration line below.
    assert(
      updated.id == itemId || debugBypassUpdateItemIdAssert,
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

    // Geometry changes are transactions; metadata-only ones (recompact: false)
    // are not. The distinction is load-bearing: the same-grid
    // `subGridDynamic` conversion flips `hasNestedGrid` through
    // `updateItem(recompact: false)` **mid-drag**, and recording there would
    // push a snapshot inside a live gesture. The gesture guard covers the
    // symmetric app-side case (`recompact: true` while a drag is in flight).
    if (recompact && !_isDraggingState.peek() && !isResizing.peek()) {
      _recordHistory();
    }

    _notifyLayoutChanged();
  }

  @override
  void replaceItem(String oldItemId, LayoutItem newItem) {
    // The per-gesture caches (_dragPivotOriginal, _dragClusterItems,
    // _dragOriginalBBox, _lastMovedPivot) are captured in onDragStart and are
    // NOT rewritten here. Replacing the pivot mid-gesture therefore leaves
    // them pointing at an id the layout no longer contains, and the next
    // onDragUpdate throws on `firstWhere`. Unreachable through the package's
    // own flows (every nest-host lookup excludes the dragged item), so this
    // documents the app-side contract rather than guarding a live path.
    assert(
      !(_isDraggingState.peek() || isResizing.peek()) || oldItemId != _pivotItemId,
      'replaceItem: cannot replace the item of the active gesture '
      '("$oldItemId" is the current pivot).',
    );

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
    _notifyLayoutChanged();
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

    _recordHistory();
    _notifyLayoutChanged();
  }

  @override
  void dispose() {
    _scrollToItemController.close().ignore();
    hoveredNestTargetId.dispose();
    // Not created through `B`, because [_rebuildHistory] swaps the instance
    // and the group would accumulate detached entries.
    _layoutHistory?.dispose();
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

  /// Sets [maxRows]. See the field for the exact enforcement points.
  @override
  void setMaxRows(int? value) {
    assert(value == null || value > 0, 'maxRows must be positive or null');
    if (maxRows.value == value) return;
    maxRows.value = value;
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
  void setDragMode(engine.DragMode mode) {
    dragMode.value = mode;
  }

  @override
  engine.DragMode getEffectiveDragMode({bool? modifierHeld}) {
    final held = modifierHeld ?? swapModifierHeld.peek();
    final base = dragMode.peek();
    if (!held) return base;
    return base == engine.DragMode.cascade ? engine.DragMode.swap : engine.DragMode.cascade;
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

    _notifyLayoutChanged();
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
    _lastDragMode = null;
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
    // Deliberately NOT compacted: removing items can never introduce an
    // overlap, so `remaining` is a valid layout as-is, and compacting here
    // shifts the source grid *while the pointer is still hovering targets
    // whose geometry depends on it* — a nested child grid inside a sibling
    // item, or sibling slivers below. Concrete failure: the dragged item sat
    // above its target's host, exit-compaction pulled the host up under the
    // pointer, the target escaped, the session flip-flopped ("the grid runs
    // away"). The hole is kept frozen for the whole session; compaction runs
    // once in [finishCrossGridExit] when the move is committed.
    layout.value = remaining;
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
        // The exit hole (see [beginCrossGridExit]) is only collapsed now
        // that the move is definitive.
        final current = layout.value;
        layout.value = compactionType.value == engine.CompactType.none
            ? _compactor.resolveCollisions(current, slotCount.value)
            : _compactor.compact(current, slotCount.value);
        _notifyLayoutChanged();
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

    _notifyLayoutChanged();
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
      final rowCap = maxRows.value;
      if (rowCap != null) {
        newH = newH.clamp(item.minH, max(item.minH, rowCap - item.y));
      }
    } else {
      newH = newH.clamp(1, slotCount.value);
      final rowCap = maxRows.value;
      if (rowCap != null) {
        newW = newW.clamp(item.minW, max(item.minW, rowCap - item.x));
      }
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
    _notifyLayoutChanged();
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

  /// Main-axis edge (exclusive) of every NON-dragged item, cached at drag
  /// start. When main-axis compaction is active, the drag target position is
  /// capped to this row/column: any deeper drop compacts straight back, so
  /// an uncapped target only makes the grid grow one row per row crossed —
  /// the sliver's extent then chases the pointer and anything below it
  /// (e.g. a sibling grid in the same scroll view) becomes unreachable.
  int _dragMaxMainOthers = 0;

  // --- View-published layout metrics (backchannel, plain fields) ---
  // Written by RenderSliverDashboard at the end of every performLayout and
  // read by DashboardMinimap on its scroll-driven rebuilds. Deliberately NOT
  // beacons: they are written during the layout phase, where notifying
  // listeners is illegal. Freshness is guaranteed by ordering: any scroll
  // tick relayouts the sliver before the minimap's AnimatedBuilder repaints.

  /// Scroll extent of every sliver before the grid (exact
  /// `precedingScrollExtent`), or null before the first layout.
  double? viewMainAxisLeadingExtent;

  /// The grid sliver's own scroll extent (exact `geometry.scrollExtent`),
  /// or null before the first layout.
  double? viewMainAxisContentExtent;

  /// Live slot width/height in pixels, or null before the first layout.
  double? viewSlotWidth;
  double? viewSlotHeight;

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
    _lastDragMode = null;

    // Snapshot layout for anti-drift
    originalLayoutOnStart.value = layout.value;

    // Cache the per-drag invariants once (see field docs).
    final snapshot = originalLayoutOnStart.value;
    final ids = selectedItemIds.value;
    _dragPivotOriginal = snapshot.firstWhere((i) => i.id == itemId);
    _dragClusterItems = snapshot.where((i) => ids.contains(i.id)).toList();
    _dragOriginalBBox = engine.calculateBoundingBox(_dragClusterItems);
    _lastMovedPivot = _dragPivotOriginal;

    final isVertical = scrollDirection.value == Axis.vertical;
    var maxMain = 0;
    for (final i in snapshot) {
      if (ids.contains(i.id)) continue;
      final edge = isVertical ? i.y + i.h : i.x + i.w;
      if (edge > maxMain) maxMain = edge;
    }
    _dragMaxMainOthers = maxMain;
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

    // 1. Calculate Pivot's new Grid Position.
    // Reason: the two spacings swap with the scroll direction (see
    // [gridCellRect]); using the vertical convention unconditionally shears
    // every horizontal drag by (mainAxisSpacing - crossAxisSpacing) * x.
    final strideX = slotWidth + (_isVerticalScroll ? crossAxisSpacing : mainAxisSpacing);
    final strideY = slotHeight + (_isVerticalScroll ? mainAxisSpacing : crossAxisSpacing);

    final newGridX = (contentPosition.dx / strideX).round();
    final newGridY = (contentPosition.dy / strideY).round();

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
    // Along the main axis, when main-axis compaction is active, cap the
    // target to the first free row/column past the other items
    // (_dragMaxMainOthers): dropping deeper compacts straight back, so the
    // uncapped value only grew the grid under the pointer indefinitely.
    // Free positioning (CompactType.none) and custom compactors keep the
    // unbounded behavior — placing an item at an arbitrary offset is a
    // feature there.
    final rowCap = maxRows.value;
    if (scrollDirection.value == Axis.vertical) {
      targetBBoxX = targetBBoxX.clamp(0, slotCount.value - originalBBox.w);
      targetBBoxY = max(0, targetBBoxY);
      if (compactionType.value == engine.CompactType.vertical) {
        targetBBoxY = min(targetBBoxY, _dragMaxMainOthers);
      }
      if (rowCap != null) {
        targetBBoxY = min(targetBBoxY, max(0, rowCap - originalBBox.h));
      }
    } else {
      targetBBoxX = max(0, targetBBoxX);
      targetBBoxY = targetBBoxY.clamp(0, slotCount.value - originalBBox.h);
      if (compactionType.value == engine.CompactType.horizontal) {
        targetBBoxX = min(targetBBoxX, _dragMaxMainOthers);
      }
      if (rowCap != null) {
        targetBBoxX = min(targetBBoxX, max(0, rowCap - originalBBox.w));
      }
    }

    // Boundary Bypass.
    // If the logical grid coordinates of the moving bounding box have not
    // changed, the background grid is mathematically identical: only update
    // the lightweight overlay dragOffset. The pivot's logical position is
    // cached from the last moveCluster result instead of an O(N) firstWhere.
    // Swap is restricted to single-item drags: a cluster has no single
    // meaningful partner, and the restriction is also what keeps the default
    // `Shift` modifier from colliding with Shift-built multi-selections.
    final effectiveMode =
        selectedItemIds.value.length == 1 ? getEffectiveDragMode() : engine.DragMode.cascade;

    // Boundary Bypass — keyed on the effective mode as well as the target
    // box, so a modifier flip with a stationary pointer is not swallowed.
    if (_lastBBoxX == targetBBoxX && _lastBBoxY == targetBBoxY && _lastDragMode == effectiveMode) {
      final movedPivot = _lastMovedPivot ?? pivotItem;
      final logicalItemPixelX = movedPivot.x * strideX;
      final logicalItemPixelY = movedPivot.y * strideY;

      dragOffset.value = Offset(
        contentPosition.dx - logicalItemPixelX,
        contentPosition.dy - logicalItemPixelY,
      );
      return;
    }

    _lastBBoxX = targetBBoxX;
    _lastBBoxY = targetBBoxY;
    _lastDragMode = effectiveMode;

    // 5. Move Cluster — or swap, when the mode asks for it AND the drop
    // qualifies. `swapElements` returns null on any frame with no valid
    // partner (empty space, a tile merely clipped, a static, a policy veto);
    // that frame falls back to the cascade so the drag never feels stuck.
    // Both paths recompute from `originalLayoutOnStart`, which is what makes
    // switching modes mid-gesture exact rather than incremental.
    final swapped = effectiveMode == engine.DragMode.swap
        ? engine.swapElements(
            originalLayoutOnStart.value,
            pivotItem,
            targetBBoxX,
            targetBBoxY,
            cols: slotCount.value,
            compactType: compactionType.value,
            policy: policy,
          )
        : null;

    final newLayout = swapped ??
        engine.moveCluster(
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

    final logicalItemPixelX = movedPivot.x * strideX;
    final logicalItemPixelY = movedPivot.y * strideY;

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
    _recordHistory();
    _notifyLayoutChanged();

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

    // Fluid preview: the tile leaves the grid (its slot becomes the
    // snap-target placeholder) and the overlay draws it at raw pixel size
    // from here on. The rect is deliberately left null until the first
    // update, so a press that never moves paints the tile exactly where it
    // already is.
    if (fluidResize.peek()) setResizeGhost(itemId, null);

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

    // Per-axis strides: spacings swap with scrollDirection (see [gridCellRect]).
    final axis = scrollDirection.peek();
    final isVertical = axis == Axis.vertical;
    final strideX = slotWidth + (isVertical ? crossAxisSpacing : mainAxisSpacing);
    final strideY = slotHeight + (isVertical ? mainAxisSpacing : crossAxisSpacing);

    final dW = delta.dx / strideX;
    final dH = delta.dy / strideY;

    // Continuous candidate, in FRACTIONAL slot units. The integer candidate is
    // literally its rounding, so the ghost and the slot it snaps to describe
    // the same gesture by construction — and every clamp below is applied to
    // both, so the ghost can never cross a barrier the placeholder respects.
    var fx = originalItem.x.toDouble();
    var fy = originalItem.y.toDouble();
    var fw = originalItem.w.toDouble();
    var fh = originalItem.h.toDouble();

    switch (handle) {
      case ResizeHandle.bottomRight:
        fw = originalItem.w + dW;
        fh = originalItem.h + dH;
      case ResizeHandle.bottomLeft:
        fw = originalItem.w - dW;
        fh = originalItem.h + dH;
        fx = originalItem.x + dW;
      case ResizeHandle.topRight:
        fw = originalItem.w + dW;
        fh = originalItem.h - dH;
        fy = originalItem.y + dH;
      case ResizeHandle.topLeft:
        fw = originalItem.w - dW;
        fh = originalItem.h - dH;
        fx = originalItem.x + dW;
        fy = originalItem.y + dH;
      case ResizeHandle.top:
        fh = originalItem.h - dH;
        fy = originalItem.y + dH;
      case ResizeHandle.bottom:
        fh = originalItem.h + dH;
      case ResizeHandle.left:
        fw = originalItem.w - dW;
        fx = originalItem.x + dW;
      case ResizeHandle.right:
        fw = originalItem.w + dW;
    }

    var newX = fx.round();
    var newY = fy.round();
    var newW = fw.round();
    var newH = fh.round();

    // Is this gesture painting a fluid ghost? Keyed on the ghost actually
    // armed for THIS item (armed in onResizeStart when `fluidResize` is on),
    // not on the flag, so toggling the feature mid-gesture cannot leave a
    // rect behind with no ghost to consume it.
    final fluid = resizeGhostId.peek() == itemId;

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
    if (fluid) {
      fw = fw.clamp(originalItem.minW.toDouble(), maxW.toDouble());
      fh = fh.clamp(originalItem.minH.toDouble(), maxH.toDouble());
    }

    // maxRows: block interactive growth past the main-axis cap. Anchored
    // resizes (top/left) never extend the far edge, so clamping the size
    // against the ORIGINAL near edge is exact.
    final rowCap = maxRows.value;
    if (rowCap != null) {
      if (isVertical && !isTopResize) {
        final cap = max(originalItem.minH, rowCap - originalItem.y);
        newH = newH.clamp(originalItem.minH, cap);
        if (fluid) fh = fh.clamp(originalItem.minH.toDouble(), cap.toDouble());
      } else if (!isVertical && !isLeftResize) {
        final cap = max(originalItem.minW, rowCap - originalItem.x);
        newW = newW.clamp(originalItem.minW, cap);
        if (fluid) fw = fw.clamp(originalItem.minW.toDouble(), cap.toDouble());
      }
    }

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
      if (fluid) {
        // Same anchor, same barriers, continuous. The barriers are resolved
        // once, against the snapped probe: an obstacle is an integer cell, and
        // sharing the probe is what keeps ghost and placeholder in agreement.
        fy = fy.clamp(minYClamp.toDouble(), maxYClamp.toDouble());
        fh = originalBottom - fy;
      }
    } else {
      // allows jumping/pushing obstacles below
      if (newY < 0) {
        newH += newY;
        newY = 0;
      }
      if (!isVertical) {
        if (newY + newH > slotCount.value) {
          newH = slotCount.value - newY;
        }
      }
      if (fluid) {
        if (fy < 0) {
          fh += fy;
          fy = 0;
        }
        if (!isVertical && fy + fh > slotCount.value) {
          fh = slotCount.value - fy;
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
      if (fluid) {
        fx = fx.clamp(minXClamp.toDouble(), maxXClamp.toDouble());
        fw = originalRight - fx;
      }
    } else {
      // allows jumping/pushing obstacles on the right
      if (newX < 0) {
        newW += newX;
        newX = 0;
      }
      if (isVertical) {
        if (newX + newW > slotCount.value) {
          newW = slotCount.value - newX;
        }
      }
      if (fluid) {
        if (fx < 0) {
          fw += fx;
          fx = 0;
        }
        if (isVertical && fx + fw > slotCount.value) {
          fw = slotCount.value - fx;
        }
      }
    }

    // Fluid preview, published on EVERY event — deliberately BEFORE the
    // boundary bypass below. The bypass exists to skip the engine call, which
    // is the only expensive part of this method; the ghost must keep tracking
    // the pointer inside a cell or it degrades to a cell-crossing cadence,
    // which is exactly the stutter this feature removes. Same shape as the
    // drag bypass, which also keeps writing `dragOffset`. One Rect allocated
    // per event, like the drag's Offset.
    if (fluid && strideX > 0 && strideY > 0) {
      resizeGhostRect.value = gridCellRect(
        x: fx,
        y: fy,
        w: fw,
        h: fh,
        slotWidth: slotWidth,
        slotHeight: slotHeight,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
        scrollDirection: axis,
      );
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
    _recordHistory();

    _notifyLayoutChanged();

    isResizing.value = false;
    // The ghost is dropped here, not left dangling: the view re-arms it for
    // the settle animation (with the frozen rect it peeked before this call)
    // only when a settle is actually configured. Any other caller — a11y, an
    // application ending a resize by hand — gets the tile back immediately.
    clearResizeGhost();
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
    clearResizeGhost();
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
    _recordHistory();
    _notifyLayoutChanged();
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
