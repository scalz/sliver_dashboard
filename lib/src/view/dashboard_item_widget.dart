import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart'
    show DashboardController;
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
/// 1. **Performance:** It caches the user's content widget (built via [itemBuilder])
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
    this.itemBuilder,
    this.itemLayoutBuilder,
    this.itemBreakpointBuilder,
    this.breakpointResolver,
    this.itemWidth,
    this.itemHeight,
    this.slotCount,
    this.itemStyle = DashboardItemStyle.defaultStyle,
    this.isFeedback = false,
    super.key,
  }) : assert(
          (itemBuilder != null ? 1 : 0) +
                  (itemLayoutBuilder != null ? 1 : 0) +
                  (itemBreakpointBuilder != null && breakpointResolver != null ? 1 : 0) ==
              1,
          'Provide exactly one builder configuration: itemBuilder, itemLayoutBuilder, or both itemBreakpointBuilder and breakpointResolver.',
        );

  /// The data model representing this item's position and dimensions.
  final LayoutItem item;

  /// Whether the dashboard is in edit mode (showing resize handles).
  final bool isEditing;

  /// A static builder that creates the widget for a dashboard item.
  ///
  /// Highly optimized; completely prevents widget subtree rebuilds during window resizing
  /// or visual dragging when grid coordinates remain unchanged.
  final DashboardItemBuilder? itemBuilder;

  /// A layout-aware builder that provides live physical pixel dimensions.
  ///
  /// Rebuilds continuously as the physical bounds are adjusted, enabling sub-pixel responsiveness
  /// and continuous visual updates during resizing.
  final DashboardItemLayoutBuilder? itemLayoutBuilder;

  /// A breakpoint-aware builder that reconstructs its subtree selectively based on a resolved state.
  ///
  /// Rebuilds only when the layout state returned by [breakpointResolver] transitions,
  /// shielding complex downstream subtrees from redundant build passes during resizing.
  final DashboardItemBreakpointBuilder? itemBreakpointBuilder;

  /// Maps the item's live physical pixel dimensions to a developer-defined layout state.
  ///
  /// Evaluated continuously during resizing when [itemBreakpointBuilder] is provided.
  final DashboardBreakpointResolver? breakpointResolver;

  /// The physical width of this item in pixels, calculated during the build phase.
  ///
  /// This value is non-null only when [trackDimensions] is true (such as when using
  /// [itemLayoutBuilder] or [itemBreakpointBuilder]) to drive layout-aware invalidation.
  final double? itemWidth;

  /// The current slotCount used by the grid.
  final int? slotCount;

  /// The physical height of this item in pixels, calculated during the build phase.
  ///
  /// This value is non-null only when [trackDimensions] is true (such as when using
  /// [itemLayoutBuilder] or [itemBreakpointBuilder]) to drive layout-aware invalidation.
  final double? itemHeight;

  /// Configuration for the visual style (focus border, radius, etc.).
  final DashboardItemStyle itemStyle;

  /// Whether this widget is being rendered as the drag feedback overlay.
  ///
  /// If true, the widget remains visible even if it is the active item,
  /// and keyboard interactions are disabled to prevent conflicts.
  final bool isFeedback;

  /// Whether the item tracks pixel dimension changes to invalidate its cache.
  bool get trackDimensions => itemLayoutBuilder != null || itemBreakpointBuilder != null;

  @override
  State<DashboardItem> createState() => _DashboardItemState();
}

class _DashboardItemState extends State<DashboardItem>
    with AutomaticKeepAliveClientMixin<DashboardItem> {
  // Cache lazy initialization
  Widget? _cachedWidget;
  late int _lastSignature;
  late bool _lastIsEditing;
  double? _lastWidth;
  double? _lastHeight;
  int? _lastSlotCount;

  bool _isFocused = false;

  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    DashboardGrabItemIntent: CallbackAction<DashboardGrabItemIntent>(
      onInvoke: (_) {
        if (!widget.isEditing || widget.item.isStatic) return null;
        final controller = DashboardControllerProvider.of(context);
        final guidance = controller.guidance ?? DashboardGuidance.byDefault;
        controller.internal.onDragStart(widget.item.id);
        _announce(guidance.a11yGrab(widget.item.id));
        return null;
      },
    ),
    DashboardDropItemIntent: CallbackAction<DashboardDropItemIntent>(
      onInvoke: (_) {
        final controller = DashboardControllerProvider.of(context);
        if (_isActive(controller)) {
          final guidance = controller.guidance ?? DashboardGuidance.byDefault;
          controller.internal.onDragEnd(widget.item.id);
          _announce(guidance.a11yDrop(widget.item.x, widget.item.y));
        }
        return null;
      },
    ),
    DashboardMoveItemIntent: CallbackAction<DashboardMoveItemIntent>(
      onInvoke: (intent) {
        final controller = DashboardControllerProvider.of(context);
        if (_isActive(controller)) {
          final guidance = controller.guidance ?? DashboardGuidance.byDefault;
          controller.moveActiveItemBy(intent.dx, intent.dy);
          _announce(guidance.a11yMove(widget.item.x + intent.dx, widget.item.y + intent.dy));
        }
        return null;
      },
    ),
    DashboardCancelInteractionIntent: CallbackAction<DashboardCancelInteractionIntent>(
      onInvoke: (_) {
        final controller = DashboardControllerProvider.of(context);
        if (_isActive(controller)) {
          final guidance = controller.guidance ?? DashboardGuidance.byDefault;
          controller.cancelInteraction();
          _announce(guidance.a11yCancel);
        }
        return null;
      },
    ),
  };

  DashboardShortcuts? _shortcutsConfigCacheKey;
  late Map<ShortcutActivator, Intent> _activeShortcuts;
  late Map<ShortcutActivator, Intent> _idleShortcuts;

  bool _isActive(DashboardController controller) =>
      controller.isDragging.peek() && controller.selectedItemIds.peek().contains(widget.item.id);

  Map<ShortcutActivator, Intent> _shortcutsFor(
    DashboardShortcuts config, {
    required bool isActive,
  }) {
    if (!identical(_shortcutsConfigCacheKey, config)) {
      _shortcutsConfigCacheKey = config;
      _activeShortcuts = <ShortcutActivator, Intent>{
        for (final key in config.drop) key: const DashboardDropItemIntent(),
        for (final key in config.cancel) key: const DashboardCancelInteractionIntent(),
        for (final key in config.moveUp) key: const DashboardMoveItemIntent(0, -1),
        for (final key in config.moveDown) key: const DashboardMoveItemIntent(0, 1),
        for (final key in config.moveLeft) key: const DashboardMoveItemIntent(-1, 0),
        for (final key in config.moveRight) key: const DashboardMoveItemIntent(1, 0),
      };
      _idleShortcuts = <ShortcutActivator, Intent>{
        for (final key in config.grab) key: const DashboardGrabItemIntent(),
      };
    }
    return isActive ? _activeShortcuts : _idleShortcuts;
  }

  // The collision cascade in LayoutEngine.moveElement can shift
  // hundreds of items' `y` on every drag frame (see moveElement). Since
  // RenderSliverDashboard.performLayout recomputes its visible index range
  // from those positions every frame, items can flicker in and out of the
  // visible+cache window purely due to the cascade, even though their Key
  // and index never change during a single drag. Without keepAlive, each
  // flicker tears the widget down and rebuilds it from scratch
  // (Element.inflateWidget), which is what dominates the CPU profile during
  // a top-of-grid drag. Keeping items alive only while a drag is active
  // avoids this thrash without disabling virtualization the rest of the time.
  bool _keepAlive = false;

  @override
  bool get wantKeepAlive => _keepAlive;

  void _updateKeepAlive(bool value) {
    if (_keepAlive == value) return;
    _keepAlive = value;
    updateKeepAlive(); // Notify Flutter to retain this widget in the keep-alive bucket
  }

  @override
  void initState() {
    super.initState();
    // We initialize the tracking variables, but NOT the widget itself.
    // The widget will be built in the build() method where context is valid.
    _lastSignature = widget.item.contentSignature;
    _lastIsEditing = widget.isEditing;
    _lastWidth = widget.itemWidth;
    _lastHeight = widget.itemHeight;
    _lastSlotCount = widget.slotCount;
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
    final signatureChanged = newSignature != _lastSignature;
    final editingChanged = widget.isEditing != _lastIsEditing;

    // Invalidate cache on dimension changes if sub-pixel or breakpoint builders are active.
    final dimensionsChanged = widget.trackDimensions &&
        (widget.itemWidth != _lastWidth ||
            widget.itemHeight != _lastHeight ||
            widget.slotCount != _lastSlotCount);

    if (signatureChanged || editingChanged || dimensionsChanged) {
      _cachedWidget = null; // Invalidate cache
      _lastSignature = newSignature;
      _lastIsEditing = widget.isEditing;
      _lastWidth = widget.itemWidth;
      _lastHeight = widget.itemHeight;
      _lastSlotCount = widget.slotCount;
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
    super.build(context);
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
      child: widget.itemBreakpointBuilder != null
          ? DashboardBreakpointBuilder<dynamic>(
              width: widget.itemWidth!,
              height: widget.itemHeight!,
              item: widget.item,
              resolver: (w, h) => widget.breakpointResolver!(w, h, widget.item, widget.slotCount!),
              builder: (context, item, breakpoint, w, h) {
                return widget.itemBreakpointBuilder!(
                  context,
                  item,
                  breakpoint,
                  w,
                  h,
                  widget.slotCount!,
                );
              },
            )
          : widget.itemLayoutBuilder != null
              ? widget.itemLayoutBuilder!(
                  context,
                  widget.item,
                  widget.itemWidth!,
                  widget.itemHeight!,
                  widget.slotCount!,
                )
              : widget.itemBuilder!(context, widget.item),
    );

    // Watch Selection State
    final selectedIds = controller.selectedItemIds.watch(context);
    final isSelected = selectedIds.contains(widget.item.id);

    // Watch Dragging State
    final isDragging = controller.isDragging.watch(context);

    // Active means "Part of the group being dragged"
    final isActive = isDragging && isSelected;

    _updateKeepAlive(isDragging);

    final semanticLabel = 'Item ${widget.item.id}, Row ${widget.item.y}, Column ${widget.item.x}';

    // Focus order ensures Tab navigation follows the grid (Row-major)
    final focusOrder = (widget.item.y * 10000 + widget.item.x).toDouble();
    final style = widget.itemStyle;

    final shortcuts = _shortcutsFor(shortcutsConfig, isActive: isActive);

    // Build the Interaction Shell
    // This part is rebuilt every time focus changes or active state changes.
    // Since FocusableActionDetector is a StatefulWidget internally, it preserves
    // the FocusNode as long as it stays in the tree, solving the focus loss issue.
    return FocusTraversalOrder(
      order: NumericFocusOrder(focusOrder),
      child: FocusableActionDetector(
        actions: _actions,
        shortcuts: widget.isEditing ? shortcuts : {},
        // Enable interaction if the item is dynamic OR if it is an interactive section barrier
        enabled: widget.isEditing &&
            (!widget.item.isStatic || widget.item.isSectionBarrier) &&
            !widget.isFeedback,
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
          selected: isSelected,
          child: Opacity(
            // Hide if dragged AND not the feedback
            opacity: (isActive && !widget.isFeedback) ? 0.0 : 1.0,
            child: Container(
              decoration: widget.isEditing &&
                      (_isFocused || isSelected) // Show border if editMode && (focused OR selected)
                  ? (style.focusDecoration ??
                      BoxDecoration(
                        border: Border.all(
                          color: isActive
                              ? (style.activeColor ?? Colors.deepOrange)
                              : (style.focusColor ?? Theme.of(context).primaryColor),
                          width: (isActive || _isFocused) ? 4 : 3,
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

/// A highly optimized performance widget that shields its child subtree from rebuilds
/// during continuous desktop window resizing.
///
/// It only invalidates the cached widget when the resolved layout type of type [T]
/// (defined by the developer) changes or when the item's content signature updates.
class DashboardBreakpointBuilder<T> extends StatefulWidget {
  /// Creates a [DashboardBreakpointBuilder].
  const DashboardBreakpointBuilder({
    required this.width,
    required this.height,
    required this.item,
    required this.resolver,
    required this.builder,
    super.key,
  });

  /// The live width of the layout item in pixels.
  final double width;

  /// The live height of the layout item in pixels.
  final double height;

  /// The layout item metadata.
  final LayoutItem item;

  /// A pure function mapping current pixel dimensions to a developer-defined layout state of type [T].
  final T Function(double width, double height) resolver;

  /// Rebuilds only when the resolved layout type [T] changes.
  final Widget Function(
    BuildContext context,
    LayoutItem item,
    T layout,
    double width,
    double height,
  ) builder;

  @override
  State<DashboardBreakpointBuilder<T>> createState() => _DashboardBreakpointBuilderState<T>();
}

class _DashboardBreakpointBuilderState<T> extends State<DashboardBreakpointBuilder<T>> {
  Widget? _cachedChild;
  late T _currentLayout;
  late int _lastItemSignature;

  @override
  void initState() {
    super.initState();
    _currentLayout = widget.resolver(widget.width, widget.height);
    _lastItemSignature = widget.item.contentSignature;
  }

  @override
  void didUpdateWidget(covariant DashboardBreakpointBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Evaluate the resolver using the new dimensions
    final newLayout = widget.resolver(widget.width, widget.height);
    final signatureChanged = widget.item.contentSignature != _lastItemSignature;

    // Reason: Only invalidate the cached subtree if a real breakpoint was crossed
    // or if the underlying item content signature has been mutated.
    if (_currentLayout != newLayout || signatureChanged) {
      _currentLayout = newLayout;
      _lastItemSignature = widget.item.contentSignature;
      _cachedChild = null; // Forces a rebuild in the next pass
    }
  }

  @override
  Widget build(BuildContext context) {
    _cachedChild ??= widget.builder(
      context,
      widget.item,
      _currentLayout,
      widget.width,
      widget.height,
    );
    return _cachedChild!;
  }
}
