import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_provider.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/a11y/dashboard_intents.dart';
import 'package:sliver_dashboard/src/view/a11y/dashboard_shortcuts.dart';
import 'package:sliver_dashboard/src/view/dashboard_configuration.dart';
import 'package:sliver_dashboard/src/view/dashboard_item_wrapper.dart';
import 'package:sliver_dashboard/src/view/dashboard_typedefs.dart';
import 'package:sliver_dashboard/src/view/guidance/dashboard_guidance.dart';
import 'package:state_beacon/state_beacon.dart';

/// A widget that wraps a single dashboard item, handling caching, focus,
/// edit mode interactions, and accessibility.
///
/// This widget is the "smart wrapper" for the user's content. Its primary responsibilities are:
/// 1. **Performance:** It caches the user's content widget (built via [builder])
///    and wraps it in a [RepaintBoundary].
/// 2. **Interaction:** It handles focus traversal and visual highlighting via [itemStyle].
/// 3. **Accessibility:** It maps keyboard shortcuts (Arrows, Space, Enter) to
///    controller actions (Move, Grab, Drop).
/// 4. **Edit Mode:** It displays resize handles when [isEditing] is true.
class DashboardItem extends StatefulWidget {
  /// Creates a [DashboardItem].
  const DashboardItem({
    required this.item,
    required this.isEditing,
    required this.builder,
    this.itemStyle = DashboardItemStyle.defaultStyle,
    this.isFeedback = false,
    super.key,
  });

  /// The data model representing this item's position and dimensions.
  final LayoutItem item;

  /// Whether the dashboard is in edit mode (showing resize handles).
  final bool isEditing;

  /// The builder that creates the actual content widget for this item.
  final DashboardItemBuilder builder;

  /// Configuration for the visual style (focus border, radius, etc.).
  final DashboardItemStyle itemStyle;

  /// Whether this widget is being rendered as the drag feedback overlay.
  ///
  /// If true, the widget remains visible even if it is the active item,
  /// and keyboard interactions are disabled to prevent conflicts.
  final bool isFeedback;

  @override
  State<DashboardItem> createState() => _DashboardItemState();
}

class _DashboardItemState extends State<DashboardItem> {
  // Cache lazy initialization
  Widget? _cachedWidget;
  late int _lastSignature;
  late bool _lastIsEditing;

  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    // We initialize the tracking variables, but NOT the widget itself.
    // The widget will be built in the build() method where context is valid.
    _lastSignature = widget.item.contentSignature;
    _lastIsEditing = widget.isEditing;
  }

  @override
  void didUpdateWidget(DashboardItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    // PERFORMANCE CRITICAL:
    // We intentionally ignore `widget.builder` changes here.
    // We only invalidate the cache if:
    // 1. The item content (w, h, id, static) changes (checked via signature).
    // 2. The global edit mode changes.

    final newSignature = widget.item.contentSignature;
    if (newSignature != _lastSignature || widget.isEditing != _lastIsEditing) {
      _cachedWidget = null; // Invalidate cache
      _lastSignature = newSignature;
      _lastIsEditing = widget.isEditing;
    }
  }

  /// Helper to announce messages to Screen Readers (TalkBack/VoiceOver).
  void _announce(String message) {
    // Use the old API for older Flutter versions, and ignore the deprecation warning
    // Until we have no other choice to use sendAnnouncement
    // ignore: deprecated_member_use
    SemanticsService.announce(message, Directionality.of(context)).ignore();
  }

  @override
  Widget build(BuildContext context) {
    // Lazy initialization: build the cache only when needed.
    // This solves the "dependOnInheritedWidget" error because 'context'
    // is fully initialized at this point.

    final controller = DashboardControllerProvider.of(context);

    final guidance = controller.guidance ?? DashboardGuidance.byDefault;
    final shortcutsConfig = controller.shortcuts ?? DashboardShortcuts.defaultShortcuts;

    // 1. Build or retrieve cached user content
    // We wrap it in RepaintBoundary here to ensure the heavy subtree isn't repainted
    // when we just change the border color or focus state.
    _cachedWidget ??= RepaintBoundary(
      child: widget.builder(context, widget.item),
    );

    // 2. Determine Active State (Grabbed)
    // We watch the beacon so this widget rebuilds when Grab/Drop happens.
    final activeId = controller.activeItemId.watch(context);
    final isActive = activeId == widget.item.id;

    final semanticLabel = 'Item ${widget.item.id}, Row ${widget.item.y}, Column ${widget.item.x}';

    // Focus order ensures Tab navigation follows the grid (Row-major)
    final focusOrder = (widget.item.y * 10000 + widget.item.x).toDouble();
    final style = widget.itemStyle;

    // 3. Define Actions
    final actions = <Type, Action<Intent>>{
      DashboardGrabItemIntent: CallbackAction<DashboardGrabItemIntent>(
        onInvoke: (_) {
          if (!widget.isEditing || widget.item.isStatic) return null;
          controller.internal.onDragStart(widget.item.id);
          _announce(guidance.a11yGrab(widget.item.id));
          return null;
        },
      ),
      DashboardDropItemIntent: CallbackAction<DashboardDropItemIntent>(
        onInvoke: (_) {
          if (isActive) {
            controller.internal.onDragEnd(widget.item.id);
            _announce(guidance.a11yDrop(widget.item.x, widget.item.y));
          }
          return null;
        },
      ),
      DashboardMoveItemIntent: CallbackAction<DashboardMoveItemIntent>(
        onInvoke: (intent) {
          if (isActive) {
            controller.moveActiveItemBy(intent.dx, intent.dy);
            final newX = widget.item.x + intent.dx;
            final newY = widget.item.y + intent.dy;
            _announce(guidance.a11yMove(newX, newY));
          }
          return null;
        },
      ),
      DashboardCancelInteractionIntent: CallbackAction<DashboardCancelInteractionIntent>(
        onInvoke: (_) {
          if (isActive) {
            controller.cancelInteraction();
            _announce(guidance.a11yCancel);
          }
          return null;
        },
      ),
    };

    // 4. Define Shortcuts (Dynamic based on state)
    final shortcuts = <ShortcutActivator, Intent>{};
    if (isActive) {
      // Mode "Grabbed" -> Listen for Drop, Cancel, Move
      for (final key in shortcutsConfig.drop) {
        shortcuts[key] = const DashboardDropItemIntent();
      }
      for (final key in shortcutsConfig.cancel) {
        shortcuts[key] = const DashboardCancelInteractionIntent();
      }
      for (final key in shortcutsConfig.moveUp) {
        shortcuts[key] = const DashboardMoveItemIntent(0, -1);
      }
      for (final key in shortcutsConfig.moveDown) {
        shortcuts[key] = const DashboardMoveItemIntent(0, 1);
      }
      for (final key in shortcutsConfig.moveLeft) {
        shortcuts[key] = const DashboardMoveItemIntent(-1, 0);
      }
      for (final key in shortcutsConfig.moveRight) {
        shortcuts[key] = const DashboardMoveItemIntent(1, 0);
      }
    } else {
      // Mode "Idle" -> Listen for Grab
      for (final key in shortcutsConfig.grab) {
        shortcuts[key] = const DashboardGrabItemIntent();
      }
    }

    // 5. Build the Interaction Shell
    // This part is rebuilt every time focus changes or active state changes.
    // Since FocusableActionDetector is a StatefulWidget internally, it preserves
    // the FocusNode as long as it stays in the tree, solving the focus loss issue.
    return FocusTraversalOrder(
      order: NumericFocusOrder(focusOrder),
      child: FocusableActionDetector(
        actions: actions,
        shortcuts: widget.isEditing ? shortcuts : {},
        enabled: widget.isEditing && !widget.item.isStatic,
        onFocusChange: (hasFocus) {
          // If we lose focus while item was active (eg. moving),
          // cancel interaction to clean state (close Trash, put back item).
          if (!hasFocus && isActive) {
            controller.cancelInteraction();
            _announce(guidance.a11yCancel);
          }
        },
        onShowFocusHighlight: (focused) {
          if (_isFocused != focused) {
            setState(() => _isFocused = focused);
          }
        },
        child: Semantics(
          container: true,
          label: semanticLabel,
          hint: widget.isEditing
              ? (isActive ? guidance.semanticsHintDrop : guidance.semanticsHintGrab)
              : null,
          selected: isActive,
          child: Opacity(
            opacity: (isActive && !widget.isFeedback) ? 0.0 : 1.0,
            child: Container(
              decoration: _isFocused
                  ? (style.focusDecoration ??
                      BoxDecoration(
                        border: Border.all(
                          color: isActive
                              ? Colors.deepOrange
                              : (style.focusColor ?? Theme.of(context).primaryColor),
                          width: isActive ? 4 : 3,
                        ),
                        borderRadius: style.borderRadius,
                      ))
                  : null,
              child: DashboardItemWrapper(
                item: widget.item,
                child: _cachedWidget!, // Use the cached heavy content
              ),
            ),
          ),
        ),
      ),
    );
  }
}
