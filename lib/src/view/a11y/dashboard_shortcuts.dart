import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Configuration for keyboard shortcuts used in the dashboard.
@immutable
class DashboardShortcuts {
  /// Creates a configuration for dashboard shortcuts.
  const DashboardShortcuts({
    this.grab = const {
      SingleActivator(LogicalKeyboardKey.space),
      SingleActivator(LogicalKeyboardKey.enter),
    },
    this.drop = const {
      SingleActivator(LogicalKeyboardKey.space),
      SingleActivator(LogicalKeyboardKey.enter),
    },
    this.cancel = const {
      SingleActivator(LogicalKeyboardKey.escape),
    },
    this.moveUp = const {
      SingleActivator(LogicalKeyboardKey.arrowUp),
    },
    this.moveDown = const {
      SingleActivator(LogicalKeyboardKey.arrowDown),
    },
    this.moveLeft = const {
      SingleActivator(LogicalKeyboardKey.arrowLeft),
    },
    this.moveRight = const {
      SingleActivator(LogicalKeyboardKey.arrowRight),
    },
    this.multiSelectKeys = const [
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
    ],
  });

  /// Default shortcuts configuration.
  static const DashboardShortcuts defaultShortcuts = DashboardShortcuts();

  /// Keys to grab (start dragging) an item.
  final Set<ShortcutActivator> grab;

  /// Keys to drop (stop dragging) an item.
  final Set<ShortcutActivator> drop;

  /// Keys to cancel the interaction.
  final Set<ShortcutActivator> cancel;

  /// Keys to move the item up.
  final Set<ShortcutActivator> moveUp;

  /// Keys to move the item down.
  final Set<ShortcutActivator> moveDown;

  /// Keys to move the item left.
  final Set<ShortcutActivator> moveLeft;

  /// Keys to move the item right.
  final Set<ShortcutActivator> moveRight;

  /// Keys held down during a click to trigger multi-selection.
  /// Defaults to Shift, Control, and Meta (Command) keys.
  final List<LogicalKeyboardKey> multiSelectKeys;
}
