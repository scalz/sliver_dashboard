import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';

/// A builder function for dashboard items.
typedef DashboardItemBuilder = Widget Function(BuildContext context, LayoutItem item);

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
