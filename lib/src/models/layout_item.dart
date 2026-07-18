import 'package:flutter/foundation.dart';

/// Defines how new items with undefined coordinates (x: -1, y: -1)
/// are automatically positioned in the grid.
enum AutoPlacementStrategy {
  /// Appends new items strictly below the bottom-most coordinate of the current layout.
  appendBottom,

  /// Searches from the top-left (0,0) down to find the first gap where the item fits.
  firstFit,
}

/// A list of [LayoutItem]s representing the entire grid layout.
typedef Layout = List<LayoutItem>;

/// A single, immutable source of truth for a dashboard item's properties.
///
/// It represents the grid position (`x`, `y`), dimensions (`w`, `h`),
/// constraints, and behavior flags (`isStatic`, `isDraggable`, etc.).
@immutable
class LayoutItem {
  /// Creates a new [LayoutItem].
  const LayoutItem({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.minW = 1,
    this.minH = 1,
    this.maxW = double.infinity,
    this.maxH = double.infinity,
    this.isDraggable,
    this.isResizable,
    bool isStatic = false,
    this.moved = false,
    this.isSectionBarrier = false,
    this.sectionTitle,
    this.hasNestedGrid = false,
  }) : isStatic =
            isStatic || isSectionBarrier; // Ensure section barriers are always static in-memory

  /// Creates a [LayoutItem] from a JSON-serializable map.
  factory LayoutItem.fromMap(Map<String, dynamic> map) {
    return LayoutItem(
      // ID is mandatory. If missing, we throw, or generate a fallback.
      // Throwing is safer to detect data corruption early.
      id: map['id'] as String,
      // Use 'num' to safely handle '1' (int) or '1.0' (double) from JSON
      x: (map['x'] as num?)?.toInt() ?? 0,
      y: (map['y'] as num?)?.toInt() ?? 0,
      w: (map['w'] as num?)?.toInt() ?? 1,
      h: (map['h'] as num?)?.toInt() ?? 1,
      minW: (map['minW'] as num?)?.toInt() ?? 1,
      minH: (map['minH'] as num?)?.toInt() ?? 1,
      // JSON doesn't support Infinity. Usually represented as null.
      maxW: (map['maxW'] as num?)?.toDouble() ?? double.infinity,
      maxH: (map['maxH'] as num?)?.toDouble() ?? double.infinity,
      isDraggable: map['isDraggable'] as bool?,
      isResizable: map['isResizable'] as bool?,
      isStatic: map['isStatic'] as bool? ?? false,
      moved: map['moved'] as bool? ?? false,
      isSectionBarrier: map['isSectionBarrier'] as bool? ?? false,
      sectionTitle: map['sectionTitle'] as String?,
      hasNestedGrid: map['hasNestedGrid'] as bool? ?? false,
    );
  }

  /// Converts the [LayoutItem] to a JSON-serializable map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'x': x,
      'y': y,
      'w': w,
      'h': h,
      'minW': minW,
      'minH': minH,
      // Map Infinity to null for valid JSON
      'maxW': maxW.isInfinite ? null : maxW,
      'maxH': maxH.isInfinite ? null : maxH,
      'isDraggable': isDraggable,
      'isResizable': isResizable,
      'isStatic': isStatic || isSectionBarrier,
      'moved': moved,
      'isSectionBarrier': isSectionBarrier,
      'sectionTitle': sectionTitle,
      'hasNestedGrid': hasNestedGrid,
    };
  }

  /// Returns a hash code representing the visual content of the item.
  /// This excludes position (x, y) and transient state (moved).
  /// Used to determine if the widget needs to be rebuilt.
  int get contentSignature => Object.hash(
        id,
        w,
        h,
        minW,
        minH,
        maxW,
        maxH,
        isDraggable,
        isResizable,
        isStatic || isSectionBarrier,
        isSectionBarrier,
        sectionTitle,
        hasNestedGrid,
      );

  /// Creates a new [LayoutItem] with updated properties.
  LayoutItem copyWith({
    String? id,
    int? x,
    int? y,
    int? w,
    int? h,
    int? minW,
    int? minH,
    double? maxW,
    double? maxH,
    bool? isDraggable,
    bool? isResizable,
    bool? isStatic,
    bool? moved,
    bool? isSectionBarrier,
    String? sectionTitle,
    bool? hasNestedGrid,
  }) {
    return LayoutItem(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
      w: w ?? this.w,
      h: h ?? this.h,
      minW: minW ?? this.minW,
      minH: minH ?? this.minH,
      maxW: maxW ?? this.maxW,
      maxH: maxH ?? this.maxH,
      isDraggable: isDraggable ?? this.isDraggable,
      isResizable: isResizable ?? this.isResizable,
      isStatic: isStatic ?? this.isStatic,
      moved: moved ?? this.moved,
      isSectionBarrier: isSectionBarrier ?? this.isSectionBarrier,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      hasNestedGrid: hasNestedGrid ?? this.hasNestedGrid,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          x == other.x &&
          y == other.y &&
          w == other.w &&
          h == other.h &&
          minW == other.minW &&
          minH == other.minH &&
          maxW == other.maxW &&
          maxH == other.maxH &&
          isDraggable == other.isDraggable &&
          isResizable == other.isResizable &&
          (isStatic || isSectionBarrier) == (other.isStatic || other.isSectionBarrier) &&
          moved == other.moved &&
          isSectionBarrier == other.isSectionBarrier &&
          sectionTitle == other.sectionTitle &&
          hasNestedGrid == other.hasNestedGrid;

  @override
  int get hashCode => Object.hash(
        id,
        x,
        y,
        w,
        h,
        minW,
        minH,
        maxW,
        maxH,
        isDraggable,
        isResizable,
        isStatic || isSectionBarrier,
        moved,
        isSectionBarrier,
        sectionTitle,
        hasNestedGrid,
      );

  @override
  String toString() {
    return 'LayoutItem(id: $id, x: $x, y: $y, w: $w, h: $h, isStatic: $isStatic)';
  }

  /// The unique identifier for the layout item.
  final String id;

  /// The x-coordinate of the item in grid units.
  final int x;

  /// The y-coordinate of the item in grid units.
  final int y;

  /// The width of the item in grid units.
  final int w;

  /// The height of the item in grid units.
  final int h;

  /// The minimum width of the item in grid units. Defaults to 1.
  final int minW;

  /// The minimum height of the item in grid units. Defaults to 1.
  final int minH;

  /// The maximum width of the item in grid units. Defaults to [double.infinity].
  final double maxW;

  /// The maximum height of the item in grid units. Defaults to [double.infinity].
  final double maxH;

  /// If true, the item can be dragged. Overrides the layout's `isDraggable`.
  final bool? isDraggable;

  /// If true, the item can be resized. Overrides the layout's `isResizable`.
  final bool? isResizable;

  /// If true, the item is static and cannot be moved or resized by user interaction.
  /// It also won't be moved by compaction or collisions.
  final bool isStatic;

  /// A flag to indicate if the item has been moved during a drag operation.
  ///
  /// This is used internally by the layout engine to prevent infinite loops
  /// in collision resolution.
  final bool moved;

  /// Whether this item represents a static visual section barrier (header).
  ///
  /// If true, the item automatically behaves as an immoveable static divider
  /// that visually splits the grid into segments.
  final bool isSectionBarrier;

  /// The text title of the section if [isSectionBarrier] is true.
  final String? sectionTitle;

  /// Whether this item hosts a nested dashboard (a `NestedDashboard` in its
  /// content).
  ///
  /// Declarative metadata for the application: it lets a shared `itemBuilder`
  /// branch generically (`if (item.hasNestedGrid) return NestedDashboard(...)`)
  /// — which is what makes a whole group portable between grids without id
  /// coupling — travels through plain toMap/fromMap round-trips, and can
  /// be targeted by `DashboardPolicy` rules. The nested layer also uses it to
  /// skip `subGridDynamic` arming on items that already host a grid.
  ///
  /// Included in [contentSignature]: converting an item to or from a grid
  /// host changes its content and must invalidate the cached item widget.
  final bool hasNestedGrid;
}
