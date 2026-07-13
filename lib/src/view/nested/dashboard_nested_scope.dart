import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';

/// Signature for the callback fired when an item has been moved from one
/// grid to another (cross-grid drag & drop, or [DashboardNestedCoordinator.moveItemToGrid]).
typedef DashboardItemMovedToGridCallback = void Function(
  LayoutItem item,
  DashboardController from,
  DashboardController to,
);

/// Signature for the callback fired when the user holds a dragged item over a
/// plain (non-nested) item for [DashboardNestedScope.nestHoverDelay] while
/// [DashboardNestedScope.subGridDynamic] is enabled.
///
/// The application decides how to convert [host] into a nested grid (typically
/// by rebuilding its content with a NestedDashboard) and then calls
/// [DashboardNestedCoordinator.moveItemToGrid] to move [dragged] into it.
typedef DashboardNestedGridRequestCallback = void Function(
  LayoutItem host,
  LayoutItem dragged,
  DashboardController hostGridController,
);

/// Signature for the callback fired when a nested-grid request (see
/// [DashboardNestedCoordinator.onNestedGridRequested]) is abandoned: the
/// request fired, but the drag ended without the dragged item landing in the
/// child grid of [host] — dropped elsewhere, returned to its origin, or
/// canceled. Lets the application revert a speculative conversion (e.g. an
/// empty panel created in response to the request).
typedef DashboardNestedGridAbandonedCallback = void Function(
  LayoutItem host,
  DashboardController hostGridController,
);

/// How the coordinator decides which grid is under a cross-grid drag.
enum CrossGridProbe {
  /// The raw pointer position decides.
  ///
  /// Predictable relative to the cursor, but when the tile is grabbed far
  /// from its center, its body can visually overlap (and push) a nested-grid
  /// host before the pointer itself reaches it.
  pointer,

  /// The center of the dragged tile decides.
  ///
  /// Target detection and placeholder placement follow the tile's visual
  /// center instead of the cursor, so behavior no longer depends on where
  /// the tile was grabbed.
  itemCenter,
}

/// The role a DashboardOverlay plays in cross-grid drag & drop.
///
/// Implemented by the overlay state; the coordinator only ever talks to grids
/// through this interface, which keeps the nested layer decoupled from the
/// overlay internals.
abstract class CrossGridDragTarget {
  /// The controller of the grid this target drives.
  DashboardController get controller;

  /// Whether this grid currently accepts items dragged from other grids.
  bool get canAcceptCrossGridItems;

  /// Whether items may be dragged out of this grid into another one.
  bool get canDragItemsOut;

  /// The render box covering the interactive grid area, or null if detached.
  RenderBox? get overlayRenderBox;

  /// The slot metrics of the grid as currently laid out, or null if the
  /// sliver is not attached yet.
  SlotMetrics? currentSlotMetrics();

  /// Called on every pointer move while a foreign item hovers this grid.
  ///
  /// Shows/moves the live placeholder (with collision pushes) at the cell
  /// under [globalPosition], sized to [item], and drives auto-scroll.
  void foreignDragOver(LayoutItem item, Offset globalPosition);

  /// Called when the foreign item leaves this grid: hides the placeholder,
  /// reverts the pushes and stops auto-scroll.
  void foreignDragLeave();

  /// Finalizes the drop of a foreign [item] at the current placeholder
  /// position. Returns the placed item, or null if no placeholder was active
  /// (in which case the caller must treat the drop as failed).
  LayoutItem? foreignDrop(LayoutItem item);

  /// Returns the item whose cell contains [globalPosition], or null.
  ///
  /// When a foreign placeholder is active, the lookup is performed against the
  /// pre-push snapshot so that hovering is stable even while the collision
  /// cascade moves items away from the cursor.
  LayoutItem? itemAtGlobal(Offset globalPosition, {String? excludeId});

  /// Highlights (or clears, when null) the item that is armed to become a
  /// nested grid host. Purely visual.
  void setNestHoverHighlight(String? itemId);

  /// Drives this grid's edge auto-scroll from a global position. Used by
  /// nested grids whose own scroll view cannot scroll (e.g. `sizeToContent`)
  /// to delegate scrolling to their parent grid.
  void autoScrollAt(Offset globalPosition);

  /// Stops any auto-scroll started via [autoScrollAt].
  void stopAutoScroll();
}

/// A live registration of a grid inside a [DashboardNestedScope].
class NestedGridRegistration {
  /// Creates a registration entry.
  NestedGridRegistration({
    required this.target,
    required this.depth,
    this.parentController,
    this.parentItemId,
  });

  /// The overlay driving the registered grid.
  final CrossGridDragTarget target;

  /// Nesting depth (number of ancestor dashboards). Used to resolve the
  /// deepest grid under the pointer, mirroring how DOM hit-testing gives
  /// the innermost droppable.
  final int depth;

  /// The controller of the parent grid, when this grid is nested inside an
  /// item of another grid (set by NestedDashboard).
  DashboardController? parentController;

  /// The id of the parent grid item hosting this grid.
  String? parentItemId;
}

/// Coordinates every dashboard living under a [DashboardNestedScope]:
///
/// * pointer claiming, so a drag started in a nested grid is not also handled
///   by its ancestors;
/// * the cross-grid drag session — temporary removal from the source grid,
///   live placeholder in the hovered grid, floating proxy, and the final drop
///   or cancel;
/// * the parent/child links used for tree export/import and for the
///   `subGridDynamic` hover detection.
///
/// The coordinator performs no layout math itself: geometry stays in the
/// overlays (view layer) and layout mutations stay in the controllers.
class DashboardNestedCoordinator {
  /// Creates a coordinator. Usually done by [DashboardNestedScope].
  DashboardNestedCoordinator({
    this.onItemMovedToGrid,
    this.onNestedGridRequested,
    this.onNestedGridRequestAbandoned,
    this.subGridDynamic = false,
    this.subGridDynamicSameGrid = false,
    this.nestHoverDelay = const Duration(milliseconds: 600),
    this.probe = CrossGridProbe.pointer,
    this.maxNestingDepth,
  });

  /// Fired after a successful cross-grid move (drag & drop or programmatic).
  DashboardItemMovedToGridCallback? onItemMovedToGrid;

  /// Fired when a dragged item is held over a plain item long enough to
  /// request a dynamic nested grid (see [subGridDynamic]).
  DashboardNestedGridRequestCallback? onNestedGridRequested;

  /// Fired when a [onNestedGridRequested] request is abandoned: the drag
  /// ended without the dragged item landing in the child grid of the
  /// requested host. Use it to revert a speculative conversion (delete the
  /// empty panel, clear the `hasNestedGrid` flag, dispose the controller).
  DashboardNestedGridAbandonedCallback? onNestedGridRequestAbandoned;

  // The last fired-but-unresolved nested-grid request. Set when the request
  // fires (both the cross-grid and the same-grid arming paths), resolved at
  // drag end. Deliberately NOT cleared when a session begins: the handoff
  // into the freshly created child grid happens through a session, and the
  // request is only confirmed by the drop that ends it.
  ({LayoutItem host, DashboardController hostGrid})? _pendingNestRequest;

  /// Records that [onNestedGridRequested] has fired for [host] in
  /// [hostGrid]. Called by both arming paths right before the callback.
  void notifyNestRequestFired(LayoutItem host, DashboardController hostGrid) {
    _pendingNestRequest = (host: host, hostGrid: hostGrid);
  }

  /// Resolves the pending nested-grid request, if any. [droppedInto] is the
  /// grid that received the item, or null when the drag ended without a
  /// cross-grid drop. Fires [onNestedGridRequestAbandoned] unless the item
  /// landed in the child grid of the requested host. Idempotent.
  void resolveNestRequest(DashboardController? droppedInto) {
    final pending = _pendingNestRequest;
    if (pending == null) return;
    _pendingNestRequest = null;
    final child = childGridsOf(pending.hostGrid)[pending.host.id];
    final confirmed = droppedInto != null && child != null && identical(droppedInto, child);
    if (!confirmed) {
      onNestedGridRequestAbandoned?.call(pending.host, pending.hostGrid);
    }
  }

  /// Enables the `subGridDynamic` hover detection.
  bool subGridDynamic;

  /// Extends [subGridDynamic] to drags that never leave their own grid.
  ///
  /// In-grid drags push their neighbours continuously, so "hovering" a
  /// sibling is normally impossible — the sibling is shoved away before the
  /// pointer can rest on it. When this is true (and [subGridDynamic] is on),
  /// keeping the pointer stationary briefly during an in-grid drag *freezes*
  /// the pushes (the pre-drag layout is restored while the drag stays alive),
  /// highlights the item under the pointer, and after [nestHoverDelay] fires
  /// [onNestedGridRequested] with the same contract as the cross-grid arming.
  /// Moving the pointer again cancels the freeze and resumes the drag;
  /// releasing right after the request drops the dragged item into the
  /// freshly created nested grid (via the regular cross-grid handoff).
  /// Independent of [subGridDynamic]: either may be enabled alone.
  /// Default: false — pausing mid-drag visibly freezes the collision pushes,
  /// which changes the feel of the drag, so this is strictly opt-in.
  bool subGridDynamicSameGrid;

  /// How long the user must hover a plain item before
  /// [onNestedGridRequested] fires.
  Duration nestHoverDelay;

  /// Which point decides the grid under a cross-grid drag (see [CrossGridProbe]).
  CrossGridProbe probe;

  /// Maximum number of nesting levels allowed, or null (default) for no limit.
  ///
  /// Depth is counted from the root grid, which is level 0. A value of `1`
  /// therefore lets the root host nested grids but stops those from hosting
  /// further grids; `0` disables nesting entirely. When a limit is set, a grid
  /// already at (or beyond) `maxNestingDepth` levels deep is not offered as a
  /// drop target for cross-grid drags, and `subGridDynamic` will not arm on
  /// its items — so users cannot create grids deeper than the limit. Programmatic
  /// [moveItemToGrid] is not constrained (the caller is explicit).
  int? maxNestingDepth;

  /// Whether a grid at [depth] (root = 0) may host a nested grid one level
  /// deeper, given [maxNestingDepth]. Always true when no limit is set.
  ///
  /// Useful from `onNestedGridRequested` or a custom builder to mirror the
  /// coordinator's own limit (e.g. to hide an "add sub-grid" affordance).
  bool canHostAtDepth(int depth) => maxNestingDepth == null || depth < maxNestingDepth!;

  /// The probe point for the active session at pointer [globalPosition]:
  /// the pointer itself, or the dragged tile's visual center.
  Offset probePointFor(
    Offset globalPosition, {
    required Offset grabOffset,
    required Size itemPixelSize,
  }) {
    switch (probe) {
      case CrossGridProbe.pointer:
        return globalPosition;
      case CrossGridProbe.itemCenter:
        return globalPosition -
            grabOffset +
            Offset(itemPixelSize.width / 2, itemPixelSize.height / 2);
    }
  }

  final List<NestedGridRegistration> _registrations = [];

  /// Grid data waiting for its nested grid to mount (see [stashChildGrid]).
  final Map<String, NestedGridData> _pendingChildGrids = {};

  /// Parent links declared by NestedDashboard, keyed by child controller.
  ///
  /// A NestedDashboard mounts *before* the overlay of the grid it hosts, so
  /// the link is recorded here and applied to the registration when the child
  /// overlay registers (and re-applied on remounts).
  final Map<DashboardController, ({DashboardController parent, String itemId})> _childLinks =
      Map.identity();

  // --- Pointer claim (DDManager.mouseHandled equivalent) ---

  CrossGridDragTarget? _pointerOwner;

  /// Claims the active pointer for [owner]. Called by an overlay when it
  /// actually starts an interaction, before its ancestors receive the same
  /// pointer-down (hit-test dispatch is deepest-first).
  void claimPointer(CrossGridDragTarget owner) => _pointerOwner = owner;

  /// Releases the pointer claim if held by [owner].
  void releasePointer(CrossGridDragTarget owner) {
    if (identical(_pointerOwner, owner)) _pointerOwner = null;
  }

  /// Whether a grid other than [me] already handles the active pointer.
  bool isPointerClaimedByOther(CrossGridDragTarget me) =>
      _pointerOwner != null && !identical(_pointerOwner, me);

  // --- Registry ---

  /// Registers a grid. Called by the overlay on mount.
  NestedGridRegistration register(CrossGridDragTarget target, {required int depth}) {
    final reg = NestedGridRegistration(target: target, depth: depth);
    final link = _childLinks[target.controller];
    if (link != null) {
      reg
        ..parentController = link.parent
        ..parentItemId = link.itemId;
    }
    _registrations.add(reg);
    return reg;
  }

  /// Unregisters a grid. Called by the overlay on dispose.
  void unregister(CrossGridDragTarget target) {
    _registrations.removeWhere((r) => identical(r.target, target));
    if (identical(_pointerOwner, target)) _pointerOwner = null;
    if (_session != null && identical(_session!.origin, target)) {
      // The source grid died mid-session (e.g. its subtree was disposed):
      // drop the proxy and abandon the session; nothing to restore into.
      _clearSession(restoreOrigin: false);
    }
  }

  /// Declares that the grid driven by [child] lives inside the item
  /// [parentItemId] of [parent]. Called by NestedDashboard.
  void linkChildGrid({
    required DashboardController parent,
    required String parentItemId,
    required DashboardController child,
  }) {
    _childLinks[child] = (parent: parent, itemId: parentItemId);
    for (final reg in _registrations) {
      if (identical(reg.target.controller, child)) {
        reg
          ..parentController = parent
          ..parentItemId = parentItemId;
        return;
      }
    }
  }

  /// Removes the parent link of [child] (called by NestedDashboard on
  /// dispose or when its controller changes).
  void unlinkChildGrid(DashboardController child) {
    _childLinks.remove(child);
    for (final reg in _registrations) {
      if (identical(reg.target.controller, child)) {
        reg
          ..parentController = null
          ..parentItemId = null;
      }
    }
  }

  /// The registration for [controller], or null.
  NestedGridRegistration? registrationOf(DashboardController controller) {
    for (final reg in _registrations) {
      if (identical(reg.target.controller, controller)) return reg;
    }
    return null;
  }

  /// Whether the item [itemId] of [host] hosts a nested grid.
  ///
  /// Reads the declared parent links rather than live registrations, so the
  /// answer stays correct while the host item is scrolled out of view and its
  /// NestedDashboard is unmounted by sliver virtualization.
  bool hasChildGrid(DashboardController host, String itemId) {
    for (final link in _childLinks.values) {
      if (identical(link.parent, host) && link.itemId == itemId) return true;
    }
    return false;
  }

  /// The child grid controllers of [parent], keyed by host item id — whether
  /// or not their NestedDashboard is currently mounted. Links survive
  /// virtualization unmounts; they are removed only by [unlinkChildGrid]
  /// (or overwritten by a new [linkChildGrid]).
  Map<String, DashboardController> childGridsOf(DashboardController parent) => {
        for (final entry in _childLinks.entries)
          if (identical(entry.value.parent, parent)) entry.value.itemId: entry.key,
      };

  /// All registered direct children of [parent] (mounted nested grids).
  List<NestedGridRegistration> childrenOf(DashboardController parent) => [
        for (final reg in _registrations)
          if (identical(reg.parentController, parent)) reg,
      ];

  /// Returns true if the grid of [reg] lives inside [parentItemId] of [parentController],
  /// either directly or nested deeply within its descendant subtree.
  ///
  /// Uses the persistent [_childLinks] authoritative registry to guarantee correctness
  /// even when portions of the parent grid hierarchy are virtualized/unmounted.
  bool isDescendantOf(
    NestedGridRegistration reg,
    DashboardController parentController,
    String parentItemId,
  ) {
    var currentController = reg.target.controller;
    while (true) {
      final link = _childLinks[currentController];
      if (link == null) break;
      if (identical(link.parent, parentController) && link.itemId == parentItemId) {
        return true;
      }
      currentController = link.parent;
    }
    return false;
  }

  /// Resolves the deepest registered grid whose interactive area contains
  /// [globalPosition]. Grids that do not [CrossGridDragTarget.canAcceptCrossGridItems]
  /// are skipped when [acceptingOnly] is true.
  ///
  /// O(G) where G is the number of live grids — a control-plane cost paid once
  /// per pointer event, never per item.
  NestedGridRegistration? targetAt(
    Offset globalPosition, {
    bool acceptingOnly = true,
    DashboardController? excludeSourceController,
    String? excludeItemId,
  }) {
    NestedGridRegistration? best;
    for (final reg in _registrations) {
      if (acceptingOnly && !reg.target.canAcceptCrossGridItems) continue;

      // Prevent a parent item from being dragged into its own child grid or deep descendants,
      // which is a recursive layout paradox and causes visual glitches/crashes.
      // We do NOT exclude the excludeSourceController itself, as items must be allowed to be dragged
      // within their own source grid without triggering a cross-grid exit session.
      if (excludeSourceController != null && excludeItemId != null) {
        if (isDescendantOf(reg, excludeSourceController, excludeItemId)) {
          continue;
        }
      }

      final box = reg.target.overlayRenderBox;
      if (box == null || !box.attached) continue;
      final local = box.globalToLocal(globalPosition);
      if (local.dx < 0 || local.dy < 0 || local.dx > box.size.width || local.dy > box.size.height) {
        continue;
      }
      if (best == null || reg.depth > best.depth) best = reg;
    }
    return best;
  }

  // --- Cross-grid drag session ---

  _CrossGridSession? _session;

  /// Whether a cross-grid drag session is in progress.
  bool get sessionActive => _session != null;

  /// Whether the active session (if any) is owned by [source].
  bool isSessionOwner(CrossGridDragTarget source) =>
      _session != null && identical(_session!.origin, source);

  /// Starts a cross-grid session: silently removes the dragged item from the
  /// source grid (temporary removal) and spawns the
  /// floating proxy that visually carries the item between grids.
  ///
  /// [proxyChild] is the widget rendered inside the proxy, already sized by
  /// the caller via [itemPixelSize].
  void beginSession({
    required CrossGridDragTarget source,
    required LayoutItem item,
    required Offset globalPosition,
    required Offset grabOffset,
    required Size itemPixelSize,
    required BuildContext overlayContext,
    required Widget proxyChild,
    double proxyOpacity = 0.85,
  }) {
    if (_session != null) return;
    final impl = source.controller.internal;
    final removed = impl.beginCrossGridExit({item.id});
    if (removed.isEmpty) return;

    final position = ValueNotifier<Offset>(globalPosition - grabOffset);
    OverlayEntry? entry;
    final overlay = Overlay.maybeOf(overlayContext, rootOverlay: true);
    if (overlay != null) {
      entry = OverlayEntry(
        builder: (context) => ValueListenableBuilder<Offset>(
          valueListenable: position,
          builder: (context, pos, child) => Positioned(
            left: pos.dx,
            top: pos.dy,
            width: itemPixelSize.width,
            height: itemPixelSize.height,
            child: child!,
          ),
          child: IgnorePointer(
            child: Opacity(opacity: proxyOpacity, child: proxyChild),
          ),
        ),
      );
      overlay.insert(entry);
    }

    _session = _CrossGridSession(
      item: removed.first,
      origin: source,
      grabOffset: grabOffset,
      itemPixelSize: itemPixelSize,
      proxyPosition: position,
      proxyEntry: entry,
    );
  }

  /// Routes a pointer move of an active session: updates the proxy, fires
  /// leave/enter between hovered grids, drives the hovered grid's placeholder
  /// and, when [subGridDynamic] is on, the nest-hover arming.
  void updateSession(Offset globalPosition) {
    final session = _session;
    if (session == null) return;
    session.proxyPosition.value = globalPosition - session.grabOffset;

    // Target detection, placeholder placement and nest-hover all use the
    // same probe point so the three stay consistent (see [CrossGridProbe]).
    final probePoint = probePointFor(
      globalPosition,
      grabOffset: session.grabOffset,
      itemPixelSize: session.itemPixelSize,
    );

    var reg = targetAt(
      probePoint,
      excludeSourceController: session.origin.controller,
      excludeItemId: session.item.id,
    );
    // Depth limit: dropping a *host* item (one that carries its own nested
    // grid) into a target adds a level below that target. Reject targets that
    // are already at the maximum nesting depth for such items. A plain leaf
    // move adds no level, so it is never blocked here.
    if (reg != null && session.item.hasNestedGrid && !canHostAtDepth(reg.depth)) {
      reg = null;
    }
    final newTarget = reg?.target;
    final oldTarget = session.over;

    if (!identical(newTarget, oldTarget)) {
      oldTarget?.foreignDragLeave();
      _clearNestHover(session);
      session.over = newTarget;
    }
    final over = session.over;
    if (over == null) return;

    // subGridDynamic: hovering a plain item (that hosts no grid yet) freezes
    // the placeholder and arms the nested-grid request after [nestHoverDelay].
    if (subGridDynamic && onNestedGridRequested != null) {
      final overReg = registrationOf(over.controller);
      final host = over.itemAtGlobal(probePoint, excludeId: session.item.id);
      // An item is a candidate for dynamic nesting only if it is dynamic, does
      // not already host a grid (checked via the live link map and the
      // declarative [LayoutItem.hasNestedGrid] flag), and its grid may host one
      // more level (see [maxNestingDepth]).
      final hostable = host != null &&
          !host.isStatic &&
          !host.isSectionBarrier &&
          !host.hasNestedGrid &&
          !hasChildGrid(over.controller, host.id) &&
          (overReg == null || canHostAtDepth(overReg.depth));
      if (hostable) {
        if (session.nestHoverId != host.id) {
          _clearNestHover(session);
          session
            ..nestHoverId = host.id
            ..nestHoverTarget = over;
          over
            ..foreignDragLeave() // freeze: revert pushes so the host stays put
            ..setNestHoverHighlight(host.id);
          session.nestTimer = Timer(nestHoverDelay, () {
            final current = _session;
            if (current == null || current.nestHoverId != host.id) return;
            notifyNestRequestFired(host, over.controller);
            onNestedGridRequested?.call(host, current.item, over.controller);
          });
        }
        return; // frozen: no placeholder while arming
      }
      if (session.nestHoverId != null) _clearNestHover(session);
    }

    over.foreignDragOver(session.item, probePoint);
  }

  /// Finalizes an active session on pointer-up.
  ///
  /// Returns the placed item when the item landed in a grid (possibly its
  /// origin), or null when the drop happened over no grid — in which case the
  /// origin layout is restored.
  LayoutItem? dropSession(Offset globalPosition) {
    final session = _session;
    if (session == null) return null;

    updateSession(globalPosition);
    final over = session.over;
    final originImpl = session.origin.controller.internal;

    LayoutItem? placed;
    if (over != null) {
      placed = over.foreignDrop(session.item);
    }

    if (placed == null) {
      resolveNestRequest(null);
      originImpl.finishCrossGridExit(outcome: CrossGridExitOutcome.canceled);
      _clearSession(restoreOrigin: false); // already restored above
      return null;
    }

    final movedAway = !identical(over!.controller, session.origin.controller);
    originImpl.finishCrossGridExit(
      outcome: movedAway ? CrossGridExitOutcome.movedAway : CrossGridExitOutcome.returned,
    );
    if (movedAway) {
      onItemMovedToGrid?.call(placed, session.origin.controller, over.controller);
    }
    resolveNestRequest(over.controller);
    _clearSession(restoreOrigin: false);
    return placed;
  }

  /// Cancels an active session (Escape, pointer cancel, disposal) and
  /// restores the source grid to its pre-drag layout.
  void cancelSession() {
    final session = _session;
    if (session == null) return;
    resolveNestRequest(null);
    session.over?.foreignDragLeave();
    session.origin.controller.internal.finishCrossGridExit(outcome: CrossGridExitOutcome.canceled);
    _clearSession(restoreOrigin: false);
  }

  void _clearNestHover(_CrossGridSession session) {
    session.nestTimer?.cancel();
    session.nestTimer = null;
    session.nestHoverTarget?.setNestHoverHighlight(null);
    session
      ..nestHoverTarget = null
      ..nestHoverId = null;
  }

  void _clearSession({required bool restoreOrigin}) {
    final session = _session;
    if (session == null) return;
    _clearNestHover(session);
    if (restoreOrigin) {
      session.origin.controller.internal
          .finishCrossGridExit(outcome: CrossGridExitOutcome.canceled);
    }
    session.proxyEntry?.remove();
    session.proxyPosition.dispose();
    _session = null;
  }

  /// Moves [itemId] from [from] to [to], preserving its size and constraints.
  ///
  /// When [x]/[y] are omitted the item is auto-placed by the target's
  /// compaction strategy. Returns the placed item, or null when the item was
  /// not found. All-or-nothing: on failure neither grid is modified.
  LayoutItem? moveItemToGrid({
    required DashboardController from,
    required DashboardController to,
    required String itemId,
    int? x,
    int? y,
  }) {
    if (identical(from, to)) return null;
    LayoutItem? item;
    for (final i in from.layout.value) {
      if (i.id == itemId) {
        item = i;
        break;
      }
    }
    if (item == null) return null;
    assert(
      !to.layout.value.any((i) => i.id == itemId),
      'moveItemToGrid: target grid already contains an item with id "$itemId"',
    );

    from.removeItems([itemId]);
    // Explicit coordinates are honored as-is by the placement engine; when
    // omitted, (-1, -1) triggers auto-placement with the appendBottom strategy.
    final moved = (x != null && y != null)
        ? item.copyWith(x: x, y: y, moved: false)
        : item.copyWith(x: -1, y: -1, moved: false);
    to.addItem(moved);
    var placed = moved;
    for (final i in to.layout.value) {
      if (i.id == itemId) {
        placed = i;
        break;
      }
    }
    onItemMovedToGrid?.call(placed, from, to);
    return placed;
  }

  // --- Tree export / deferred child layouts ---

  /// Stashes grid data for a nested grid that has not mounted yet.
  ///
  /// NestedDashboard consumes it (keyed by the host item id) on first
  /// registration, enabling one-call tree loading.
  void stashChildGrid(String parentItemId, NestedGridData data) {
    _pendingChildGrids[parentItemId] = data;
  }

  /// Takes (and removes) stashed grid data for [parentItemId], if any.
  NestedGridData? takeStashedChildGrid(String parentItemId) =>
      _pendingChildGrids.remove(parentItemId);

  /// Delivers grid data to the nested grid hosted by [parentItemId]: applies
  /// it immediately when that grid is already mounted, otherwise stashes it
  /// for consumption on mount. Used by `loadNestedTree` so that re-loading a
  /// tree over live grids works without a remount.
  void deliverChildGrid(String parentItemId, NestedGridData data) {
    // Links (not registrations) so delivery also reaches linked grids whose
    // NestedDashboard is currently unmounted by virtualization.
    for (final entry in _childLinks.entries) {
      if (entry.value.itemId == parentItemId) {
        final controller = entry.key;
        if (data.slotCount != null && data.slotCount! > 0) {
          controller.setSlotCount(data.slotCount!);
        }
        controller.importLayout([for (final i in data.items) i.toMap()]);
        return;
      }
    }
    stashChildGrid(parentItemId, data);
  }

  /// Releases coordinator resources. Called by the scope on dispose.
  void dispose() {
    _pendingNestRequest = null; // teardown
    _clearSession(restoreOrigin: true);
    _registrations.clear();
    _pendingChildGrids.clear();
    _childLinks.clear();
  }
}

class _CrossGridSession {
  _CrossGridSession({
    required this.item,
    required this.origin,
    required this.grabOffset,
    required this.itemPixelSize,
    required this.proxyPosition,
    required this.proxyEntry,
  });

  final LayoutItem item;
  final CrossGridDragTarget origin;
  final Offset grabOffset;
  final Size itemPixelSize;
  final ValueNotifier<Offset> proxyPosition;
  final OverlayEntry? proxyEntry;

  CrossGridDragTarget? over;

  // subGridDynamic hover state
  String? nestHoverId;
  CrossGridDragTarget? nestHoverTarget;
  Timer? nestTimer;
}

/// Enables nested dashboards and cross-grid drag & drop for every Dashboard
/// in its subtree.
///
/// Wrap the common ancestor of all related dashboards (typically above the
/// root Dashboard) — nested NestedDashboard's register automatically:
///
/// ```dart
/// DashboardNestedScope(
///   onItemMovedToGrid: (item, from, to) => save(),
///   child: Dashboard(controller: root, itemBuilder: buildItem),
/// )
/// ```
///
/// Without this scope, dashboards behave exactly as before: the nested layer
/// adds zero work to single-grid setups.
class DashboardNestedScope extends StatefulWidget {
  /// Creates a scope enabling cross-grid interactions for its subtree.
  const DashboardNestedScope({
    required this.child,
    super.key,
    this.coordinator,
    this.onItemMovedToGrid,
    this.onNestedGridRequested,
    this.onNestedGridRequestAbandoned,
    this.subGridDynamic = false,
    this.subGridDynamicSameGrid = false,
    this.nestHoverDelay = const Duration(milliseconds: 600),
    this.probe = CrossGridProbe.pointer,
    this.maxNestingDepth,
  });

  /// The subtree containing the dashboards.
  final Widget child;

  /// Optional externally-owned coordinator (for testing or advanced setups).
  /// When null, the scope creates and owns one.
  final DashboardNestedCoordinator? coordinator;

  /// Fired after every successful cross-grid move.
  final DashboardItemMovedToGridCallback? onItemMovedToGrid;

  /// Fired when a dynamic nested grid is requested (see [subGridDynamic]).
  final DashboardNestedGridRequestCallback? onNestedGridRequested;

  /// Fired when a nested-grid request is abandoned (drag ended without
  /// dropping into the requested host's child grid). See
  /// [DashboardNestedCoordinator.onNestedGridRequestAbandoned].
  final DashboardNestedGridAbandonedCallback? onNestedGridRequestAbandoned;

  /// Enables `subGridDynamic` behavior: holding a dragged item
  /// over a plain item arms a request to convert it into a nested grid.
  final bool subGridDynamic;

  /// Extends [subGridDynamic] to same-grid drags: pausing the pointer during
  /// an in-grid drag freezes the pushes and arms the hovered sibling.
  /// See [DashboardNestedCoordinator.subGridDynamicSameGrid]. Default: false.
  final bool subGridDynamicSameGrid;

  /// Hover duration before [onNestedGridRequested] fires.
  final Duration nestHoverDelay;

  /// Which point decides the grid under a cross-grid drag
  /// (pointer — default — or the dragged tile's center).
  final CrossGridProbe probe;

  /// Maximum nesting depth, or null (default) for no limit.
  ///
  /// The root grid is level 0. `1` allows one level of nesting; `0` disables
  /// nesting. See [DashboardNestedCoordinator.maxNestingDepth].
  final int? maxNestingDepth;

  /// The coordinator of the nearest enclosing scope, or null.
  static DashboardNestedCoordinator? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DashboardNestedScopeProvider>()?.coordinator;

  @override
  State<DashboardNestedScope> createState() => _DashboardNestedScopeState();
}

class _DashboardNestedScopeState extends State<DashboardNestedScope> {
  late DashboardNestedCoordinator _coordinator;
  late bool _ownsCoordinator;

  @override
  void initState() {
    super.initState();
    _ownsCoordinator = widget.coordinator == null;
    _coordinator = widget.coordinator ?? DashboardNestedCoordinator();
    _syncCoordinator();
  }

  @override
  void didUpdateWidget(covariant DashboardNestedScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCoordinator();
  }

  void _syncCoordinator() {
    _coordinator
      ..onItemMovedToGrid = widget.onItemMovedToGrid
      ..onNestedGridRequested = widget.onNestedGridRequested
      ..onNestedGridRequestAbandoned = widget.onNestedGridRequestAbandoned
      ..subGridDynamic = widget.subGridDynamic
      ..subGridDynamicSameGrid = widget.subGridDynamicSameGrid
      ..nestHoverDelay = widget.nestHoverDelay
      ..probe = widget.probe
      ..maxNestingDepth = widget.maxNestingDepth;
  }

  @override
  void dispose() {
    if (_ownsCoordinator) _coordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DashboardNestedScopeProvider(
      coordinator: _coordinator,
      child: widget.child,
    );
  }
}

class _DashboardNestedScopeProvider extends InheritedWidget {
  const _DashboardNestedScopeProvider({
    required this.coordinator,
    required super.child,
  });

  final DashboardNestedCoordinator coordinator;

  @override
  bool updateShouldNotify(_DashboardNestedScopeProvider oldWidget) =>
      !identical(coordinator, oldWidget.coordinator);
}

/// Serializable payload of one nested grid: its layout and (optionally) its
/// slot count. Saves the container column for nested grids,
/// and NestedDashboard.autoSlotCount may override it at
/// runtime from the host item width.
class NestedGridData {
  /// Creates the payload.
  const NestedGridData({required this.items, this.slotCount});

  /// The child grid layout.
  final List<LayoutItem> items;

  /// The child grid slot count at save time, if recorded.
  final int? slotCount;
}
