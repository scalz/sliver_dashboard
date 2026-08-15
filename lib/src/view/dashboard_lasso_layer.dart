import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/view/guidance/guidance_bubble.dart';

/// Everything needed to paint one frame of the rubberband ("lasso")
/// selection rectangle.
///
/// The rectangle is expressed in **overlay-local pixels**: `DashboardOverlay`
/// owns the content-origin arithmetic and publishes the already-resolved rectangle here,
/// so this layer performs no coordinate math of its own.
@immutable
class LassoOverlayState {
  /// Creates a [LassoOverlayState].
  const LassoOverlayState({
    required this.rect,
    required this.fillColor,
    required this.borderColor,
    required this.borderWidth,
    this.clipRect,
    this.message,
  });

  /// The rubberband rectangle, in overlay-local pixels.
  final Rect rect;

  /// Visible area of the grid's sliver, in overlay-local pixels. The
  /// rectangle is clipped to it so it never paints over a pinned app bar or
  /// a neighbouring sliver. Null when the overlay bounds are unavailable
  /// (one frame at mount), in which case nothing is clipped.
  final Rect? clipRect;

  /// Fill of the rectangle.
  final Color fillColor;

  /// Border color of the rectangle.
  final Color borderColor;

  /// Border stroke width of the rectangle.
  final double borderWidth;

  /// Guidance message drawn beside the rectangle, or null when guidance is
  /// disabled (`DashboardController.guidance == null`).
  final String? message;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LassoOverlayState &&
        other.rect == rect &&
        other.clipRect == clipRect &&
        other.fillColor == fillColor &&
        other.borderColor == borderColor &&
        other.borderWidth == borderWidth &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(rect, clipRect, fillColor, borderColor, borderWidth, message);
}

/// Paints the rubberband rectangle.
class LassoPainter extends CustomPainter {
  /// Creates a [LassoPainter].
  const LassoPainter(this.state);

  /// The rectangle and colors to paint.
  final LassoOverlayState state;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = state.rect;
    // A press that has not travelled yet produces a degenerate rectangle;
    // drawing it would paint a stray 1px line under the cursor.
    if (rect.width <= 0 && rect.height <= 0) return;

    final clip = state.clipRect;
    if (clip != null) {
      canvas
        ..save()
        ..clipRect(clip);
    }

    canvas
      ..drawRect(rect, Paint()..color = state.fillColor)
      ..drawRect(
        rect,
        Paint()
          ..color = state.borderColor
          ..strokeWidth = state.borderWidth
          ..style = PaintingStyle.stroke,
      );

    if (clip != null) canvas.restore();
  }

  @override
  bool shouldRepaint(LassoPainter oldDelegate) => oldDelegate.state != state;
}

/// The rubberband selection layer of `DashboardOverlay`.
///
/// Driven by a [ValueListenable] rather than by controller state so that a
/// lasso drag rebuilds this subtree only — never the scroll view, never the
/// item shells. When [state] holds null the layer collapses to an empty box
/// and costs nothing.
class DashboardLassoLayer extends StatelessWidget {
  /// Creates a [DashboardLassoLayer].
  const DashboardLassoLayer({required this.state, super.key});

  /// The current rectangle to paint, or null when no lasso is in flight.
  final ValueListenable<LassoOverlayState?> state;

  /// Horizontal room reserved for the guidance label.
  static const double _labelMaxWidth = 260;

  /// Vertical room reserved for the guidance label.
  static const double _labelHeight = 28;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LassoOverlayState?>(
      valueListenable: state,
      builder: (context, value, _) {
        if (value == null) return const SizedBox.shrink();
        return IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: LassoPainter(value)),
                ),
              ),
              ..._buildLabel(context, value),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildLabel(BuildContext context, LassoOverlayState value) {
    final message = value.message;
    if (message == null) return const [];

    // Anchor below the rectangle, clamped inside the visible sliver area so
    // a lasso drawn against the bottom or right edge keeps its label on
    // screen. Without a clip rect (one frame at mount) the label is simply
    // placed at the anchor.
    final clip = value.clipRect;
    var left = value.rect.left;
    var top = value.rect.bottom + 8;
    if (clip != null) {
      left = left.clamp(clip.left, max(clip.left, clip.right - _labelMaxWidth));
      top = top.clamp(clip.top, max(clip.top, clip.bottom - _labelHeight));
    }

    return [
      Positioned(
        left: left,
        top: top,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _labelMaxWidth),
          // Same bubble the hover / long-press guidance uses, so the lasso
          // label is not a second tooltip style.
          child: GuidanceBubble(message: message),
        ),
      ),
    ];
  }
}
