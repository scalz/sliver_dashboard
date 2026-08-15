import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Safely executes [body] on a simulated macOS desktop environment,
/// ensuring that the global foundation platform override is unconditionally
/// restored to its original state on completion (even on test failures).
Future<void> runOnDesktop(Future<void> Function() body) async {
  final original = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    // Ensures restoration is executed synchronously inside the testWidgets execution body
    // BEFORE Flutter binding's _verifyInvariants runs, avoiding foundation variable leaks.
    debugDefaultTargetPlatformOverride = original;
  }
}

/// Runs [body] with the foundation platform override forced to [platform],
/// restoring the previous value **inside** the test body.
Future<void> runOnPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  final original = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = original;
  }
}

/// Recording canvas.
class RecordingCanvas implements Canvas {
  final List<Offset> translations = <Offset>[];
  final List<Rect> clipRects = <Rect>[];
  final List<Rect> rects = <Rect>[];
  final List<(Offset, Offset)> lines = <(Offset, Offset)>[];
  int saveCalls = 0;
  int restoreCalls = 0;

  /// Lines whose endpoints share a `dy`: the row separators of a vertical grid.
  Iterable<(Offset, Offset)> get horizontalLines => lines.where((l) => l.$1.dy == l.$2.dy);

  /// Lines whose endpoints share a `dx`: the column separators.
  Iterable<(Offset, Offset)> get verticalLines => lines.where((l) => l.$1.dx == l.$2.dx);

  @override
  void translate(double dx, double dy) => translations.add(Offset(dx, dy));

  @override
  void clipRect(Rect rect, {ClipOp clipOp = ClipOp.intersect, bool doAntiAlias = true}) =>
      clipRects.add(rect);

  @override
  void drawRect(Rect rect, Paint paint) => rects.add(rect);

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines.add((p1, p2));

  @override
  void save() => saveCalls++;

  @override
  void restore() => restoreCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
