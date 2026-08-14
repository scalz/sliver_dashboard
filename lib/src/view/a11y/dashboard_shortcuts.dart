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
    this.cloneKeys = const [
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
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

  /// Keys held down when a drag starts to CLONE the tile instead of moving
  /// it. Defaults to the `Alt` / `Option` keys.
  ///
  /// Only consulted when a clone callback is registered (`onCloneRequested`
  /// on the dashboard or on the enclosing `DashboardNestedScope`); with no
  /// callback the modifier is ignored and the drag is a plain move.
  ///
  /// **Must not overlap [multiSelectKeys].** They are read from the same
  /// pointer-down event, so a key listed in both would toggle the selection
  /// AND request a clone. [multiSelectKeys] wins at runtime (a selection
  /// gesture is never turned into a duplication), and an overlapping
  /// configuration trips an assertion in debug builds.
  final List<LogicalKeyboardKey> cloneKeys;
}
