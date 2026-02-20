import 'package:flutter/material.dart';

/// A widget that paints a dot at the location of the pointer when the user
/// presses down on it.
class PointerDotWidget extends StatefulWidget {
  /// The child widget.
  final Widget child;

  const PointerDotWidget({super.key, required this.child});

  @override
  State<PointerDotWidget> createState() => _PointerDotWidgetState();
}

class _PointerDotWidgetState extends State<PointerDotWidget> {
  Offset? _position;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        setState(() {
          _position = event.localPosition;
        });
      },
      onPointerMove: (event) {
        // Only update if the pointer is down, which we infer by _position != null
        if (_position != null) {
          setState(() {
            _position = event.localPosition;
          });
        }
      },
      onPointerUp: (event) {
        setState(() {
          _position = null;
        });
      },
      onPointerCancel: (event) {
        setState(() {
          _position = null;
        });
      },
      child: CustomPaint(painter: _DotPainter(_position), child: widget.child),
    );
  }
}

class _DotPainter extends CustomPainter {
  final Offset? position;
  final Paint _paint;

  _DotPainter(this.position)
    : _paint = Paint()
        ..color = Colors.blue.withOpacity(0.5)
        ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (position != null) {
      canvas.drawCircle(position!, 20.0, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotPainter oldDelegate) {
    return oldDelegate.position != position;
  }
}
