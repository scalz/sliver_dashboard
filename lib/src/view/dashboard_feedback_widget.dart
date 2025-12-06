import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/dashboard_item_widget.dart';
import 'package:sliver_dashboard/src/view/dashboard_typedefs.dart';
import 'package:state_beacon/state_beacon.dart';

/// A widget that renders the visual feedback for an item being dragged.
///
/// This widget floats above the dashboard grid (usually within a [Stack]) and
/// follows the user's pointer. It calculates its absolute position based on
/// the grid's slot metrics, the current scroll offset, and the active drag offset
/// from the [DashboardController].
///
/// It uses an [AnimatedBuilder] to listen to the [scrollController], ensuring
/// the feedback item stays visually synchronized even if the dashboard scrolls
/// underneath it (e.g., during auto-scrolling).
class DashboardFeedbackItem extends StatelessWidget {
  /// Creates a [DashboardFeedbackItem].
  const DashboardFeedbackItem({
    required this.item,
    required this.builder,
    required this.controller,
    required this.scrollController,
    required this.slotWidth,
    required this.slotHeight,
    required this.mainAxisSpacing,
    required this.crossAxisSpacing,
    required this.scrollDirection,
    required this.isEditing,
    this.itemGlobalKeySuffix = '',
    this.feedbackBuilder,
    super.key,
  });

  /// The layout item currently being dragged.
  final LayoutItem item;

  /// The builder used to render the content of the item.
  final DashboardItemBuilder builder;

  /// The controller managing the drag state and offsets.
  final DashboardController controller;

  /// The scroll controller of the dashboard, used to adjust the vertical/horizontal
  /// position relative to the viewport.
  final ScrollController scrollController;

  /// The width of a single grid slot in pixels.
  final double slotWidth;

  /// The height of a single grid slot in pixels.
  final double slotHeight;

  /// The spacing between items on the main axis.
  final double mainAxisSpacing;

  /// The spacing between items on the cross axis.
  final double crossAxisSpacing;

  /// The scroll direction of the dashboard.
  final Axis scrollDirection;

  /// A suffix appended to the item's key to ensure uniqueness.
  final String itemGlobalKeySuffix;

  /// Whether the dashboard is currently in edit mode.
  final bool isEditing;

  /// An optional builder to customize the appearance of the item while dragging.
  /// If null, [builder] is used.
  final DashboardItemFeedbackBuilder? feedbackBuilder;

  @override
  Widget build(BuildContext context) {
    // Watch the drag offset specifically here.
    // This limits rebuilds to just this widget during drag.
    final dragOffset = (controller as DashboardControllerImpl).dragOffset.watch(context);

    return AnimatedBuilder(
      animation: scrollController,
      builder: (context, _) {
        final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;

        double top;
        double left;
        double width;
        double height;

        if (scrollDirection == Axis.vertical) {
          left = item.x * (slotWidth + crossAxisSpacing);
          top = (item.y * (slotHeight + mainAxisSpacing)) - scrollOffset;
          width = item.w * (slotWidth + crossAxisSpacing) - crossAxisSpacing;
          height = item.h * (slotHeight + mainAxisSpacing) - mainAxisSpacing;
        } else {
          left = (item.x * (slotWidth + mainAxisSpacing)) - scrollOffset;
          top = item.y * (slotHeight + crossAxisSpacing);
          width = item.w * (slotWidth + mainAxisSpacing) - mainAxisSpacing;
          height = item.h * (slotHeight + crossAxisSpacing) - crossAxisSpacing;
        }

        // Apply the drag offset (visual delta)
        left += dragOffset.dx;
        top += dragOffset.dy;

        // Use _DashboardItem to get the cached content widget
        final content = DashboardItem(
          item: item,
          isEditing: isEditing,
          builder: builder,
        );

        // Apply custom feedback builder if provided, otherwise use the content directly
        final feedbackWidget =
            feedbackBuilder != null ? feedbackBuilder!(context, item, content) : content;

        return Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: feedbackWidget,
        );
      },
    );
  }
}
