import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';

/// A static builder function for dashboard items (optimized; skips rebuilds on resize).
typedef DashboardItemBuilder = Widget Function(BuildContext context, LayoutItem item);

/// Alternative builder providing live physical pixel dimensions (rebuilds continuously on resize).
typedef DashboardItemLayoutBuilder = Widget Function(
  BuildContext context,
  LayoutItem item,
  double width,
  double height,
  int slotCount,
);

/// A responsive builder that reconstructs the child subtree ONLY when the resolved breakpoint transitions.
typedef DashboardItemBreakpointBuilder = Widget Function(
  BuildContext context,
  LayoutItem item,
  dynamic breakpoint,
  double width,
  double height,
  int slotCount,
);

/// Maps physical dimensions to a developer-defined custom breakpoint state.
typedef DashboardBreakpointResolver = dynamic Function(
  double width,
  double height,
  LayoutItem item,
  int slotCount,
);

/// A builder for the widget that is dragged from an external source.
typedef DraggableFeedbackBuilder = Widget Function(BuildContext context);

/// Signature for the callback that produces the duplicate of [source] when a
/// drag starts with the clone modifier held (`Alt` / `Option` by default, see
/// `DashboardShortcuts.cloneKeys`).
///
/// [source] is the tile under the pointer, exactly as it exists on [grid] at
/// pointer-down. [grid] is the controller the clone will be inserted into —
/// the same grid as [source] — and is what lets a single scope-wide handler
/// serve several grids.
///
/// The application owns the identity of the duplicate: return a [LayoutItem]
/// carrying a **new id that is unique across the whole grid tree** (the
/// cross-grid moves and the tree codec assume tree-wide unique ids), plus
/// whatever business metadata the duplicate needs — typically
/// `source.copyWith(id: newId, extra: {...})`. Returning `null` cancels the
/// duplication: the gesture degrades to a plain move of [source].
///
/// The returned item's `x` / `y` are **ignored**: the clone is always
/// inserted at [source]'s own coordinates so it materializes exactly under
/// the cursor. Its size and constraints are honoured.
typedef DashboardCloneRequestCallback = LayoutItem? Function(
  LayoutItem source,
  DashboardController grid,
);

/// A callback for onDrop which provides T data and the LayoutItem
typedef DashboardDropCallback<T> = FutureOr<String?> Function(T data, LayoutItem item);

/// A builder for the data that is dropped onto the dashboard.
typedef DraggableDataBuilder<T> = T Function();

/// A builder for the item feedback (the widget that follows the finger).
/// [child] is the standard widget built by itemBuilder.
typedef DashboardItemFeedbackBuilder = Widget Function(
  BuildContext context,
  LayoutItem item,
  Widget child,
);

/// A builder for the trash/delete area.
/// [isHovered] is true if the dragged item is currently over the trash area.
/// [isActive] is true if the item has been hovered long enough to trigger deletion on drop.
typedef DashboardTrashBuilder = Widget Function(
  BuildContext context,
// never mind
// ignore: avoid_positional_boolean_parameters
  bool isHovered,
  bool isActive,
  String? activeItemId,
);

/// A callback to confirm the deletion of multiple items.
/// Returns `true` to proceed with deletion, `false` to cancel.
typedef DashboardWillDeleteCallback = Future<bool> Function(List<LayoutItem> items);

/// A callback fired when items are deleted.
typedef DashboardItemsDeletedCallback = void Function(List<LayoutItem> items);

/// A builder function for rendering custom section headers.
typedef DashboardSectionHeaderBuilder = Widget Function(BuildContext context, LayoutItem item);

/// Resolves the template [LayoutItem] an external draggable payload of type [T] will become.
///
/// Called while the payload hovers the grid so the placeholder reflects the
/// real footprint. `x` and `y` are ignored (the pointer decides those), and the
/// returned `id` is ignored (`onDrop` names the tile).
///
/// Constraints (`minW`, `minH`, `maxW`, `maxH`), flags (`isDraggable`,
/// `isResizable`, `isStatic`, `isSectionBarrier`, `hasNestedGrid`, `isDropTarget`),
/// and [LayoutItem.extra] are preserved upon drop.
///
/// Returning `null` falls back to DashboardOverlay.placeholderWidth and
/// DashboardOverlay.placeholderHeight.
typedef DashboardExternalTemplateBuilder<T> = LayoutItem? Function(T data);

/// Builder for accessibility messages related to an item ID.
typedef A11yItemMessageBuilder = String Function(String itemId);

/// Builder for accessibility messages related to a grid position.
typedef A11yPositionMessageBuilder = String Function(int x, int y);

/// Builder for accessibility messages carrying a plain count, such as the
/// number of items a rubberband ("lasso") selection ended up covering.
typedef A11yCountMessageBuilder = String Function(int count);
