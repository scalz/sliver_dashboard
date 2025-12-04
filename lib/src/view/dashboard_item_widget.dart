import 'package:flutter/material.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/dashboard_configuration.dart';
import 'package:sliver_dashboard/src/view/dashboard_item_wrapper.dart';
import 'package:sliver_dashboard/src/view/dashboard_typedefs.dart';

/// A widget that wraps a single dashboard item, handling caching, focus, and
/// edit mode interactions.
///
/// This widget is the "smart wrapper" for the user's content. Its primary responsibilities are:
/// 1. **Performance:** It caches the user's content widget (built via [builder])
///    and wraps it in a [RepaintBoundary]. It prevents unnecessary rebuilds
///    by comparing the [LayoutItem.contentSignature].
/// 2. **Interaction:** It handles focus traversal and visual highlighting via [itemStyle].
/// 3. **Accessibility:** It wraps the content in [Semantics] to provide context
///    (position, size) to screen readers.
/// 4. **Edit Mode:** It displays resize handles when [isEditing] is true.
class DashboardItem extends StatefulWidget {
  /// Creates a [DashboardItem].
  const DashboardItem({
    required this.item,
    required this.isEditing,
    required this.builder,
    this.itemStyle = DashboardItemStyle.defaultStyle,
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
    //debugPrint('_DashboardItem initState Item ${widget.item.id}');

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
      /*
      if (widget.item.w != oldWidget.item.w) {
        debugPrint('Item ${widget.item.id} W changed: ${oldWidget.item.w} -> ${widget.item.w}');
      }
      if (widget.item.h != oldWidget.item.h) {
        debugPrint('Item ${widget.item.id} H changed: ${oldWidget.item.h} -> ${widget.item.h}');
      }
      if (widget.item.isStatic != oldWidget.item.isStatic) {
        debugPrint('Item ${widget.item.id} isStatic changed');
      }
      if (widget.item.isDraggable != oldWidget.item.isDraggable) {
        debugPrint(
          'Item ${widget.item.id} isDraggable changed: ${oldWidget.item.isDraggable} -> ${widget.item.isDraggable}',
        );
      }
      if (widget.item.isResizable != oldWidget.item.isResizable) {
        debugPrint(
          'Item ${widget.item.id} isResizable changed: ${oldWidget.item.isResizable} -> ${widget.item.isResizable}',
        );
      }
      */

      _cachedWidget = null; // Invalidate cache
      _lastSignature = newSignature;
      _lastIsEditing = widget.isEditing;
    }
  }

  Widget _buildCachedWidget() {
    final semanticLabel = 'Item ${widget.item.id}, Row ${widget.item.y}, Column ${widget.item.x}';
    final focusOrder = (widget.item.y * 10000 + widget.item.x).toDouble();
    final style = widget.itemStyle;

    final userContent = widget.builder(context, widget.item);

    // Isolate painting
    final contentWithBoundary = RepaintBoundary(child: userContent);

    return FocusTraversalOrder(
      order: NumericFocusOrder(focusOrder),
      child: Focus(
        debugLabel: 'DashboardItem-${widget.item.id}',
        canRequestFocus: widget.isEditing,
        onFocusChange: (hasFocus) {
          if (_isFocused != hasFocus) {
            setState(() {
              _isFocused = hasFocus;
            });
          }
        },
        child: Container(
          decoration: _isFocused
              ? (style.focusDecoration ??
                  BoxDecoration(
                    border: Border.all(
                      color: style.focusColor ?? Theme.of(context).primaryColor,
                      width: 3,
                    ),
                    borderRadius: style.borderRadius,
                  ))
              : null,
          child: Semantics(
            container: true,
            label: semanticLabel,
            hint: widget.isEditing ? 'Double tap to drag or resize' : null,
            child: DashboardItemWrapper(
              item: widget.item,
              child: contentWithBoundary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Lazy initialization: build the cache only when needed.
    // This solves the "dependOnInheritedWidget" error because 'context'
    // is fully initialized at this point.
    _cachedWidget ??= _buildCachedWidget();

    return _cachedWidget!;
  }
}
