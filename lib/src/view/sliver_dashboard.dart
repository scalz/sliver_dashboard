import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_provider.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/dashboard_configuration.dart';
import 'package:sliver_dashboard/src/view/dashboard_item_widget.dart';
import 'package:sliver_dashboard/src/view/dashboard_typedefs.dart';
import 'package:state_beacon/state_beacon.dart';

/// A callback for profiling layout performance.
/// [duration] is the time taken for performLayout.
typedef LayoutProfileCallback = void Function(Duration duration);

/// Custom parent data for children of [RenderSliverDashboard].
///
/// Stores the calculated pixel offset for painting each child.
class SliverDashboardParentData extends SliverMultiBoxAdaptorParentData {
  /// The paint offset of the child.
  late Offset paintOffset;
}

/// A sliver that displays the dashboard grid.
///
/// This widget connects to the [DashboardController] to listen for layout changes
/// and renders the items using a high-performance [SliverDashboardLayout].
///
/// It can be used directly inside a [CustomScrollView] alongside other slivers.
///
/// **Note:** To enable drag-and-drop interactions, this widget must be an
/// descendant of a DashboardOverlay (or the Dashboard wrapper).
class SliverDashboard extends StatefulWidget {
  /// Creates a [SliverDashboard].
  const SliverDashboard({
    required this.itemBuilder,
    super.key,
    this.gridStyle,
    this.itemStyle = DashboardItemStyle.defaultStyle,
    this.scrollDirection = Axis.vertical,
    this.slotAspectRatio = 1.0,
    this.mainAxisSpacing = 8.0,
    this.crossAxisSpacing = 8.0,
    this.breakpoints,
    this.itemGlobalKeySuffix = '',
    this.onPerformLayout,
    this.fillViewport = false,
  });

  /// A builder that creates the widgets for each dashboard item.
  final DashboardItemBuilder itemBuilder;

  /// Styling options for the background grid in edit mode.
  /// If null, no grid is painted.
  final GridStyle? gridStyle;

  /// Styling options for the item focus.
  final DashboardItemStyle itemStyle;

  /// The direction of scrolling for the dashboard.
  final Axis scrollDirection;

  /// The aspect ratio of each grid slot.
  final double slotAspectRatio;

  /// The spacing between items on the main axis (vertical).
  final double mainAxisSpacing;

  /// The spacing between items on the cross axis (horizontal).
  final double crossAxisSpacing;

  /// A map of breakpoints where the key is the minimum width and the value
  /// is the number of columns (slotCount).
  final Map<double, int>? breakpoints;

  /// A suffix to append to global keys for dashboard items.
  final String itemGlobalKeySuffix;

  /// Callback for testing/profiling layout performance.
  final LayoutProfileCallback? onPerformLayout;

  /// If true, force grid to fill viewport
  final bool fillViewport;

  @override
  State<SliverDashboard> createState() => _SliverDashboardState();
}

class _SliverDashboardState extends State<SliverDashboard> {
  late DashboardController _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // REASONING: Retrieve the controller from the nearest ancestor provider (O(1) operation).
    _controller = DashboardControllerProvider.of(context);
  }

  @override
  Widget build(BuildContext context) {
    // Watch layout changes
    _controller.layout.watch(context);
    _controller.activeItemId.watch(context); // Watch active ID here
    final isEditing = _controller.isEditing.watch(context);

    // Use SliverLayoutBuilder instead of LayoutBuilder to return a RenderSliver
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        // --- RESPONSIVE LOGIC ---
        if (widget.breakpoints != null) {
          // In a vertical sliver, crossAxisExtent is the width
          final width = constraints.crossAxisExtent;
          final targetSlots = _calculateSlots(width, widget.breakpoints!);

          if (targetSlots != _controller.slotCount.value) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _controller.setSlotCount(targetSlots);
              }
            });
            // Skip frame optimization: Return an empty Sliver
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          }
        }

        return SliverDashboardLayout(
          items: _controller.layout.value,
          slotCount: _controller.slotCount.value,
          scrollDirection: widget.scrollDirection,
          slotAspectRatio: widget.slotAspectRatio,
          mainAxisSpacing: widget.mainAxisSpacing,
          crossAxisSpacing: widget.crossAxisSpacing,
          onPerformLayout: widget.onPerformLayout,
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = _controller.layout.value[index];

              // Reason: We return the DashboardItem always.
              // The item itself handles its visibility (Opacity 0.0) if it is the active item,
              // to preserve its FocusNode for keyboard accessibility.
              return KeyedSubtree(
                key: ValueKey('${item.id}${widget.itemGlobalKeySuffix}'),
                child: DashboardItem(
                  item: item,
                  isEditing: isEditing,
                  itemStyle: widget.itemStyle,
                  builder: widget.itemBuilder,
                ),
              );
            },
            childCount: _controller.layout.value.length,
            // Allows Flutter to track a reordered item and preserve its State (and thus our cache).
            findChildIndexCallback: (Key key) {
              if (key is ValueKey<String>) {
                final layout = _controller.layout.value;
                for (var i = 0; i < layout.length; i++) {
                  if (ValueKey('${layout[i].id}${widget.itemGlobalKeySuffix}') == key) {
                    return i;
                  }
                }
              }
              return null;
            },
          ),
        );
      },
    );
  }

  int _calculateSlots(double width, Map<double, int> breakpoints) {
    final sortedBreakpoints = breakpoints.keys.toList()..sort();
    var slots = _controller.slotCount.value;

    for (final breakpoint in sortedBreakpoints) {
      if (width >= breakpoint) {
        slots = breakpoints[breakpoint]!;
      } else {
        break;
      }
    }
    return slots;
  }
}

/// A low-level sliver that displays a grid of items based on the dashboard layout.
///
/// This is a [MultiChildRenderObjectWidget] that uses a [RenderSliverDashboard]
/// to perform the actual layout.
class SliverDashboardLayout extends SliverMultiBoxAdaptorWidget {
  /// Creates a [SliverDashboardLayout].
  const SliverDashboardLayout({
    required this.items,
    required this.slotCount,
    required super.delegate,
    this.scrollDirection = Axis.vertical,
    this.slotAspectRatio = 1.0,
    this.mainAxisSpacing = 8.0,
    this.crossAxisSpacing = 8.0,
    this.onPerformLayout,
    super.key,
  });

  /// The list of layout items to display.
  final List<LayoutItem> items;

  /// The number of columns in the grid.
  final int slotCount;

  /// The scroll direction.
  final Axis scrollDirection;

  /// The aspect ratio of each grid slot.
  final double slotAspectRatio;

  /// The spacing between items on the main axis (vertical).
  final double mainAxisSpacing;

  /// The spacing between items on the cross axis (horizontal).
  final double crossAxisSpacing;

  /// Callback for testing/profiling layout performance.
  final LayoutProfileCallback? onPerformLayout;

  @override
  RenderSliverDashboard createRenderObject(BuildContext context) {
    final element = context as SliverMultiBoxAdaptorElement;
    return RenderSliverDashboard(
      childManager: element,
      items: items,
      slotCount: slotCount,
      scrollDirection: scrollDirection,
      slotAspectRatio: slotAspectRatio,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      onPerformLayout: onPerformLayout,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSliverDashboard renderObject) {
    renderObject
      ..items = items
      ..slotCount = slotCount
      ..scrollDirection = scrollDirection
      ..slotAspectRatio = slotAspectRatio
      ..mainAxisSpacing = mainAxisSpacing
      ..crossAxisSpacing = crossAxisSpacing
      ..onPerformLayout = onPerformLayout;
  }
}

/// The render object that implements the sliver grid layout.
class RenderSliverDashboard extends RenderSliverMultiBoxAdaptor {
  /// Creates a [RenderSliverDashboard].
  RenderSliverDashboard({
    required super.childManager,
    required List<LayoutItem> items,
    required int slotCount,
    required Axis scrollDirection,
    required double slotAspectRatio,
    required double mainAxisSpacing,
    required double crossAxisSpacing,
    this.onPerformLayout,
  })  : _items = items,
        _slotCount = slotCount,
        _scrollDirection = scrollDirection,
        _slotAspectRatio = slotAspectRatio,
        _mainAxisSpacing = mainAxisSpacing,
        _crossAxisSpacing = crossAxisSpacing;

  List<LayoutItem> _items;

  /// The list of layout items to display.
  List<LayoutItem> get items => _items;
  set items(List<LayoutItem> value) {
    if (_items == value) return;
    _items = value;
    markNeedsLayout();
  }

  int _slotCount;

  /// The number of slots in the cross-axis.
  int get slotCount => _slotCount;
  set slotCount(int value) {
    if (_slotCount == value) return;
    _slotCount = value;
    markNeedsLayout();
  }

  Axis _scrollDirection;

  /// The scroll direction of the grid.
  Axis get scrollDirection => _scrollDirection;
  set scrollDirection(Axis value) {
    if (_scrollDirection == value) return;
    _scrollDirection = value;
    markNeedsLayout();
  }

  double _slotAspectRatio;

  /// The aspect ratio of a single grid slot.
  double get slotAspectRatio => _slotAspectRatio;
  set slotAspectRatio(double value) {
    if (_slotAspectRatio == value) return;
    _slotAspectRatio = value;
    markNeedsLayout();
  }

  double _mainAxisSpacing;

  /// The spacing between items on the main axis.
  double get mainAxisSpacing => _mainAxisSpacing;
  set mainAxisSpacing(double value) {
    if (_mainAxisSpacing == value) return;
    _mainAxisSpacing = value;
    markNeedsLayout();
  }

  double _crossAxisSpacing;

  /// The spacing between items on the cross axis.
  double get crossAxisSpacing => _crossAxisSpacing;
  set crossAxisSpacing(double value) {
    if (_crossAxisSpacing == value) return;
    _crossAxisSpacing = value;
    markNeedsLayout();
  }

  /// Callback for testing/profiling layout performance.
  LayoutProfileCallback? onPerformLayout;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SliverDashboardParentData) {
      child.parentData = SliverDashboardParentData();
    }
  }

  @override
  void performLayout() {
    final stopwatch = onPerformLayout == null ? null : Stopwatch();
    stopwatch?.start();
    final constraints = this.constraints;
    final childManager = this.childManager;

    // 1. Handle empty state
    if (_items.isEmpty) {
      childManager
        ..didStartLayout()
        ..didFinishLayout();
      geometry = SliverGeometry.zero;
      if (stopwatch != null) {
        stopwatch.stop();
        onPerformLayout?.call(stopwatch.elapsed);
      }
      return;
    }

    childManager
      ..didStartLayout()
      ..setDidUnderflow(false);

    // 2. Calculate Slot Metrics
    final crossAxisExtent = constraints.crossAxisExtent;
    final double slotWidth;
    final double slotHeight;

    final isVertical = _scrollDirection == Axis.vertical;

    if (isVertical) {
      slotWidth = (crossAxisExtent - (_slotCount - 1) * _crossAxisSpacing) / _slotCount;
      slotHeight = slotWidth / _slotAspectRatio;
    } else {
      slotHeight = (crossAxisExtent - (_slotCount - 1) * _mainAxisSpacing) / _slotCount;
      slotWidth = slotHeight * _slotAspectRatio;
    }

    // 3. Pre-calculate item geometries and total scroll extent
    final itemRects = List<Rect>.filled(_items.length, Rect.zero);
    var maxScrollExtent = 0.0;

    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      final double x;
      final double y;
      final double w;
      final double h;

      if (isVertical) {
        x = item.x * (slotWidth + _crossAxisSpacing);
        y = item.y * (slotHeight + _mainAxisSpacing);
        w = item.w * (slotWidth + _crossAxisSpacing) - _crossAxisSpacing;
        h = item.h * (slotHeight + _mainAxisSpacing) - _mainAxisSpacing;
        final bottom = y + h;
        if (bottom > maxScrollExtent) maxScrollExtent = bottom;
      } else {
        x = item.x * (slotWidth + _mainAxisSpacing);
        y = item.y * (slotHeight + _crossAxisSpacing);
        w = item.w * (slotWidth + _mainAxisSpacing) - _mainAxisSpacing;
        h = item.h * (slotHeight + _crossAxisSpacing) - _crossAxisSpacing;
        final right = x + w;
        if (right > maxScrollExtent) maxScrollExtent = right;
      }

      itemRects[i] = Rect.fromLTWH(x, y, w > 0 ? w : 0, h > 0 ? h : 0);
    }

    // 4. Determine Visible Window (including cache)
    final targetStart = constraints.scrollOffset + constraints.cacheOrigin;
    final targetEnd = constraints.scrollOffset + constraints.remainingCacheExtent;

    // 5. Find Visible Index Range
    var minVisibleIndex = _items.length;
    var maxVisibleIndex = -1;

    for (var i = 0; i < _items.length; i++) {
      final rect = itemRects[i];
      final itemStart = isVertical ? rect.top : rect.left;
      final itemEnd = isVertical ? rect.bottom : rect.right;

      if (itemEnd >= targetStart && itemStart <= targetEnd) {
        if (i < minVisibleIndex) minVisibleIndex = i;
        if (i > maxVisibleIndex) maxVisibleIndex = i;
      }
    }

    // Handle case where no items are visible
    if (maxVisibleIndex < minVisibleIndex) {
      minVisibleIndex = 0;
      maxVisibleIndex = -1;
    }

    // 6. Garbage Collection (Robust)
    var leadingGarbage = 0;
    var trailingGarbage = 0;

    if (firstChild != null) {
      final firstChildIndex = indexOf(firstChild!);
      final lastChildIndex = indexOf(lastChild!);

      // Calculate leading garbage: items in [firstChildIndex, lastChildIndex] that are < minVisibleIndex
      // The last index to remove is min(lastChildIndex, minVisibleIndex - 1)
      final int lastRemoveIndex = min(lastChildIndex, minVisibleIndex - 1);
      if (lastRemoveIndex >= firstChildIndex) {
        leadingGarbage = lastRemoveIndex - firstChildIndex + 1;
      }

      // Calculate trailing garbage: items in [firstChildIndex, lastChildIndex] that are > maxVisibleIndex
      // The first index to remove is max(firstChildIndex, maxVisibleIndex + 1)
      final int firstRemoveIndex = max(firstChildIndex, maxVisibleIndex + 1);
      if (firstRemoveIndex <= lastChildIndex) {
        trailingGarbage = lastChildIndex - firstRemoveIndex + 1;
      }

      collectGarbage(leadingGarbage, trailingGarbage);
    }

    // 7. Layout Children

    // Case A: No children exist yet (fresh start or after full GC).
    if (firstChild == null) {
      if (minVisibleIndex <= maxVisibleIndex) {
        final rect = itemRects[minVisibleIndex];
        final initialOffset = isVertical ? rect.top : rect.left;

        if (addInitialChild(index: minVisibleIndex, layoutOffset: initialOffset)) {
          // Important: Set the paintOffset for the initial child immediately
          final childParentData = firstChild?.parentData;
          if (childParentData is SliverDashboardParentData) {
            childParentData.paintOffset = Offset(rect.left, rect.top);
          }
        } else {
          minVisibleIndex = maxVisibleIndex + 1;
        }
      }
    }

    // Case B: Fill trailing
    var trailingChild = lastChild;
    while (trailingChild != null && indexOf(trailingChild) < maxVisibleIndex) {
      final index = indexOf(trailingChild) + 1;
      final rect = itemRects[index];

      final childConstraints = BoxConstraints.tightFor(
        width: rect.width,
        height: rect.height,
      );

      final newChild =
          insertAndLayoutChild(childConstraints, after: trailingChild, parentUsesSize: true);
      final childParentData = newChild?.parentData;
      if (newChild == null || childParentData is! SliverDashboardParentData) break;

      childParentData
        ..layoutOffset = isVertical ? rect.top : rect.left
        ..paintOffset = Offset(rect.left, rect.top);

      trailingChild = newChild;
    }

    // Case C: Fill leading
    var leadingChild = firstChild;
    while (leadingChild != null && indexOf(leadingChild) > minVisibleIndex) {
      final index = indexOf(leadingChild) - 1;
      final rect = itemRects[index];

      final childConstraints = BoxConstraints.tightFor(
        width: rect.width,
        height: rect.height,
      );

      final newChild = insertAndLayoutLeadingChild(childConstraints, parentUsesSize: true);
      final childParentData = newChild?.parentData;
      if (newChild == null || childParentData is! SliverDashboardParentData) break;

      childParentData
        ..layoutOffset = isVertical ? rect.top : rect.left
        ..paintOffset = Offset(rect.left, rect.top);

      leadingChild = newChild;
    }

    // 8. Re-layout existing children
    var child = firstChild;
    while (child != null) {
      final index = indexOf(child);
      final rect = itemRects[index];

      final childParentData = child.parentData;
      if (childParentData is! SliverDashboardParentData) break;

      childParentData
        ..layoutOffset = isVertical ? rect.top : rect.left
        ..paintOffset = Offset(rect.left, rect.top);

      child.layout(
        BoxConstraints.tightFor(width: rect.width, height: rect.height),
        parentUsesSize: true,
      );

      child = childAfter(child);
    }

    // 9. Calculate Geometry
    final paintExtent = calculatePaintOffset(
      constraints,
      from: 0,
      to: maxScrollExtent,
    );

    final cacheExtentVal = calculateCacheOffset(
      constraints,
      from: 0,
      to: maxScrollExtent,
    );

    geometry = SliverGeometry(
      scrollExtent: maxScrollExtent,
      paintExtent: paintExtent,
      cacheExtent: cacheExtentVal,
      maxPaintExtent: maxScrollExtent,
      hasVisualOverflow:
          maxScrollExtent > constraints.remainingPaintExtent || constraints.scrollOffset > 0.0,
    );

    childManager.didFinishLayout();

    if (stopwatch != null) {
      stopwatch.stop();
      onPerformLayout?.call(stopwatch.elapsed);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (firstChild == null) return;
    final isVertical = scrollDirection == Axis.vertical;

    var child = firstChild;
    while (child != null) {
      final childParentData = child.parentData;
      if (childParentData is! SliverDashboardParentData) break;

      final mainAxisLayoutOffset = childParentData.layoutOffset!;

      if (mainAxisLayoutOffset + (isVertical ? child.size.height : child.size.width) >=
              constraints.scrollOffset &&
          mainAxisLayoutOffset <= constraints.scrollOffset + constraints.remainingPaintExtent) {
        final Offset finalPaintOffset;
        if (isVertical) {
          finalPaintOffset = offset +
              Offset(
                childParentData.paintOffset.dx,
                mainAxisLayoutOffset - constraints.scrollOffset,
              );
        } else {
          finalPaintOffset = offset +
              Offset(
                mainAxisLayoutOffset - constraints.scrollOffset,
                childParentData.paintOffset.dy,
              );
        }
        context.paintChild(child, finalPaintOffset);
      }
      child = childAfter(child);
    }
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    var child = lastChild;
    final isVertical = scrollDirection == Axis.vertical;
    while (child != null) {
      final parentData = child.parentData;
      if (parentData is! SliverDashboardParentData) break;

      // The `mainAxisPosition` passed to hitTestChildren is relative to the
      // sliver's paint origin, which is the top of the visible portion.
      // We need to compare it against the child's position, which is also
      // relative to that same origin.
      final childMainAxisPosition = parentData.layoutOffset! - constraints.scrollOffset;
      final childCrossAxisPosition =
          isVertical ? parentData.paintOffset.dx : parentData.paintOffset.dy;

      final childCrossAxisExtent = isVertical ? child.size.width : child.size.height;
      final childMainAxisExtent = isVertical ? child.size.height : child.size.width;

      if (mainAxisPosition >= childMainAxisPosition &&
          mainAxisPosition < childMainAxisPosition + childMainAxisExtent &&
          crossAxisPosition >= childCrossAxisPosition &&
          crossAxisPosition < childCrossAxisPosition + childCrossAxisExtent) {
        // The hit is within the child's bounds, so we now convert to the
        // child's local coordinate system to perform the final hit test.
        final localCrossAxis = crossAxisPosition - childCrossAxisPosition;
        final localMainAxis = mainAxisPosition - childMainAxisPosition;

        if (child.hitTest(
          BoxHitTestResult.wrap(result),
          position: isVertical
              ? Offset(localCrossAxis, localMainAxis)
              : Offset(localMainAxis, localCrossAxis),
        )) {
          // The hit was successful, so we have found our target.
          // Add the child to the result and report the hit.
          result.add(
            SliverHitTestEntry(
              this,
              mainAxisPosition: mainAxisPosition,
              crossAxisPosition: crossAxisPosition,
            ),
          );
          return true;
        }
      }
      child = childBefore(child);
    }
    return false;
  }

  // override childMainAxisPosition, childCrossAxisPosition and applyPaintTransform
  // to ensure consistency with the paint logic and Flutter's tooltips alignment.
  @override
  double childMainAxisPosition(RenderBox child) {
    final childParentData = child.parentData! as SliverDashboardParentData;
    return childParentData.layoutOffset! - constraints.scrollOffset;
  }

  @override
  double childCrossAxisPosition(RenderBox child) {
    final childParentData = child.parentData! as SliverDashboardParentData;
    return _scrollDirection == Axis.vertical
        ? childParentData.paintOffset.dx
        : childParentData.paintOffset.dy;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final mainAxisDelta = childMainAxisPosition(child);
    final crossAxisDelta = childCrossAxisPosition(child);

    if (_scrollDirection == Axis.vertical) {
      transform.translateByDouble(crossAxisDelta, mainAxisDelta, 0, 1);
    } else {
      transform.translateByDouble(mainAxisDelta, crossAxisDelta, 0, 1);
    }
  }
}
