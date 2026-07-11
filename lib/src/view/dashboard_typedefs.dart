import 'dart:async';

import 'package:flutter/material.dart';
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

/// Builder for accessibility messages related to an item ID.
typedef A11yItemMessageBuilder = String Function(String itemId);

/// Builder for accessibility messages related to a grid position.
typedef A11yPositionMessageBuilder = String Function(int x, int y);
