## 2.0.0

### Highlights

Sliver Dashboard 2.0 turns the single grid into a multi-grid system:
dashboards nest inside items, and items drag freely across
grids — nested, siblings, or independent slivers sharing one scroll view —
with dimension projection between different column counts. Tiles can slide
with GPU-only reflow animations (opt-in), the minimap gains overlay markers,
multiple viewport indicators and pixel-exact scroll mapping, and desktop
interactions get O(1) hover resolution with jitter-free nest targeting. The
whole tree saves and restores in one call.

**No API breaking changes.** All new parameters are optional with defaults
preserving 1.x behavior; without a `DashboardNestedScope` in the tree, the
new code paths reduce to a few null-checks per pointer event.

**Behavioral changes** (corrections of 1.x defects that are observable):

- The minimap's viewport indicator and tap-to-scroll now map onto the
  *grid's own scroll segment* (auto-derived from exact metrics the grid
  sliver publishes at each layout pass) instead of the whole scrollable.
  Bare-grid setups render identically; scrollables containing app bars,
  section headers or a `fillViewport` filler now render correctly instead
  of drawing the indicator at the wrong place/size. Override with
  `DashboardMinimap.mainAxisLeadingExtent` / `mainAxisContentExtent`.
- Under main-axis compaction, the in-grid drag target is capped to the
  first free row/column past the other items: the grid no longer grows one
  row per row crossed below the content (which made anything after the
  grid recede at the pointer's own speed). Dropping deeper compacted
  straight back anyway, so no capability is lost. Free positioning under
  `CompactType.none` and custom compactors is unchanged.

### New Features

- **`NestedDashboard`**: embed a full dashboard inside a grid item at any depth.
- **Cross-grid drag & drop**: drag items between a parent grid,
  its nested grids, and sibling grids under a shared `DashboardNestedScope`.
  Live push-preview placeholder in whichever grid is hovered, floating drag
  proxy (honors `itemFeedbackBuilder`), auto-scroll on the hovered grid,
  constraint/flag/id preservation, and pre-drag restore when a drop lands on
  no grid. Exactly one `onLayoutChanged` per affected grid, emitted at drop
  time (never mid-gesture). The source grid keeps its geometry frozen (a
  hole where the item left) for the whole session, and approaching an item
  that already hosts a child grid freezes the collision pushes — so a
  target grid never shifts away from the pointer mid-drag.
- **`DashboardNestedScope`**: opt-in coordinator scope with
  `onItemMovedToGrid`, `subGridDynamic`, `nestHoverDelay`,
  `onNestedGridRequested`.
- **`autoSlotCount`**: the nested grid's slot
  count follows its host item width, keeping inner/outer cells visually
  consistent during host resizes.
- **`sizeToContent`** (+ `sizeToContentMax`, `chromeExtent`): the host item
  auto-grows/shrinks so the nested grid never scrolls internally. Manual
  host resizes are not fought mid-gesture (the content-driven height sync
  pauses during drag *and* resize, on both the parent and the child grid),
  and background grid lines are painted only for the rows the content
  occupies (new `Dashboard.fillViewport` param, default `true`, set to
  `false` by `NestedDashboard` under `sizeToContent`).
- **`subGridDynamic`**: holding a dragged item over a plain item highlights it
  and fires `onNestedGridRequested` after `nestHoverDelay`, letting the app
  convert it into a nested grid.
- **Recursive persistence**: `exportNestedTree` / `loadNestedTree` save and
  restore the whole tree in one call — robust to sliver virtualization
  (parent links persist while a host item is scrolled out of view, so its
  subtree still exports; call `coordinator.unlinkChildGrid` when removing a
  nested grid permanently) (`subGrid: {slotCount, items}` payloads,
  delivered automatically to grids that mount later).
- **Programmatic moves**: `DashboardNestedCoordinator.moveItemToGrid`.
- **`maxNestingDepth`** (`DashboardNestedScope` / `DashboardNestedCoordinator`,
  default `null` = unlimited): caps how many nesting levels users can create.
  The root grid is level 0, so `1` allows one level of nesting and `0`
  disables it. Enforced where levels are *created* — cross-grid drops of a
  host item, and `subGridDynamic` arming — while plain leaf moves and explicit
  `moveItemToGrid` calls are unaffected. `canHostAtDepth(depth)` exposes the
  same predicate for building UI affordances.
- **`CrossGridProbe`** (`DashboardNestedScope.probe`): choose whether the
  pointer (default) or the dragged tile's visual center decides which grid it
  enters — the latter makes enter-vs-push independent of where the tile was
  grabbed.
- **Auto-scroll delegation**: grids whose own scroll view cannot scroll
  (`sizeToContent` nested grids) forward edge auto-scroll to their parent
  grid, recursively — dragging a child tile downward grows the host *and*
  scrolls the parent to follow.
- **New optional `Dashboard` parameters**: `crossGridDragOut`,
  `acceptCrossGridItems` (both default `true`, only meaningful inside a
  scope).
- **`LayoutItem.hasNestedGrid`** (default `false`): declarative flag marking
  items that host a nested dashboard. Lets a shared `itemBuilder` branch
  generically (`if (item.hasNestedGrid) return NestedDashboard(...)`) — which
  makes whole groups portable between grids without id coupling — travels
  through plain `exportLayout`/`importLayout` round-trips, is targetable by
  `DashboardPolicy`, and is included in `contentSignature` (toggling it
  invalidates the cached item widget). The nested codec self-heals it: linked
  hosts export with the flag set, and items carrying a `subGrid` payload are
  normalized to `hasNestedGrid: true` on import. `subGridDynamic` skips
  arming on flagged items even when their grid was never linked in the
  session.
- **`DashboardController.updateItem(id, transform, {recompact})`**: safe,
  controller-owned single-item mutation (flags, title, constraints, size),
  replacing hand-written `layout.value` rewrites. No-op on unknown id or an
  equal result, id changes are rejected (assert in debug, defensively
  restored in release), transformed geometry is passed through bound
  correction so invalid `w`/`h`/position cannot corrupt the layout, and
  exactly one `onLayoutChanged` fires per effective change.
  `recompact: false` skips pulling items back for metadata-only edits.
- **`DashboardController.replaceItem`**: A new public API to swap/replace an existing
  grid item in-place. Automatically enforces ascending ID order, corrects bounds,
  and performs write-through updates to active pre-drag snapshots. Designed to support
  clean dynamic nested grid group/folder conversions on hover.
- New controller capabilities (internal API): temporary cross-grid removal
  with three-way resolution (`movedAway` / `returned` / `canceled`),
  template-preserving external drop (`onDropExternalItem`), programmatic
  clamped resize (`setItemSize`).
- **Cross-Sliver Drag & Drop:** Drag tiles between independent sibling
  `SliverDashboard` widgets separated by other native slivers (e.g.
  `SliverAppBar`, `SliverList`) within the same `DashboardNestedScope`.
  Containment is sliver-precise and allocation-free; dragging into empty
  space outside the sliver opens a session behind an exit hysteresis and
  never shadows the trash flow. In multi-sliver trees, each overlay needs a
  `sliverKey`, an explicit `controller`, and a `padding` matching the
  surrounding `SliverPadding`.
- **Dimension Projection Policies:** Added a configurable `projectionPolicy` with three modes:
  - `preserveLogicalSize`: Keeps the exact original grid dimensions (e.g. 2x2 remains 2x2).
  - `preserveVisualProportion`: Automatically scales tile dimensions proportionally based on the column count ratio between the source and target grids (e.g., a w:2 item in an 8-col grid scales down to w:1 in a 4-col grid, keeping its visual 25% width ratio).
  - `custom`: Delegates the scaling arithmetic to a developer-defined `customProjectionCallback`.
    Projection output is always sanitized against the target grid — including
    custom callback output — and memoized per session.
- **Shadowing Decoupling:** Added the optional `controller` parameter to
  `SliverDashboard` and `sliverKey` to `DashboardOverlay` to safely support
  multiple concurrent sliver grids in the same viewport without context
  collision or shadowing.
- **Paint-Phase Reflow Animations** (`animateReflow`, default `false`):
  pushed/compacted tiles slide smoothly (150 ms, `reflowDuration`)
  to their new slot during drags and resizes. Layout stays instantaneous and
  deterministic — only the painted offset interpolates, translating each
  tile's cached `RepaintBoundary` layer on the GPU: zero widget rebuilds,
  zero re-rasterization, zero allocation per paint pass. Slot-metric changes
  (viewport resize, breakpoints, slot count) snap by design; hit-testing and
  semantics use the final position immediately.
- **Exact minimap scroll mapping**: the grid sliver publishes its real
  `precedingScrollExtent`, scroll extent and live slot sizes onto the
  controller at each layout pass; `DashboardMinimap` uses them to map its
  viewport indicator and tap-to-scroll pixel-exactly (see Behavioral
  changes), with `mainAxisLeadingExtent` / `mainAxisContentExtent`
  overrides.
- **Minimap markers** (`DashboardMinimap.markers`): custom overlay markers
  (status dots, badges — circle/square/diamond/triangle, per-item alignment)
  rendered in a dedicated cached layer. All markers are batched into one
  `Path` per distinct color; the layer re-rasterizes only when the marker
  list changes by value, never on scroll. A marker's `size` is a maximum:
  it is capped to its tile's minimap rectangle.
- **Multiple viewport indicators** (`DashboardMinimap.viewportIndicators`):
  several `ViewportIndicator`s (one per scroll segment / sibling grid), each
  with its own segment mapping (`mainAxisLeadingExtent` /
  `mainAxisContentExtent`) and style overrides. Painted by the single
  scroll-bound viewport layer. For a single grid, omit this and let the
  default indicator map itself automatically.
- **Hover spatial index**: `itemAtGlobal` resolves through an O(1)
  coordinate-bucket index above 16 items (identity-cached per layout list
  instance) instead of an O(N) scan per pointer event.
- **Hover jitter filter** (`hoverJitterTolerance`, default 4 px): low-pass on
  nest-hover host switching — sub-tolerance pointer noise at tile borders no
  longer flickers the highlight or restarts the nest-hover timer.

### Bug Fixes

- **Auto-scroll tick placeholder re-anchoring**: while auto-scrolling under a
  stationary pointer, the tick re-anchored any active placeholder with the
  `DragTarget` size (`placeholderWidth/Height`) and could resurrect a
  placeholder from a stale position; it now uses the hovering item's real
  size for cross-grid drags and only re-anchors when a hover is actually
  active.
- **Overlay hit-testing with nested dashboards**: the overlay previously
  returned the first grid item found on the hit-test path, which for nested
  layouts is an item of the *inner* grid — crashing the outer grid's drag
  start on an unknown id. Hit-test entries are now filtered by sliver
  ownership, so the outer grid correctly resolves to its own host item.
- **Placeholder Collision Policies**: Fixed an issue where the drag-over
  placeholder ignored `DashboardPolicy` rules (specifically custom `canCollide` exclusions),
  causing protected items (like folders/panels) to be pushed during external
  or cross-grid hover events.
- **Sliver Layout Caching**: Resolved an issue where programmatic slot count updates on empty or unmodified grids were ignored due to constraint-caching optimization.
- **Intuitive Resizing Anchors:** Fixed a layout defect where resizing an item's top or left edge against a static obstacle, section barrier, or grid boundary caused the item to expand downwards or rightwards. The layout engine now strictly respects the opposite edge as a fixed anchor during resize operations, stopping the resize interaction immediately when a static boundary is reached.
- **Unbounded drag growth** (see Behavioral changes): in-grid drags below
  the content no longer grow the grid indefinitely under main-axis
  compaction, so slivers placed after the grid stay reachable mid-drag.
- **Minimap viewport mapping** (see Behavioral changes): the indicator and
  tap-to-scroll are now correct in scrollables containing more than the
  bare grid.
- `MinimapStyle` now implements value equality (`==`/`hashCode`), so painter
  `shouldRepaint` short-circuits even when a style is constructed inline.

### Documentation & Tooling

- `README_NESTED_GRID.md`: feature guide.
- New example entry point `example/lib/nested_example.dart` and a demo
  launcher in `example/lib/main.dart`.
- Test Suite Consolidation & Reorganization: Reorganized, added and improved test files.

## 1.2.0

**No breaking changes in this release.**

### New Features
Easily create per-item breakpoints. The grid already computes every item's pixel size and slotCount during layout, so it now hands them to your builder directly — no extra layout passes.

- **DashboardItemLayoutBuilder**: Added an alternative builder providing live physical pixel dimensions and slotCount, for continuous sub-pixel responsiveness during resize.
- **DashboardItemBreakpointBuilder**: Added an alternative builder, the selective variant — rebuilds only when the resolved breakpoint changes, shielding heavy subtrees from resize churn.
- **DashboardBreakpointResolver**: maps pixel dimensions + item metadata + slotCount to your own layout states.

### Performance & Refinements
- **Granular Rebuild Short-Circuiting**: Isolated physical dimension and slot-count invalidations so that standard `DashboardItemBuilder` execution remains unaffected by resize events.
- **Lazy RenderSliver Lookup & Paint-Phase Alignment**: Deferred sliver metric queries to the paint phase, resolving a first-frame visual grid misalignment when entering edit mode.


## 1.1.1

### Enhancement
- **Interactive Section Barriers**: Section barriers can now be dragged and rearranged in edit mode to easily organize layout sections.

### Bug Fixes
- **Visual Offsets**: Fixed a bug where tiles could temporarily jump out of place or overlap when rebuilding parent widgets (such as toggling the minimap).
- **Immovable Dividers**: Ensured section barriers correctly act as static, immovable layout boundaries during compaction while remaining draggable by the user.
- **Identity Reconciliation**: Resolved element-tracking and focus issues inside the sliver list by assigning stable keys to section barriers.

## 1.1.0

**No breaking changes in this release.**

### New Features
- **DashboardItemStyle.activeColor**: Added `activeColor` to customize the border outline color when an item is actively being dragged.

### Performance Optimizations
- **Monotonic Cascade Solver**: Optimized the collision resolution pipeline in `moveElement` using a monotonic cascade paired with O(N*k) row-indexed queries, replacing the unconditional O(N^2) verification pass on every frame.
- **Fast Skyline Compaction**: Promoted the default controller compaction initialization from the legacy compactor to the O(N log N) Skyline-based `FastVerticalCompactor`.
- **Sliver Index Stability**: Resolved parent tree rebuilds during cluster dragging by sorting layouts alphabetically by ID to guarantee sliver child index stability.
- **Drag Invariant Caching**: Cached drag invariants (pivot, cluster, bounding box) in the controller to prevent redundant allocations during active pointer moves.
- **Key-Map Optimization**: Replaced list key-mapping in `_getOrUpdateKeyToIndex` with an allocation-free string-identity sequence check during active drags.
- **Allocation-Free Layout Pass**: Implemented a reusable `Float64List` scratch buffer in `performLayout` to eliminate `Rect` allocations and reduce minor-GC pressure.
- **Minimap Layer Separation**: Restructured the mini-map to use layered painting (caching item coordinates in a `RepaintBoundary` and painting viewport changes on scroll notifications), reducing canvas repaint draw calls.
- **SlotMetrics Repaint Guard**: Added value-based equality to `SlotMetrics` to prevent redundant background grid painting.
- **Keep-Alive Drag State**: Added temporary `KeepAlive` support on active elements during drags to prevent unnecessary widget lifecycle churn.
- **Web Gesture Throttling**: Added a high-precision `Stopwatch` trailing-edge throttle to safely capture late-arriving pointer positions without overloading the browser thread.

### Bug Fixes & Refinements
- **Programmatic Scroll Safety**: Added safety checks in `scrollToItem` to prevent Future deadlocks when the controller is detached from an active overlay.
- **Bound-Correction Safeguards**: Enhanced `correctBounds` with safeguards for zero/negative coordinates and assertions for breakpoint mismatches.
- **Compaction Determinism**: Introduced alphabetical ID-sorting tie-breakers to `sortLayoutItems` and Skyline compactors to ensure deterministic placement on multi-collision overlaps.
- **Boundary painting bounds**: Optimized row painting inside the grid background custom painter to clamp drawn lines strictly within the visible viewport.

## 1.0.0

### New Features
- **DashboardPolicy API**: Introduced a declarative interaction policy interface (`DashboardPolicy`). You can now intercept, validate, and block drag/resize starts, coordinate moves, or granular item-to-item collisions (e.g. blocking charts from pushing KPIs) on-the-fly without having to write a full custom compaction delegate.
- **Visual Section Barriers & Segmented Grids**: Added support for dividing a single dashboard grid into distinct, organized sections. `LayoutItem` now supports the `isSectionBarrier` flag and `sectionTitle` property. When enabled, the item behaves as an immoveable horizontal divider and renders a section header using either a default style or a fully customizable `sectionHeaderBuilder` callback on `Dashboard` / `SliverDashboard`.
- **Auto-Shrink on Drag**: Introduced adaptive neighbor shrinkage during drag operations. When moving items, enabling `allowAutoShrink` via `setAllowAutoShrink(allow: true)` on the controller allows the engine to dynamically contract neighboring items' heights down to their `minH` limits to make room for the moving item, minimizing vertical layout shifts and offering smoother, more cohesive grid reflows.

- **Unified Interactive Playground**: You can now test all major capabilities (on Web, Desktop, and Mobile), including standard grid vs direct sliver composition, visual section barriers, adaptive neighbor shrinking, live JSON schema export/import editing, custom drag handles, and interactive mini-map scrubbing.

### Bug Fixes
- **Skyline Compactors Overlap Resolutions**: Fixed a layout bug in both `FastHorizontalCompactor` and `FastVerticalCompactor` where widgets exceeding standard slot boundaries along the infinite scroll axis were incorrectly forced to index `0` and overlapped. The compaction engines now dynamically calculate their internal Skyline tide tracking arrays based on the actual physical bounds of the layout, fully supporting infinite rows and columns.

## 0.10.0

### New Features
- **Customizable Auto-Placement**: Added support for dense, gap-filling item placement.
  - Introduced `AutoPlacementStrategy` enum with two strategies:
    - `appendBottom`: The classic behavior, appending new items below the existing layout.
    - `firstFit`: A Tetris-style placement that finds the first available empty slot from the top-left (0,0) to recycle grid fragmentation.
  - Exposed `strategy` parameter in both `addItem` and `addItems` on `DashboardController`.

- **Custom Drag Handles & Gestures**: Touch gestures on mobile devices were hardcoded to long-presses. Introduced the `DragStartGesture` configuration parameter (`longPress`, `tap`, `none`), alongside the `DashboardDragStartListener` and `DashboardDelayedDragStartListener` widgets. You can now fully customize gesture delays or designate dedicated drag handle icons to manipulate dashboard items.


### Bug Fixes
- **Flicker-free Breakpoint Transitions**: Resolved the single-frame flash/blink when resizing across viewport breakpoints. The grid now renders with the previous column layout on the transitioning frame before snapping to the new size, preserving scroll extents and preventing layout shifts. (thx @kamil-matula)
- **Fixed Horizontal Resizing Collisions**: Resolved an issue where resizing items on horizontally scrollable dashboards resulted in vertical collision stacking. Collision pushes and secondary overlap resolutions now dynamically follow the controller's active `compactionType` instead of being vertically hardcoded.
- **Immoveable Static Items in Multi-Selection**: Fixed a case where static items could be dragged and relocated if they were added to a multi-selection group.
- **Mobile Gesture Interruptions**: Resolved an issue on touch devices where system alerts, dragging off-screen, or gesture takeovers left the dashboard locked in an active dragging state.
- **Asynchronous Scroll Safety**: Fixed a bug in `scrollToItem` where an interrupted scroll animation or a disposed `ScrollController` would cause the returned `Future` to hang indefinitely. Scroll animations are now safely encapsulated in a try-catch block to correctly propagate exceptions.
- **Skyline Compactors Enabled**: Upgraded the default dashboard compactors to use the optimized algorithms. This reduces the computational complexity of layout reflows, significantly improving frame rates during rapid dragging and window resizing on large layouts.
- **Non-Destructive Bounds Correction**: Fixed a case where any item with a negative abscisse (`x < 0`) was resized to span the entire column count. The engine now safely clamps the item's width to the maximum available slot space, preserving its original user-defined size.
- **Negative Coordinates Sanitization**: Fixed an edge case where importing malformed layouts with negative Y coordinates (like `y: -1`) under `CompactType.none` (NoCompactor) bypassed validation. It now cleanly clamps negative Y coordinates to 0.

- **Lints**: Maintain backward compatibility with older Flutter versions by temporarily keeping `CustomScrollView`'s `cacheExtent`. This deprecation is ignored locally for now and will be removed once Flutter version will stop to support it.

**No breaking change in this release.**

## 0.9.1

### New Feature
- **Programmatic Scrolling**: Added `scrollToItem` to `DashboardController`.
  - Supports custom `alignment` (0.0 to 1.0), `duration`, and `curve`.
  - Returns a `Future<void>` that completes only when the scroll animation is finished.
  - Automatically uses `jumpTo` instead of `animateTo` when `duration` is set to `Duration.zero`.

- **Fix:** Invalid pointer location in items. (thx @hpoul)
- Update state_beacon
- Tests
 

## 0.9.0

### New Feature
- Added **Pluggable Compaction Strategies**.
  - You can now implement your own compaction algorithms by extending `CompactorDelegate` and passing it to `controller.setCompactor()`.
  - Useful for specific business rules (e.g., "Gravity towards center", "Fixed headers") or performance optimizations.
- **Refactor:** The internal compaction logic now uses the Strategy Pattern (`VerticalCompactor`, `HorizontalCompactor`).
- Huge performance improvements on compaction algorithm
- Added benchmark.dart in tests and results to readme
- Added tests
- Updated README and example

- **Fix:** In free positioning mode (compaction: none), autoscroll of external draggable item.

## 0.8.0

### New Features
- **Multi-Selection & Cluster Drag:**
  - Users can now select multiple items using `Shift` + Click (or `Ctrl`/`Meta`) or customizable keys.
  - Added `multiSelectKeys` to `DashboardShortcuts` to define which keys (e.g. Alt, Shift) trigger multi-selection.
  - Dragging one selected item moves the entire group together.
  - Visual feedback displays all items in the cluster during the drag.
  - Added `toggleSelection(id)` or `clearSelection()`.
- **Batch Operations:**
  - Dragging a selection to the Trash deletes all items in the group.
  - Added `removeItems(List<String>)` to the controller.
- Tests.
- Updated README and main.dart example.

### Breaking Changes
- **Callbacks:**
  - `onLayoutChanged(items)` becomes `onLayoutChanged(items, slotCount)`. This allows to persist layouts specifically for the current breakpoint.
  - `onItemDeleted(item)` is replaced by `onItemsDeleted(List<LayoutItem> items)`.
  - `onWillDelete(item)` now receives `List<LayoutItem> items`.

## 0.7.0

- **Feat:** Enhanced Responsive Behavior with **Layout Memory**.
  - The dashboard now remembers the arrangement of items for each screen size (column count).
  - Switching between Mobile and Desktop layouts restores your specific arrangement for that view.
  - Items added or removed in one view are automatically synced to the others.
  - Added tests.
  - Updated README and main.dart example.

## 0.6.1 - 2025-12-11
- **Fix:** Improved Mini-Map rendering in horizontal mode to prevent the widget from becoming too small.
- **Fix:** Fixed visual misalignment in the Mini-Map. The rendering now correctly accounts for `mainAxisSpacing` and `crossAxisSpacing`.
- Added tests.
- Updated README and main.dart example.

## 0.6.0 - 2025-12-10

- **Feat:** Added `DashboardMinimap` widget.
  - Visualizes the entire dashboard layout in a small, scalable widget.
  - Displays a "Viewport" indicator showing the currently visible area of the dashboard.
  - Customizable via `MinimapStyle`.
  - Tests
  - Updated README and main example 

## 0.5.0 - 2025-12-10

- **Feat:** Added `optimizeLayout()` to the controller. This feature compacts the grid by filling empty gaps (defragmentation), respecting static items and the visual order of elements.
- Updated README and main example

## 0.4.0 - 2025-12-10

**New feature:**

Added full Accessibility (A11y) support.
- **Keyboard Navigation:** Users can now navigate the grid using `Tab`, grab items with `Space`/`Enter`, move them with `Arrow Keys`, and drop them with `Space`/`Enter`.
- **Screen Readers:** Integrated with `SemanticsService` to announce item selection, movement coordinates, and actions.
- **Localization:** All accessibility messages and semantic hints are now fully configurable/localizable via `DashboardGuidance`.
- **Custom Shortcuts:** Key bindings can now be customized via `DashboardShortcuts` (e.g. supporting WASD).
- **Focus Management:** Improved focus retention during drag operations and ensured drag cancellation if focus is lost.
- Tests

**Fix:** 
- Resolved visual glitches where items would overlap temporarily during drag operations.
- Test to avoid regression.

## 0.3.3 - 2025-12-09
- **Fix:** Fixed an issue where item, in sliver composition mode, was not correctly clipped when resizing beyond the viewport bounds.

## 0.3.2 - 2025-12-08
- Improve pub score.

## 0.3.1 - 2025-12-08
- Updated `README.md`

## 0.3.0 - 2025-12-08

**New feature:**

Introduces Sliver direct composition via DashboardOverlay, and decouples interaction logic from the rendering layer.

- Introduced `DashboardOverlay` widget to handle all global interactions (drag, resize, trash, auto-scroll) and background rendering.
- Added `SliverDashboard` widget for direct composition within `CustomScrollView` (allows SliverAppBar, SliverList, etc.).
- Refactored the main `Dashboard` widget to use `DashboardOverlay` internally (backward compatibility).
- **Grid Clipping behavior:** 
  - When using `SliverDashboard` to compose with others slivers, the grid stops precisely at the content end (allowing subsequent slivers to be visible).
  If no subsequent slivers to be visible (eg. `SliverAppBar` + `SliverDashboard`), you can set `fillViewport` to true to extend grid in viewport.
  - When using `Dashboard` widget, in an `Expanded`, the grid fills the viewport, and `fillViewport` has no action. 

**Documentation:**

- Updated `README.md` and `architecture.md` to reflect the new Overlay/Sliver architecture and document the `fillViewport` parameter.
- Added `main_sliver.dart` example demonstrating sliver composition. 

## 0.2.0 - 2025-12-06

**Breaking Changes:**

*   **Refactored Controller API:** `DashboardController` is now a strict interface. Internal methods (like `onDragUpdate`, `dragOffset`, etc.) are no longer exposed publicly. This improves IDE autocompletion and prevents accidental misuse of internal logic.
    *   *Migration:* If you were using internal methods, you should stop doing so as they are managed by the package. If you absolutely need access for advanced custom widgets, you can cast the controller to `DashboardControllerImpl` (not recommended).

**Improvements:**

*   Added `DashboardControllerImpl` to handle logic separately from the interface.

## 0.1.5

* Fix secondary collisions where multiple items pushed by the resizing element would temporarily overlap at the same Y coordinate.
* Add test to verify that multiple items pushed by a resize operation stack correctly instead of merging.

## 0.1.4

* Fix resize behavior during auto-scroll
* Add tests to verify auto-scroll behavior for both resize and external drag scenarios.

## 0.1.3

* Updated README.md

## 0.1.2

* Updated README.md contributing section, architecture.md and added an AGENTS.md file.

## 0.1.1

* Initial release.

## 0.1.0 - 2025-12-05

* Initial release.
