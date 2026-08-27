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
    this.delete = const {
      SingleActivator(LogicalKeyboardKey.delete),
      SingleActivator(LogicalKeyboardKey.backspace),
    },
    this.selectAll = const {
      SingleActivator(LogicalKeyboardKey.keyA, control: true),
      SingleActivator(LogicalKeyboardKey.keyA, meta: true),
    },
    this.duplicate = const {
      SingleActivator(LogicalKeyboardKey.keyD, control: true),
      SingleActivator(LogicalKeyboardKey.keyD, meta: true),
    },
    this.undo = const {
      SingleActivator(LogicalKeyboardKey.keyZ, control: true),
      SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
    },
    this.redo = const {
      SingleActivator(LogicalKeyboardKey.keyY, control: true),
      SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true),
      SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true),
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
    this.lassoModifier = const [
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
    ],
    this.swapModeModifier = const [
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
    ],
  });

  /// Default shortcuts configuration.
  static const DashboardShortcuts defaultShortcuts = DashboardShortcuts();

  /// Keys to grab (start dragging) an item.
  final Set<ShortcutActivator> grab;

  /// Keys to drop (stop dragging) an item.
  final Set<ShortcutActivator> drop;

  /// Keys to cancel the interaction or clear selection.
  final Set<ShortcutActivator> cancel;

  /// Keys to move the item up.
  final Set<ShortcutActivator> moveUp;

  /// Keys to move the item down.
  final Set<ShortcutActivator> moveDown;

  /// Keys to move the item left.
  final Set<ShortcutActivator> moveLeft;

  /// Keys to move the item right.
  final Set<ShortcutActivator> moveRight;

  /// Keys to delete the selected / focused items.
  final Set<ShortcutActivator> delete;

  /// Keys to select all editable items in the grid.
  final Set<ShortcutActivator> selectAll;

  /// Keys to duplicate the selected / focused items.
  final Set<ShortcutActivator> duplicate;

  /// Keys to undo the last layout change.
  final Set<ShortcutActivator> undo;

  /// Keys to redo the last undone layout change.
  final Set<ShortcutActivator> redo;

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

  /// Keys that must be held on pointer-down over empty grid space for a
  /// rubberband ("lasso") selection to be armed. Defaults to the `Shift`
  /// keys.
  ///
  /// **Overlapping [multiSelectKeys] is legal and is the default.** The two
  /// are read from the same pointer-down but answer different questions —
  /// [multiSelectKeys] decides whether the lasso *adds to* the current
  /// selection, this list decides whether it starts at all. To keep both
  /// gestures reachable, a key that appears in both is treated as the
  /// trigger only (the lasso replaces the selection) under
  /// `modifierRequired`; hold a second, non-overlapping [multiSelectKeys]
  /// key to get an additive lasso in that mode.
  final List<LogicalKeyboardKey> lassoModifier;

  /// Keys that temporarily flip the drag mode to the OPPOSITE of
  /// `DashboardController.dragMode` while held. Defaults to the `Shift` keys.
  ///
  /// With the default `DragMode.cascade`, holding this turns the drag into a
  /// direct position swap; with `DragMode.swap` set as the controller
  /// default, holding it restores the cascade. Pass an **empty list** to
  /// remove the toggle entirely, leaving `dragMode` in sole control.
  ///
  /// Only consulted for **single-item** drags: a cluster drag has no
  /// meaningful swap partner, and this restriction is also what keeps the
  /// `Shift` default safe next to [multiSelectKeys] — a Shift-built
  /// multi-selection can never be silently turned into a swap.
  final List<LogicalKeyboardKey> swapModeModifier;
}
