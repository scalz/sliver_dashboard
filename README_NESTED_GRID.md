# Nested Grids — `sliver_dashboard`

Grids inside grid items, **continuous
drag & drop between any grids** (parent ↔ child ↔ siblings, any depth),
auto-sized hosts, dynamic sub-grid creation, and recursive save/load.

**Zero breaking change**: every new parameter is optional, and without a
`DashboardNestedScope` in the tree the added code paths reduce to a single
null-check per pointer event.

---

## 1. Quick start

```dart
final root   = DashboardController(initialLayout: [...]);
final group1 = DashboardController(initialLayout: [...]);

DashboardNestedScope(
onItemMovedToGrid: (item, from, to) => persist(),
child: Dashboard(
controller: root,
itemBuilder: (context, item) {
// Branch on the declarative flag (LayoutItem.hasNestedGrid) rather
// than on ids: hosts stay portable between grids and across save/load.
if (item.hasNestedGrid) {
return NestedDashboard(
controller: group1,
parentItemId: item.id,       // required: links the tree
itemBuilder: buildLeafItem,
sizeToContent: true,         // host grows/shrinks with content
);
}
return buildLeafItem(context, item);
},
),
)
```

That's all: with both grids in edit mode, items drag seamlessly in and out of
`group-1`, with the live push-preview placeholder in whichever grid is hovered.

## 3. Architecture (respects the project layering)

- **engine** — untouched. All cross-grid math reuses `moveElement` /
  compactors through the existing placeholder path.
- **controller** (`DashboardControllerImpl`, accessed via `.internal`):
  - `beginCrossGridExit(ids)` — temporary removal, **silent** (no
    `onLayoutChanged` mid-gesture), returns pre-drag geometry; internal drag
    state reset without the drop compaction.
  - `finishCrossGridExit(outcome:)` — `movedAway` (commit + one event),
    `returned` (discard silently: the re-insert already emitted), `canceled`
    (restore pre-drag snapshot).
  - `onDropExternalItem(template:)` — like `onDropExternal` but preserves id,
    min/max, flags. `setItemSize(id, w:, h:)` — clamped programmatic resize.
  - `hoveredNestTargetId` beacon — `subGridDynamic` highlight; only the light
    item shells rebuild (content stays behind its `RepaintBoundary`).
- **view**:
  - `DashboardNestedScope` / `DashboardNestedCoordinator` — registry
    (depth-ordered), pointer claim, cross-grid session state machine, proxy,
    tree links, stash. O(G) per pointer event, G = number of live grids.
    Also resolves **drop targets** during a session (§5quinquies): the hovered
    item is probed once per event and shared with the `subGridDynamic` arming,
    and the two hover states are mutually exclusive.
  - `DashboardOverlay` — implements `CrossGridDragTarget`; **hit-test
    ownership fix** (entries from a nested sliver are skipped so the parent
    resolves to its own host item instead of crashing on a foreign id);
    `_showPlaceholderAt` refactor shared by the `DragTarget` path and
    cross-grid drags; auto-scroll driven on whichever grid is hovered.
  - `NestedDashboard` — child `Dashboard` + registration + `autoSlotCount` +
    `sizeToContent` (post-frame, loop-guarded, skipped while the parent grid
    is mid-gesture).

### Performance notes (quantified)

- Without a scope: 1 null-check in `_onPointerDown`, 1 in `_onPointerMove`, 1
  in `_performUpdate`. No allocation, no registry.
- Without an `onItemDroppedOnHost` callback: the drop-target resolver returns
  on a single null-check, so §5quinquies costs nothing per pointer event.
- With a scope: `targetAt` is O(G) point-in-rect tests per pointer event
  (G = live grids, typically 2–5) — control-plane cost, never per item.
- During a cross-grid hover, the hovered grid runs exactly the pre-existing
  external-drag path (`showPlaceholder`): same cost as the already-shipped
  `DragTarget` flow, now on the audit-patched `FastVerticalCompactor`.
- Proxy: one `OverlayEntry` + `ValueNotifier<Offset>`; only the proxy
  repositions per event, no grid rebuilds beyond the placeholder diff.

## 4. `subGridDynamic`

```dart
DashboardNestedScope(
  subGridDynamic: true,
  nestHoverDelay: const Duration(milliseconds: 600),
  onNestedGridRequested: (host, dragged, hostGrid) {
    // 1. Mark `host` as a group in your app state so your itemBuilder now
    //    returns a NestedDashboard for it (create/lookup its controller).
    // 2. Move the dragged item into it:
    coordinator.moveItemToGrid(from: hostGrid, to: newChild, itemId: dragged.id);
  },
  child: ...,
)
```

While the user holds a dragged item over a plain item, the placeholder is
frozen (pushes reverted so the host stays under the cursor — hover detection
runs against the pre-push snapshot), the host shows the highlight ring, and
after `nestHoverDelay` the callback fires. Content creation is app-side in
Flutter — see divergences below.

## 5. Serialization

```dart
final tree = exportNestedTree(coordinator, rootController); // JSON-encodable
loadNestedTree(coordinator, rootController, tree);          // one call
```

Payloads for grids that are not mounted yet are stashed and applied
automatically when their `NestedDashboard` mounts. **Item ids must be unique
across the whole tree** (the same invariant cross-grid moves rely on; asserted
in debug on `moveItemToGrid`).

## 5quinquies. Drop targets — closed hosts & custom tiles

A tile can **receive** dropped items without rendering a nested grid: a closed
folder icon, an archive bin, an "add to group" badge. This is the counterpart
of `subGridDynamic`: there, hovering *creates* a grid; here, the tile swallows
the drop and nothing is created.

```dart
DashboardNestedScope(
  onItemDroppedOnHost: (draggedItems, host, hostGrid, sourceGrid) {
    // The layout is already back to its pre-drag state: nothing landed on
    // any grid, and the items are still in the grid the drag started from.
    sourceGrid.removeItems(draggedItems.map((i) => i.id).toList());
    myFolderModel.addAll(host.id, draggedItems);
  },
  child: ...,
)
```

A tile is a drop target when either:

- it carries `hasNestedGrid: true` **while its child grid is not mounted** —
  a *closed* host. The mounted case is deliberately excluded: there the
  pointer can enter the child sliver, and the regular cross-grid session owns
  the interaction. This is what makes collapsible folders work: mount the
  `NestedDashboard` and the tile is a grid; render something else (an icon)
  and the same tile is a drop target — see the `nested2` example, which
  drives the swap from an `itemBreakpointBuilder`;
- or it is flagged `LayoutItem(isDropTarget: true)` — an explicit target,
  which needs no nesting at all (`Dashboard.onItemDroppedOnHost` works
  without a scope for that case).

**Collapsing is an app decision.** `NestedDashboard` deliberately does *not*
unlink on unmount (sliver virtualization unmounts it whenever the host leaves
the viewport, and the link must survive that). So when you swap a mounted
grid for a closed-folder rendering, call
`coordinator.unlinkChildGrid(childController)` yourself — expanding re-links
automatically when `NestedDashboard` mounts again. Keep the child controller
alive (own it in your `State`) so the contents survive the round trip.

**Interaction model.** While a target is hovered, layout pushes freeze so it
stays under the cursor, the placement preview is withdrawn (the item must
never look like it is about to land where it will be swallowed), and the tile
shows the nest highlight — stylable via `DashboardItemStyle(nestTargetColor:
..., nestTargetDecoration: ...)`. Targeting is by **pointer position**, so the
dragged item may be larger than the target. On release the drag resolves as a
silent exit: the items go back where they started and the callback decides
what the drop means — doing nothing rejects it, and they simply stay home.

**Same-grid and cross-grid.** Both work: an item pulled out of an open folder
(or any sibling grid) can be filed straight into a closed one. Same-grid drags
resolve in the overlay; cross-grid drags resolve in the coordinator's session,
through the existing `CrossGridExitOutcome.canceled` path — no new transaction
state, so the "at most one `onLayoutChanged` per grid per cross-grid gesture"
invariant is untouched. `sourceGrid` (4th argument) is the grid holding the
items now, `hostGrid` the one owning the target tile; for a same-grid drop
they are the same controller.

An `isDropTarget` tile never arms `subGridDynamic`: an explicit target must
not also be a speculative nest candidate.

## 5quater-bis. Same-grid dynamic nesting (`subGridDynamicSameGrid`)

`DashboardNestedScope(subGridDynamicSameGrid: true)` extends dynamic nesting
to drags that never leave their own grid (independent of `subGridDynamic`:
either flag may be enabled alone). Because an
in-grid drag pushes its neighbours on every frame, a hovered sibling is
normally shoved away before the pointer can rest on it; the pause detector
solves this: keep the pointer stationary for a short beat (~350 ms) and the
pushes freeze (the pre-drag layout is restored while the drag stays alive),
the sibling under the pointer is highlighted, and after `nestHoverDelay` the
usual `onNestedGridRequested(host, dragged, controller)` fires. From there
the flow is identical to the cross-grid case: convert the host in your
callback (flip `hasNestedGrid` via `updateItem`, mount a `NestedDashboard`),
and the held drag hands itself over to the freshly mounted grid on the next
pointer move — or on the release itself, which drops the item straight into
the new panel. Moving the pointer before the delay elapses cancels
everything and resumes the drag exactly where it was. The option is off by
default: the visible freeze changes the feel of the drag, which is why the
equivalent behavior is opt-in. `maxNestingDepth` and the
single-item rule apply as usual, and pausing over the trash never arms.

Because the request is speculative (the app converts the host *before* the
drop is committed), the drag may still end elsewhere. Wire
`onNestedGridRequestAbandoned(host, hostGridController)` — fired for both the
same-grid and the cross-grid arming paths whenever the drag ends without the
item landing in the requested host's child grid — and revert the conversion
there: clear the `hasNestedGrid` flag (`updateItem`, `recompact: false`),
unlink and dispose the child controller. Without it, every armed-but-unused
leaf stays converted as an empty nested grid. Make the revert conditional on
the child grid being **empty**: if anything already landed in it, the
conversion is no longer speculative, and a revert handler must never destroy
delivered items (defense in depth against any spurious abandon).

## 5quater. Limiting nesting depth

`DashboardNestedScope(maxNestingDepth: n)` caps how deep users can nest. The
root grid is level 0, so `1` allows one level of nested grids, and `0` turns
nesting off entirely; `null` (the default) means no limit. The cap is enforced
only where a *new level* would be created — dropping a host item into a grid
that is already at the limit, or arming `subGridDynamic` on such a grid.
Moving a plain leaf between grids never creates a level and is never blocked,
and `moveItemToGrid` is left to the caller. `coordinator.canHostAtDepth(depth)`
exposes the same test so you can, say, hide an "add sub-grid" button.

## 5ter. The `hasNestedGrid` flag

`LayoutItem.hasNestedGrid` (default `false`) is declarative metadata marking a
host item. What it buys: generic builders (see quick start) that make whole
groups draggable between grids without id coupling; persistence through plain
`exportLayout`/`importLayout` round-trips; `DashboardPolicy` targeting (e.g.
"nothing may push a group"). It is part of `contentSignature`, so converting
an item to/from a host invalidates its cached widget and the builder swap
takes effect immediately. The nested codec keeps it consistent automatically:
exports set it on linked hosts, imports set it on items carrying a `subGrid`
payload. `subGridDynamic` never arms on a flagged item — and a flagged item whose child
grid is **not mounted** is treated as a closed host, i.e. a drop target
(§5quinquies). Note it remains
*declarative*: the runtime source of truth for "which grids exist" is the
coordinator's link map — the flag complements it, it does not replace it.

## 5bis. Interaction fine-tuning

### Which point decides the target grid — `CrossGridProbe`

By default the **pointer position** decides which grid a dragged tile enters.
Consequence: if the tile is grabbed far from its center,
its body can visually overlap — and therefore *push* — a nested-grid host item
while the pointer is still over the parent grid; only when the pointer itself
crosses into the nested area does the tile enter it. So "push the host" vs
"enter the host" depends on where the tile was grabbed.

`DashboardNestedScope(probe: CrossGridProbe.itemCenter)` makes the **dragged
tile's visual center** the probe instead: target detection *and* placeholder
placement follow the tile's center, so the behavior no longer depends on the
grab point. Trade-off: with a very large tile over a small nested grid, entry
happens later (when the center crosses), which can feel delayed — hence
pointer stays the default.

### Auto-scroll and `sizeToContent`

Two complementary behaviors, chosen per `NestedDashboard`:

- **`sizeToContent: false` (default):** the host item keeps its size; the
  nested grid scrolls internally with its own edge auto-scroll during child
  drags. This is the "fixed-size window" mode.
- **`sizeToContent: true`:** the host item grows/shrinks with the content and
  the nested grid never scrolls internally. Since its scroll view cannot
  scroll, its edge auto-scroll is **delegated to the parent grid**: dragging a
  child tile toward the bottom edge grows the host *and* scrolls the parent
  viewport to keep revealing it. Delegation is recursive (a sizeToContent grid
  inside a sizeToContent grid bubbles up to the first scrollable ancestor
  grid) and applies to cross-grid hovers over such grids too.