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
