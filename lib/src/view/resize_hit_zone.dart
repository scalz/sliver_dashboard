import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';

/// The resize-zone width on an axis whose two opposite sides both carry an
/// active handle.
///
/// An axis at least `3 x handleSide` long keeps [handleSide] untouched; below
/// that, a third of the extent guarantees a free centre. The floor is itself
/// capped by [handleSide], so a deliberately thin zone is never widened.
double effectiveResizeHandleSide(
  double handleSide,
  double extent,
  double minHandleSide,
) {
  final third = extent / 3;
  if (third >= handleSide) return handleSide;
  return math.min(handleSide, math.max(third, minHandleSide));
}

/// The width of the resize zone along each edge of an item, `null` for an
/// edge that carries no active handle (no zone at all).
///
/// Single source of truth for the hit test AND the drawn handles: if they
/// disagree, the cursor announces a resize where a press starts a drag.
@immutable
class ResizeZoneGeometry {
  /// Resolves the four edge zones of an item of [size].
  ///
  /// Per axis: both sides active -> [effectiveResizeHandleSide]; one side
  /// active -> at most half the extent, so the other half stays draggable
  /// (no floor: it could swallow that half on a tiny item); none -> no zone.
  /// [handles] `null` means all eight handles.
  factory ResizeZoneGeometry.resolve({
    required Size size,
    required double handleSide,
    required Set<ResizeHandle>? handles,
    double minHandleSide = kMinResizeHandleSide,
  }) {
    bool any(ResizeHandle a, ResizeHandle b, ResizeHandle c) =>
        handles == null || handles.contains(a) || handles.contains(b) || handles.contains(c);

    final left = any(ResizeHandle.topLeft, ResizeHandle.left, ResizeHandle.bottomLeft);
    final right = any(ResizeHandle.topRight, ResizeHandle.right, ResizeHandle.bottomRight);
    final top = any(ResizeHandle.topLeft, ResizeHandle.top, ResizeHandle.topRight);
    final bottom = any(ResizeHandle.bottomLeft, ResizeHandle.bottom, ResizeHandle.bottomRight);

    final zoneX = _axisZone(both: left && right, handleSide, size.width, minHandleSide);
    final zoneY = _axisZone(both: top && bottom, handleSide, size.height, minHandleSide);
    return ResizeZoneGeometry._(
      left: left ? zoneX : null,
      top: top ? zoneY : null,
      right: right ? zoneX : null,
      bottom: bottom ? zoneY : null,
    );
  }

  const ResizeZoneGeometry._({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Zone width along the left edge, `null` when no left handle is active.
  final double? left;

  /// Zone height along the top edge, `null` when no top handle is active.
  final double? top;

  /// Zone width along the right edge, `null` when no right handle is active.
  final double? right;

  /// Zone height along the bottom edge, `null` when no bottom handle is active.
  final double? bottom;

  // With a single active side (or none, where the value is dropped by
  // the null mapping in `resolve`) the zone may take at most half the axis.
  static double _axisZone(
    double handleSide,
    double extent,
    double minHandleSide, {
    required bool both,
  }) =>
      both
          ? effectiveResizeHandleSide(handleSide, extent, minHandleSide)
          : math.min(handleSide, extent / 2);
}
