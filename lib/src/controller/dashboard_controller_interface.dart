import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart' as engine;
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/a11y/dashboard_shortcuts.dart';
import 'package:sliver_dashboard/src/view/guidance/dashboard_guidance.dart';
import 'package:state_beacon/state_beacon.dart';

/// A callback that is fired when a user starts a drag or resize interaction
/// on a dashboard item.
///
/// The [LayoutItem] that is being interacted with is passed as an argument.
typedef DashboardItemInteractionCallback = void Function(LayoutItem item);

/// A callback that is fired when the layout of the dashboard changes.
///
/// [items]: The new layout items.
/// [slotCount]: The number of columns associated with this layout (useful for responsive persistence).
typedef DashboardLayoutChangeListener = void Function(List<LayoutItem> items, int slotCount);

/// The public contract for the Dashboard Controller.
///
/// This interface exposes only the methods and properties intended for public use,
/// keeping the internal logic (drag updates, calculations) hidden from the IDE autocomplete.
/// Manages the state and interactions of the dashboard.
///
/// This controller is the single source of truth for the dashboard's layout.
/// It uses `state_beacon` for reactive state management, ensuring that UI
/// updates are efficient and predictable.
abstract class DashboardController {
  /// Creates a new [DashboardController].
  ///
  /// - [initialLayout]: The starting layout for the dashboard.
  /// - [initialSlotCount]: The number of columns in the grid.
  factory DashboardController({
    List<LayoutItem> initialLayout,
    int initialSlotCount,
    DashboardItemInteractionCallback? onInteractionStart,
    DashboardLayoutChangeListener? onLayoutChanged,
  }) = DashboardControllerImpl;

  // --- PUBLIC STATE (Beacons) ---

  /// The reactive state of the dashboard layout.
  ///
  /// Widgets can listen to this beacon to rebuild whenever the layout changes.
  WritableBeacon<List<LayoutItem>> get layout;

  /// The reactive state for the dashboard's edit mode.
  WritableBeacon<bool> get isEditing;

  /// The number of columns in the dashboard grid.
  ///
  /// Changing this value will trigger a relayout.
  WritableBeacon<int> get slotCount;

  /// A reactive property to control collision behavior.
  /// If `true` (default), items will push each other on drag/resize.
  /// If `false`, items will be allowed to overlap.
  WritableBeacon<bool> get preventCollision;

  /// This controls "push" direction.
  /// If null, no compaction for precise placement.
  WritableBeacon<engine.CompactType> get compactionType;

  /// The scroll direction of the dashboard.
  WritableBeacon<Axis> get scrollDirection;

  /// The size of the touch target for resizing handles.
  WritableBeacon<double> get resizeHandleSide;

  /// Default Handles color style.
  WritableBeacon<Color?> get handleColor;

  /// A reactive property to control resize behavior.
  WritableBeacon<engine.ResizeBehavior> get resizeBehavior;

  /// The set of IDs of the currently selected items.
  WritableBeacon<Set<String>> get selectedItemIds;

  /// Whether a drag operation is currently in progress.
  /// Useful to distinguish between "Selected" (static highlight) and "Dragging" (moving).
  ReadableBeacon<bool> get isDragging;

  /// The ID of the primary active item (usually the one under the cursor or the first selected).
  /// Returns null if no item is selected/active.
  ReadableBeacon<String?> get activeItemId;

  // --- PUBLIC PROPERTIES ---

  /// An optional callback that is fired when a user starts a drag or resize
  /// gesture on an item.
  ///
  /// This can be used to trigger haptic feedback, logging, or other custom
  /// actions. The specific [LayoutItem] being interacted with is provided.
  DashboardItemInteractionCallback? get onInteractionStart;

  /// A callback that is fired whenever the layout changes.
  DashboardLayoutChangeListener? get onLayoutChanged;

  /// The set of messages to display for user guidance. Can be null if disabled.
  DashboardGuidance? get guidance;
  set guidance(DashboardGuidance? value);

  /// Returns the current placeholder item.
  /// Used by the view to determine the drop position.
  LayoutItem? get currentDragPlaceholder;

  // --- PUBLIC METHODS ---

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
  });

  /// Adds a new item to the dashboard.
  ///
  /// The new item is added, and the layout is re-compacted to find a suitable
  /// position for it.
  void addItem(LayoutItem newItem, {engine.CompactType? overrideCompactType});

  /// Removes an item from the dashboard by its ID.
  ///
  /// After removal, the layout is re-compacted to fill any empty space.
  void removeItem(String itemId, {engine.CompactType? overrideCompactType});

  /// Removes multiple items from the dashboard by their IDs.
  void removeItems(List<String> itemIds);

  /// Selects or deselects an item.
  ///
  /// [itemId]: The item to toggle.
  /// [multi]: If true (e.g. Shift/Ctrl click), adds/removes from current selection.
  ///          If false (Simple click), clears previous selection and selects this one.
  void toggleSelection(String itemId, {bool multi = false});

  /// Clears the current selection.
  void clearSelection();

  /// Toggles the edit mode for the dashboard.
  void toggleEditing();

  /// Sets the edit mode for the dashboard.
  // ignore: avoid_positional_boolean_parameters
  void setEditMode(bool editing);

  /// Sets the number of columns for the grid and triggers a relayout.
  void setSlotCount(int newSlotCount);

  /// Sets the collision behavior for the dashboard.
  // ignore: avoid_positional_boolean_parameters
  void setPreventCollision(bool prevent);

  /// Sets the compaction behavior for the dashboard.
  void setCompactionType(engine.CompactType type);

  /// Sets the resize behavior for the dashboard.
  void setResizeBehavior(engine.ResizeBehavior behavior);

  /// Sets the resize handle side length.
  void setResizeHandleSide(double side);

  /// Sets the default color of handles.
  void setHandleColor(Color? color);

  /// Moves the currently active item by a grid delta (keyboard navigation).
  ///
  /// [dx] is the horizontal change in columns.
  /// [dy] is the vertical change in rows.
  void moveActiveItemBy(int dx, int dy);

  /// Cancels the current interaction (drag/resize) and reverts the layout
  /// to its state before the interaction started.
  void cancelInteraction();

  /// The keyboard shortcuts configuration.
  /// If null, defaults to [DashboardShortcuts.defaultShortcuts].
  DashboardShortcuts? get shortcuts;
  set shortcuts(DashboardShortcuts? value);

  /// Optimizes the layout by compacting items to remove gaps.
  ///
  /// This operation respects the visual order of items (top-left to bottom-right)
  /// and treats static items as immovable obstacles.
  void optimizeLayout();

  /// Exports the current layout state to a list of maps (JSON-ready).
  List<Map<String, dynamic>> exportLayout();

  /// Imports a layout from a list of maps.
  ///
  /// This replaces the current layout.
  /// [jsonLayout] is the list of maps (e.g. from JSON decode).
  void importLayout(List<dynamic> jsonLayout);

  /// Disposes all the beacons to prevent memory leaks.
  void dispose();
}
