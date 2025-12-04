import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_provider.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/guidance/guidance_interactor.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';
import 'package:state_beacon/state_beacon.dart';

/// A wrapper for dashboard items that automatically adds resize handles
/// when the dashboard is in edit mode.
class DashboardItemWrapper extends StatelessWidget {
  /// Creates a DashboardItemWrapper.
  const DashboardItemWrapper({
    required this.item,
    required this.child,
    this.handleColor,
    super.key,
  });

  /// The layout item this widget represents.
  final LayoutItem item;

  /// The actual content widget for the dashboard item.
  final Widget child;

  /// The color of the resize handles. Defaults to the theme's primary color.
  final Color? handleColor;

  @override
  Widget build(BuildContext context) {
    final controller = DashboardControllerProvider.of(context);
    final isEditing = controller.isEditing.watch(context);
    final useHandleColor = handleColor ?? controller.handleColor.value;

    final content = isEditing && (item.isResizable ?? true) && !item.isStatic
        ? Stack(
            fit: StackFit.expand,
            children: [
              child,
              Positioned(
                top: 0,
                left: 0,
                child: ResizeHandleWidget(handle: ResizeHandle.topLeft, color: useHandleColor),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: ResizeHandleWidget(handle: ResizeHandle.topRight, color: useHandleColor),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                child: ResizeHandleWidget(handle: ResizeHandle.bottomLeft, color: useHandleColor),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: ResizeHandleWidget(handle: ResizeHandle.bottomRight, color: useHandleColor),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Align(
                  child: ResizeHandleWidget(handle: ResizeHandle.top, color: useHandleColor),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Align(
                  child: ResizeHandleWidget(handle: ResizeHandle.bottom, color: useHandleColor),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                child: Align(
                  child: ResizeHandleWidget(handle: ResizeHandle.left, color: useHandleColor),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: Align(
                  child: ResizeHandleWidget(handle: ResizeHandle.right, color: useHandleColor),
                ),
              ),
            ],
          )
        : child;

    return controller.guidance != null ? GuidanceInteractor(item: item, child: content) : content;
  }
}
