## 1.2.0
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
