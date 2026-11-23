import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_provider.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/dashboard_typedefs.dart';
import 'package:sliver_dashboard/src/view/guidance/guidance_interactor.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';
import 'package:sliver_dashboard/src/view/resize_hit_zone.dart';
import 'package:state_beacon/state_beacon.dart';

/// [ResizeHandleWidget]'s default size, the upper bound of a drawn handle.
const double _defaultHandleSize = 20;

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
    final showsHandles = isEditing && (item.isResizable ?? true) && !item.isStatic;
    final handleSide = showsHandles ? controller.resizeHandleSide.watch(context) : 0.0;

    final content = showsHandles
        ? Stack(
            fit: StackFit.expand,
            children: [
              child,
              // The handles are sized from the laid-out tile, with their own layer
              // child stays first and is never re-parented when the tile size changes.
              LayoutBuilder(
                builder: (context, constraints) => _buildHandles(
                  constraints.biggest,
                  handleSide: handleSide,
                  resolver: controller.internal.resizeZoneResolver,
                  color: useHandleColor,
                ),
              ),
            ],
          )
        : child;

    return controller.guidance != null ? GuidanceInteractor(item: item, child: content) : content;
  }

  // Only the active handles are drawn, each at most as large as the
  // zone `calculateResizeHandle` gives it (same `ResizeZoneGeometry`), so the
  // resize cursor never shows where a press would start a drag.
  Widget _buildHandles(
    Size size, {
    required double handleSide,
    required ResizeZoneResolver? resolver,
    required Color? color,
  }) {
    final zones = resolver?.call(item, size);
    final handles = zones?.handles;
    final geometry = ResizeZoneGeometry.resolve(
      size: size,
      handleSide: zones?.side ?? handleSide,
      handles: handles,
    );
    final l = geometry.left ?? 0;
    final t = geometry.top ?? 0;
    final r = geometry.right ?? 0;
    final b = geometry.bottom ?? 0;
    // Edge handles are centred on the part of their edge that is not a corner
    // zone; with all handles active that is the edge's own centre.
    final spanX = size.width - l - r;
    final spanY = size.height - t - b;
    final topSize = _fit(t, spanX);
    final bottomSize = _fit(b, spanX);
    final leftSize = _fit(l, spanY);
    final rightSize = _fit(r, spanY);

    bool shows(ResizeHandle handle) => handles == null || handles.contains(handle);
    Widget at(
      ResizeHandle handle,
      double handleSize, {
      double? top,
      double? left,
      double? right,
      double? bottom,
    }) =>
        Positioned(
          top: top,
          left: left,
          right: right,
          bottom: bottom,
          child: ResizeHandleWidget(handle: handle, size: handleSize, color: color),
        );

    return Stack(
      children: [
        if (shows(ResizeHandle.topLeft)) at(ResizeHandle.topLeft, _fit(l, t), top: 0, left: 0),
        if (shows(ResizeHandle.topRight)) at(ResizeHandle.topRight, _fit(r, t), top: 0, right: 0),
        if (shows(ResizeHandle.bottomLeft))
          at(ResizeHandle.bottomLeft, _fit(l, b), bottom: 0, left: 0),
        if (shows(ResizeHandle.bottomRight))
          at(ResizeHandle.bottomRight, _fit(r, b), bottom: 0, right: 0),
        if (shows(ResizeHandle.top) && topSize > 0)
          at(ResizeHandle.top, topSize, top: 0, left: l + (spanX - topSize) / 2),
        if (shows(ResizeHandle.bottom) && bottomSize > 0)
          at(ResizeHandle.bottom, bottomSize, bottom: 0, left: l + (spanX - bottomSize) / 2),
        if (shows(ResizeHandle.left) && leftSize > 0)
          at(ResizeHandle.left, leftSize, left: 0, top: t + (spanY - leftSize) / 2),
        if (shows(ResizeHandle.right) && rightSize > 0)
          at(ResizeHandle.right, rightSize, right: 0, top: t + (spanY - rightSize) / 2),
      ],
    );
  }

  static double _fit(double a, double b) => math.min(_defaultHandleSize, math.min(a, b));
}
