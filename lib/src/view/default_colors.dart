import 'package:flutter/widgets.dart';

/// Built-in color defaults, independent of any design library.
///
/// Reason: `lib/` imports `package:flutter/widgets.dart` only (see
/// `test/meta/no_design_library_test.dart`), so the package compiles against
/// both the in-SDK `material.dart` and the standalone `material_ui` package.
/// The values are the Material swatches the package used before, so the
/// defaults look identical. Not exported: applications override them through
/// the style classes, never by reading these.
abstract final class DefaultColors {
  /// Focus / selection ring and resize handles (Material `blueAccent`).
  static const Color focus = Color(0xFF448AFF);

  /// Ring of the actively dragged item and of a nest target (`deepOrange`).
  static const Color active = Color(0xFFFF5722);

  /// Lasso border (`blue`).
  static const Color lassoBorder = Color(0xFF2196F3);

  /// Grid lines and placeholder fill (`black12`).
  static const Color gridLine = Color(0x1F000000);

  /// Guidance bubble background on a light / dark platform (`grey[800]` / `grey[300]`).
  static const Color bubbleLight = Color(0xFF424242);

  /// See [bubbleLight].
  static const Color bubbleDark = Color(0xFFE0E0E0);

  /// Guidance bubble shadow (`black26`).
  static const Color bubbleShadow = Color(0x42000000);
}
