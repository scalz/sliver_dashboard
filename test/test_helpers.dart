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
