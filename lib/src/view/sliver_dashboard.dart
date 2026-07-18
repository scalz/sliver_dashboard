import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_provider.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
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
  /// The paint offset of the child (full content coordinates, scroll-invariant).
  Offset paintOffset = Offset.zero;

  /// Whether [paintOffset] has been assigned at least once. Freshly created
  /// children (scrolled into view) have no previous position: reflow
  /// animations snap them instead of animating from `Offset.zero`.
  bool hasPaintOffset = false;
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
    this.controller,
    this.itemBuilder,
    this.itemLayoutBuilder,
    this.itemBreakpointBuilder,
    this.breakpointResolver,
    this.sectionHeaderBuilder,
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
    this.animateReflow = false,
    this.reflowDuration = const Duration(milliseconds: 150),
    super.key,
  }) : assert(
          (itemBuilder != null ? 1 : 0) +
                  (itemLayoutBuilder != null ? 1 : 0) +
                  (itemBreakpointBuilder != null && breakpointResolver != null ? 1 : 0) ==
              1,
          'Provide exactly one builder configuration.',
        );

  /// An optional controller to bind directly to this sliver.
  ///
  /// If provided, this sliver will bypass the nearest [DashboardControllerProvider]
  /// ancestor and use this controller instance instead, preventing provider shadowing
  /// in multi-sliver composition layouts.
  final DashboardController? controller;

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

  /// Optional builder to customize the appearance of section headers.
  final DashboardSectionHeaderBuilder? sectionHeaderBuilder;

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

  /// Enables paint-phase slide transitions for tiles pushed or compacted by a
  /// drag/resize.
  ///
  /// Layout stays instantaneous and deterministic (the controller/engine are
  /// untouched); only the *painted* position of a moved tile is interpolated
  /// over [reflowDuration]. Each tile's content is already cached
  /// behind a `RepaintBoundary`, so the interpolation translates the cached
  /// layer on the GPU — zero widget rebuilds, zero re-rasterization.
  ///
  /// Disabled by default: on low-end web clients the extra paint pump
  /// (markNeedsPaint per frame for 150 ms after each cell crossing) is a cost
  /// some integrators prefer to avoid.
  ///
  /// Known limits (by design): hit-testing and semantics use the final
  /// position immediately; a slot-metric change (viewport resize, breakpoint,
  /// slot-count change) snaps instead of animating.
  final bool animateReflow;

  /// Duration of a single tile slide when [animateReflow] is true.
  final Duration reflowDuration;

  /// Callback for testing/profiling layout performance.
  final LayoutProfileCallback? onPerformLayout;

  /// If true, force grid to fill viewport
  final bool fillViewport;

  @override
  State<SliverDashboard> createState() => _SliverDashboardState();
}

class _SliverDashboardState extends State<SliverDashboard> with TickerProviderStateMixin {
  /// Publishes the sliver's exact layout metrics onto the controller (plain
  /// fields — written during layout, so no beacon/notify is allowed here).
  /// Consumed by DashboardMinimap to map its viewport indicator and
  /// tap-to-scroll onto the grid's real scroll segment.
  void _publishLayoutMetrics(
    double leadingExtent,
    double contentExtent,
    double slotWidth,
    double slotHeight,
  ) {
    _controller.internal
      ..viewMainAxisLeadingExtent = leadingExtent
      ..viewMainAxisContentExtent = contentExtent
      ..viewSlotWidth = slotWidth
      ..viewSlotHeight = slotHeight;
  }

  late DashboardController _controller;

  // Cache variables to avoid GC churn and string allocations
  List<LayoutItem>? _lastLayout;
  Map<Key, int>? _cachedKeyToIndex;

  /// Retrieves or rebuilds the Key-to-Index map only when the ID sequence changes.
  Map<Key, int> _getOrUpdateKeyToIndex(List<LayoutItem> currentLayout) {
    final last = _lastLayout;
    final cached = _cachedKeyToIndex;

    if (cached != null && last != null) {
      if (identical(last, currentLayout)) return cached;

      if (last.length == currentLayout.length) {
        var sameOrder = true;
        for (var i = 0; i < currentLayout.length; i++) {
          final a = last[i].id;
          final b = currentLayout[i].id;
          if (!identical(a, b) && a != b) {
            sameOrder = false;
            break;
          }
        }
        if (sameOrder) {
          _lastLayout = currentLayout;
          return cached;
        }
      }
    }

    _lastLayout = currentLayout;
    return _cachedKeyToIndex = {
      for (var i = 0; i < currentLayout.length; i++)
        ValueKey('${currentLayout[i].id}${widget.itemGlobalKeySuffix}'): i,
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // REASONING: Retrieve the controller from the widget if provided,
    // otherwise fall back to the nearest ancestor provider (O(1) operation).
    _controller = widget.controller ?? DashboardControllerProvider.of(context);
  }

  @override
  void didUpdateWidget(covariant SliverDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller = widget.controller ?? DashboardControllerProvider.of(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch layout changes
    _controller.layout.watch(context);
    final isEditing = _controller.isEditing.watch(context);
    _controller.isDragging.watch(context);

    final ctrlSlotCount = _controller.slotCount.watch(context);

    final layout = _controller.layout.value;
    final keyToIndex = _getOrUpdateKeyToIndex(layout);

    // Use SliverLayoutBuilder instead of LayoutBuilder to return a RenderSliver
    final sliverContent = SliverLayoutBuilder(
      // Bind the widget key directly to the active slotCount.
      // Changing the key forces Flutter to unmount the old sub-grid and perform
      // a clean layout pass, ensuring correct slot size calculations even on empty grids.
      key: ValueKey('sliver-layout-builder-$ctrlSlotCount'),
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
          }
        }

        // Pre-calculate the physical slot sizes during the build phase
        // to allow single-pass pixel updates.
        final crossAxisExtent = constraints.crossAxisExtent;
        final slotCount = _controller.slotCount.value;
        final double slotWidth;
        final double slotHeight;
        final isVertical = widget.scrollDirection == Axis.vertical;

        if (isVertical) {
          slotWidth = (crossAxisExtent - (slotCount - 1) * widget.crossAxisSpacing) / slotCount;
          slotHeight = slotWidth / widget.slotAspectRatio;
        } else {
          slotHeight = (crossAxisExtent - (slotCount - 1) * widget.mainAxisSpacing) / slotCount;
          slotWidth = slotHeight * widget.slotAspectRatio;
        }

        return SliverDashboardLayout(
          items: _controller.layout.value,
          slotCount: _controller.slotCount.value,
          scrollDirection: widget.scrollDirection,
          slotAspectRatio: widget.slotAspectRatio,
          mainAxisSpacing: widget.mainAxisSpacing,
          crossAxisSpacing: widget.crossAxisSpacing,
          onPerformLayout: widget.onPerformLayout,
          isEditing: isEditing,
          animateReflow: widget.animateReflow,
          reflowDuration: widget.reflowDuration,
          vsync: this,
          onLayoutMetrics: _publishLayoutMetrics,
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = _controller.layout.value[index];

              // Calculate exact dimensions analytically only if a responsive builder is active.
              final double? itemWidth;
              final double? itemHeight;

              if (widget.itemLayoutBuilder != null || widget.itemBreakpointBuilder != null) {
                if (isVertical) {
                  itemWidth =
                      item.w * (slotWidth + widget.crossAxisSpacing) - widget.crossAxisSpacing;
                  itemHeight =
                      item.h * (slotHeight + widget.mainAxisSpacing) - widget.mainAxisSpacing;
                } else {
                  itemWidth =
                      item.w * (slotWidth + widget.mainAxisSpacing) - widget.mainAxisSpacing;
                  itemHeight =
                      item.h * (slotHeight + widget.crossAxisSpacing) - widget.crossAxisSpacing;
                }
              } else {
                itemWidth = null;
                itemHeight = null;
              }

              // If the item represents a Section Barrier, we render it
              // using the custom or default section header builder instead of
              // passing it to the standard card itemBuilder.
              if (item.isSectionBarrier) {
                return KeyedSubtree(
                  key: ValueKey('${item.id}${widget.itemGlobalKeySuffix}'),
                  child: DashboardItem(
                    item: item,
                    isEditing: isEditing,
                    itemStyle: widget.itemStyle,
                    itemWidth: itemWidth,
                    itemHeight: itemHeight,
                    slotCount: slotCount,
                    // Section barriers are static headers that do not require
                    // pixel tracking. We build them using the optimized 2-parameter itemBuilder.
                    itemBuilder: (ctx, item) =>
                        widget.sectionHeaderBuilder?.call(ctx, item) ??
                        _DefaultSectionHeader(item: item),
                  ),
                );
              }

              // We return the DashboardItem always.
              // The item itself handles its visibility (Opacity 0.0) if it is the active item,
              // to preserve its FocusNode for keyboard accessibility.
              return KeyedSubtree(
                key: ValueKey('${item.id}${widget.itemGlobalKeySuffix}'),
                child: DashboardItem(
                  item: item,
                  isEditing: isEditing,
                  itemStyle: widget.itemStyle,
                  itemWidth: itemWidth,
                  itemHeight: itemHeight,
                  slotCount: slotCount,
                  itemBuilder: widget.itemBuilder,
                  itemLayoutBuilder: widget.itemLayoutBuilder,
                  itemBreakpointBuilder: widget.itemBreakpointBuilder,
                  breakpointResolver: widget.breakpointResolver,
                ),
              );
            },
            childCount: _controller.layout.value.length,
            // Allows Flutter to track a reordered item and preserve its State (and thus our cache).
            findChildIndexCallback: (key) => keyToIndex[key],
          ),
        );
      },
    );

    // Wrap subtree in a dedicated provider if a specific controller was passed,
    // so that child widgets (DashboardItems) automatically resolve to this correct instance.
    if (widget.controller != null) {
      return DashboardControllerProvider(
        controller: widget.controller!,
        child: sliverContent,
      );
    }

    return sliverContent;
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
    required this.vsync,
    this.scrollDirection = Axis.vertical,
    this.slotAspectRatio = 1.0,
    this.mainAxisSpacing = 8.0,
    this.crossAxisSpacing = 8.0,
    this.onPerformLayout,
    this.isEditing = false,
    this.animateReflow = false,
    this.reflowDuration = const Duration(milliseconds: 150),
    this.onLayoutMetrics,
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

  /// Whether the dashboard is in edit mode.
  final bool isEditing;

  /// See [SliverDashboard.animateReflow].
  final bool animateReflow;

  /// See [SliverDashboard.reflowDuration].
  final Duration reflowDuration;

  /// Sink for the sliver's exact layout metrics (preceding extent, own
  /// scroll extent, slot sizes), invoked at the end of every layout pass.
  final void Function(double leading, double extent, double slotW, double slotH)? onLayoutMetrics;

  /// Ticker provider driving the paint-phase reflow interpolation.
  ///
  /// A [Ticker] (rather than raw `SchedulerBinding` frame callbacks) keeps
  /// the animation muted when the route is hidden and fully deterministic
  /// under `flutter_test`'s fake frame clock.
  final TickerProvider vsync;

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
      isEditing: isEditing,
      animateReflow: animateReflow,
      reflowDuration: reflowDuration,
      vsync: vsync,
      onLayoutMetrics: onLayoutMetrics,
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
      ..onPerformLayout = onPerformLayout
      ..isEditing = isEditing
      ..animateReflow = animateReflow
      ..reflowDuration = reflowDuration
      ..vsync = vsync
      ..onLayoutMetrics = onLayoutMetrics

      // Force a layout pass on structural widget updates to ensure child parentData offsets are aligned
      ..markNeedsLayout();
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
    required TickerProvider vsync,
    this.onPerformLayout,
    this.onLayoutMetrics,
    bool isEditing = false,
    bool animateReflow = false,
    Duration reflowDuration = const Duration(milliseconds: 150),
  })  : _items = items,
        _slotCount = slotCount,
        _scrollDirection = scrollDirection,
        _slotAspectRatio = slotAspectRatio,
        _mainAxisSpacing = mainAxisSpacing,
        _crossAxisSpacing = crossAxisSpacing,
        _isEditing = isEditing,
        _animateReflow = animateReflow,
        _reflowDurationUs = reflowDuration.inMicroseconds,
        _vsync = vsync;

  List<LayoutItem> _items;

  /// The list of layout items to display.
  List<LayoutItem> get items => _items;
  set items(List<LayoutItem> value) {
    // Identity guard: the controller emits a new list instance only when the
    // layout actually changed; identical instances mean identical geometry.
    if (identical(_items, value)) return;
    _items = value;
    // Reason: reflow transitions must only be seeded by genuine layout
    // mutations. Scroll-driven relayouts reuse the same list instance and
    // therefore never pay the offset-comparison cost.
    _reflowSeedPass = _animateReflow;
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

  bool _isEditing;

  /// Whether the dashboard is in edit mode.
  bool get isEditing => _isEditing;
  set isEditing(bool value) {
    if (_isEditing == value) return;
    _isEditing = value;
    markNeedsLayout();
  }

  /// Callback for testing/profiling layout performance.
  LayoutProfileCallback? onPerformLayout;

  /// Sink invoked at the end of every layout pass with the sliver's exact
  /// metrics. Plain function call, no allocation, no notify — safe in layout.
  void Function(double leading, double extent, double slotW, double slotH)? onLayoutMetrics;

  // ==========================================================================
  // Paint-phase reflow animations
  // ==========================================================================

  bool _animateReflow;

  /// Whether pushed/compacted tiles slide to their new slot during paint.
  bool get animateReflow => _animateReflow;
  set animateReflow(bool value) {
    if (_animateReflow == value) return;
    _animateReflow = value;
    if (!value) {
      _transitions.clear();
      _stopReflowTicker();
      markNeedsPaint();
    }
  }

  int _reflowDurationUs;

  /// Duration of a tile slide, stored in microseconds for hot-path math.
  Duration get reflowDuration => Duration(microseconds: _reflowDurationUs);
  set reflowDuration(Duration value) {
    final us = value.inMicroseconds;
    if (_reflowDurationUs == us) return;
    _reflowDurationUs = us;
  }

  TickerProvider _vsync;

  /// The ticker provider driving the reflow pump.
  TickerProvider get vsync => _vsync;
  set vsync(TickerProvider value) {
    if (identical(_vsync, value)) return;
    _vsync = value;
    // Reason: an active ticker belongs to the old provider; recreate lazily.
    _stopReflowTicker();
    _ticker?.dispose();
    _ticker = null;
    if (_transitions.isNotEmpty) _startReflowTicker();
  }

  /// Active slide transitions, keyed by [LayoutItem.id]. Instances are
  /// mutated in place on retarget, so steady dragging allocates at most one
  /// small object per tile for the whole gesture.
  final Map<String, _ReflowTransition> _transitions = <String, _ReflowTransition>{};

  /// True for exactly one layout pass after the [items] instance changed.
  bool _reflowSeedPass = false;

  // Slot metrics of the previous pass: a metric change (viewport resize,
  // breakpoint, slot-count) moves every tile at once — that reflow snaps.
  double _reflowLastSlotW = -1;
  double _reflowLastSlotH = -1;
  int _reflowLastSlotCount = -1;

  Ticker? _ticker;
  // Monotonic animation clock in microseconds, advanced by the ticker. Using
  // ticker elapsed (frame timestamps) keeps tests deterministic and avoids
  // SchedulerBinding.currentFrameTimeStamp assertions outside frames.
  int _animNowUs = 0;
  int _animAccumulatedUs = 0;

  void _onReflowTick(Duration elapsed) {
    _animNowUs = _animAccumulatedUs + elapsed.inMicroseconds;
    // Time-based pruning (not visibility-based): a tile GC'd out of the
    // viewport mid-slide must not keep the ticker alive forever.
    _transitions.removeWhere((_, t) => _animNowUs - t.startUs >= _reflowDurationUs);
    if (_transitions.isEmpty) _stopReflowTicker();
    // One more paint after emptying, so tiles settle on their rest position.
    markNeedsPaint();
  }

  void _startReflowTicker() {
    final ticker = _ticker ??= _vsync.createTicker(_onReflowTick);
    // The TickerFuture is deliberately discarded: it only completes when the
    // ticker is stopped with `canceled: false` and NEVER completes on cancel
    // or dispose, so awaiting it could suspend forever — and this is
    // synchronous render-object code anyway. Lifecycle is owned by
    // _onReflowTick (time-based pruning) and _stopReflowTicker.
    if (!ticker.isActive) ticker.start().ignore();
  }

  void _stopReflowTicker() {
    final ticker = _ticker;
    if (ticker != null && ticker.isActive) {
      _animAccumulatedUs = _animNowUs;
      ticker.stop();
    }
  }

  /// Seeds or retargets the slide of item [id] from its current *visual*
  /// position toward ([toX], [toY]).
  void _seedTransition(String id, double fromX, double fromY, double toX, double toY) {
    final existing = _transitions[id];
    if (existing != null) {
      // Retarget mid-flight: continue from the interpolated position for a
      // continuous motion instead of jumping back to the stale origin.
      final p = _transitionProgress(existing);
      existing
        ..fromX = existing.fromX + (existing.toX - existing.fromX) * p
        ..fromY = existing.fromY + (existing.toY - existing.fromY) * p
        ..toX = toX
        ..toY = toY
        ..startUs = _animNowUs;
      return;
    }
    _transitions[id] = _ReflowTransition(
      fromX: fromX,
      fromY: fromY,
      toX: toX,
      toY: toY,
      startUs: _animNowUs,
    );
  }

  /// Number of in-flight reflow transitions (test hook).
  @visibleForTesting
  int get debugActiveReflowTransitionCount => _transitions.length;

  /// The *painted* (possibly interpolated) offset of item [id] right now, or
  /// null when the item is unknown (test hook).
  @visibleForTesting
  Offset? debugReflowPaintOffsetFor(String id) {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].id != id) continue;
      final t = _transitions[id];
      if (t != null) {
        final p = _transitionProgress(t);
        if (p < 1) {
          return Offset(
            t.fromX + (t.toX - t.fromX) * p,
            t.fromY + (t.toY - t.fromY) * p,
          );
        }
      }
      // Rest position: recompute from grid coordinates is unnecessary — every
      // laid-out child stores it, but the child may be GC'd; fall back to the
      // transition target if one existed, else null.
      return null;
    }
    return null;
  }

  /// Eased progress of [t] at the current animation clock, in [0, 1]
  /// (easeOutCubic — matches the platform reflow feel of gridstack/Muuri
  /// without allocating a Curve object).
  double _transitionProgress(_ReflowTransition t) {
    if (_reflowDurationUs <= 0) return 1;
    var p = (_animNowUs - t.startUs) / _reflowDurationUs;
    if (p >= 1) return 1;
    if (p < 0) p = 0;
    final inv = 1 - p;
    return 1 - inv * inv * inv;
  }

  /// Applies the computed geometry to a child's parent data, seeding a reflow
  /// transition when this pass is an animatable layout mutation and the
  /// tile's paint offset actually moved.
  ///
  /// Reason — placement in the hot path: this replaces the previous inline
  /// double assignment. Cost when animations are disabled or on scroll
  /// passes: one bool check. No allocation either way (transitions mutate in
  /// place).
  void _applyChildGeometry(
    SliverDashboardParentData pd,
    int index,
    double x,
    double y,
    double layoutOffset, {
    required bool animatePass,
  }) {
    if (animatePass && pd.hasPaintOffset) {
      final old = pd.paintOffset;
      if (old.dx != x || old.dy != y) {
        final item = _items[index];
        // The drag placeholder snaps: animating it would make the drop
        // preview lag behind the pointer.
        if (item.id != '__placeholder__') {
          _seedTransition(item.id, old.dx, old.dy, x, y);
        }
      }
    }
    pd
      ..layoutOffset = layoutOffset
      ..paintOffset = Offset(x, y)
      ..hasPaintOffset = true;
  }

  // Reused geometry scratch buffer: [left, top, width, height] per item.
  // Replaces the per-layout-pass List<Rect>.filled(N) allocation (~60k
  // short-lived Rect objects per second during autoscroll drags at N=1000),
  // eliminating dart2js minor-GC pressure in the drag hot path.
  Float64List _geom = Float64List(0);

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

      final emptyExtent = _isEditing ? 200.0 : 0.0;

      geometry = SliverGeometry(
        scrollExtent: emptyExtent,
        paintExtent: calculatePaintOffset(constraints, from: 0, to: emptyExtent),
        maxPaintExtent: emptyExtent,
      );

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

    // 2bis. Reflow-animation gating.
    // A pass may seed slide transitions only when (a) the feature is on,
    // (b) the items *instance* changed since the previous pass (a genuine
    // layout mutation — scroll relayouts reuse the instance) and (c) the slot
    // metrics are unchanged. A metric change (viewport resize, breakpoint,
    // slot count) moves every tile at once; that reflow snaps and any
    // in-flight transition is dropped, because its from/to coordinates were
    // expressed in the old metric space.
    final metricsChanged = slotWidth != _reflowLastSlotW ||
        slotHeight != _reflowLastSlotH ||
        _slotCount != _reflowLastSlotCount;
    final animatePass = _animateReflow && _reflowSeedPass && !metricsChanged;
    _reflowLastSlotW = slotWidth;
    _reflowLastSlotH = slotHeight;
    _reflowLastSlotCount = _slotCount;
    _reflowSeedPass = false;
    if (metricsChanged && _transitions.isNotEmpty) {
      _transitions.clear();
    }

    // 3. Pre-calculate item geometries and total scroll extent
    final itemCount = _items.length;
    // Prevent GC churn during scrolling. The Float64List is reused across
    // layout passes, avoiding allocating dynamic `List<Rect>` or `Rect` objects.
    if (_geom.length < itemCount * 4) {
      _geom = Float64List(itemCount * 4);
    }
    final geom = _geom;
    var maxScrollExtent = 0.0;

    for (var i = 0; i < itemCount; i++) {
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

      final base = i * 4;
      geom[base] = x;
      geom[base + 1] = y;
      geom[base + 2] = w > 0 ? w : 0;
      geom[base + 3] = h > 0 ? h : 0;
    }

    if (_isEditing) {
      maxScrollExtent += isVertical ? slotHeight : slotWidth;
    }

    // 4. Determine Visible Window
    final targetStart = constraints.scrollOffset + constraints.cacheOrigin;
    final targetEnd = constraints.scrollOffset + constraints.remainingCacheExtent;

    // 5. Find Visible Index Range
    var minVisibleIndex = _items.length;
    var maxVisibleIndex = -1;

    for (var i = 0; i < itemCount; i++) {
      final base = i * 4;
      final itemStart = isVertical ? geom[base + 1] : geom[base];
      final itemEnd = itemStart + (isVertical ? geom[base + 3] : geom[base + 2]);
      if (itemEnd >= targetStart && itemStart <= targetEnd) {
        if (i < minVisibleIndex) minVisibleIndex = i;
        if (i > maxVisibleIndex) maxVisibleIndex = i;
      }
    }

    if (maxVisibleIndex < minVisibleIndex) {
      minVisibleIndex = 0;
      maxVisibleIndex = -1;
    }

    // 6. Garbage Collection
    var leadingGarbage = 0;
    var trailingGarbage = 0;

    if (firstChild != null) {
      final firstChildIndex = indexOf(firstChild!);
      final lastChildIndex = indexOf(lastChild!);

      final int lastRemoveIndex = min(lastChildIndex, minVisibleIndex - 1);
      if (lastRemoveIndex >= firstChildIndex) {
        leadingGarbage = lastRemoveIndex - firstChildIndex + 1;
      }

      final int firstRemoveIndex = max(firstChildIndex, maxVisibleIndex + 1);
      if (firstRemoveIndex <= lastChildIndex) {
        trailingGarbage = lastChildIndex - firstRemoveIndex + 1;
      }

      collectGarbage(leadingGarbage, trailingGarbage);
    }

    // 7. Layout Children & Fill Gaps

    // Case A: No children exist yet (fresh start or after full GC).
    if (firstChild == null) {
      if (minVisibleIndex <= maxVisibleIndex) {
        final base = minVisibleIndex * 4;
        final initialOffset = isVertical ? geom[base + 1] : geom[base];
        if (addInitialChild(index: minVisibleIndex, layoutOffset: initialOffset)) {
          final childParentData = firstChild?.parentData;
          if (childParentData is SliverDashboardParentData) {
            _applyChildGeometry(
              childParentData,
              minVisibleIndex,
              geom[base],
              geom[base + 1],
              initialOffset,
              animatePass: animatePass,
            );
          }
        }
      }
    }

    // Case B: Fill Leading (Before firstChild)
    // We do this before the main loop to ensure we start at minVisibleIndex
    var leadingChild = firstChild;
    while (leadingChild != null && indexOf(leadingChild) > minVisibleIndex) {
      final index = indexOf(leadingChild) - 1;
      final base = index * 4;
      final childConstraints =
          BoxConstraints.tightFor(width: geom[base + 2], height: geom[base + 3]);

      final newChild = insertAndLayoutLeadingChild(childConstraints, parentUsesSize: true);
      final childParentData = newChild?.parentData;
      if (newChild == null || childParentData is! SliverDashboardParentData) break;

      _applyChildGeometry(
        childParentData,
        index,
        geom[base],
        geom[base + 1],
        isVertical ? geom[base + 1] : geom[base],
        animatePass: animatePass,
      );

      leadingChild = newChild;
    }

    // Case C: Fill Gaps & Trailing (From firstChild onwards)
    // This single loop handles both filling gaps in the middle and extending to the end.
    var child = firstChild;
    while (child != null) {
      // 1. Layout current child
      final index = indexOf(child);
      final base = index * 4;
      final childParentData = child.parentData;
      if (childParentData is SliverDashboardParentData) {
        _applyChildGeometry(
          childParentData,
          index,
          geom[base],
          geom[base + 1],
          isVertical ? geom[base + 1] : geom[base],
          animatePass: animatePass,
        );
      }
      child.layout(
        BoxConstraints.tightFor(width: geom[base + 2], height: geom[base + 3]),
        parentUsesSize: true,
      );

      // 2. Check for Gap after this child
      // If this is the last child, we check up to maxVisibleIndex.
      // If there is a next child, we check up to its index.
      final nextChild = childAfter(child);
      final nextIndex = nextChild == null ? maxVisibleIndex + 1 : indexOf(nextChild);

      if (nextIndex > index + 1) {
        // Gap detected! Insert missing children.
        var insertIndex = index + 1;
        var previousChild = child;

        while (insertIndex < nextIndex) {
          final insertBase = insertIndex * 4;
          final insertConstraints = BoxConstraints.tightFor(
            width: geom[insertBase + 2],
            height: geom[insertBase + 3],
          );
          final newChild =
              insertAndLayoutChild(insertConstraints, after: previousChild, parentUsesSize: true);

          if (newChild == null) break; // Should not happen

          final newParentData = newChild.parentData;
          if (newParentData is SliverDashboardParentData) {
            _applyChildGeometry(
              newParentData,
              insertIndex,
              geom[insertBase],
              geom[insertBase + 1],
              isVertical ? geom[insertBase + 1] : geom[insertBase],
              animatePass: animatePass,
            );
          }

          previousChild = newChild;
          insertIndex++;
        }
        // After filling the gap, the 'nextChild' (if it existed) is still valid
        // and will be processed in the next iteration of the outer loop.
        // If nextChild was null, we just filled up to maxVisibleIndex and we are done.
      }

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

    // Publish exact metrics for consumers outside the render tree (minimap
    // viewport segment). Plain field writes on the controller — never a
    // beacon: we are inside the layout phase.
    onLayoutMetrics?.call(
      constraints.precedingScrollExtent,
      geometry!.scrollExtent,
      slotWidth,
      slotHeight,
    );

    if (_animateReflow && _transitions.isNotEmpty) {
      _startReflowTicker();
    }

    if (stopwatch != null) {
      stopwatch.stop();
      onPerformLayout?.call(stopwatch.elapsed);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (firstChild == null) return;
    final isVertical = scrollDirection == Axis.vertical;
    // Reflow interpolation is a pure paint-offset substitution: layout,
    // hit-testing and semantics already sit at the final coordinates; only
    // the painted position of a sliding tile lags by <= reflowDuration. Each
    // tile is a RepaintBoundary, so painting the cached layer at a shifted
    // offset is a GPU layer translation — equivalent to a Matrix4.translate
    // without allocating a TransformLayer per child per frame.
    final animating = _animateReflow && _transitions.isNotEmpty;

    var child = firstChild;
    while (child != null) {
      final childParentData = child.parentData;
      if (childParentData is! SliverDashboardParentData) break;

      var paintX = childParentData.paintOffset.dx;
      var paintY = childParentData.paintOffset.dy;

      if (animating) {
        final index = childParentData.index;
        if (index != null && index >= 0 && index < _items.length) {
          final t = _transitions[_items[index].id];
          if (t != null) {
            final p = _transitionProgress(t);
            if (p < 1) {
              paintX = t.fromX + (t.toX - t.fromX) * p;
              paintY = t.fromY + (t.toY - t.fromY) * p;
            }
          }
        }
      }

      // Cull against the *visual* main-axis position so a tile sliding in
      // from a currently invisible slot does not pop.
      final mainAxisPos = isVertical ? paintY : paintX;

      if (mainAxisPos + (isVertical ? child.size.height : child.size.width) >=
              constraints.scrollOffset &&
          mainAxisPos <= constraints.scrollOffset + constraints.remainingPaintExtent) {
        final Offset finalPaintOffset;
        if (isVertical) {
          finalPaintOffset = offset +
              Offset(
                paintX,
                paintY - constraints.scrollOffset,
              );
        } else {
          finalPaintOffset = offset +
              Offset(
                paintX - constraints.scrollOffset,
                paintY,
              );
        }
        context.paintChild(child, finalPaintOffset);
      }
      child = childAfter(child);
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (_transitions.isNotEmpty) _startReflowTicker();
  }

  @override
  void detach() {
    _stopReflowTicker();
    super.detach();
  }

  @override
  void dispose() {
    _stopReflowTicker();
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
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

class _DefaultSectionHeader extends StatelessWidget {
  const _DefaultSectionHeader({required this.item});

  final LayoutItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Text(
          item.sectionTitle ?? 'Section',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// Mutable per-tile slide state for the paint-phase reflow animation.
///
/// Mutated in place on retarget so a sustained drag (a cell crossing every
/// few frames) allocates at most one instance per pushed tile.
class _ReflowTransition {
  _ReflowTransition({
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
    required this.startUs,
  });

  double fromX;
  double fromY;
  double toX;
  double toY;
  int startUs;
}
