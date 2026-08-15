import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The visual shell of every guidance message in the package.
///
/// Extracted from `GuidanceInteractor` so the rubberband ("lasso") label
/// looks exactly like the hover / long-press bubbles instead of being a
/// second, subtly different tooltip style. The interactor still owns *when*
/// and *where* an item bubble is shown (it is anchored to a `LayoutItem` via
/// a `LayerLink` inside an `OverlayEntry`); the lasso label has no item to
/// anchor to and is painted in-tree, so only the appearance is shared.
class GuidanceBubble extends StatelessWidget {
  /// Creates a [GuidanceBubble].
  const GuidanceBubble({required this.message, super.key});

  /// The text to display.
  final String message;

  static bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fontSize = _isMobile ? 16.0 : 14.0;
    final padding = _isMobile
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 8);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[300] : Colors.grey[800],
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            message,
            style: TextStyle(
              color: isDark ? Colors.black : Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
