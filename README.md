# Sliver Dashboard

[![pub package](https://img.shields.io/pub/v/sliver_dashboard.svg)](https://pub.dev/packages/sliver_dashboard)
[![pub points](https://img.shields.io/pub/points/sliver_dashboard)](https://pub.dev/packages/sliver_dashboard/score)
[![pub downloads](https://img.shields.io/pub/dm/sliver_dashboard)](https://pub.dev/packages/sliver_dashboard)
![Coverage](https://raw.githubusercontent.com/scalz/sliver_dashboard/main/coverage_badge.svg)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

> ⭐️ **Enjoying `sliver_dashboard`?** Consider giving it a star on [GitHub](https://github.com/scalz/sliver_dashboard) and a 👍 on [pub.dev](https://pub.dev/packages/sliver_dashboard) — it helps other developers discover the package!

**A high-performance and scalable dashboard engine for Flutter, built on Slivers.**

`sliver_dashboard` is a sliver-native layout engine for building interactive, user-configurable dashboards with drag & drop, resizing, nested grids, and viewport virtualization. Designed as an engine rather than a monolithic widget, it composes naturally with Flutter's scrolling system while remaining responsive with hundreds or thousands of tiles.

Ideal for analytics platforms, IoT control panels, project management tools, no-code builders, and any application requiring complex, interactive layouts across mobile, desktop, and web.

<p align="center">
  <img src="https://raw.githubusercontent.com/scalz/sliver_dashboard/main/img/single_grid.gif" alt="Sliver Dashboard Demo" width="500"/>
</p>

## Features

- **High Performance:** Built on Flutter's `Sliver` protocol with **smart caching**. It only renders visible items and prevents unnecessary rebuilds of children during drag/resize operations.
- **Sliver Composition:** Integrate the dashboard's grid seamlessly with other slivers like `SliverAppBar` and `SliverList` within a single `CustomScrollView`.
- **Nested Grids:** Embed full dashboards inside grid items (`NestedDashboard`) at any depth, and **drag items between grids** (parent ↔ child ↔ siblings) with a live push-preview placeholder. Supports auto-sizing hosts, dynamic sub-grid creation, and one-call recursive save/load.
- **Cross-Sliver Drag & Drop:** drag tiles between independent sibling `SliverDashboard`s sharing one `CustomScrollView`, with **dimension projection policies** (`preserveLogicalSize`, `preserveVisualProportion`, or a custom callback) translating item sizes between grids of different column counts.
- **Fully Customizable:** Control the number of columns, aspect ratio, spacing, grid and handles style. Items can be draggable, resizable, and static. Support for dedicated **Drag Handles** (`DashboardDragStartListener`) and configurable mobile drag start gestures (long-press, tap, or handle-only).
- **Declarative Interaction Policies (`DashboardPolicy`):** Inject granular business rules (e.g., "charts cannot push system KPIs", "block dragging on Row 0") on-the-fly without having to write custom compaction delegates.
- **Segmented Grids (Section Barriers):** Divide your grid into organized visual sections using static section barriers with custom header builders while maintaining strict collision boundaries.
- **Horizontal & Vertical Layouts:** Supports both vertical (default) and horizontal scrolling directions.
- **Smart Collision Detection:** Choose your desired behavior:
  - **Push:** Items push each other out of the way to avoid overlap.
  - **Push or Shrink:** Items can be shrinked or pushed when resizing a neighbour item.
  - **Auto-Shrink on Drag:** Move large widgets over smaller items, and the engine automatically contracts neighboring elements to clear room.
- **Compaction:** Choose your desired behavior:
  - **None:** Free positioning. Items are not compacted.
  - **Vertical:** Items are compacted to top.
  - **Horizontal:** Items are compacted to left.
  - **Custom:** Implement `CompactorDelegate` to define custom rules (e.g., specific gravity, fixed zones).
- **Built-in Trash:** Easy-to-implement drag-to-delete functionality. Or implement your own using available callbacks.
- **Custom Feedback:** Customize the appearance of items while they are being dragged. Use onInteractionStart callback for haptic feedback...
- **Reflow Animations:** pushed/compacted tiles slide to their new slot.
- **Fluid Resize:** opt-in pixel-tracking resize. Tiles resize fluidly in raw pixels and smoothly animate into their snapped slot on release.
- **Drag From Outside:** Drop new items from external sources directly into the grid with auto-scrolling support.
- **Guidance:** Optional contextual tooltips/guidance messages.
- **Responsive Layouts:** Automatically adapt the number of columns (`slotCount`) based on the screen width using the built-in `breakpoints` property.
- **Accessibility:** Full keyboard navigation support (Tab, Arrows, Space, Enter, customizable keys) and Screen Reader announcements (TalkBack/VoiceOver).
- **Mini-Map:** A customizable widget to visualize the entire dashboard layout and current viewport, perfect for large grids. Supports **overlay markers** (status dots/badges per item) and **multiple viewport indicators** for multi-sliver scroll views.
- **Multi-Selection:** Select and move multiple items at once using `Shift` + Click (customizable keys), or by **dragging a selection rectangle** ("lasso") over empty grid space on desktop and web.
- **Duplicate on Drag:** Hold `Alt` / `Option` (customizable) when you start dragging a tile to drag a *copy* of it out, leaving the original in place. The application mints the id and the business payload through `onCloneRequested`.
- **Undo / Redo:** A native, transactional layout history with reactive `canUndo` / `canRedo` beacons and business-logic veto hooks (`onWillUndo` / `onWillRedo`). One entry per completed operation — a 100-frame drag records exactly one snapshot.
- **Utilities**: Import/Export, find free cells, get last row, Auto Layout & Bulk Add.

## Try the Demo

[Launch Live Demo](https://scalz.github.io/sliver_dashboard_web_demo/)

*Note on Web Performance:*
This playground is built using standard JavaScript compilation:
```bash
flutter build web --base-href ... --release
```
This intentionally showcase the demo in non-WASM mode to verify efficiency.
The package is WebAssembly (WASM) compatible. Building your production application with the --wasm flag will yield even greater execution speedups.

## Table of Contents

- [Getting Started](#getting-started)
- [Core API](#core-api)
  - [Controlling Edit Mode](#controlling-edit-mode)
  - [Adding and Removing Items](#adding-and-removing-items)
  - [Interaction Callbacks](#interaction-callbacks)
  - [Empty slot interactions & business metadata](#empty-slot-interactions--business-metadata)
  - [Programmatic Scrolling](#programmatic-scrolling)
  - [Import / Export (Persistence)](#import--export-persistence)
  - [Undo / Redo (Layout History)](#undo--redo-layout-history)
- [Drag & Drop](#drag--drop)
  - [Dragging From Outside](#dragging-from-outside)
  - [Persisting Layout Changes](#persisting-layout-changes)
  - [Drag to Delete (Trash Bin)](#drag-to-delete-trash-bin)
  - [Custom Drag Handles & Mobile Gestures](#custom-drag-handles--mobile-gestures)
  - [Custom Drag Feedback](#custom-drag-feedback)
  - [Haptic Feedback](#haptic-feedback)
  - [Multi Selection and Cluster Drag](#multi-selection-and-cluster-drag)
  - [Swap Mode (Direct Position Exchange)](#swap-mode-direct-position-exchange)
  - [Per-Grid Drop Rules (`canAcceptItem`)](#per-grid-drop-rules-canacceptitem)
  - [Rectangle / Lasso Selection](#rectangle--lasso-selection)
  - [Duplicate on Drag (Alt / Option)](#duplicate-on-drag-alt--option)
  - [Adaptive Neighbor Shrinking (Auto-Shrink on Drag)](#adaptive-neighbor-shrinking-auto-shrink-on-drag)
- [Layout & Structure](#layout--structure)
  - [Segmented Grids & Section Barriers](#segmented-grids--section-barriers)
  - [Custom Section Headers](#custom-section-headers)
  - [Scroll direction](#scroll-direction)
  - [Allowing free positioning](#allowing-free-positioning)
  - [Auto Layout bulk add](#auto-layout-bulk-add)
  - [Responsive Layouts](#responsive-layouts)
  - [Layout Optimizer](#layout-optimizer)
- [Appearance & Accessibility](#appearance--accessibility)
  - [Configuration & Styles](#configuration--styles)
  - [Guidance Messages](#guidance-messages)
  - [Mini Map](#mini-map)
  - [Accessibility and Keyboard Navigation](#accessibility-and-keyboard-navigation)
- [Advanced & Extensibility](#advanced--extensibility)
  - [Advanced Sliver Composition](#advanced-sliver-composition)
  - [Nested Grids & Cross-Grid Drag](#nested-grids--cross-grid-drag)
  - [Minimap Markers & Multiple Viewports](#minimap-markers--multiple-viewports)
  - [Reflow Animations](#reflow-animations)
  - [Fluid Resize](#fluid-resize)
  - [Custom Compaction Strategy](#custom-compaction-strategy)
  - [Interaction & Collision Policies (Custom Rules)](#interaction--collision-policies-custom-rules)
  - [Utilities](#utilities)
- [Benchmark](#benchmark)
- [Contributing](#contributing)

## Getting Started

### 1. Add Dependency

Add `sliver_dashboard` to your `pubspec.yaml`:

```yaml
dependencies:
  sliver_dashboard: ^.. # Replace with the latest version
```

### 2. Create a Controller

The `DashboardController` is the brain of your dashboard. It manages the layout and all interactions.

```dart
import 'package:sliver_dashboard/sliver_dashboard.dart';

// Create a controller and define your initial layout.
final controller = DashboardController(
  initialSlotCount: 5,
  initialLayout: [
    const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
    const LayoutItem(id: 'b', x: 2, y: 1, w: 1, h: 2),
    const LayoutItem(id: 'c', x: 3, y: 0, w: 2, h: 1, isStatic: true), // A static item
  ],
);
```

### 3. Build the Dashboard Widget

For basic usage, use the `Dashboard` widget. It handles the scroll view creation for you.

```dart
import 'package:flutter/material.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

class MyDashboardPage extends StatelessWidget {
  const MyDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Dashboard')),
      body: Dashboard(
        controller: controller,
        itemBuilder: (context, item) {
          // Build your custom widget for each item.
          // Ideally, look up your business data using item.id
          return Card(
            child: Center(child: Text('Item ${item.id}')),
          );
        },
      ),
    );
  }
}
```

## Core API

Everyday controller operations: toggling edit mode, mutating the layout, listening to interactions, and persisting it.

### Controlling Edit Mode

Toggle edit mode to enable/disable dragging and resizing.

```dart
IconButton(
    icon: const Icon(Icons.edit),
    onPressed: () => controller.toggleEditing(),
)
```

### Adding and Removing Items

Programmatically add or remove items from the dashboard.

```dart
void addNewItem() {
  final newItem = LayoutItem(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    x: 0,
    y: 0, // The engine will find the best spot
    w: 1,
    h: 1,
  );
  controller.addItem(newItem);
}

void deleteItem(String id) {
  controller.removeItem(id);
}
```

### Interaction Callbacks

Hook into the lifecycle of drag and resize events.

```dart
Dashboard(
  controller: controller,
  onItemDragStart: (item) => print('Started dragging ${item.id}'),
  onItemDragUpdate: (item, offset) => print('Dragging at $offset'), // Useful for custom hit-testing
  onItemDragEnd: (item) => print('Stopped dragging ${item.id}'),
  onItemResizeStart: (item) => print('Started resizing ${item.id}'),
  onItemResizeEnd: (item) => print('Stopped resizing ${item.id}'),
)
```

### Empty slot interactions & business metadata

```dart
Dashboard<String>(
  controller: controller,
  scrollController: scrollController,
  itemBuilder: (context, item) => MyWidget(type: item.extra?['type']),
  // "Add a widget here": fires with the tapped grid cell, items excluded.
  onSlotTap: (x, y) => showAddMenuAt(x, y),
  onSlotLongPress: (x, y) => showContextMenuAt(x, y),
)

// Layout + configuration in ONE payload:
controller.addItem(LayoutItem(
  id: 'sales', x: -1, y: -1, w: 2, h: 2,
  extra: {'type': 'chart_pie', 'title': 'Sales'},
));
final json = controller.exportLayout(); // extra included

// Fixed-surface dashboards (TV, kiosk, A4): cap the grid at 6 rows.
controller.setMaxRows(6);
```

### Programmatic Scrolling

You can programmatically scroll the dashboard to make a specific item visible.
The method returns a `Future` that completes only when the scroll animation is fully finished, allowing you to chain actions (like highlighting the item after arrival).

```dart
// Scroll to an item by its ID

// Smooth animated scroll
await controller.scrollToItem(
  'item_15',
  alignment: 0.5, // 0.0 = top edge, 0.5 = center, 1.0 = bottom edge
  duration: const Duration(milliseconds: 500),
);

// Instant jump (Perfect for large grids or search results)
await controller.scrollToItem(
  'item_1200',
  duration: Duration.zero,
);
```

### Import / Export (Persistence)

Easily save and restore layouts using JSON-compatible Maps. Can be used for persisting the user's dashboard configuration to a database or shared preferences.
**Note:** importLayout automatically validates the data, corrects bounds if the slot count has changed, and resolves overlaps.

```dart
// 1. Export to JSON-ready list of maps
final List<Map<String, dynamic>> layoutData = controller.exportLayout();
// Save to your DB...
await myDatabase.save('dashboard_layout', layoutData);

// 2. Import from JSON
final List<dynamic> loadedData = await myDatabase.get('dashboard_layout');
controller.importLayout(loadedData);
```

### Undo / Redo (Layout History)

The controller keeps a transactional history of the spatial layout. One entry is
recorded per **completed** operation — never per frame, so a two-second drag
costs exactly one snapshot, not 120.

```dart
// Reactive: bind the buttons straight to the beacons.
IconButton(
  icon: const Icon(Icons.undo),
  onPressed: controller.canUndo.watch(context)
      ? () => controller.undo()
      : null,
);

await controller.undo(); // true when a state was restored
await controller.redo();

controller.clearHistory();          // keeps the layout, resets the stack
controller.setMaxHistoryLength(50); // default: 30 (throws when negative)
```

#### Opting out entirely

Layout history is enabled by default (30 steps, negligible memory footprint).
Pass `maxHistoryLength: 0` if you wish to disable history tracking entirely for zero memory usage.

```dart
final controller = DashboardController(maxHistoryLength: 0);
controller.setMaxHistoryLength(0);  // Disable history at runtime
controller.setMaxHistoryLength(30); // Re-enable history (starts a fresh stack)
```

`canUndo` and `canRedo` stay `false`, `undo()` / `redo()` return `false`, and
`clearHistory()` is a no-op. Everything else, `onLayoutChanged` included,
behaves exactly as before.

#### Business-logic hooks

```dart
final controller = DashboardController(
  // Veto: return false to cancel. May be async (dialog, network check).
  // The layout, the cursor and the beacons are left untouched on refusal.
  onWillUndo: (candidateLayout) async => askUser(candidateLayout),
  onWillRedo: (candidateLayout) => true,

  // Fired after a successful operation, *in addition to* onLayoutChanged.
  onUndo: (restoredLayout, slotCount) => analytics.log('undo'),
  onRedo: (restoredLayout, slotCount) => analytics.log('redo'),
);
```

`undo()` and `redo()` always emit `onLayoutChanged` first, so an existing
auto-save keeps working with no change.

#### What is recorded — and what is not

| Recorded (one entry each) | Not recorded |
|---|---|
| drag end, resize end | drag/resize **frames** |
| `addItem` / `addItems` | `setSlotCount` (responsive breakpoints) |
| `removeItem` / `removeItems` | `updateItem(recompact: false)` (metadata only) |
| `importLayout` | cross-grid drops between two dashboards |
| `optimizeLayout` | keyboard nudges (`moveActiveItemBy`) |
| `updateItem(recompact: true)` | any operation whose result is unchanged |

Three consequences worth knowing:

* **Gestures are atomic.** `undo()` returns `false` while a drag or resize is in
  flight — you can only undo a committed transaction.
* **Breakpoints are not history.** A snapshot stores the column count it was
  taken under. If the grid changed breakpoint since, the restored layout is
  re-projected onto the current column count instead of being replayed
  verbatim; otherwise it is restored byte-for-byte with no recompaction.
  Undoing across a breakpoint also rewrites the layout the responsive cache
  keeps for the breakpoint the action was performed in, so resizing the window
  back does not resurrect the state you just reverted.
* **History is per grid.** With `NestedDashboard`, each controller owns its own
  stack. Moves *between* grids are deliberately not recorded: undoing one side
  alone would duplicate the item.

## Drag & Drop

Everything about moving items: external sources, deletion, gestures, feedback, and multi-item drags.

### Dragging From Outside

You can drag items from an external source (palette, sidebar) directly into the Dashboard. The grid handles auto-scrolling, live collision pushes, and placement automatically.

Use `externalTemplateBuilder` to define the intrinsic size, resize constraints, and metadata of each component type so the hover preview and the inserted tile match the component's true footprint:

```dart
// 1. The Source
Draggable<ComponentSpec>(
  data: const ComponentSpec(type: 'chart_sales', defaultW: 4, defaultH: 2, minW: 2),
  feedback: const Card(child: Text('Dragging Chart (4x2)...')),
  child: const Text('Sales Chart'),
)

// 2. The Target (Dashboard or DashboardOverlay)
Dashboard<ComponentSpec>(
  controller: controller,
  // Define template geometry and constraints per payload
  externalTemplateBuilder: (spec) => LayoutItem(
    id: '', // ignored — onDrop provides the real persistent id
    x: 0, y: 0, // ignored — pointer decides
    w: spec.defaultW,
    h: spec.defaultH,
    minW: spec.minW,
    extra: {'type': spec.type},
  ),
  // Commit the drop and assign the persistent ID
  onDrop: (spec, placeholder) async {
    final saved = await api.createWidget(spec, x: placeholder.x, y: placeholder.y);
    return saved.id; // null cancels the drop
  },
  itemBuilder: (context, item) => MyWidget(item),
  // Optional: Customize the placeholder shown while hovering
  externalPlaceholderBuilder: (context, item) {
    return Container(color: Colors.blue.withOpacity(0.2));
  },
)
```

| Field | On Drop | Behavior |
|---|---|---|
| `w`, `h` | **Honoured** | Sizes the hover placeholder and the final tile |
| `minW`, `minH`, `maxW`, `maxH` | **Honoured** | Preserves component resize constraints |
| `extra` | **Honoured** | Seeds business metadata immediately without a secondary write |
| `isSectionBarrier`, `isStatic` | **Honoured** | Allows dragging section dividers or static cards directly from a palette |
| `id`, `x`, `y`, `moved` | **Ignored** | `onDrop` assigns the ID; coordinates are resolved by pointer placement |

#### The id `onDrop` returns

`onDrop` is the single place where **your application, not the package, names the tile**. Returning `null` cancels the drop and leaves the layout untouched.

This is important when dragging entities that **do not exist yet in your backend**: the payload carries an unsaved draft, the drop commits it, and the ID assigned by your database on insert becomes the tile's permanent ID.


```dart
onDrop: (WidgetDraft draft, LayoutItem placeholder) async {
  try {
    // `placeholder` contains the exact grid coordinates resolved by the engine
    final saved = await api.createWidget(
      draft,
      x: placeholder.x,
      y: placeholder.y,
      w: placeholder.w,
      h: placeholder.h,
    );
    cache[saved.id] = saved;
    return saved.id; // One identity shared across DB and grid
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not add: $e')));
    return null; // Cancel drop: placeholder disappears, layout untouched
  }
},
```

The same rule applies to [`onCloneRequested`](#duplicate-on-drag-alt--option): a duplicate tile needs a **new ID unique across the entire grid tree**.

> **Carrying business data on the tile:** Do not subclass `LayoutItem`. The layout engine reconstructs items using `copyWith` during pushes and compaction, so custom subclasses would be lost. Use [`extra`](#layoutitem) for JSON-serializable metadata, and keep live controllers/widgets in an application-side map keyed by the tile ID.

#### What the grid does while an async `onDrop` is awaited

When `onDrop` performs an asynchronous operation (e.g. API request), be aware of the engine's concurrency contract:

- **The grid is not locked:** No modal barrier is installed. The user can still drag other tiles, resize items, or hit undo while your request is in flight.
- **The placeholder stays frozen:** The placeholder remains at its release position with neighbours pushed aside (rendering your `externalPlaceholderBuilder`).
- **Concurrent drops can race:** If a second drop occurs before the first completes, the single placeholder is replaced by the newest one.

Depending on your UX requirements, two architectural patterns are recommended:

##### Option A: Optimistic Placement (Fastest UX)
Mint a local ID immediately, return it synchronously to let the grid place the tile instantly, and sync with your backend in the background (with a rollback if the API fails).

##### Option B: Guarded Drop (Safe & Synchronized)
Keep the `await`, make the operation exclusive with an in-flight guard, and always bound the network call with a timeout:

```dart
bool _dropInFlight = false;

onDrop: (draft, placeholder) async {
  // Prevent concurrent drops from clashing while one is pending
  if (_dropInFlight) return null;
  _dropInFlight = true;
  setState(() {}); // Show loading indicator in your palette if desired
  
  try {
    final saved = await api.createWidget(
    draft,
    x: placeholder.x,
    y: placeholder.y,
    ).timeout(const Duration(seconds: 5));
    
    cache[saved.id] = saved;
    return saved.id;
  } on TimeoutException {
    messenger.showSnackBar(const SnackBar(content: Text('Server timeout')));
    return null; // Cancels drop, removes placeholder cleanly
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    return null;
  } finally {
    _dropInFlight = false;
    if (mounted) setState(() {});
  }
},
```

Always bound the wait. Without a timeout, an unreachable server leaves the
placeholder on the grid for as long as the request hangs, and the user has no
way to dismiss it.

Give `externalPlaceholderBuilder` a pending state so the frozen rectangle reads
as "saving" rather than "stuck".

### Persisting Layout Changes

#### When `onLayoutChanged` fires — read this first

`onLayoutChanged` is called **once per completed transaction, never per frame**. `onDragUpdate` runs at 60/120 Hz internally without notifying; `onDragEnd` and `onResizeEnd` emit exactly once when the gesture commits.

It fires on: drag end, resize end, item add/remove/update, import, `optimizeLayout`, and **undo / redo**.

```dart
DashboardController(
  initialSlotCount: 12,
  onLayoutChanged: (items, slotCount) => repo.save(items, slotCount),
);
```

#### Immutability and Debouncing

The `items` list passed to `onLayoutChanged` is an **unmodifiable snapshot** (`List<LayoutItem>.unmodifiable`). Attempting to mutate it directly (`items.sort(...)`, `items.clear()`) will throw an `UnsupportedError`. If you need a mutable working copy, call `items.toList()`.

If you debounce database writes to batch multiple rapid tile moves, map the snapshot immediately into lightweight DTOs:

```dart
List<({String id, int x, int y, int w, int h})>? _pending;
Timer? _debounce;

void _onLayoutChanged(List<LayoutItem> items, int slotCount) {
  // 1. Capture data immediately
  _pending = [
    for (final i in items) (id: i.id, x: i.x, y: i.y, w: i.w, h: i.h),
  ];
  // 2. Coalesce rapid moves
  _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 300), _flush);
}

@override
void dispose() {
  _debounce?.cancel();
  super.dispose();
}
```

Similarly, candidate layouts passed to `onWillUndo` / `onWillRedo` are unmodifiable and must not be retained across async gaps expecting them to remain live.

#### Write a diff in one transaction

`onLayoutChanged` provides a complete layout snapshot. To optimize backend writes, diff against your last written state and batch in a single database transaction:

```dart
Future<void> _flush() async {
  final snapshot = _pending;
  if (snapshot == null) return;
  _pending = null;

  final changed = [
    for (final row in snapshot)
      if (_lastWritten[row.id] != row) row,
  ];
  if (changed.isEmpty) return;

  await db.transaction(() async {
    await db.widgets.putMany(changed);
  });
  for (final row in changed) {
    _lastWritten[row.id] = row;
  }

  // Cleanup deleted entries from memory cache
  final liveIds = {for (final row in snapshot) row.id};
  _lastWritten.removeWhere((id, _) => !liveIds.contains(id));
}
```

#### The persistence key includes the column count

The callback signature is `(items, slotCount)`. With [responsive breakpoints](#responsive-layouts), key your persistence on **`(dashboardId, slotCount)`** so a mobile layout does not overwrite the desktop column arrangement.

#### Guard against the remote sync feedback loop

If your backend broadcasts updates that you feed back into `controller.importLayout()`, prevent recursive echo loops with a simple synchronous guard:

```dart
bool _applyingRemote = false;

void _onRemoteDataReceived(List<LayoutItem> remoteItems) {
  _applyingRemote = true;
  try {
    // importLayout triggers onLayoutChanged synchronously
    controller.importLayout([for (final i in remoteItems) i.toMap()]);
  } finally {
    _applyingRemote = false;
  }
}

void _onLayoutChanged(List<LayoutItem> items, int slotCount) {
  if (_applyingRemote) return; // Ignore echo of our own remote sync
  _saveToDatabase(items, slotCount);
}
```

#### Undo / redo persist for free — but only the geometry

`undo()` and `redo()` fire `onLayoutChanged` like any other change, so once the
listener is wired the history is persisted with no extra work.

However, **history restores positions, never database entities**. 
If an item was permanently deleted from your database, undoing will put a ghost tile on the grid. 
If your dashboard supports undo on delete, use **soft deletes** in your backend (`deleted_at` timestamp) so restored items remain valid.

```dart
onItemsDeleted: (items) async {
  // Soft delete: recoverable by undo.
  await db.widgets.markDeleted([for (final i in items) i.id]);
},
```

### Drag to Delete (Trash Bin)

The package handles the logic for detecting when an item is dropped over a specific area.
It offers two ways to implement a "trash bin" to delete items by dragging them.

#### Option 1: Built-in (Recommended)

The easiest way. The package handles the display, the hit-testing (detecting if the item is over the trash), the arming delay (to prevent accidental deletions), and the removal logic.

```dart
Dashboard( // or DashboardOverlay
  controller: controller,
  // 1. Define how the trash bin looks. 
  // It receives 'isHovered' and 'isArmed' (hovered long enough).
  trashBuilder: (context, isHovered, isArmed, activeItemId) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isArmed ? Colors.red : (isHovered ? Colors.orange : Colors.grey),
              borderRadius: BorderRadius.circular(10),
            ),
          child: Icon(isArmed ? Icons.delete_forever : Icons.delete),
      ),
    );
  },
  // 2. Optional: Configure the delay before the trash becomes "armed".
  // Defaults to 800ms.
  trashHoverDelay: const Duration(milliseconds: 800),
  // Use predefined position for the trash
  // trashLayout: TrashLayout.bottomCenter,
  // Or use custom
  trashLayout: TrashLayout(
    visible: TrashLayout.bottomCenter.visible.copyWith(bottom: 80),
    hidden: TrashLayout.bottomCenter.hidden,
  ),
  // 3. Optional: Confirm deletion before it happens.
  // Return true to delete, false to cancel.
  onWillDelete: (items) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete ${items.length} items?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ?? false;
  },
  // 4. Handle batch deletion.
  // Item are AUTOMATICALLY removed from the controller before this callback.
  onItemsDeleted: (items) {
    // You just need to remove your corresponding business data.
    myData.removeItems(items);
  },
)
```

#### Option 2: Custom Implementation (External Trash)

Use this if your trash bin is located **outside** the `Dashboard` widget tree (e.g., in a static `BottomNavigationBar` or `AppBar`).

```dart
// 1. Define state and a GlobalKey to locate your external trash widget
final GlobalKey _trashKey = GlobalKey();
bool _isHoveringTrash = false;

// 2. In your build method
Dashboard( // or DashboardOverlay
  controller: controller,  
  // Detect drag updates to perform manual hit-testing
  onItemDragUpdate: (item, globalPosition) {
    final renderBox = _trashKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // Check if the drag position is inside your custom widget
    final localPos = renderBox.globalToLocal(globalPosition);
    final isHovering = renderBox.hitTest(BoxHitTestResult(), position: localPos);
  
    if (_isHoveringTrash != isHovering) {
      setState(() => _isHoveringTrash = isHovering);
    }
  },  
  // Handle the drop
  onItemDragEnd: (item) {
  if (_isHoveringTrash) {
    // Manually remove the item
    controller.removeItem(item.id);
    myData.remove(item.id);
    // Perform other cleanup...
    }
    setState(() => _isHoveringTrash = false);
  },
)

// 3. Your Custom Trash Widget (can be anywhere)
Container(
  key: _trashKey, // Important: Attach the key!
  color: _isHoveringTrash ? Colors.red : Colors.grey,
  child: const Icon(Icons.delete),
)
```

### Custom Drag Handles & Mobile Gestures

By default, dragging on mobile is initiated by a long-press on any part of the card . You can fully customize this behavior using the `dragStartGesture` parameter  or restrict dragging to a **dedicated handle** (like an icon) using `DashboardDragStartListener` .

#### 1. Tap-to-drag on Mobile
If you want items to be draggable immediately on touch/down (without any long-press delay) :
```dart
Dashboard(
  controller: controller,
  dragStartGesture: DragStartGesture.tap, // Instant dragging on mobile
  itemBuilder: (context, item) => MyCard(item),
)
```

#### 2. Restricting Drag to a Custom Handle (Icon)
To make your grid items draggable *only* when dragging a specific handle (icon) :
1. Set `dragStartGesture: DragStartGesture.none` on your `Dashboard` to disable dragging on the card's body .
2. Wrap your handle widget in a `DashboardDragStartListener` .

```dart
Dashboard(
  controller: controller,
  dragStartGesture: DragStartGesture.none, // Disable card-body drag
  itemBuilder: (context, item) {
    return Card(
      child: Stack(
        children: [
          Center(child: Text('Item ${item.id}')),
          // Add a custom drag handle in the corner
          Positioned(
            right: 8,
            top: 8,
            child: DashboardDragStartListener(
              itemId: item.id,
              child: const Icon(Icons.drag_handle),
            ),
          ),
        ],
      ),
    );
  },
)
```
*Note: Use `DashboardDelayedDragStartListener` if you want your custom handle to require a long-press to start dragging.*

### Custom Drag Feedback

Customize the look of the item while it is being dragged (e.g., add transparency or elevation).

```dart
Dashboard(
  controller: controller,
  itemFeedbackBuilder: (context, item, child) {
    return Opacity(
      opacity: 0.7,
      child: Material(
        elevation: 10,
        child: child, // The original widget
      ),
    );
  },
)
```

### Haptic Feedback

On mobile platforms, you may want to use haptic feedback for drag and resize start events.

```dart
final controller = DashboardController(
  // This can be used to trigger haptic feedback, logging, or other custom
  // actions. The specific [LayoutItem] being interacted with is provided.
  onInteractionStart: (item) {
    HapticFeedback.mediumImpact();
  },
  // ...
);
```

### Multi Selection and Cluster Drag

Users can select multiple items by holding `Shift` (or `Ctrl`/`Cmd`) while clicking,
or by dragging a [selection rectangle](#rectangle--lasso-selection) over empty space
on desktop and web.
Dragging any item in the selection moves the entire group ("Cluster Drag").

**Programmatic Selection:**
```dart
// Select multiple items
controller.toggleSelection('item_1', multi: true);
controller.toggleSelection('item_2', multi: true);

// Clear selection
controller.clearSelection();

// Check selection
print(controller.selectedItemIds.value);

// 2. Customize Multi-Selection Keys
controller.shortcuts = DashboardShortcuts(
  multiSelectKeys: [LogicalKeyboardKey.altLeft],
);
```

> **Note:** `Alt` is also the default modifier for [Duplicate on Drag](#duplicate-on-drag-alt--option).
> If you move multi-selection onto `Alt`, move `cloneKeys` elsewhere in the same
> `DashboardShortcuts` — the two sets must stay disjoint.

### Per-Grid Drop Rules (`canAcceptItem`)

In a nested tree, a scope-wide predicate decides which items each grid accepts:

```dart
DashboardNestedScope(
  canAcceptItem: (item, targetGrid, sourceGrid) {
    // Only the sidebar grid takes notes; everything else takes anything.
    if (identical(targetGrid, sidebarController)) {
      return item.extra['type'] == 'note';
    }
    return true;
  },
  child: ...,
)
```

**A refused grid is transparent, not a dead zone.** The drag passes straight
through it to the enclosing grid, which becomes the target — so a note dropped
over a chart-only sub-grid lands in the parent instead of being stuck. Refusing
every grid resolves to no target at all and the drop cancels normally.

| Rule | Behaviour |
|---|---|
| Signature | `(item, targetGrid, sourceGrid)`. `sourceGrid` is the grid the item was picked up from, so rules work in both directions ("only takes charts", "nothing leaves the archive"). For a same-grid drag both are the same controller. |
| When it runs | On every pointer event, for the one or two grids actually under the pointer — evaluated after the cheap containment and `canAcceptCrossGridItems` checks. Keep it cheap and side-effect free. |
| Memoization | None. A predicate may legitimately depend on live state, such as the target grid already being full. |
| Exit sessions | A scope where every other grid refuses the item does not open one, so the tile never pops into a floating proxy it cannot land from. |
| Per-grid override | None, by design. The predicate runs while resolving *which* grid is under the pointer, before any grid owns the interaction — branch on `targetGrid` instead. |

**Two cases it cannot cover**, because both run before the target controller
exists: dropping onto a **closed** host tile (`onItemDroppedOnHost` — the child
grid is not mounted) and arming a **dynamic** nested grid (`subGridDynamic` —
the grid is being requested, not entered). Both callbacks hand you the host
item and the grids involved, which is where those rules belong.

### Swap Mode (Direct Position Exchange)

By default a dragged tile **pushes** the tiles it lands on (`DragMode.cascade`,
the historical behaviour). Swap mode makes it **trade places** with them
instead.

```dart
// Make swap the default for every drag:
controller.setDragMode(DragMode.swap);

// Or leave the default cascade and let the user reach swap with a modifier:
controller.shortcuts = const DashboardShortcuts(
  swapModeModifier: [LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight],
);
```

The modifier always selects the **opposite** of `dragMode`, so it works as a
temporary toggle either way:

| `dragMode` | Modifier released | Modifier held |
|---|---|---|
| `cascade` (default) | cascade | **swap** |
| `swap` | swap | **cascade** |

Pass `swapModeModifier: []` to remove the toggle entirely and leave `dragMode`
in sole control. On platforms without a hardware keyboard the modifier is never
held, so `dragMode` alone decides.

**What the package guarantees:**

| Rule | Behaviour |
|---|---|
| Default | `DragMode.cascade`. Nothing about existing drags changes unless you opt in. |
| Qualification | The drag box must cover **more than 50% of the candidate's own area**. Measured against the candidate, not the mover, so a small tile dropped on a large one does not swap until it is genuinely on it. |
| No candidate | The frame falls back to the cascade — a swap-mode drag over empty space, or one that merely clips a neighbour, still moves the tile. |
| Where the partner goes | To the mover's **pre-drag** slot, clamped into the grid. |
| Several candidates | Best coverage wins; ties break on absolute overlap, then on id. Deterministic and independent of layout order. |
| Static tiles | Never swapped, and a static tile is never a valid partner. Section barriers follow the same rule as elsewhere. |
| Policy | `canCollide` and `canMoveTo` are honoured for both items; a veto means no swap. |
| 0-overlap | Collision resolution runs whenever the result actually collides — the partner reshaped into a different slot, or a bystander the drag box clipped without qualifying to swap with. A clean same-size swap collides with nothing and stays a pure coordinate exchange with no cascade. |
| Multi-selection | Swap applies to **single-item drags only**. A cluster drag always cascades. |
| Mid-drag toggle | Pressing or releasing the modifier re-runs the layout immediately, with no pointer movement required. |

You can read the resolved mode at any time, which is handy for a UI indicator:

```dart
final mode = controller.getEffectiveDragMode(); // cascade or swap, right now
```

### Rectangle / Lasso Selection

On desktop and web, dragging from **empty grid space** draws a selection
rectangle; every tile it overlaps is selected live while you drag.

It is configured on the **controller**, next to `shortcuts` and `guidance` —
it is interaction policy, not grid painting, so it stays available on a
dashboard that draws no background grid, and each grid of a nested tree
carries its own policy:

```dart
controller.lassoStyle = const LassoStyle(
  // emptySpace (default): an empty-space drag draws the rectangle.
  // modifierRequired: only while DashboardShortcuts.lassoModifier is held.
  // disabled: no rubberband at all.
  mode: LassoSelectionMode.emptySpace,
  fillColor: Color(0x332196F3),
  borderColor: Colors.blue,
  borderWidth: 1,
);

// Shorthands:
controller.lassoStyle = LassoStyle.off;        // feature disabled
controller.lassoStyle = LassoStyle.byDefault;  // back to the defaults
```

**What the package guarantees:**

| Rule | Behaviour |
|---|---|
| Platform | Desktop and web only. Never armed on Android / iOS, where an empty-space drag scrolls the grid. |
| Opt-out | `controller.lassoStyle = LassoStyle.off` restores the previous empty-space-drag behaviour exactly. |
| Edit mode | Required, like every other interaction. |
| Press on a tile | Never a lasso — it is a drag or a resize. |
| Press on empty space with **no movement** | Nothing happens: no selection change, no announcement. Clicking the background does not clear the selection. |
| Intersection | Pixel-precise: a rectangle drawn entirely inside the gutter between two tiles selects neither. |
| Selection semantics | Replaces the current selection. **Additive** while a `multiSelectKeys` key is held. |
| Static tiles | Never selected. Section barriers are (they are selectable by click too). |
| Scrolling | Supported. The anchor is stored in grid-content space, so edge auto-scroll and the mouse wheel grow the rectangle over the content instead of shearing it. |
| Nested grids | The innermost editing grid owns the gesture; the parent never drags its host tile underneath it. |

**Requiring a modifier** — useful when the grid shares its `CustomScrollView`
with other slivers, or when your app already binds empty-space drags:

```dart
controller
  ..lassoStyle = const LassoStyle(mode: LassoSelectionMode.modifierRequired)
  ..shortcuts = const DashboardShortcuts(
    lassoModifier: [LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight],
  );
```

> **Note:** `lassoModifier` and `multiSelectKeys` both default to `Shift`, and
> that overlap is legal (unlike `cloneKeys` vs `multiSelectKeys`). They answer
> different questions: `multiSelectKeys` decides whether the lasso *adds to*
> the selection, `lassoModifier` decides whether it *starts*. Under
> `modifierRequired`, a key that is both counts as the trigger only — hold a
> second, non-overlapping `multiSelectKeys` key for an additive lasso there.

Both modifier states are published on the controller, so a mode indicator
needs no key listener of its own:

```dart
final lassoArmed = controller.lassoModifierHeld.watch(context);
final swapArmed = controller.swapModifierHeld.watch(context);
```

**Cursor and messages** — the `precise` cursor over empty space and the label
drawn beside the rectangle follow the `guidance` opt-in; **screen-reader
announcements do not** and fire with the built-in English defaults when
`guidance` is null:

```dart
Dashboard(
  guidance: DashboardGuidance(
    lassoSelect: InteractionGuidance(
      SystemMouseCursors.precise,
      'Drag over empty space to select items',
    ),
    a11yLassoStart: 'Rectangle selection started.',
    a11yLassoEnd: (count) => '$count items selected',
  ),
)
```

### Duplicate on Drag (Alt / Option)

Holding `Alt` (`Option` on macOS) when a drag starts duplicates the tile: the copy
follows the cursor while the original stays behind.

**The feature is off until you register `onCloneRequested`.** There is no default
clone: only your application can mint an id and decide what duplicating one of
your widgets means.

> Tip: Store your tile configuration inside LayoutItem.extra when cloning so your itemBuilder can render the duplicate immediately without requiring external state lookups.

```dart
var counter = 0;

Dashboard<String>(
  controller: controller,
  itemBuilder: _buildCard,
  onCloneRequested: (source, grid) {
    // Return null to refuse the duplication: the gesture then degrades to a
    // plain move of the source.
    if (source.extra?['unique'] == true) return null;

    return source.copyWith(
      id: 'copy_${counter++}',
      extra: {...?source.extra, 'clonedFrom': source.id},
    );
  },
)
```

**What the package guarantees:**

| Rule | Behaviour |
|---|---|
| No callback registered | The modifier is ignored; Alt+drag is a plain move. Costs one null check per pointer-down. |
| Alt + **click** (no movement) | Nothing happens at all — no insertion, no history entry, no selection change. The copy is created on the first real movement. |
| Callback returns `null` | Duplication cancelled; the gesture continues as a plain move of the source. |
| Returned id already exists | Rejected (assertion in debug, plain move in release). A clone must carry an id **unique across the whole grid tree**. |
| Returned `x` / `y` | Ignored. The copy is always inserted on the source's own cell so it appears under the cursor. Size and constraints are honoured. |
| Resize handles | The modifier never applies: Alt + drag from an edge is a plain resize. |
| Static items / section barriers | Never cloned (they are not draggable either). |
| Multi-selection modifier also held | Selection wins; no duplication. |
| Selection after the copy is created | Reduced to the clone alone — a duplication is always a single-item drag. |
| Undo | The gesture records **two** entries: the insertion, then the drop. `undo()` once puts the copy back where it appeared; twice removes it. |

**Changing the modifier** — `cloneKeys` follows the same pattern as `multiSelectKeys`
and must stay disjoint from it (both are read from the same pointer-down;
`multiSelectKeys` wins, and an overlap trips an assertion in debug):

```dart
controller.shortcuts = const DashboardShortcuts(
  cloneKeys: [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight],
);
```

**Nested grids** — a `NestedDashboard` takes its own `onCloneRequested`, or you can
register one handler for the whole tree on the scope and branch on the `grid`
argument:

```dart
DashboardNestedScope(
  onCloneRequested: (source, grid) => identical(grid, readOnlyPanel)
      ? null
      : source.copyWith(id: newId()),
  child: ...,
)
```

A per-grid callback always takes precedence over the scope-wide one.

### Adaptive Neighbor Shrinking (Auto-Shrink on Drag)

When dragging a large widget over smaller items, the default behavior pushes everything downwards, which can cause significant layout shifts. You can enable **Auto-Shrink on Drag** to dynamically contract neighboring items' heights down to their `minH` limits to clear room first :

```dart
// Enable auto-shrink dynamically via the controller
controller.setAllowAutoShrink(allow: true)
```
Note: If neighbors hit their minH limit and still cannot fit, the engine gracefully falls back to pushing them downwards, keeping your layout.

## Layout & Structure

Shaping the grid itself: sections, axis, free placement, bulk placement, breakpoints, and automatic optimization.

### Segmented Grids & Section Barriers

You can organize your widgets into distinct, visually separated groups (e.g. "Overview", "Analytics") within a single `DashboardController` . Simply add a static section barrier item spanning the full width of the grid :

```dart
final controller = DashboardController(
  initialSlotCount: 8,
  initialLayout: [
    // 1. Define a Section Barrier spanning full width (8 columns)
    const LayoutItem(
      id: 'section_1',
      x: 0,
      y: 0,
      w: 8,
      h: 1,
      isSectionBarrier: true,
      sectionTitle: '📌 System Performance',
    ),
    // Dynamic items inside Section 1
    const LayoutItem(id: '9', x: 0, y: 1, w: 2, h: 2),

    // 2. Define a second Section Barrier
    const LayoutItem(
      id: 'section_2',
      x: 0,
      y: 3,
      w: 8,
      h: 1,
      isSectionBarrier: true,
      sectionTitle: '📊 User Analytics',
    ),
    const LayoutItem(id: '15', x: 0, y: 4, w: 2, h: 2),
  ],
);
```

### Custom Section Headers

By default, the package renders a clean text header using your active Theme's primary color . You can fully customize this using the sectionHeaderBuilder callback

```dart
Dashboard(
  controller: controller,
  // Custom section header builder
  sectionHeaderBuilder: (context, item) {
    return Container(
      color: Colors.blue.shade50,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.bookmark, color: Colors.blue),
          const SizedBox(width: 8),
          Text(
            item.sectionTitle ?? '',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  },
  itemBuilder: (context, item) => MyCard(item),
)
```

### Scroll direction

Simply change the `scrollDirection`. The dashboard and all interactions will adapt.

```dart
Dashboard(
    scrollDirection: Axis.horizontal,
    controller: controller,
    itemBuilder: (context, item) { /* ... */ },
)
```

### Allowing free positioning

By default, items push each other. You can disable this to allow free positioning items without compaction.

```dart
// To allow free positioning:
controller.setCompactionType(CompactType.none);

// To re-enable push behavior:
controller.setCompactionType(CompactType.vertical);
```

> **Note on `CompactType.none`: Pushes are permanent.** Free positioning means elements only move        
> when pushed by a collision: when an expanding item (via manual resize or
> sizeToContent) pushes a neighbor, shrinking the item back does not pull
> the neighbor back. The engine does not track push provenance. Gaps left this
> way are by design; use vertical or horizontal compaction for self-healing,
> gap-filling layouts.
>
> * **For automatic gap filling:** Use `CompactType.vertical` or `CompactType.horizontal` compaction for self-healing layouts.
> * **For on-demand cleanup in free mode:** Call **`controller.optimizeLayout()`** to defragment the grid and compact empty gaps on demand,
    > or use **`controller.availableFreeAreas`** / **`controller.firstFreeArea`** to inspect open slots programmatically.

### Auto Layout bulk add

Generate a layout automatically or add items without specifying coordinates (set `x: -1, y: -1`). By default, the engine appends them below the current layout. You can configure this using the `strategy` parameter:

```dart
// Create fresh new page with auto placement
final items = placeNewItems(
  existingLayout: [],
  newItems: ['A', 'B', 'C'].map((id) => LayoutItem(
    id: id,
    x: -1, y: -1, // auto-placement
    w: 2, h: 2,
  )).toList(),
  cols: 8,
);
controller.layout.value = items;

// You can add items at a specific position, or let the controller place them automatically by using `-1`.

// Add item at a specific position (x: 2, y: 0)
controller.addItem(
  LayoutItem(id: 'fixed', x: 2, y: 0, w: 2, h: 2),
);

// 1. Tetris-style "First Fit" Placement (Fills gaps from top-left)
controller.addItem(
  LayoutItem(id: 'new_item', x: -1, y: -1, w: 2, h: 2),
  strategy: AutoPlacementStrategy.firstFit,
);

// 2. Default "Append Bottom" Placement (Appends strictly below existing content)
controller.addItems(
  [
    LayoutItem(id: 'a', x: -1, y: -1, w: 2, h: 2),
    LayoutItem(id: 'b', x: -1, y: -1, w: 1, h: 1),
  ],
  strategy: AutoPlacementStrategy.appendBottom, // Default behavior
);
```

### Responsive Layouts

You can automatically adapt the number of columns (`slotCount`) based on the available width by passing a `breakpoints` map.

**Smart Layout Memory:** The controller remembers the specific arrangement of items for each column count. If a user organizes their dashboard on Desktop (8 cols), switches to Mobile (4 cols), and comes back to Desktop, their original Desktop arrangement is restored.

```dart
// 1. Create your controller and register the layout changed callback
final controller = DashboardController(
  initialSlotCount: 8,
  initialLayout: [ ... ],
  onLayoutChanged: (items, slotCount) {
    // Save layout specifically for this screen size (persistence)
    final key = 'layout_$slotCount';
    myStorage.save(key, items);
  },
);
Dashboard(
  controller: controller,
  // Define breakpoints:
  // Mobile: 0-599px -> 4 cols
  // Tablet: 600-1199px -> 8 cols
  // Desktop: 1200px+ -> 12 cols
  breakpoints: {
    0: 4,
    600: 8,
    1200: 12
  },
)
```

### Layout Optimizer

If your dashboard becomes fragmented (full of gaps) after many moves, you can use the optimizer to compact the layout.
It uses a "Visual Bin Packing" algorithm that fills gaps while preserving the visual order (top-left to bottom-right) of your items. Static items act as obstacles and are not moved.

```dart
// Call this when you want to compact the grid
controller.optimizeLayout();
```

## Appearance & Accessibility

Visual configuration, user guidance, and inclusive interaction.

### Configuration & Styles

```dart
Dashboard(
  controller: controller,
  scrollDirection: Axis.vertical, // or Axis.horizontal
  resizeBehavior: ResizeBehavior.push, // or ResizeBehavior.shrink
  gridStyle: GridStyle(
    lineColor: Colors.black12, // Color of the background grid lines
    lineWidth: 1,
    fillColor: Colors.black12, // Highlight color for active item slot
    handleColor: Colors.indigo.shade400, // Color for handles
  ),
  itemStyle: DashboardItemStyle(
    focusColor: Colors.indigoAccent, // Border color when focused/selected
    activeColor: Colors.deepOrange,   // Border color when actively dragged
    displacedColor: Colors.amber,    // Border color when displaced by drag push cascade
    borderRadius: BorderRadius.circular(12), // Match your card's border radius
    // Or provide a fully custom BoxDecoration:
    // focusDecoration: BoxDecoration(
    //   border: Border.all(color: Colors.green, width: 4),
    //   borderRadius: BorderRadius.circular(12),
    // ),
  ),
  // Define the aspect ratio of a single slot (1x1)
  slotAspectRatio: 1.0,
  // Spacing between items
  mainAxisSpacing: 10,
  crossAxisSpacing: 10,
  // Padding around the grid
  padding: const EdgeInsets.all(10),
)
```

#### Grid Viewport Filling (`fillViewport`)

In native Sliver integration mode, the grid naturally stops drawing at the last item's position. To force the grid to fill the entire visible screen area (viewport) when your content is sparse, use the `fillViewport` parameter.

*   **`Dashboard` (Wrapper)**: This widget sets `fillViewport: true` by default.
*   **`SliverDashboard` / `DashboardOverlay`**: Set this manually.

```dart
// Example of forcing the grid to fill the entire screen height
DashboardOverlay(
  // ...
  fillViewport: true,
  // ...
)
```

### Guidance Messages

Display contextual help messages to users during interactions. This feature is enabled by providing a `DashboardGuidance` object. If the `guidance` parameter is `null`, the feature is disabled.
You can also use DashboardGuidance.byDefault for default English guidance, or set your custom translated guidance as below:

```dart
Dashboard(
  controller: controller,
  // Provide a DashboardGuidance object to enable the feature.
  // You can override default messages for translation or customization.
  guidance: const DashboardGuidance(
    move: InteractionGuidance(SystemMouseCursors.grab, 'Click/Drag to move'),
    tapToResize: 'Tap and hold to change size',
  ),
  itemBuilder: (context, item) { /* ... */ },
)
```

### Mini Map

For large dashboards, you can add a Mini-Map to visualize the layout and the current viewport.

```dart
Stack(
  children: [
    Dashboard(
      controller: controller,
      scrollController: scrollController, // Required
      // ...
    ),
    Positioned(
      right: 20,
      bottom: 20,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Container(
          // Vertical: Fixed width (120), Flexible height (max 200)
          // Horizontal: Fixed height (120), Flexible width (max 300)
          width: isVertical ? 120 : null,
          height: isVertical ? null : 120,
          constraints: BoxConstraints(
            maxHeight: isVertical ? 200 : 120,
            maxWidth: isVertical ? 120 : 300,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DashboardMinimap(
            controller: controller,
            scrollController: scrollController, // Must match Dashboard's controller
            // Pass width only in vertical mode to enforce width-based scaling
            width: isVertical ? 120 : null,
            style: const MinimapStyle(
              itemColor: Colors.grey,
              displacedItemColor: Colors.amber, // Highlight displaced items during drag
              viewportColor: Color(0x332196F3),
            ),
          ),
        ),
      ),
    ),
  ],
)
```

### Accessibility and Keyboard Navigation

The dashboard is fully accessible out of the box. When **Edit Mode** is enabled, users can navigate and manipulate the grid using only the keyboard.

| Key | Action |
| :--- | :--- |
| **Tab** / **Shift + Tab** | Focus the next / previous item. |
| **Space** / **Enter** | **Grab** the focused item (arm drag) or **Drop** the item. |
| **Arrow Keys** | **Move** the grabbed item (Up, Down, Left, Right). |
| **Delete** / **Backspace** | **Delete** the selected or focused item(s) (fires `onWillDelete` / `onItemsDeleted`). |
| **Ctrl + A** / **Cmd + A** | **Select all** non-static items in the grid. |
| **Ctrl + D** / **Cmd + D** | **Duplicate** the selected item(s) via `onCloneRequested`. |
| **Ctrl + Z** / **Cmd + Z** | **Undo** the last layout change. |
| **Ctrl + Y** / **Cmd + Shift + Z** | **Redo** the last undone layout change. |
| **Escape** | **Cancel** current drag movement, or **Deselect all** when idle. |

**Screen Readers:** The dashboard integrates with `SemanticsService` to announce:
*   Item selection ("Item {id} grabbed").
*   Movement updates ("Row {y}, Column {x}").
*   Drop and Cancel actions.

**Customization:**

You can translate messages using `DashboardGuidance` and customize key bindings using `DashboardShortcuts`.

```dart
Dashboard(
  controller: controller,
  // 1. Customize Messages (i18n)
  guidance: DashboardGuidance(
    move: InteractionGuidance(SystemMouseCursors.grab, 'Move'),
    a11yGrab: (id) => 'Item $id grabbed. Use arrows to move.',
    a11yDrop: (x, y) => 'Dropped on Row $y, Column $x.',
    a11yMove: (x, y) => 'Row $y, Column $x',
    a11yCancel: 'Cancelled.',
    semanticsHintGrab: 'Press Space to grab',
    semanticsHintDrop: 'Press Space to drop',
  ),
);

// 2. Customize Keys (e.g. WASD)
controller.shortcuts = DashboardShortcuts(
  moveUp: {const SingleActivator(LogicalKeyboardKey.keyW)},
  moveLeft: {const SingleActivator(LogicalKeyboardKey.keyA)},
  moveDown: {const SingleActivator(LogicalKeyboardKey.keyS)},
  moveRight: {const SingleActivator(LogicalKeyboardKey.keyD)},
  // Keep defaults for others
  grab: DashboardShortcuts.defaultShortcuts.grab,
  drop: DashboardShortcuts.defaultShortcuts.drop,
  cancel: DashboardShortcuts.defaultShortcuts.cancel,
);
```

## Advanced & Extensibility

Deeper integrations: sliver composition, nested dashboards, and custom engine strategies.

### Advanced Sliver Composition

For advanced layouts (e.g., collapsing app bars, mixed lists and grids), use `DashboardOverlay` and `SliverDashboard`.

1.  **`DashboardOverlay`**: Wraps your `CustomScrollView`. It handles gestures, auto-scrolling, the background grid, and the trash bin.
2.  **`SliverDashboard`**: Renders the grid items inside the scroll view.

- **Grid Clipping behavior:**
  - When using `SliverDashboard` to compose with others slivers, the grid stops precisely at the content end (allowing subsequent slivers to be visible).
    If no subsequent slivers to be visible (eg. `SliverAppBar` + `SliverDashboard`), you can set `fillViewport` to true to extend grid in viewport.
  - While using `Dashboard` widget, in an `Expanded`, the grid fills the viewport, and `fillViewport` has no action.

```dart
  // You must provide the same ScrollController to both the Overlay and the ScrollView
final scrollController = ScrollController();

@override
Widget build(BuildContext context) {
  return Scaffold(
    // 1. Wrap with DashboardOverlay
    body: DashboardOverlay(
      controller: controller,
      scrollController: scrollController,
      
      // Define grid styling here so it renders behind the slivers
      gridStyle: const GridStyle(lineColor: Colors.red), 
      padding: const EdgeInsets.all(8),
      // grid stops precisely at the content of the dashboard
      // to not draw grid behind subsequent slivers
      fillViewport: false, 
      
      // Handle external drops here
      onDrop: (data, item) => 'new_id', 
      
      // Used for drag feedback rendering
      itemBuilder: (ctx, item) => MyCard(item), 
      
      // 2. Your CustomScrollView
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          const SliverAppBar(
            title: Text('My Dashboard'),
            floating: true,
            expandedHeight: 200,
          ),
          
          // 3. The Dashboard Sliver
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: SliverDashboard(
              itemBuilder: (ctx, item) => MyCard(item),
            ),
          ),
          
          // 4. Other Slivers
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, index) => ListTile(title: Text('Item $index')),
              childCount: 20,
            ),
          ),
        ],
      ),
    ),
  );
}
```

### Nested Grids & Cross-Grid Drag

Embed a full dashboard inside a grid item, and let users drag items **between**
grids — parent ↔ nested ↔ siblings, at any depth. The item leaves its source
grid live, a push-preview placeholder follows the cursor in whichever grid is
hovered, and dropping outside every grid restores the source layout.

<p align="center">
  <img src="https://raw.githubusercontent.com/scalz/sliver_dashboard/main/img/nested_grids.gif" alt="Nested grids" width="400"/>
</p>

```dart
final root  = DashboardController(initialLayout: [...]);
final group = DashboardController(initialLayout: [...]);

DashboardNestedScope(
  onItemMovedToGrid: (item, from, to) => persist(),
  child: Dashboard(
    controller: root,
    itemBuilder: (context, item) {
      if (item.id == 'group-1') {
        return NestedDashboard(
          controller: group,
          parentItemId: item.id,   // links the tree
          sizeToContent: true,     // host item grows/shrinks with content
          itemBuilder: buildLeafItem,
        );
      }
      return buildLeafItem(context, item);
    },
  ),
)
```

Key options:

- `NestedDashboard.autoSlotCount` (default `true`): the nested grid's column
  count follows its host item width — inner and outer cells keep the same
  visual size while the host is resized.
- `NestedDashboard.sizeToContent` (+ `sizeToContentMax`, `chromeExtent`): the
  host item's height adapts so the nested grid never scrolls internally.
- `Dashboard.crossGridDragOut` / `Dashboard.acceptCrossGridItems` (default
  `true`): per-grid opt-out of leaving/receiving items.
- `DashboardNestedScope.subGridDynamic` + `onNestedGridRequested`: holding a
  dragged item over a plain item highlights it and, after `nestHoverDelay`,
  asks your app to convert it into a nested grid.
- `DashboardNestedScope.probe`: whether the pointer or the dragged tile's visual center
  decides which grid it enters, independent of the grab point.
- Auto-scroll: fixed-size nested grids (`sizeToContent: false`) scroll
  internally with edge auto-scroll; `sizeToContent: true` grids delegate edge
  auto-scroll to the parent grid, which scrolls to follow the growing content.
- `DashboardNestedScope.subGridDynamicSameGrid` (default `false`): the
  same-grid variant of `subGridDynamic` (the two flags are independent) —
  pause the pointer mid-drag over a sibling to freeze the pushes and arm it
  as a nested-grid host. Opt-in because the visible freeze changes the drag
  feel.
- `DashboardNestedScope.onNestedGridRequestAbandoned`: fired when a
  nested-grid request ends without the item landing in the requested host's
  child grid — revert your speculative conversion there (the example shows
  how).
- `DashboardNestedScope.maxNestingDepth` (default `null` = unlimited): cap the
  number of nesting levels users can create (root is level 0, so `1` = one
  level, `0` = nesting off). Plain item moves are never blocked; only the
  creation of a deeper level is.
- `LayoutItem.hasNestedGrid`: declarative host flag — branch your builder on
  it (`if (item.hasNestedGrid) return NestedDashboard(...)`) instead of on
  ids, so groups stay portable between grids and across save/load.
- Programmatic move: `coordinator.moveItemToGrid(from: a, to: b, itemId: 'x')`.

| `DimensionProjectionPolicy` | Preserves | Typical use |
|---|---|---|
| `preserveLogicalSize` (default) | `w`/`h` in cells | grids of equal physical density |
| `preserveVisualProportion` | the fraction of the container | grids of similar width, different density |
| `preservePixelSize` | the physical pixel span | nested panels; grids of very different widths |
| `custom` | delegated to the application | domain rules |

> **`preserveVisualProportion` is not "same apparent size".** It preserves the
> *fraction of the container*. Because a nested grid occupies a cell-range
> of its parent, its container is physically much narrower: a tile representing
> "1/6 of the page" becoming "1/6 of the panel" shrinks accordingly. To keep a
> tile's apparent physical size when entering a panel, use `preservePixelSize`.
>
> With a 24-column page 1200 px wide and a panel hosted in a 6-column tile split
> into 12 columns, a `w:4` tile (193 px) projects to:
> `preserveLogicalSize` → 87 px, `preserveVisualProportion` → 40 px,
> `preservePixelSize` → 193 px.

> `moveItemToGrid` is **deliberately unprojected**: the caller is explicit and
> owns the geometry. To reproduce the sizing a drag would have produced, use
> `coordinator.projectItemBetween(from:, to:, item:)` then `setItemSize`.

Persistence of the whole tree is a single call each way:

```dart
final tree = exportNestedTree(coordinator, root); // JSON-encodable
loadNestedTree(coordinator, root, tree);          // nested payloads delivered
                                                  // automatically on mount
```

Notes: cross-grid drags carry a single item (multi-selection drags stay in
their grid), and item ids must be unique across the tree. See
[`README_NESTED_GRID.md`](README_NESTED_GRID.md) for the full guide and
documented behaviors.

#### Drop targets: closed folders & custom tiles

A tile can receive dropped items **without showing a nested grid** — closed
folder icons, archive bins, "add to group" badges:

```dart
Dashboard<String>(
  controller: controller,
  scrollController: scrollController,
  onItemDroppedOnHost: (draggedItems, host, hostGrid, sourceGrid) {
    // The layout is already back to its pre-drag state: nothing landed on
    // the grid, and the items are still in the grid the drag started from.
    // You decide what the drop means.
    sourceGrid.removeItems(draggedItems.map((i) => i.id).toList());
    myFolderModel.addAll(host.id, draggedItems);
  },
  itemBuilder: (context, item) => MyTile(item),
)
```

A tile is a drop target when either:

- it is flagged `LayoutItem(isDropTarget: true)` — an explicit target, or
- it carries `hasNestedGrid: true` **while its child grid is not mounted** —
  a closed folder. Once the child grid is mounted, the regular cross-grid
  drag owns the interaction instead.

While a target is hovered, layout pushes freeze so it stays under the
cursor and it shows the nest highlight, stylable via
`DashboardItemStyle(nestTargetColor: ..., nestTargetDecoration: ...)`.
Targeting is by **pointer position**, so the dragged item may be larger than
the target. Doing nothing in the callback rejects the drop: the items simply
return home. Set `DashboardNestedScope.onItemDroppedOnHost` instead for a
scope-wide default. Costs nothing while no callback is registered.

This works for drags started in the same grid **and** for items dragged out
of another grid — including a nested one, so a tile can be pulled out of an
open folder and filed straight into a closed one. In both cases the items
end up back where the drag started, which is why the callback hands you
`sourceGrid` (the grid holding them now) alongside `hostGrid` (the grid
owning the target tile); for a same-grid drop they are the same controller.

#### Multi-Sliver Drag & Drop (Sibling Grids)

<p align="center">
  <img src="https://raw.githubusercontent.com/scalz/sliver_dashboard/main/img/multi_sliver_cross_drag.gif" alt="Cross drag&drop in Multi Sliver" width="400"/>
</p>

You can also coordinate drag-and-drop operations across completely separate sibling grids (e.g., separated by a collapsing `SliverAppBar` or a normal native `SliverList`) inside the same `CustomScrollView`.

To prevent `DashboardControllerProvider` shadowing and resolve target metrics with absolute precision, you must pass unique `GlobalKey`s and bind controllers directly to the slivers:

```dart
final scrollController = ScrollController();
final sliverKey1 = GlobalKey();
final sliverKey2 = GlobalKey();

@override
Widget build(BuildContext context) {
  return DashboardNestedScope(
    projectionPolicy: DimensionProjectionPolicy.preserveVisualProportion,
    child: DashboardOverlay(
      controller: controller1,
      scrollController: scrollController,
      sliverKey: sliverKey1, // Bind key to the overlay
      padding: const EdgeInsets.all(8.0), // MUST match the SliverPadding below
      child: DashboardOverlay(
        controller: controller2,
        scrollController: scrollController,
        sliverKey: sliverKey2, // Bind key to the overlay
        padding: const EdgeInsets.all(8.0), // MUST match the SliverPadding below
        child: CustomScrollView(
          controller: scrollController,
          slivers: [
            const SliverAppBar(title: Text('Dense Grid (8 Columns)')),
            SliverPadding(
              padding: const EdgeInsets.all(8.0),
              sliver: SliverDashboard(
                key: sliverKey1,       // Match key on the sliver
                controller: controller1, // Pass controller directly
                itemBuilder: buildItem,
              ),
            ),
            SliverList(delegate: ...), // Normal list separator
            const SliverAppBar(title: Text('Large Grid (4 Columns)')),
            SliverPadding(
              padding: const EdgeInsets.all(8.0),
              sliver: SliverDashboard(
                key: sliverKey2,       // Match key on the sliver
                controller: controller2, // Pass controller directly
                itemBuilder: buildItem,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
```

### Minimap Markers & Multiple Viewports

```dart
DashboardMinimap(
  controller: controller,
  scrollController: scrollController,
  markers: const [
    MinimapMarker(itemId: 'sales', color: Colors.red), // status dot
    MinimapMarker(
      itemId: 'alerts',
      color: Colors.amber,
      shape: MinimapMarkerShape.triangle,
      alignment: Alignment.bottomLeft,
    ),
  ],
)
```

For a single grid, do NOT pass `viewportIndicators`: the default indicator
maps itself onto the grid's exact scroll segment automatically (the sliver
publishes its real `precedingScrollExtent`, scroll extent and slot sizes at
every layout pass). Hardcoding a `mainAxisContentExtent` that doesn't match
the real segment will clamp the indicator against a fictional boundary and
make it look like a gauge.

`viewportIndicators` is for the advanced case of drawing SEVERAL indicators
on one minimap (e.g. sibling grids sharing a scroll view). Even then, feed
each indicator the values its grid publishes rather than constants:

```dart
viewportIndicators: [
  for (final grid in [grid1, grid2])
    ViewportIndicator(
      scrollController: scrollController,
      mainAxisLeadingExtent: grid.internal.viewMainAxisLeadingExtent ?? 0,
      mainAxisContentExtent: grid.internal.viewMainAxisContentExtent,
    ),
],
```

Markers live in their own cached layer (one batched `Path` per distinct
color) and only re-rasterize when the marker list changes by value — scroll
ticks still repaint nothing but the thin viewport layer.

Need real widgets instead of painted dots? `markerBuilder` is the opt-in
escape hatch — and `onItemTap` makes the minimap navigable:

```dart
DashboardMinimap(
  controller: controller,
  scrollController: scrollController,
  // Widget markers: for SMALL sets (~50). Prefer `markers` beyond that —
  // the Path layer adds zero objects per marker and never repaints on
  // scroll, while widgets are re-reconciled every minimap rebuild.
  markerBuilder: (context, item) => alerts.contains(item.id)
      ? const Align(
           alignment: Alignment.centerLeft, 
           child: Icon(Icons.warning, size: 8, color: Colors.red),
        )
      : null, // null = no marker for this item
  // Tap an item on the minimap: select it, scroll to it, open it…
  // (suppresses tap-to-scroll for that tap; empty areas still scroll)
  onItemTap: (item) => controller.scrollToItem(item.id),
)
```

### Desktop Hover Fine-Tuning

On dense layouts (>= 16 items) pointer-to-item resolution uses an O(1)
coordinate-bucket index instead of a linear scan, and a low-pass jitter
filter (`DashboardNestedScope(hoverJitterTolerance: 4)`) stops the
nest-hover highlight from flickering when the cursor rests on a tile border.

### Reflow Animations

Tiles pushed or compacted during a drag/resize can slide smoothly to their new
slot instead of snapping:

```dart
Dashboard(
  animateReflow: true, // default: false
  reflowDuration: const Duration(milliseconds: 150),
  // ...
)
```

Design notes: the layout itself stays instantaneous and deterministic (the
engine and controller are untouched); only the *painted* position of a moved
tile is interpolated during the paint phase of `RenderSliverDashboard`. Each
tile's content is cached behind a `RepaintBoundary`, so the slide is a GPU
translation of the cached layer — no widget rebuilds, no re-rasterization.
Hit-testing and screen-reader focus use the final position immediately, and a
slot-metric change (window resize, breakpoint, slot count) snaps by design.

### Fluid Resize

By default a resize is quantised: the tile jumps one full slot at a time, because
the tile you see is the one the sliver lays out from the snapped grid
coordinates. `fluidResize` gives the gesture the same architecture a drag has
had all along.

```dart
Dashboard(
  fluidResize: true,                                        // default: false
  resizeSettleDuration: const Duration(milliseconds: 120),  // Duration.zero = snap
  // ...
)
```

What changes while a handle is dragged:

- the tile is lifted into the overlay and drawn at the **exact pixel size the
  pointer describes**, clamped to `minW` / `minH` / `maxW` / `maxH`, to static
  obstacles (the anchored top/left barriers) and to the grid bounds;
- its slot stays behind as the **snap-target placeholder** — the hole plus the
  `GridStyle.fillColor` highlight — showing the size and position the tile will
  actually take;
- **neighbours reflow against the projected slot**, exactly as before: the engine
  still receives the snapped candidate, so collision, push/shrink behaviour and
  `animateReflow` are unchanged;
- on release the tile animates from its raw rect into the snapped slot over
  `resizeSettleDuration`.

Resize handles are rendered on the lifted tile, so the handle stays under the
cursor for the whole gesture.

Also available on `NestedDashboard` (per grid), and on the controller for raw
`DashboardOverlay` compositions:

```dart
controller.setFluidResize(true);
```

**Why it is off by default.** The preview publishes one rectangle per pointer
event instead of one per cell crossing. With `itemBuilder` or
`itemBreakpointBuilder` that costs nothing — the content stays cached behind its
`RepaintBoundary` — but with `itemLayoutBuilder`, whose contract is to rebuild on
every pixel of the tile's live dimensions, it means a content rebuild at pointer
frequency. On low-end web clients that is a cost worth opting into rather than
inheriting.

### Custom Compaction Strategy

If the default vertical/horizontal compaction doesn't fit your needs (e.g., you want a Tetris-like gravity or specific sorting rules), you can implement your own strategy.

1.  Create a class that extends `CompactorDelegate`.
2.  Implement `compact` and `resolveCollisions`.
3.  Inject it into the controller.

```dart
class MyCustomCompactor extends CompactorDelegate {
  @override
  List<LayoutItem> compact(List<LayoutItem> layout, int cols, {bool allowOverlap = false}) {
    // Your custom logic here...
    // You can use helpers like sortLayoutItems, getFirstCollision, etc.
    return layout;
  }

  @override
  List<LayoutItem> resolveCollisions(List<LayoutItem> layout, int cols) {
    // Logic to push items away during drag
    return layout;
  }
}

// Usage
controller.setCompactor(MyCustomCompactor());
```

### Interaction & Collision Policies (Custom Rules)

To enforce granular business rules (e.g. "KPI widgets cannot push Chart widgets", "Notes cannot be dragged to Row 0", or "disable resizing on certain conditions") without writing a custom compaction delegate, you can inject a custom `DashboardPolicy`:

```dart
class MyDashboardPolicy extends DashboardPolicy {
  @override
  bool canDrag(LayoutItem item) => item.id != 'locked-item';

  @override
  bool canResize(LayoutItem item) => item.w < 6;

  @override
  bool canMoveTo(LayoutItem item, int targetX, int targetY, List<LayoutItem> currentLayout) {
    // Block moving any item into Row 0 (reserved system area)
    return targetY > 0;
  }

  @override
  bool canCollide(LayoutItem itemA, LayoutItem itemB) {
    // Block charts from pushing system KPIs
    if (itemA.id.startsWith('chart') && itemB.id.startsWith('kpi')) {
      return false;
    }
    return true;
  }
}

// Inject the policy into your controller
controller.policy = MyDashboardPolicy();
```

### Utilities

The controller provides useful getters to help you interact with the layout programmatically.

```dart
// Gets the Y-coordinate of the bottom-most edge of the layout.
// Useful for adding an item below all existing content.
int nextRow = controller.lastRowNumber;

// Find all empty rectangular spaces in the grid.
List<LayoutItem> emptySpaces = controller.availableFreeAreas;

// Find all contiguous horizontal free spaces in each row.
List<LayoutItem> horizontalSpaces = controller.availableHorizontalFreeAreas;

// Find the first empty space in the grid, starting top-left.
LayoutItem? firstSpace = controller.firstFreeArea;

// Find the first empty space in the last row that contains items.
LayoutItem? spotInLastRow = controller.lastRowFreeArea;

// Check if an item of a certain size can fit anywhere on the board.
final itemToCheck = const LayoutItem(id: '_', x: 0, y: 0, w: 2, h: 2);
if (controller.canItemFit(itemToCheck)) {
  print("A 2x2 item can fit!");
}

// You can then use this information to add a new item precisely.
if (spotInLastRow != null) {
  final newItem = LayoutItem(
    id: 'new',
    x: spotInLastRow.x,
    y: spotInLastRow.y,
    w: spotInLastRow.w,
    h: 1, // Only take 1 row of the available space
  );
  controller.addItem(newItem);
}
```

## Benchmark

`sliver_dashboard` is designed for raw execution speed. Even under extreme stress tests, all real-time interactive operations (dragging, resizing, compaction) execute in microseconds under native Dart AOT—well within a 120 Hz frame budget (8.33 ms) even with thousands of items.

| Operation (1,000 items)     | Standard Compactor | Fast/Tide Compactor |
|:----------------------------| :--- | :--- |
| **Vertical Compaction**     | ~532 µs | ~497 µs |
| **Horizontal Compaction**   | ~944 µs | ~520 µs |
| **Interactive Resize**      | ~749 µs | *N/A* |
| **Interactive Drag (Move)** | ~701 µs | *N/A* |

**View Detailed Benchmarks:** For the complete, high-density performance breakdown (up to 10,000 items), algorithmic analysis, and instructions on how to compile and run the benchmark suite on your own machine, see the dedicated [BENCHMARK.md](BENCHMARK.md) document.

## Contributing

Contributions are welcome! To ensure the project remains high-quality, reliable, and consistent, please follow the guidelines below when contributing code.

### Architecture & AI-Assisted Contributions

For a comprehensive look at the engine's core design philosophy and layout pipeline, you can read this design decisions document: [Building a Dashboard Engine on Flutter Slivers](DESIGN_DECISIONS.md).

The development of `sliver_dashboard` can be assisted using AI coding assistants under a disciplined, structured framework to ensure code quality and performance:

*   **Strict Architectural Constraints:** All contributions must align with the State, Logic, and View layers detailed in [ARCHITECTURE.md](ARCHITECTURE.md). AI assistants are further guided by the rules in [AGENTS.md](AGENTS.md) file, which dictates core invariants (such as avoiding allocations during layout phases, enforcing proper tree isolation via `RepaintBoundary`, and maintaining row-index consistency).
*   **Systematic Human Review:** No generated code is merged without manual review to verify algorithmic efficiency, readability, and overall design cohesion.
*   **CI Test Verification:** The suite of 800+ regression tests running in CI serves as the final validator. Every contribution, whether handwritten or co-authored with an AI, must pass all tests and respect documented performance budgets.

#### How to Contribute:
1. **Understand the System:** Read [ARCHITECTURE.md](ARCHITECTURE.md) to familiarize yourself with the declarative UI, reactive state management, and nested grids protocol.
2. **Setup your AI Assistant:** If you plan to contribute using AI tools (such as Cursor, Copilot, or custom LLM prompts), please ensure you point your assistant to the instructions in [AGENTS.md](AGENTS.md) before writing any code.

#### Quality Standards

This package tries to maintain strict code quality standards with high test coverage and strict guidelines in place. All contributions must adhere to the following quality standards:

- **Core Engine (`LayoutEngine`):** > 95% coverage
- **Controller (`DashboardController`):** > 95% coverage
- **Global Package:** > 95% coverage

#### Code Style and Linting:

- The project uses **Dart** formatting and linting rules. Before submitting any changes, ensure your code is properly formatted.
- Uses `dart analyze` to enforce coding best practices, and any warnings or errors will result in a failed build.
- **Formatting:** Always run `dart format .` to automatically fix any formatting issues.

#### Running Tests Locally

Before submitting your pull request, it’s important to run the tests locally to verify everything works as expected. To run the tests and check the coverage:

1. Run the following command to execute the tests and collect coverage:
```bash
flutter test --coverage
```

2. If you have `lcov` installed, you can generate a human-readable coverage report:
```bash
genhtml coverage/lcov.info -o coverage/html
```
or depending on your setup
```bash
perl "%GENHTML%" -o coverage\html coverage\lcov.info
```
This will generate an HTML report that you can open in your browser to check the code coverage and ensure the tests are passing.

#### Continuous Integration (CI) Pipeline

Every pull request and push to the `main` branch automatically triggers a set of checks, including:

- **Code Formatting:** Ensures all code is formatted correctly according to Dart style guide.
- **Static Code Analysis:** Runs `flutter analyze` to catch potential errors, warnings, and linting issues.
- **Unit Tests:** Runs the test suite to verify that the code behaves as expected, with code coverage being tracked to maintain high standards.

#### Code Quality Enforcement

The CI pipeline will fail if:

- **Linting violations** are detected.
- **Static analysis** reveals warnings or errors.
- **Tests fail**, or the code coverage decreases below the required threshold.
  Pull requests should pass all checks before they can be merged into the `main` branch.