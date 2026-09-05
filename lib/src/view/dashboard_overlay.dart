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
import 'package:sliver_dashboard/src/view/dashboard_lasso_layer.dart';
import 'package:sliver_dashboard/src/view/dashboard_typedefs.dart';
import 'package:sliver_dashboard/src/view/guidance/dashboard_guidance.dart';
import 'package:sliver_dashboard/src/view/nested/dashboard_nested_scope.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';
import 'package:sliver_dashboard/src/view/sliver_dashboard.dart';
import 'package:state_beacon/state_beacon.dart';

/// Internal flag to allow overriding kIsWeb during unit tests
/// to safely execute and cover the Web throttle mechanism.
@visibleForTesting
bool debugOverrideIsWeb = false;

/// Test hook: injectable time source for the pointer-throttle gate. When
/// null (production), real elapsed time from an internal [Stopwatch] is
/// used. Tests provide a controlled Duration so the gate is DETERMINISTIC:
/// the real clock made the throttle untestable — coverage instrumentation
/// and suite load stretch the delay between two synthetic pointer events
/// past the 16 ms window, flipping the observed behavior between isolated
/// and full-suite runs.
@visibleForTesting
Duration Function()? debugThrottleClock;

/// Internal flag to allow bypassing the clone-id assertion during unit
/// tests, so the defensive release-mode path (reject the duplicate id and
/// fall back to a plain move) is reachable and covered.
@visibleForTesting
bool debugBypassCloneIdAssert = false;

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

  /// Deletion veto callback.
  DashboardWillDeleteCallback? get onWillDelete => null;

  /// Deletion commit callback.
  DashboardItemsDeletedCallback? get onItemsDeleted => null;

  /// Clone callback.
  DashboardCloneRequestCallback? get onCloneRequested => null;
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
    this.onSlotTap,
    this.onSlotLongPress,
    this.onItemDroppedOnHost,
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
    this.resizeSettleDuration = const Duration(milliseconds: 120),
    this.placeholderWidth = 1,
    this.placeholderHeight = 1,
    this.externalTemplateBuilder,
    this.onDrop,
    this.itemGlobalKeySuffix = '',
    this.backgroundBuilder,
    this.fillViewport = false,
    this.dragStartGesture = DragStartGesture.longPress,
    this.crossGridDragOut = true,
    this.acceptCrossGridItems = true,
    this.onCloneRequested,
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

  /// Called when the user taps an EMPTY slot of this grid (no item under the
  /// pointer). Receives the tapped grid coordinates. Fires only for taps
  /// inside this grid's own sliver bounds, so several grids sharing a scroll
  /// view never cross-fire; with `fillViewport: true` (the single-grid
  /// default) the bounds include the empty area below the content. Costs
  /// nothing outside the tap event itself.
  final void Function(int x, int y)? onSlotTap;

  /// Long-press variant of [onSlotTap]. On mobile with
  /// [DragStartGesture.longPress], long-pressing an ITEM still starts a
  /// drag: only empty-slot long-presses reach this callback.
  final void Function(int x, int y)? onSlotLongPress;

  /// Fired when dragged items are released over a DROP TARGET tile: an item
  /// flagged [LayoutItem.isDropTarget], or a nested host whose child grid is
  /// not mounted (a "closed folder").
  ///
  /// While such a tile is hovered, layout pushes freeze so it stays under
  /// the cursor and it takes the nest highlight; on release the drag is
  /// cancelled — the layout returns to its pre-drag state, so nothing lands
  /// on the parent grid — and this callback runs. The app owns the outcome
  /// (consume the items with `removeItems`, reject the drop by doing
  /// nothing, …). Targeting is by POINTER position, so the dragged item may
  /// be larger than the target.
  ///
  /// Handles same-grid drags; drags coming from ANOTHER grid (including a
  /// nested one) are routed by the coordinator to the scope-wide callback.
  /// Falls back to `DashboardNestedScope.onItemDroppedOnHost` when null.
  /// Zero cost per pointer move while both are null.
  final DashboardItemDroppedOnHostCallback? onItemDroppedOnHost;

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

  /// How long a fluid-resize ghost takes to settle into its snapped slot
  /// after the pointer is released.
  ///
  /// [Duration.zero] releases without any animation (the ghost is dropped on
  /// the same frame). Ignored entirely when `fluidResize` is off.
  final Duration resizeSettleDuration;

  /// The width of the placeholder item in grid units when dragging from outside.
  final int placeholderWidth;

  /// The height of the placeholder item in grid units when dragging from outside.
  final int placeholderHeight;

  /// Optional builder to resolve the template [LayoutItem] for an external draggable payload of type [T].
  ///
  /// When provided and returning non-null, its width and height size the hover
  /// placeholder, and its constraints/flags/extra seed the item upon drop.
  /// If null or returning null, falls back to [placeholderWidth] and [placeholderHeight].
  final DashboardExternalTemplateBuilder<T>? externalTemplateBuilder;

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

  /// Produces the duplicate of a tile dragged with the clone modifier held
  /// (`Alt` / `Option` by default, see `DashboardShortcuts.cloneKeys`).
  ///
  /// **The feature is off until this callback is registered**: with no
  /// callback the modifier is ignored entirely and an Alt+drag is a plain
  /// move. There is no "default clone" — only the application can mint an id
  /// and decide what duplicating one of its widgets means.
  ///
  /// Sequence: the modifier is read once, at pointer-down, on the tile under
  /// the cursor. Nothing happens yet — a plain Alt+CLICK never duplicates
  /// anything. On the first pointer movement past the drag threshold the
  /// callback runs, the returned item is inserted at the source's own
  /// coordinates, and the drag session starts **on the clone**, leaving the
  /// source where it was. Returning `null` cancels the duplication and the
  /// gesture degrades to a plain move of the source.
  ///
  /// Ignored for resize gestures (the modifier only affects a body drag),
  /// for static items and section barriers (never draggable), and while a
  /// multi-selection modifier is also held.
  ///
  /// Falls back to `DashboardNestedScope.onCloneRequested` when null, so a
  /// tree of nested grids can register one handler and branch on the `grid`
  /// argument. Costs one null check per pointer-down while both are null.
  final DashboardCloneRequestCallback? onCloneRequested;

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

  // Id of the drop-target tile currently hovered (closed nested host or
  // isDropTarget item). Non-null means the layout is frozen and the release
  // resolves as onItemDroppedOnHost instead of a grid placement.
  String? _dropTargetHostId;

  /// Overlay-level callback, falling back to the scope-wide one.
  DashboardItemDroppedOnHostCallback? get _dropOnHostCallback =>
      widget.onItemDroppedOnHost ?? _nestedCoordinator?.onItemDroppedOnHost;

  /// Overlay-level clone callback, falling back to the scope-wide one.
  ///
  /// Null when the feature is not configured, which is the single check that
  /// keeps Alt+drag free for every existing setup.
  DashboardCloneRequestCallback? get _cloneCallback =>
      widget.onCloneRequested ?? _nestedCoordinator?.onCloneRequested;

  /// Source tile of a PENDING Alt+drag clone: the clone modifier was held at
  /// pointer-down over this tile, but the pointer has not yet travelled far
  /// enough for the gesture to be a drag, so nothing has been inserted and no
  /// drag session exists yet.
  ///
  /// The duplication cannot happen at pointer-down. `_onPointerDown`
  /// fires on the raw button press (no threshold), so inserting there would
  /// make a plain Alt+CLICK silently duplicate a tile and push a history
  /// entry. Deferring to the first real move also means the clone is created
  /// exactly once, before `onDragStart`, so the drag pivot is the clone from
  /// the very first frame and is never swapped mid-gesture (see the
  /// "Active Pivot Is Immutable Mid-Gesture" invariant).
  ///
  /// Resolved by [_resolvePendingClone] on the first qualifying move, and
  /// dropped by [_resetOperationState] / [_handleMobileTap] otherwise.
  LayoutItem? _pendingCloneSource;

  /// Movement, in logical pixels, past which a pointer-down is treated as a
  /// drag rather than a click. Shared by the deferred-clone resolution and
  /// the deferred multi-selection clear so the two agree on what a "click"
  /// is.
  static const double _dragMoveTolerance = 2;

  /// Sub-pixel tolerance below which a fluid-resize ghost is considered to be
  /// already sitting on its snapped slot, so no settle animation is armed.
  static const double _settleEpsilon = 0.5;

  // ===========================================================================
  // Rubberband ("lasso") selection — desktop / web only
  // ===========================================================================

  /// A press on empty grid space that COULD become a lasso, but has not
  /// travelled far enough yet.
  ///
  /// Two-phase for the same reason the Alt+drag clone is (see
  /// [_pendingCloneSource]): `_onPointerDown` fires on the raw button press,
  /// so committing here would turn every click on the background into a
  /// selection wipe. Resolved by [_startLasso] on the first move past
  /// [_dragMoveTolerance]; dropped by [_clearLassoState] otherwise.
  ///
  /// Carries the anchor **already resolved into content space** rather than
  /// just the global position. Arming has to resolve it anyway to know the
  /// press is over a live grid, so re-deriving it at start duplicated a
  /// `_gridPointAtGlobal` call (one `SlotMetrics` allocation) and introduced
  /// a failure branch that could not happen. It is also the more correct
  /// anchor: it pins the rectangle to the cell that was under the cursor when
  /// the button went down, even if the wheel scrolled the grid before the
  /// gesture crossed the threshold.
  ({Offset global, Offset content, SlotMetrics metrics})? _pendingLasso;

  /// Anchor corner of a LIVE lasso, in **grid-content pixels** (the space
  /// [_gridPointAtGlobal] returns). Non-null exactly while a lasso is in
  /// flight, and the single predicate every lasso branch tests.
  ///
  /// Content space — not overlay-local, not global — is what makes the
  /// rectangle survive a scroll: the anchor stays pinned to the grid while
  /// the content moves under it (edge auto-scroll, mouse wheel).
  Offset? _lassoAnchorContent;

  /// Selection the lasso started from, and therefore preserves. Empty for a
  /// replacing lasso, which is the default; populated only when an additive
  /// modifier was held at the press (see [_startLasso]).
  Set<String> _lassoBaseSelection = const <String>{};

  /// Reusable scratch buffer for the per-event intersection pass. Reused so
  /// the O(N) scan allocates nothing on a frame that does not change the
  /// selection — which is the overwhelming majority of them.
  final List<String> _lassoHitScratch = <String>[];

  /// Ids the previous intersection pass produced. The selection beacon is
  /// written ONLY when this set changes: `Set` has identity equality in
  /// Dart, so an unguarded write would notify on every pointer event and
  /// rebuild every item shell at pointer frequency.
  Set<String> _lastLassoHits = const <String>{};

  /// The painted rectangle. A plain [ValueNotifier] rather than a beacon:
  /// nothing outside this widget consumes it, and it must not participate in
  /// the controller's reactive graph (a lasso is a view-layer gesture).
  final ValueNotifier<LassoOverlayState?> _lassoOverlay = ValueNotifier<LassoOverlayState?>(null);

  /// The scroll controller [_onScrollDuringLasso] is registered on, kept
  /// explicitly so a `didUpdateWidget` swapping the controller cannot strand
  /// the listener on the old one.
  ScrollController? _lassoScrollListenerTarget;

  /// Effective guidance, falling back to the built-in English messages.
  ///
  /// Screen-reader announcements are NOT opt-in ("accessible out of the
  /// box"): `guidance == null` disables the visual tooltip and the cursor
  /// change, never the announcements.
  DashboardGuidance get _effectiveGuidance =>
      widget.controller.guidance ?? DashboardGuidance.byDefault;

  /// Effective shortcuts, falling back to the defaults.
  DashboardShortcuts get _effectiveShortcuts =>
      widget.controller.shortcuts ?? DashboardShortcuts.defaultShortcuts;

  /// Rubberband policy and appearance.
  LassoStyle get _lassoStyle => widget.controller.lassoStyle;

  /// Whether one of [DashboardShortcuts.lassoModifier] is held right now.
  bool get _isLassoModifierHeld => _anyHeld(_effectiveShortcuts.lassoModifier);

  /// Whether one of [DashboardShortcuts.swapModeModifier] is held right now.
  ///
  /// An empty list means "no modifier configured", which yields `false` and
  /// leaves `DashboardController.dragMode` in sole control.
  bool get _isSwapModifierHeld => _anyHeld(_effectiveShortcuts.swapModeModifier);

  static bool _anyHeld(List<LogicalKeyboardKey> keys) {
    if (keys.isEmpty) return false;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    for (var i = 0; i < keys.length; i++) {
      if (pressed.contains(keys[i])) return true;
    }
    return false;
  }

  /// The drop-target tile under [globalPosition], or null.
  ///
  /// Returns null immediately when no callback is registered, which is what
  /// keeps the feature free for every existing setup.
  LayoutItem? _dropTargetAt(Offset globalPosition) {
    if (_dropOnHostCallback == null) return null;
    if (_ownsCrossGridSession || _activeResizeHandle != null) return null;
    // Pausing over the trash is a delete intent, not a drop intent.
    if (_isHoveringTrash.peek()) return null;
    final snapshot = widget.controller.internal.dragOriginSnapshot;
    if (snapshot == null) return null;
    final host = _itemAtGlobalIn(snapshot, globalPosition, excludeId: _activeItemId);
    if (host == null || host.isSectionBarrier) return null;
    // Never target a member of the dragged cluster.
    if (widget.controller.selectedItemIds.value.contains(host.id)) return null;
    // A MOUNTED child grid owns the interaction: the pointer must be able to
    // enter it for a real cross-grid drop. Only closed hosts are targets.
    if (_nestedCoordinator?.hasChildGrid(widget.controller, host.id) ?? false) {
      return null;
    }
    if (!host.isDropTarget && !host.hasNestedGrid) return null;
    // Statics ARE allowed here (unlike the nest-arming path): an immovable
    // archive tile is a legitimate target, and it needs no freeze to stay
    // under the cursor.
    return host;
  }

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

  /// Set for exactly one pointer-up: the fluid ghost was handed to the settle
  /// animation and must survive [_resetOperationState].
  bool _resizeSettleArmed = false;

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
  Duration _lastThrottleFlush = Duration.zero;
  Duration get _throttleNow => debugThrottleClock?.call() ?? _throttleStopwatch.elapsed;
  Offset? _pendingThrottledPosition;
  Timer? _throttleFlushScheduled;

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  DashboardWillDeleteCallback? get onWillDelete => widget.onWillDelete;

  @override
  DashboardItemsDeletedCallback? get onItemsDeleted => widget.onItemsDeleted;

  @override
  DashboardCloneRequestCallback? get onCloneRequested => _cloneCallback;

  @override
  void startDragging(String itemId, Offset globalPosition) {
    if (!widget.controller.isEditing.value) return;
    _onPointerDown(globalPosition);
  }

  @override
  void initState() {
    super.initState();
    _setupScrollListener();
    // Desktop / web only: the lasso cursor must react to a modifier press
    // that arrives WITHOUT any pointer movement, and key state changes emit
    // no pointer event. Two Set lookups per key event; never registered on
    // Android / iOS, where the lasso does not exist.
    if (!_isMobile) {
      HardwareKeyboard.instance.addHandler(_handleModifierKey);
    }
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
      itemStart = item.y * (metrics.slotHeight + metrics.mainAxisSpacing);
      itemSize = item.h * (metrics.slotHeight + metrics.mainAxisSpacing) - metrics.mainAxisSpacing;
    } else {
      itemStart = item.x * (metrics.slotWidth + metrics.mainAxisSpacing);
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
    if (!_isMobile) {
      HardwareKeyboard.instance.removeHandler(_handleModifierKey);
    }
    _detachLassoScrollListener();
    _lassoOverlay.dispose();
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
            _updatePlaceholderPosition(details.offset, details.data);
            return true;
          },
          onMove: (details) {
            _lastGlobalPosition = details.offset;
            _updatePlaceholderPosition(details.offset, details.data);
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
                final template = widget.externalTemplateBuilder?.call(details.data);
                if (template != null) {
                  widget.controller.internal.onDropExternalItem(
                    template: template.copyWith(
                      id: newId,
                      x: placeholder.x,
                      y: placeholder.y,
                    ),
                  );
                } else {
                  widget.controller.internal.onDropExternal(newId: newId);
                }
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
                      sliverKey: widget.sliverKey,
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
                    child: _buildLassoCursorRegion(_buildGestureContent()),
                  ),
                ),

                // 3. Rubberband selection rectangle.
                // Above the content so it is visible, below the drag
                // feedback so a cross-grid proxy is never hidden by it, and
                // pointer-transparent (the layer wraps itself in an
                // IgnorePointer). Driven by a ValueNotifier, so a lasso drag
                // rebuilds this subtree and nothing else.
                Positioned.fill(
                  child: DashboardLassoLayer(state: _lassoOverlay),
                ),

                // 4. Feedback & Trash
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

  /// The interactive grid content: the gesture layer and the caller's
  /// scroll view.
  ///
  /// Extracted so [_buildLassoCursorRegion] can hand it through as a
  /// pre-built `child`, which is what keeps a modifier press from rebuilding
  /// the scroll view.
  Widget _buildGestureContent() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: widget.onSlotTap != null
          ? (details) => _handleSlotGesture(
                details.globalPosition,
                widget.onSlotTap,
              )
          : null,
      onLongPressStart: (_isMobile && widget.dragStartGesture == DragStartGesture.longPress) ||
              widget.onSlotLongPress != null
          ? (details) {
              if (_nestedCoordinator?.isPointerClaimedByOther(this) ?? false) {
                return;
              }

              // Empty-slot long-press wins; item long-press
              // keeps its historical role (drag start on
              // mobile longPress mode).
              if (widget.onSlotLongPress != null && _hitTest(details.globalPosition).item == null) {
                _handleSlotGesture(
                  details.globalPosition,
                  widget.onSlotLongPress,
                );
                return;
              }
              if (_isMobile && widget.dragStartGesture == DragStartGesture.longPress) {
                _onPointerDown(details.globalPosition);
              }
            }
          : null,
      onLongPressMoveUpdate: _isMobile && widget.dragStartGesture == DragStartGesture.longPress
          ? (details) => _onPointerMove(details.globalPosition)
          : null,
      onLongPressEnd: _isMobile && widget.dragStartGesture == DragStartGesture.longPress
          ? (details) => _onPointerUp()
          : null,
      onLongPressCancel:
          _isMobile && widget.dragStartGesture == DragStartGesture.longPress ? _onPointerUp : null,
      child: widget.child,
    );
  }

  /// Wraps the grid content in the [MouseRegion] carrying the lasso cursor.
  ///
  /// The region is deliberately an ANCESTOR of the item shells: Flutter
  /// resolves the cursor from the innermost non-deferring `MouseRegion` on
  /// the hit path, so an item's own cursor (grab, resize) wins by
  /// construction and this one only ever surfaces over empty grid space.
  /// That is what makes "lasso cursor over empty space" cost zero hit tests
  /// and zero per-hover work.
  ///
  /// [child] is built once by the caller and passed straight through, so a
  /// modifier press rebuilds this `MouseRegion` and nothing under it
  /// (`Element.updateChild` short-circuits on an identical widget instance).
  Widget _buildLassoCursorRegion(Widget child) {
    return Builder(
      builder: (context) {
        final isEditing = widget.controller.isEditing.watch(context);
        final modifierDown = widget.controller.lassoModifierHeld.watch(context);
        return MouseRegion(
          cursor: _lassoCursor(
            isEditing: isEditing,
            modifierDown: modifierDown,
          ),
          child: child,
        );
      },
    );
  }

  /// Resolves an empty-slot gesture: converts the position to grid
  /// coordinates through the same [SlotMetrics] math the drag pipeline
  /// uses, and fires [callback] when the tap landed on this grid but on no
  /// item.
  void _handleSlotGesture(
    Offset globalPosition,
    void Function(int x, int y)? callback,
  ) {
    if (callback == null) return;
    if (_hitTest(globalPosition).item != null) return;
    final renderSliver = _findRenderSliver();
    if (renderSliver == null || !renderSliver.attached) return;
    // Containment: strict sliver bounds keep several grids sharing one
    // scroll view from cross-firing. fillViewport declares that this grid
    // visually owns the remaining viewport (single-grid usage — the visual
    // filler would overlap following slivers in a multi-sliver tree
    // anyway), so the below-content area is tappable there; the x-range and
    // y >= 0 gates below still reject taps outside the grid's band.
    if (!widget.fillViewport && !isPointInsideSliver(globalPosition)) return;

    final overlayBox = context.findRenderObject();
    if (overlayBox is! RenderBox) return;
    final localPosition = overlayBox.globalToLocal(globalPosition);
    final metrics = _getMetricsFromSliver(renderSliver);
    final viewportScroll =
        widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;
    // pixelToGrid subtracts padding.top itself; precedingScrollExtent
    // already contains the SliverPadding's top extent, so re-add it once.
    // For a single grid this reduces to the plain scroll offset.
    final effectiveOffset =
        viewportScroll - renderSliver.constraints.precedingScrollExtent + metrics.padding.top;
    final g = metrics.pixelToGrid(localPosition, effectiveOffset);
    if (g.x < 0 || g.x >= metrics.slotCount || g.y < 0) return;
    // maxRows: the surface past the cap is not a valid slot — without this
    // gate, a tap on the trailing edit row (or below) handed the app
    // coordinates it would naturally turn into an out-of-cap add.
    final rowCap = widget.controller.maxRows.value;
    if (rowCap != null) {
      final mainCoord = metrics.scrollDirection == Axis.vertical ? g.y : g.x;
      if (mainCoord >= rowCap) return;
    }
    callback(g.x, g.y);
  }

  /// Handles simple tap on Mobile to toggle selection.
  void _handleMobileTap(Offset globalPosition) {
    // This branch deliberately bypasses _onPointerUp, so an armed clone that
    // never became a drag has to be released HERE — including the pointer
    // claim taken at pointer-down. Leaking that claim would lock every
    // ancestor grid out of dragging, permanently, after a single tap.
    if (_pendingCloneSource != null) {
      _pendingCloneSource = null;
      _nestedCoordinator?.releasePointer(this);
    }

    // Same bypass hazard, one gesture further: with DragStartGesture.tap a
    // press on a handle opens a resize in `_onPointerDown`, and a release
    // that never moved lands HERE instead of in `_onPointerUp`. Left alone it
    // latches `isResizing` — and, once a fluid preview is on, hides the tile
    // behind a ghost nothing will ever clear. A tap resized nothing, so the
    // interaction is cancelled rather than committed.
    if (_activeResizeHandle != null) {
      widget.controller.internal.cancelInteraction();
      _resetOperationState();
    }

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
        // Fluid resize: the ghost lives in this same layer, so both gestures
        // resolve their origin through [_contentOriginOf] and neither
        // re-derives the transform. A drag always wins — a settling ghost can
        // still be armed for a few frames when the next gesture starts.
        final resizeGhostId = widget.controller.internal.resizeGhostId.watch(context);
        if (!isDragging) {
          if (resizeGhostId == null) return const SizedBox.shrink();
          return _buildResizeGhost(context, resizeGhostId);
        }

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

        final frame = _resolveFeedbackFrame();

        if (pivotItem == null || clusterItems.isEmpty || frame == null) {
          return const SizedBox.shrink();
        }

        final isEditing = widget.controller.isEditing.watch(context);
        final metrics = frame.metrics;
        final currentSliverStart = frame.sliverStart;
        final sliverBounds = frame.bounds;

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

  /// The single overlay-copy of the item being resized, drawn at the raw
  /// pixel rect the controller publishes (or animating into its snapped slot
  /// once the pointer is up).
  ///
  /// The tile itself is hidden in the grid, so its slot reads as the
  /// snap-target placeholder — same three-part composition as a drag.
  Widget _buildResizeGhost(BuildContext context, String ghostId) {
    final item = widget.controller.layout.value.firstWhereOrNull((i) => i.id == ghostId);
    final frame = _resolveFeedbackFrame();
    if (item == null || frame == null) return const SizedBox.shrink();

    // The settle phase is DERIVED, not stored: a ghost still armed while the
    // resize is over is one that has been handed to the animation.
    final isResizing = widget.controller.internal.isResizing.watch(context);
    final isEditing = widget.controller.isEditing.watch(context);

    return DashboardFeedbackItem(
      key: ValueKey('resize_ghost_$ghostId'),
      item: item,
      itemBuilder: widget.itemBuilder,
      itemLayoutBuilder: widget.itemLayoutBuilder,
      itemBreakpointBuilder: widget.itemBreakpointBuilder,
      breakpointResolver: widget.breakpointResolver,
      feedbackBuilder: widget.itemFeedbackBuilder,
      controller: widget.controller,
      slotWidth: frame.metrics.slotWidth,
      slotHeight: frame.metrics.slotHeight,
      mainAxisSpacing: frame.metrics.mainAxisSpacing,
      crossAxisSpacing: frame.metrics.crossAxisSpacing,
      scrollDirection: frame.metrics.scrollDirection,
      itemGlobalKeySuffix: widget.itemGlobalKeySuffix,
      isEditing: isEditing,
      sliverStartPos: frame.sliverStart,
      sliverBounds: frame.bounds,
      itemStyle: widget.itemStyle,
      isResizeGhost: true,
      isSettling: !isResizing,
      settleDuration: widget.resizeSettleDuration,
      onSettleEnd: _onResizeSettleEnd,
    );
  }

  /// Live sliver, its metrics and the content origin, or null while any of
  /// the three is momentarily unavailable (mount frame, detached sliver).
  ///
  /// Extracted so the drag feedback and the resize ghost cannot drift apart:
  /// one lookup, one metrics refresh, one call to [_contentOriginOf].
  ({SlotMetrics metrics, Offset sliverStart, Rect? bounds})? _resolveFeedbackFrame() {
    final renderSliver = _findRenderSliver();
    if (renderSliver != null) {
      _activeSliverMetrics = _getMetricsFromSliver(renderSliver);
    }

    final metrics = _activeSliverMetrics;
    if (metrics == null || renderSliver == null || !renderSliver.attached) return null;

    final origin = _contentOriginOf(renderSliver, metrics);
    return (metrics: metrics, sliverStart: origin.sliverStart, bounds: origin.bounds);
  }

  /// Drops the ghost once its settle animation has landed on the snapped slot.
  void _onResizeSettleEnd() => widget.controller.internal.clearResizeGhost();

  /// Hands the frozen raw rect over to the settle animation, re-arming the
  /// ghost that `onResizeEnd` just dropped.
  ///
  /// Skipped — tile back on the same frame — whenever there is nothing to
  /// animate: no fluid preview ([from] null), no settle configured, or a raw
  /// rect already coincident with the slot the item landed in. The last case
  /// is not an optimisation: the animation is what clears the ghost, and an
  /// implicit animation with equal endpoints never reports an end, so arming
  /// it there would hide the tile forever.
  void _armResizeSettle(LayoutItem settled, Rect? from, SlotMetrics? metrics) {
    if (from == null || metrics == null || widget.resizeSettleDuration <= Duration.zero) return;

    final target = metrics.cellRect(settled.x, settled.y, settled.w, settled.h);
    if ((target.left - from.left).abs() < _settleEpsilon &&
        (target.top - from.top).abs() < _settleEpsilon &&
        (target.width - from.width).abs() < _settleEpsilon &&
        (target.height - from.height).abs() < _settleEpsilon) {
      return;
    }

    widget.controller.internal.setResizeGhost(settled.id, from);
    _resizeSettleArmed = true;
  }

  /// Resolves where this grid's content origin currently sits in
  /// overlay-local pixels, together with the visible band of its sliver.
  ///
  /// Single implementation of the **Content-Origin Convention** for the
  /// layers painted on top of the scroll view (drag feedback, rubberband
  /// selection): the main-axis origin is
  /// `precedingScrollExtent - scrollOffset` and the main-axis padding must
  /// NEVER be added on top of it (the `SliverPadding` already forwarded it);
  /// the cross-axis padding is not part of the scroll extent and IS added
  /// manually. Any new layer reuses this rather than re-deriving the
  /// transform — the two sites that once re-derived it both double-counted
  /// the leading padding, an error of exactly zero pixels on the
  /// padding-free grids the suite used to exercise.
  ///
  /// `bounds` is null only while the overlay's Stack has no render object,
  /// which happens for one frame at mount; callers then simply do not clip.
  ({Offset sliverStart, Rect? bounds}) _contentOriginOf(
    RenderSliverDashboard renderSliver,
    SlotMetrics metrics,
  ) {
    final isVertical = metrics.scrollDirection == Axis.vertical;
    final sliverLayoutStart = renderSliver.constraints.precedingScrollExtent;
    final scrollOffset = widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;
    final visualStart = sliverLayoutStart - scrollOffset;

    final sliverStart = isVertical
        ? Offset(metrics.padding.left, visualStart)
        : Offset(visualStart, metrics.padding.top);

    final overlayBox = _overlayStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null) return (sliverStart: sliverStart, bounds: null);

    final overlaySize = overlayBox.size;
    final clipStart = max(visualStart, renderSliver.constraints.overlap);
    final raw = isVertical
        ? Rect.fromLTRB(0, clipStart, overlaySize.width, overlaySize.height)
        : Rect.fromLTRB(clipStart, 0, overlaySize.width, overlaySize.height);

    return (
      sliverStart: sliverStart,
      bounds: raw.intersect(Offset.zero & overlaySize),
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
      // In multi-sliver environments, resolve the exact targeted render object
      // by searching strictly within the localized subtree of the sliver's
      // GlobalKey.
      //
      // Reason — NO fallback to the unscoped walk below once a key was given.
      // The key's context can be null for a frame (mount, remount, GlobalKey
      // move), and the unscoped walk would then return a SIBLING grid's sliver.
      // That reference is attached, so the cache guard above would keep it
      // forever: `_hitTest` would stop matching this grid's own items
      // (`identical(parent, ownSliver)` never true, hence no drag at all) and
      // `_isInsideSliver` would report another grid's bounds. Returning null for
      // one frame is recoverable — every caller null-checks — latching a foreign
      // sliver is not.
      final rootObject = key.currentContext?.findRenderObject();
      if (rootObject is RenderSliverDashboard) {
        found = rootObject;
      } else {
        rootObject?.visitChildren(visitor);
      }
      _renderSliver = found;
      return found;
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

    // A new press always supersedes a clone or a lasso armed by a previous
    // one — and a fluid-resize ghost still settling, which would otherwise
    // keep its tile hidden underneath the new gesture for up to one settle
    // duration. Both writes dedupe when no ghost is armed.
    _pendingCloneSource = null;
    _pendingLasso = null;
    widget.controller.internal.clearResizeGhost();

    final hit = _hitTest(position);
    final foundItem = hit.item;
    final itemRenderBox = hit.itemRenderBox;
    final renderSliver = hit.renderSliver;

    if (foundItem != null && itemRenderBox != null && renderSliver != null) {
      // Prevent dragging static items, unless the item is an interactive section barrier
      if (foundItem.isStatic && !foundItem.isSectionBarrier) return;

      final shortcuts = widget.controller.shortcuts ?? DashboardShortcuts.defaultShortcuts;
      final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;
      final isMultiSelect = shortcuts.multiSelectKeys.any(pressedKeys.contains);
      final isAlreadySelected = widget.controller.selectedItemIds.peek().contains(foundItem.id);
      _shouldClearSelectionOnUp = false;

      // GESTURE KIND
      // Resolved BEFORE the selection logic, because the clone modifier must
      // only ever arm a body drag. Reading the handle here (it used to be
      // computed further down) is what keeps Alt + drag-from-an-edge a plain
      // resize instead of duplicating the tile and resizing the duplicate.
      final itemLocalPosition = itemRenderBox.globalToLocal(position);

      final handle = calculateResizeHandle(
        localPosition: itemLocalPosition,
        size: itemRenderBox.size,
        handleSide: widget.resizeHandleSide,
        isResizable: foundItem.isResizable ?? true,
      );

      // ALT + DRAG CLONING (arming only)
      // The duplicate is NOT created here: `_onPointerDown` fires on the raw
      // button press, so inserting now would make a plain Alt+click duplicate
      // a tile. The request is armed and resolved on the first real move (see
      // [_pendingCloneSource] and [_resolvePendingClone]).
      final cloneCallback = _cloneCallback;
      assert(
        cloneCallback == null || !shortcuts.cloneKeys.any(shortcuts.multiSelectKeys.contains),
        'DashboardShortcuts: cloneKeys and multiSelectKeys must be disjoint. '
        'Both are read from the same pointer-down event, so a shared key '
        'would toggle the selection AND request a clone (multiSelectKeys '
        'wins at runtime).',
      );
      // A multi-selection modifier wins over the clone modifier. The
      // two key sets are configurable and an application may legitimately
      // overlap them (the README documents Alt as a multi-select key); a
      // selection gesture must never be silently turned into a duplication.
      final wantsClone = cloneCallback != null &&
          handle == null &&
          !isMultiSelect &&
          shortcuts.cloneKeys.any(pressedKeys.contains);

      // MULTI-SELECTION LOGIC
      // Skipped entirely while arming a clone: the source's selection state
      // must be left untouched (an Alt+click that never becomes a drag is a
      // no-op), and `onDragStart` on the clone owns the selection from there.
      if (!wantsClone) {
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
      }

      _activeSliverMetrics = _getMetricsFromSliver(renderSliver);

      if (widget.scrollController.hasClients) {
        _initialScrollOffset = widget.scrollController.offset;
      }

      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox) return;
      final overlayBox = renderObject;

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

      _operationStartPosition = position;
      _activeResizeHandle = handle;

      // Claim the pointer so ancestor overlays skip it (see _onPointerDown).
      // Taken even while merely arming a clone: ancestors test the claim in
      // THEIR pointer-down, which runs after ours (deepest-first dispatch),
      // so deferring it would let the parent grid drag the host tile out from
      // under an armed gesture. The matching release happens in
      // _resetOperationState — and, for the mobile-tap branch that bypasses
      // _onPointerUp, in _handleMobileTap.
      _nestedCoordinator?.claimPointer(this);

      if (wantsClone) {
        // Armed, not started: `_activeItemId` deliberately stays null so no
        // drag machinery runs until the pointer proves this is a drag.
        _pendingCloneSource = foundItem;
        return;
      }

      _activeItemId = foundItem.id;
      _activeItemInitialLayout = foundItem;

      if (handle != null) {
        widget.onItemResizeStart?.call(foundItem);
        widget.controller.internal.onResizeStart(foundItem.id);
      } else {
        widget.onItemDragStart?.call(foundItem);
        // Seed the modifier state: a key already held when the drag starts
        // emits no key event, so the handler would never see it.
        _syncSwapModifier(reevaluate: false);
        widget.controller.internal.onDragStart(foundItem.id);
      }
    } else {
      // Empty grid space: candidate for a rubberband selection.
      _maybeArmLasso(position);
    }
  }

  /// Materializes the clone armed at pointer-down and opens the drag session.
  ///
  /// Runs at most once per gesture, on the first move that qualifies as a
  /// drag. The session always starts — on the clone when the application
  /// produced one, on [source] itself otherwise, so a refused duplication
  /// degrades to a plain move instead of swallowing the gesture.
  void _resolvePendingClone(LayoutItem source) {
    final callback = _cloneCallback;
    // A policy that refuses to drag the source refuses the clone too, and
    // `onDragStart` bails out before opening any session — which would strand
    // the freshly inserted duplicate on the grid with no gesture to carry it
    // away. Never mint one in that case.
    final policy = widget.controller.policy;
    final dragRefused = policy != null && !policy.canDrag(source);
    // The callback can disappear between the press and the first move (a
    // rebuild with `onCloneRequested: null`): treat it exactly like a refusal.
    final clone = dragRefused ? null : callback?.call(source, widget.controller);
    final inserted = clone == null ? null : _insertClone(source: source, clone: clone);
    final effective = inserted ?? source;

    _activeItemId = effective.id;
    _activeItemInitialLayout = effective;

    // Deferred from _onPointerDown: these fire once the gesture is real, and
    // with the item that is actually being dragged — the clone, never the
    // source it was minted from.
    widget.controller.onInteractionStart?.call(effective);
    widget.onItemDragStart?.call(effective);
    // onDragStart resets the selection to {effective.id} whenever
    // that id is not already selected, which is always true for a fresh
    // clone. That is what keeps the pivot inside the selection (the cluster
    // invariant) without this method touching the selection itself.
    _syncSwapModifier(reevaluate: false);
    widget.controller.internal.onDragStart(effective.id);
  }

  /// Inserts [clone] on [source]'s own cell and returns it as the controller
  /// actually placed it, or null when the request must be rejected.
  LayoutItem? _insertClone({required LayoutItem source, required LayoutItem clone}) {
    final controller = widget.controller;

    // A clone is a NEW item. Reusing an existing id would put two identical
    // ValueKeys in the sliver (a hard crash on the next layout) and break the
    // tree-wide id uniqueness that cross-grid moves and the tree codec rely
    // on. This is an application contract violation: loud in debug, degraded
    // to a plain move in release rather than corrupting the layout.
    final duplicateId =
        clone.id == source.id || controller.layout.value.any((i) => i.id == clone.id);
    assert(
      !duplicateId || debugBypassCloneIdAssert,
      'onCloneRequested returned the id "${clone.id}", which already exists '
      'in this grid. A clone must carry a NEW id, unique across the whole '
      'grid tree.',
    );
    if (duplicateId) return null;

// `moved` is reset too: it is the engine's transient "displaced by a
    // cascade" marker. An application has no legitimate reason to hand us
    // one on a brand-new item, so it is normalized at the trust boundary
    // like x/y. NOT COVERED BY VALUE, and cannot be: every compactor except
    // NoCompactor resets it anyway, and under NoCompactor `moveElement`
    // sets it back to true inside the same pointer event. No public API can
    // sample the interval.
    controller.addItem(clone.copyWith(x: source.x, y: source.y, moved: false));

    // Read the item BACK from the layout instead of trusting the instance we
    // were handed: addItem runs auto-placement, bound correction and a
    // compaction pass, so the geometry that landed on the grid is the
    // controller's, not the application's.
    final inserted = controller.layout.value.firstWhereOrNull((i) => i.id == clone.id);
    if (inserted == null) return null;

    _clampGrabOffsetTo(inserted, source);
    return inserted;
  }

  /// Re-clamps the grab offset when the clone is smaller than the tile it was
  /// captured on.
  ///
  /// [_dragGrabOffset] is measured inside the SOURCE's render box. A clone
  /// with different dimensions can be narrower or shorter than that offset,
  /// which would hold the feedback — and therefore the resolved drop cell —
  /// off the pointer for the entire gesture.
  void _clampGrabOffsetTo(LayoutItem inserted, LayoutItem source) {
    if (inserted.w == source.w && inserted.h == source.h) return;
    final metrics = _activeSliverMetrics;
    final grab = _dragGrabOffset;
    if (metrics == null || grab == null) return;

    final isVertical = metrics.scrollDirection == Axis.vertical;
    final spacingX = isVertical ? metrics.crossAxisSpacing : metrics.mainAxisSpacing;
    final spacingY = isVertical ? metrics.mainAxisSpacing : metrics.crossAxisSpacing;
    final double cloneWidth = max(0, inserted.w * metrics.slotWidth + (inserted.w - 1) * spacingX);
    final double cloneHeight =
        max(0, inserted.h * metrics.slotHeight + (inserted.h - 1) * spacingY);

    _dragGrabOffset = Offset(
      grab.dx.clamp(0.0, cloneWidth),
      grab.dy.clamp(0.0, cloneHeight),
    );
  }

  void _onPointerMove(Offset position) {
    // Deferred Alt+drag clone. Nothing was inserted at pointer-down, so a
    // plain Alt+click left the grid untouched; the duplicate materializes
    // here, on the first movement that qualifies as a drag, and the session
    // opens directly on it. Placed before the web throttle so the clone is
    // never delayed by a throttled frame.
    var justCloned = false;
    final pendingClone = _pendingCloneSource;
    if (pendingClone != null) {
      if ((position - _operationStartPosition).distance <= _dragMoveTolerance) return;
      _pendingCloneSource = null;
      _resolvePendingClone(pendingClone);
      justCloned = true;
    }

    // Rubberband selection. Placed before the `_activeItemId` guard (a lasso
    // has no active item) and before the web throttle: the rectangle must
    // track the cursor at device frequency to feel attached to it, and the
    // per-event cost is bounded by design — one O(N) scan whose result is
    // published to the selection beacon ONLY when the resolved id set
    // changes, plus one clipped `drawRect` behind its own RepaintBoundary.
    final pendingLasso = _pendingLasso;
    if (pendingLasso != null) {
      if ((position - pendingLasso.global).distance <= _dragMoveTolerance) return;
      _pendingLasso = null;
      _startLasso(pendingLasso.content, pendingLasso.metrics);
    }
    if (_lassoAnchorContent != null) {
      _lastGlobalPosition = position;
      _handleAutoScroll(position);
      _updateLasso(position);
      return;
    }

    if (_activeItemId == null) return;

    // Stopwatch Throttling.
    // To prevent event queue flooding from high-polling mice, we throttle updates on Web.
    // Using a Stopwatch avoids allocating garbage (DateTime.now() objects) while remaining
    // completely independent of Flutter's frame rendering cycles, avoiding visual lockups
    // when sub-slot moves are bypassed.
    // The event that just inserted a clone is NEVER throttled. The
    // insertion and the first `_performUpdate` must land in the same pointer
    // event, because between them the layout holds the raw insertion result:
    // the source and the clone both claim one cell, and `FastVerticalCompactor`
    // breaks that tie ALPHABETICALLY BY ID (see its sort comparator), so which
    // of the two gets snapped one row down depends on the id the application
    // minted. Returning here would let that intermediate layout be painted for
    // one throttle window — a visible flash whose direction varies with the
    // clone's id. Running the update in the same event makes the tie purely
    // internal: the clone lands under the cursor and the source is pushed,
    // whatever the ids sort like.
    if (kIsWeb || debugOverrideIsWeb) {
      // Gate model: now - lastFlush, with an injectable [debugThrottleClock].
      // `justCloned` skips the DEFERRAL, not the bookkeeping: the flush stamp
      // is still recorded below so the throttle cadence stays anchored to the
      // real clock instead of drifting by one window after every clone.
      final now = _throttleNow;
      if (!justCloned && now - _lastThrottleFlush < const Duration(milliseconds: 16)) {
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
      _lastThrottleFlush = now;
      _pendingThrottledPosition = null;
    }

    // If it starts tp move, this is not a "clic", so we won't unselect group at the end.
    if ((position - _operationStartPosition).distance > _dragMoveTolerance) {
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

      // Closed-host / custom drop target. Checked BEFORE the approach
      // freeze below, which handles hosts whose child grid is mounted: here
      // the pointer has nowhere to enter, so the tile itself is the target.
      final dropTarget = _dropTargetAt(position);
      if (dropTarget != null) {
        final impl = widget.controller.internal;
        if (_dropTargetHostId != dropTarget.id) {
          _dropTargetHostId = dropTarget.id;
          impl
            ..freezeDragPushes()
            ..setNestTargetHover(dropTarget.id);
        }
        // Keep the dragged tile glued to the pointer while frozen (same
        // offset convention as the approach-freeze path below).
        final frozenSnapshot = impl.dragOriginSnapshot;
        final pivot = frozenSnapshot?.firstWhereOrNull((i) => i.id == _activeItemId);
        if (pivot != null) {
          // Per-axis strides: the spacings swap with the scroll direction.
          impl.setDragOffset(
            relativePos - Offset(pivot.x * metrics.strideX, pivot.y * metrics.strideY),
          );
        }
        _checkTrash(position);
        return; // hold: no pushes, no placement while over a drop target
      }
      if (_dropTargetHostId != null) {
        // Left the target without releasing: resume normal pushes.
        _dropTargetHostId = null;
        widget.controller.internal.setNestTargetHover(null);
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
            // Reason: per-axis strides swap with scrollDirection (see [gridCellRect]).
            impl.setDragOffset(
              relativePos - Offset(pivot.x * metrics.strideX, pivot.y * metrics.strideY),
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
      // A live rubberband selection resolves here and nowhere else: the
      // selection was committed continuously during the drag, so releasing
      // only has to announce the result and tear the gesture down. The
      // `finally` below still runs (state reset + pointer-claim release).
      if (_lassoAnchorContent != null) {
        _finishLasso();
        return;
      }

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

      // Release over a drop target: silent exit. The pre-drag layout is
      // restored (nothing lands on the parent grid) and the app decides what
      // the drop means — consume the items, or ignore the drop entirely.
      final dropHostId = _dropTargetHostId;
      if (dropHostId != null && _activeResizeHandle == null && !_ownsCrossGridSession) {
        final impl = widget.controller.internal;
        final snapshot = impl.dragOriginSnapshot ?? widget.controller.layout.value;
        final host = widget.controller.layout.value.firstWhereOrNull((i) => i.id == dropHostId) ??
            snapshot.firstWhereOrNull((i) => i.id == dropHostId);
        final selectedIds = widget.controller.selectedItemIds.value;
        final ids = selectedIds.isEmpty ? {currentItem.id} : selectedIds;
        final dragged = snapshot.where((i) => ids.contains(i.id)).toList();
        if (dragged.isEmpty) dragged.add(currentItem);
        impl
          ..cancelInteraction()
          ..setNestTargetHover(null);
        _dropTargetHostId = null;
        if (host != null) {
          // Same-grid drop: source and host grid are the same controller.
          _dropOnHostCallback?.call(
            dragged,
            host,
            widget.controller,
            widget.controller,
          );
        }
        widget.onItemDragEnd?.call(currentItem);
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
        // Peeked BEFORE the commit: onResizeEnd drops the ghost, and this is
        // the rectangle the tile must animate FROM.
        final rawRect = widget.controller.internal.resizeGhostRect.peek();
        final metrics = _activeSliverMetrics;
        widget.controller.internal.onResizeEnd(_activeItemId!);
        // Re-read AFTER the commit: onResizeEnd resolves collisions, so the
        // slot the ghost must land in is not necessarily the one the pointer
        // released over.
        final settled =
            widget.controller.layout.value.firstWhereOrNull((i) => i.id == currentItem.id) ??
                currentItem;
        _armResizeSettle(settled, rawRect, metrics);
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
    _pendingCloneSource = null;
    _frozenOverChildHostId = null;
    if (_dropTargetHostId != null) {
      widget.controller.internal.setNestTargetHover(null);
      _dropTargetHostId = null;
    }
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
    // A ghost still armed here belongs to no live gesture — unless the settle
    // animation owns it, in which case the ghost widget clears it on landing.
    if (_resizeSettleArmed) {
      _resizeSettleArmed = false;
    } else {
      widget.controller.internal.clearResizeGhost();
    }
    _clearLassoState();
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

  // ===========================================================================
  // Rubberband ("lasso") selection
  // ===========================================================================

  /// Arms a rubberband selection on a press over empty grid space.
  ///
  /// Nothing is selected and nothing is painted here — see
  /// [_pendingLasso] for why the gesture is two-phase.
  void _maybeArmLasso(Offset position) {
    // Pointer devices only. On Android / iOS an empty-space drag scrolls the
    // grid, and the Listener does not even deliver moves unless a drag is
    // already live, so an armed lasso there could never be resolved OR
    // released.
    if (_isMobile) return;

    final style = _lassoStyle;
    switch (style.mode) {
      case LassoSelectionMode.disabled:
        return;
      case LassoSelectionMode.modifierRequired:
        if (!_isLassoModifierHeld) return;
      case LassoSelectionMode.emptySpace:
        break;
    }

    // Same containment rule as the empty-slot gestures: strict sliver bounds
    // keep several grids sharing one scroll view from cross-firing, relaxed
    // under fillViewport (single-grid usage, where the grid owns the
    // remaining viewport).
    if (!widget.fillViewport && !isPointInsideSliver(position)) return;
    final point = _gridPointAtGlobal(position);
    if (point == null) return;

    _pendingLasso = (
      global: position,
      content: Offset(point.dx, point.dy),
      metrics: point.metrics,
    );
    _operationStartPosition = position;

    // Claim the pointer for exactly the reason the armed clone does:
    // ancestors test the claim in THEIR pointer-down, which runs after ours
    // (deepest-first dispatch). Without it, a lasso started on a nested
    // grid's background would also have the parent grid drag the host tile.
    // Released in [_resetOperationState], which every pointer-up path
    // reaches through its `finally`.
    _nestedCoordinator?.claimPointer(this);
  }

  /// Promotes an armed lasso into a live one on the first qualifying move.
  ///
  /// [anchorContent] and [metrics] were resolved when the gesture armed, so
  /// this cannot fail.
  void _startLasso(Offset anchorContent, SlotMetrics metrics) {
    final shortcuts = _effectiveShortcuts;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final modifierRequired = _lassoStyle.mode == LassoSelectionMode.modifierRequired;

    // Additive vs replacing. A held multi-selection modifier means "add to
    // what is already selected" — the universal desktop convention. The one
    // subtlety: under `modifierRequired` the lasso trigger is Shift by
    // default and Shift is ALSO a multi-select key, so treating it as
    // additive would make a replacing lasso unreachable in that mode. A key
    // that is both the trigger and a multi-select key therefore counts as
    // the trigger only; hold a second, non-overlapping multi-select key to
    // get an additive lasso there.
    var additive = false;
    for (final key in shortcuts.multiSelectKeys) {
      if (!pressed.contains(key)) continue;
      if (modifierRequired && shortcuts.lassoModifier.contains(key)) continue;
      additive = true;
      break;
    }

    _lassoBaseSelection =
        additive ? widget.controller.selectedItemIds.peek().toSet() : const <String>{};
    _lastLassoHits = const <String>{};
    _lassoHitScratch.clear();
    _lassoAnchorContent = anchorContent;
    _activeSliverMetrics = metrics;
    _attachLassoScrollListener();

    // A replacing lasso wipes the previous selection at START, not at
    // release: the rectangle is a live preview and must not show stale
    // selections for its whole duration.
    if (!additive && widget.controller.selectedItemIds.peek().isNotEmpty) {
      widget.controller.clearSelection();
    }

    // Use the old API for older Flutter versions, and ignore the deprecation warning
    // Until we have no other choice to use sendAnnouncement
    // ignore: deprecated_member_use
    SemanticsService.announce(_effectiveGuidance.a11yLassoStart, _lassoTextDirection).ignore();
  }

  /// Recomputes the rectangle, the selection and the painted frame for
  /// [position]. Called from the pointer move, and from the scroll listener
  /// so the anchor stays pinned to the content while the grid scrolls under
  /// it (edge auto-scroll, mouse wheel).
  void _updateLasso(Offset position) {
    final anchor = _lassoAnchorContent;
    if (anchor == null) return;
    final point = _gridPointAtGlobal(position);
    if (point == null) return;

    final metrics = point.metrics;
    _activeSliverMetrics = metrics;

    final left = min(anchor.dx, point.dx);
    final top = min(anchor.dy, point.dy);
    final right = max(anchor.dx, point.dx);
    final bottom = max(anchor.dy, point.dy);

    _applyLassoSelection(metrics, left, top, right, bottom);
    _paintLasso(metrics, left, top, right, bottom);
  }

  /// O(N) intersection of the content-space rectangle against every item's
  /// pixel bounds, publishing the result **only when the resolved id set
  /// actually changed**.
  ///
  /// That guard is the load-bearing part, not the linear scan: `Set` has
  /// identity equality in Dart, so an unconditional write to
  /// `selectedItemIds` would notify on every pointer event and rebuild every
  /// visible item shell at pointer frequency (120 Hz on a fast desktop
  /// mouse). With it, a rectangle growing inside the cells it already covers
  /// costs one scan and zero rebuilds.
  ///
  /// Intersection is pixel-precise rather than cell-precise: a rectangle
  /// drawn entirely inside the gutter between two tiles selects neither,
  /// which is what users expect from a rubberband.
  void _applyLassoSelection(
    SlotMetrics metrics,
    double left,
    double top,
    double right,
    double bottom,
  ) {
    final isVertical = metrics.scrollDirection == Axis.vertical;
    final spacingX = isVertical ? metrics.crossAxisSpacing : metrics.mainAxisSpacing;
    final spacingY = isVertical ? metrics.mainAxisSpacing : metrics.crossAxisSpacing;
    final strideX = metrics.slotWidth + spacingX;
    final strideY = metrics.slotHeight + spacingY;

    final hits = _lassoHitScratch..clear();
    final layout = widget.controller.layout.peek();
    for (var i = 0; i < layout.length; i++) {
      final item = layout[i];
      if (item.id == '__placeholder__') continue;
      // Pure statics are not selectable (same rule as a plain click, which
      // returns before touching the selection). Section barriers ARE: they
      // are static but interactive, and clicking one already selects it.
      if (item.isStatic && !item.isSectionBarrier) continue;

      final itemLeft = item.x * strideX;
      final itemTop = item.y * strideY;
      final itemRight = itemLeft + item.w * strideX - spacingX;
      final itemBottom = itemTop + item.h * strideY - spacingY;

      if (itemRight < left || itemLeft > right) continue;
      if (itemBottom < top || itemTop > bottom) continue;
      hits.add(item.id);
    }

    var changed = hits.length != _lastLassoHits.length;
    if (!changed) {
      for (var i = 0; i < hits.length; i++) {
        if (_lastLassoHits.contains(hits[i])) continue;
        changed = true;
        break;
      }
    }
    if (!changed) return;

    _lastLassoHits = hits.toSet();
    widget.controller.selectedItemIds.value = <String>{
      ..._lassoBaseSelection,
      ...hits,
    };
  }

  /// Publishes the painted frame: content rectangle translated through the
  /// shared content origin, clipped to this grid's visible band.
  void _paintLasso(
    SlotMetrics metrics,
    double left,
    double top,
    double right,
    double bottom,
  ) {
    final renderSliver = _findRenderSliver();
    if (renderSliver == null || !renderSliver.attached) return;

    final origin = _contentOriginOf(renderSliver, metrics);
    final style = _lassoStyle;
    _lassoOverlay.value = LassoOverlayState(
      rect: Rect.fromLTRB(left, top, right, bottom).shift(origin.sliverStart),
      clipRect: origin.bounds,
      fillColor: style.fillColor,
      borderColor: style.borderColor,
      borderWidth: style.borderWidth,
      // The tooltip follows the guidance opt-in; the announcements above do
      // not (a11y is not opt-in).
      message: widget.controller.guidance?.lassoSelect.message,
    );
  }

  /// Finalizes a live lasso on release: announces the resulting selection
  /// size and tears the gesture down. The selection itself is already
  /// committed — it was updated live throughout the drag.
  void _finishLasso() {
    final count = widget.controller.selectedItemIds.peek().length;
    // Use the old API for older Flutter versions, and ignore the deprecation warning
    // Until we have no other choice to use sendAnnouncement
    // ignore: deprecated_member_use
    SemanticsService.announce(_effectiveGuidance.a11yLassoEnd(count), _lassoTextDirection).ignore();
    _stopScrollTimer();
    _clearLassoState();
  }

  /// Drops every trace of an armed or live lasso. Idempotent: it runs on
  /// every pointer-up through [_resetOperationState], including the vast
  /// majority that never armed one.
  void _clearLassoState() {
    _pendingLasso = null;
    _lassoAnchorContent = null;
    _lassoBaseSelection = const <String>{};
    _lastLassoHits = const <String>{};
    _lassoHitScratch.clear();
    _detachLassoScrollListener();
    _lassoOverlay.value = null;
  }

  void _attachLassoScrollListener() {
    if (_lassoScrollListenerTarget != null) return;
    _lassoScrollListenerTarget = widget.scrollController..addListener(_onScrollDuringLasso);
  }

  void _detachLassoScrollListener() {
    _lassoScrollListenerTarget?.removeListener(_onScrollDuringLasso);
    _lassoScrollListenerTarget = null;
  }

  /// Re-derives the rectangle when the content scrolls under a stationary
  /// pointer. The anchor lives in content space, so this is a pure
  /// re-projection: the selection it resolves is unchanged unless the
  /// pointer's own content coordinates moved.
  void _onScrollDuringLasso() {
    final position = _lastGlobalPosition;
    if (position == null || _lassoAnchorContent == null) return;
    _updateLasso(position);
  }

  /// Cursor to apply over empty grid space (item cursors are set deeper in
  /// the tree and win over this one by construction — Flutter picks the
  /// innermost non-deferring cursor on the hit path).
  MouseCursor _lassoCursor({required bool isEditing, required bool modifierDown}) {
    final guidance = widget.controller.guidance;
    if (guidance == null || _isMobile || !isEditing) return MouseCursor.defer;
    if (_lassoAnchorContent != null) return guidance.lassoSelect.cursor;
    return switch (_lassoStyle.mode) {
      LassoSelectionMode.emptySpace => guidance.lassoSelect.cursor,
      LassoSelectionMode.modifierRequired =>
        modifierDown ? guidance.lassoSelect.cursor : MouseCursor.defer,
      LassoSelectionMode.disabled => MouseCursor.defer,
    };
  }

  /// Mirrors the two drag-related modifiers into observable state, and
  /// re-evaluates a live drag when the swap modifier flips.
  ///
  /// Registered on desktop only and never consumes the event. Costs a handful
  /// of `Set.contains` per key event, and short-circuits to nothing when the
  /// state did not change — a held key repeating does not re-run a layout
  /// pass.
  ///
  /// `HardwareKeyboard` updates its pressed-key map BEFORE dispatching to
  /// handlers, so the getters read here are accurate for the event being
  /// delivered.
  bool _handleModifierKey(KeyEvent event) {
    if (event is KeyRepeatEvent) return false;

    final lassoHeld = _isLassoModifierHeld;
    final lassoBeacon = widget.controller.lassoModifierHeld;
    if (lassoHeld != lassoBeacon.peek()) lassoBeacon.value = lassoHeld;

    _syncSwapModifier(reevaluate: true);
    return false;
  }

  /// Publishes the swap-modifier state to the controller and, when a drag is
  /// live and the effective mode actually changed, replays the current
  /// pointer position so the layout reflects the new mode immediately.
  ///
  /// The replay is mandatory: without it the mode would only take effect on
  /// the next pointer movement, and a user holding the modifier over a
  /// stationary cursor would see nothing happen. It is guarded on a real mode
  /// change so that pressing an unrelated key mid-drag costs nothing.
  void _syncSwapModifier({required bool reevaluate}) {
    final controller = widget.controller;
    final held = _isSwapModifierHeld;
    if (held == controller.swapModifierHeld.peek()) return;

    final before = controller.getEffectiveDragMode();
    controller.swapModifierHeld.value = held;
    if (!reevaluate) return;
    if (controller.getEffectiveDragMode() == before) return;

    // Resizes have no drag mode, and a lasso has no dragged item.
    final position = _lastGlobalPosition;
    if (position == null) return;
    if (_activeItemId == null || _activeResizeHandle != null) return;
    if (_activeSliverMetrics == null) return;
    _performUpdate(position);
  }

  TextDirection get _lassoTextDirection => Directionality.maybeOf(context) ?? TextDirection.ltr;

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
            grabFraction: _nestedCoordinator?.sessionGrabFraction ?? Offset.zero,
          );
        } else if (widget.controller.currentDragPlaceholder != null) {
          // External DragTarget hover only; never resurrect a placeholder
          // from a stale position (e.g. when scrolled by delegation).
          final p = widget.controller.currentDragPlaceholder!;
          _showPlaceholderAt(
            _lastGlobalPosition!,
            w: p.w,
            h: p.h,
          );
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

  void _updatePlaceholderPosition(Offset globalPosition, T data) {
    final template = widget.externalTemplateBuilder?.call(data);
    _showPlaceholderAt(
      globalPosition,
      w: template?.w ?? widget.placeholderWidth,
      h: template?.h ?? widget.placeholderHeight,
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

  /// Shows (or moves) the external/foreign placeholder of size [w] x [h] so
  /// that [globalPosition] falls at [grabFraction] of the tile.
  ///
  /// [grabFraction] defaults to `(0,0)` — the top-left — which is exactly what
  /// the [DragTarget] path supplies, since `DragTargetDetails.offset` already
  /// IS the feedback's top-left corner. Cross-grid drags pass the raw pointer
  /// position together with the session's grab fraction, so the placeholder
  /// lands under the floating proxy instead of one grab-offset away from it.
  void _showPlaceholderAt(
    Offset globalPosition, {
    required int w,
    required int h,
    Offset grabFraction = Offset.zero,
  }) {
    final point = _gridPointAtGlobal(globalPosition);
    if (point == null) return;

    final metrics = point.metrics;
    _activeSliverMetrics = metrics;

    // Defensive clamp — a foreign/projected item wider than this grid
    // would invert the x/y clamp range below (`x.clamp(0, slotCount - w)`
    // throws ArgumentError when the upper bound is negative). The coordinator
    // sanitizes projections, but this method is also reachable via the public
    // DragTarget path with caller-provided dimensions.
    final isVertical = metrics.scrollDirection == Axis.vertical;
    final clampedW = isVertical ? min(w, metrics.slotCount) : w;
    final clampedH = !isVertical ? min(h, metrics.slotCount) : h;

    final spacingX = isVertical ? metrics.crossAxisSpacing : metrics.mainAxisSpacing;
    final spacingY = isVertical ? metrics.mainAxisSpacing : metrics.crossAxisSpacing;
    final strideX = metrics.slotWidth + spacingX;
    final strideY = metrics.slotHeight + spacingY;

    // The anchor is re-derived from the tile's size IN THIS GRID.
    // Reusing the source grid's pixel offset would drift by the density ratio
    // the moment the item is projected into a grid of a different slot size.
    final anchorX = point.dx - grabFraction.dx * (clampedW * strideX - spacingX);
    final anchorY = point.dy - grabFraction.dy * (clampedH * strideY - spacingY);

    final x = (anchorX / strideX).floor();
    final y = (anchorY / strideY).floor();

    final clampedX = max(0, isVertical ? x.clamp(0, metrics.slotCount - clampedW) : x);
    final clampedY = max(0, isVertical ? y : y.clamp(0, metrics.slotCount - clampedH));

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
    _showPlaceholderAt(
      globalPosition,
      w: item.w,
      h: item.h,
      grabFraction: _nestedCoordinator?.sessionGrabFraction ?? Offset.zero,
    );
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
        // An explicit drop target is never a speculative nest candidate.
        !host.isDropTarget &&
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
        coordinator.hasAnyTargetBesides(this, draggedItem: item) &&
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
      // Second `targetAt` call site: the session-entry probe. It must apply
      // the same business filter as the in-session one, or a grid that
      // refuses the item would still capture the handover on entry and only
      // reject it on the next pointer event.
      draggedItem: item,
      sourceController: widget.controller,
    );

    // Ancestor handover requires a REAL exit. `targetAt` can resolve an
    // ancestor grid while the pointer is still physically inside ours:
    // containment for a linked child defers to the parent's `itemAtGlobal`,
    // and any disagreement there (host pushed by a cascade, point mapping to
    // a neighbouring cell, host momentarily unresolvable) hands the point
    // back to the parent. Starting a session then silently removes the item
    // from this grid and drops a placeholder in the parent, whose collision
    // pushes move the HOST tile while the dragged tile pops into the floating
    // proxy — both appear to move at once, which is exactly the reported bug.
    //
    // Siblings (same depth) and DEEPER grids keep the immediate handover:
    // they never overlap our own bounds, so resolving one already means the
    // pointer left us. Only shallower targets need the exit gate.
    final isEnteringAncestor = reg != null && reg.depth < _nestedDepth;
    final entersOtherGrid =
        reg != null && !identical(reg.target, this) && (!isEnteringAncestor || isOutside);

    // Start cross-grid session immediately if the pointer exits our overlay bounds,
    // or if it enters another valid registered target.
    if (isOutside || entersOtherGrid) {
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
