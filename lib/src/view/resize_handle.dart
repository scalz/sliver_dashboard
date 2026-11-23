import 'package:flutter/widgets.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_provider.dart';
import 'package:sliver_dashboard/src/view/default_colors.dart';
import 'package:sliver_dashboard/src/view/guidance/dashboard_guidance.dart';
import 'package:sliver_dashboard/src/view/resize_hit_zone.dart';

/// An enum representing the different types of resize handles.
///
/// Each handle corresponds to a specific position on a widget's boundary,
/// enabling resizing interactions in different directions. The available
/// handles are:
///
/// - [topLeft]: Resizes from the top-left corner.
/// - [top]: Resizes from the top edge.
/// - [topRight]: Resizes from the top-right corner.
/// - [left]: Resizes from the left edge.
/// - [right]: Resizes from the right edge.
/// - [bottomLeft]: Resizes from the bottom-left corner.
/// - [bottom]: Resizes from the bottom edge.
/// - [bottomRight]: Resizes from the bottom-right corner.
enum ResizeHandle {
  /// Resizes from the top-left corner.
  topLeft,

  /// Resizes from the top edge.
  top,

  /// Resizes from the top-right corner.
  topRight,

  /// Resizes from the left edge.
  left,

  /// Resizes from the right edge.
  right,

  /// Resizes from the bottom-left corner.
  bottomLeft,

  /// Resizes from the bottom edge.
  bottom,

  /// Resizes from the bottom-right corner.
  bottomRight,
}

/// A widget that displays an "L" shaped, interactive visual indicator for a resize handle.
/// This widget is designed to be placed in the corner of a Stack.
class ResizeHandleWidget extends StatefulWidget {
  /// Creates a resize handle widget.
  const ResizeHandleWidget({
    required this.handle,
    this.size = 20.0,
    this.color,
    this.strokeWidth = 2.5,
    super.key,
  });

  /// The type of handle this widget represents, which determines its shape and cursor.
  final ResizeHandle handle;

  /// The size of the handle's touch target and visual indicator.
  final double size;

  /// The color of the handle. Defaults to the package's focus color (blue accent).
  final Color? color;

  /// The thickness of the "L" shape lines.
  final double strokeWidth;

  @override
  State<ResizeHandleWidget> createState() => _ResizeHandleWidgetState();
}

class _ResizeHandleWidgetState extends State<ResizeHandleWidget> {
  MouseCursor _getCursorForHandle(ResizeHandle handle, DashboardGuidance? guidance) {
    if (guidance != null) {
      switch (handle) {
        case ResizeHandle.topLeft:
        case ResizeHandle.bottomRight:
          return guidance.resizeTopLeft.cursor;
        case ResizeHandle.topRight:
        case ResizeHandle.bottomLeft:
          return guidance.resizeTopRight.cursor;
        case ResizeHandle.top:
        case ResizeHandle.bottom:
          return guidance.resizeY.cursor;
        case ResizeHandle.left:
        case ResizeHandle.right:
          return guidance.resizeX.cursor;
      }
    }

    // Fallback to default cursors
    switch (handle) {
      case ResizeHandle.topLeft:
      case ResizeHandle.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case ResizeHandle.topRight:
      case ResizeHandle.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
      case ResizeHandle.top:
      case ResizeHandle.bottom:
        return SystemMouseCursors.resizeUpDown;
      case ResizeHandle.left:
      case ResizeHandle.right:
        return SystemMouseCursors.resizeLeftRight;
    }
  }

  @override
  Widget build(BuildContext context) {
    DashboardGuidance? guidance;
    try {
      final controller = DashboardControllerProvider.of(context);
      guidance = controller.guidance;
      // This will use defaults
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      // Not in a dashboard context, use defaults
      guidance = null;
    }

    final cursor = _getCursorForHandle(widget.handle, guidance);
    return MouseRegion(
      cursor: cursor,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _HandlePainter(
            handle: widget.handle,
            color: widget.color ?? DefaultColors.focus,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}

/// A custom painter that draws a shape for a specific handle.
class _HandlePainter extends CustomPainter {
  _HandlePainter({
    required this.handle,
    required this.color,
    required this.strokeWidth,
  });

  final ResizeHandle handle;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    switch (handle) {
      case ResizeHandle.topLeft:
        path
          ..moveTo(size.width, 0)
          ..lineTo(0, 0)
          ..lineTo(0, size.height);
      case ResizeHandle.topRight:
        path
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width, size.height);
      case ResizeHandle.bottomLeft:
        path
          ..moveTo(0, 0)
          ..lineTo(0, size.height)
          ..lineTo(size.width, size.height);
      case ResizeHandle.bottomRight:
        path
          ..moveTo(size.width, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height);
      case ResizeHandle.top:
        path
          ..moveTo(0, 0)
          ..lineTo(size.width, 0);
      case ResizeHandle.bottom:
        path
          ..moveTo(0, size.height)
          ..lineTo(size.width, size.height);
      case ResizeHandle.left:
        path
          ..moveTo(0, 0)
          ..lineTo(0, size.height);
      case ResizeHandle.right:
        path
          ..moveTo(size.width, 0)
          ..lineTo(size.width, size.height);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HandlePainter oldDelegate) {
    return oldDelegate.handle != handle ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Floor of the clamped resize zone, in logical pixels, used by
/// [calculateResizeHandle] so that very small items stay resizable.
const double kMinResizeHandleSide = 8;

/// Which resize handles an item exposes, and how wide their press zone is.
///
/// Returned per item by a `ResizeZoneResolver`.
@immutable
class ResizeZones {
  /// Creates a resize-zone configuration. The defaults are the grid's own
  /// behaviour: all eight handles, `resizeHandleSide` wide.
  const ResizeZones({this.handles = allHandles, this.side});

  /// All eight handles, the default of [handles].
  static const Set<ResizeHandle> allHandles = {
    ResizeHandle.topLeft,
    ResizeHandle.top,
    ResizeHandle.topRight,
    ResizeHandle.left,
    ResizeHandle.right,
    ResizeHandle.bottomLeft,
    ResizeHandle.bottom,
    ResizeHandle.bottomRight,
  };

  /// The active handles: only these react to a press and are drawn. An empty
  /// set disables resizing. Compared by content; do not mutate it in place.
  final Set<ResizeHandle> handles;

  /// The zone width before the per-axis reduction; `null` uses the grid's
  /// `resizeHandleSide`.
  final double? side;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResizeZones &&
          side == other.side &&
          handles.length == other.handles.length &&
          handles.containsAll(other.handles);

  @override
  int get hashCode {
    var mask = 0;
    for (final handle in handles) {
      mask |= 1 << handle.index;
    }
    return Object.hash(side, mask);
  }
}

/// Returns the resize handle under [localPosition] (in the item's local
/// coordinates), or `null` when a press there should start a drag.
///
/// Each edge reserves [handleSide] pixels, reduced **per axis** to fit the
/// item:
/// - both opposite sides carry an active handle: at most a third of the
///   extent, never below [minHandleSide] nor above [handleSide]. An axis at
///   least `3 × handleSide` long keeps the full zone; below
///   `2 × minHandleSide` the whole axis is a resize zone;
/// - one side only: at most half the extent, so the other half drags;
/// - no side: no zone on that axis.
///
/// [enabledHandles] limits the active handles (`null` = all of them, see
/// [ResizeZones]). A press in the zone of a disabled handle starts a drag; it
/// never falls back to a neighbouring handle.
ResizeHandle? calculateResizeHandle({
  required Offset localPosition,
  required Size size,
  required double handleSide,
  required bool isResizable,
  Set<ResizeHandle>? enabledHandles,
  double minHandleSide = kMinResizeHandleSide,
}) {
  if (!isResizable) return null;
  if (enabledHandles != null && enabledHandles.isEmpty) return null;

  final zones = ResizeZoneGeometry.resolve(
    size: size,
    handleSide: handleSide,
    handles: enabledHandles,
    minHandleSide: minHandleSide,
  );
  final top = zones.top;
  final bottom = zones.bottom;
  final left = zones.left;
  final right = zones.right;

  final handle = _classify(
    isTop: top != null && localPosition.dy <= top,
    isBottom: bottom != null && localPosition.dy >= size.height - bottom,
    isLeft: left != null && localPosition.dx <= left,
    isRight: right != null && localPosition.dx >= size.width - right,
  );
  if (handle == null || enabledHandles == null || enabledHandles.contains(handle)) {
    return handle;
  }
  return null;
}

ResizeHandle? _classify({
  required bool isTop,
  required bool isBottom,
  required bool isLeft,
  required bool isRight,
}) {
  // Corners
  if (isTop && isLeft) return ResizeHandle.topLeft;
  if (isTop && isRight) return ResizeHandle.topRight;
  if (isBottom && isLeft) return ResizeHandle.bottomLeft;
  if (isBottom && isRight) return ResizeHandle.bottomRight;

  // Sides
  if (isTop && !isLeft && !isRight) return ResizeHandle.top;
  if (isBottom && !isLeft && !isRight) return ResizeHandle.bottom;
  if (isLeft && !isBottom && !isTop) return ResizeHandle.left;
  if (isRight && !isBottom && !isTop) return ResizeHandle.right;

  return null;
}
