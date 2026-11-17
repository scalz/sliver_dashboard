import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sliver_dashboard/src/view/default_colors.dart';

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
  const GuidanceBubble({
    required this.message,
    this.color,
    this.textColor,
    super.key,
  });

  /// The text to display.
  final String message;

  /// Background override; see `DashboardGuidance.bubbleColor`.
  final Color? color;

  /// Text color override; see `DashboardGuidance.bubbleTextColor`.
  final Color? textColor;

  static bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    // Reason: no design-library Theme is readable from `widgets.dart`; the
    // platform brightness is the design-agnostic signal that remains.
    final isDark = MediaQuery.maybeOf(context)?.platformBrightness == Brightness.dark;
    final fontSize = _isMobile ? 16.0 : 14.0;
    final padding = _isMobile
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 8);

    return Directionality(
      textDirection: TextDirection.ltr,
      // Reason: the bubble lives in an OverlayEntry, whose ambient text style
      // is WidgetsApp's debug error style (red, underlined). A fresh
      // DefaultTextStyle replaces it instead of merging into it.
      child: DefaultTextStyle(
        style: const TextStyle(decoration: TextDecoration.none),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? (isDark ? DefaultColors.bubbleDark : DefaultColors.bubbleLight),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: DefaultColors.bubbleShadow,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            message,
            style: TextStyle(
              color: textColor ?? (isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF)),
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
