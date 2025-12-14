import 'dart:collection';
import 'dart:math';

import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/models/utility.dart';

/// Defines the compaction strategy for the layout.
enum CompactType {
  /// No compression
  none,

  /// Compresses the layout vertically.
  vertical,

  /// Compresses the layout horizontally.
  horizontal,
}

/// Defines the behavior of items when a resize operation causes a collision.
enum ResizeBehavior {
  /// Colliding items are pushed downwards to make space.
  push,

  /// Colliding items are shrunk to make space, if possible.
  shrink,
}

/// A strategy delegate for compacting the layout and resolving collisions.
///
/// Implement this interface to create custom layout behaviors (e.g. Tetris-like,
/// Gravity-based, or fixed-position layouts).
abstract class CompactorDelegate {
  /// Constructor for [CompactorDelegate].
  const CompactorDelegate();

  /// Compacts the layout by removing gaps according to specific rules.
  List<LayoutItem> compact(
    List<LayoutItem> layout,
    int cols, {
    bool allowOverlap = false,
  });

  /// Resolves overlaps by pushing items without necessarily compacting (pulling back).
  /// Used primarily during drag operations to ensure validity without fighting the user.
  List<LayoutItem> resolveCollisions(
    List<LayoutItem> layout,
    int cols,
  );
}

// ============================================================================
// DEFAULT IMPLEMENTATIONS
// ============================================================================

/// Default vertical compaction (Gravity pulls up).
class VerticalCompactor extends CompactorDelegate {
  /// Creates a new [VerticalCompactor].
  const VerticalCompactor();

  @override
  List<LayoutItem> compact(
    List<LayoutItem> layout,
    int cols, {
    bool allowOverlap = false,
  }) {
    if (allowOverlap) return List.from(layout);

    final compareWith = getStatics(layout).toList();
    final sorted = sortLayoutItems(layout, CompactType.vertical);
    final out = List<LayoutItem?>.filled(layout.length, null);

    for (final l in sorted) {
      var newL = l;
      if (!l.isStatic) {
        newL = _compactItemVertical(compareWith, l, cols, sorted);
        compareWith.add(newL);
      }

      final index = layout.indexWhere((item) => item.id == l.id);
      if (newL.x == l.x && newL.y == l.y && !l.moved) {
        out[index] = l;
      } else {
        out[index] = newL.copyWith(moved: false);
      }
    }
    return out.whereType<LayoutItem>().toList();
  }

  @override
  List<LayoutItem> resolveCollisions(List<LayoutItem> layout, int cols) {
    return _resolveCollisionsDefault(layout, CompactType.vertical);
  }

  LayoutItem _compactItemVertical(
    List<LayoutItem> compareWith,
    LayoutItem l,
    int cols,
    List<LayoutItem> fullLayout,
  ) {
    var currentItem = l;

    // Move up
    while (currentItem.y > 0 && getFirstCollision(compareWith, currentItem) == null) {
      currentItem = currentItem.copyWith(y: currentItem.y - 1);
    }

    // Resolve collisions by moving down
    LayoutItem? collidesWith;
    while ((collidesWith = getFirstCollision(compareWith, currentItem)) != null) {
      currentItem = resolveCompactionCollision(
        fullLayout,
        currentItem,
        collidesWith!.y + collidesWith.h,
        'y',
      );
    }

    return currentItem.copyWith(y: max(currentItem.y, 0));
  }
}

/// Horizontal compaction (Gravity pulls left).
class HorizontalCompactor extends CompactorDelegate {
  /// Creates a new [HorizontalCompactor].
  const HorizontalCompactor();

  @override
  List<LayoutItem> compact(
    List<LayoutItem> layout,
    int cols, {
    bool allowOverlap = false,
  }) {
    if (allowOverlap) return List.from(layout);

    final compareWith = getStatics(layout).toList();
    final sorted = sortLayoutItems(layout, CompactType.horizontal);
    final out = List<LayoutItem?>.filled(layout.length, null);

    for (final l in sorted) {
      var newL = l;
      if (!l.isStatic) {
        newL = _compactItemHorizontal(compareWith, l, cols, sorted);
        compareWith.add(newL);
      }

      final index = layout.indexWhere((item) => item.id == l.id);
      if (newL.x == l.x && newL.y == l.y && !l.moved) {
        out[index] = l;
      } else {
        out[index] = newL.copyWith(moved: false);
      }
    }
    return out.whereType<LayoutItem>().toList();
  }

  @override
  List<LayoutItem> resolveCollisions(List<LayoutItem> layout, int cols) {
    return _resolveCollisionsDefault(layout, CompactType.horizontal);
  }

  LayoutItem _compactItemHorizontal(
    List<LayoutItem> compareWith,
    LayoutItem l,
    int cols,
    List<LayoutItem> fullLayout,
  ) {
    var currentItem = l;

    // 1. Move left as far as possible
    while (currentItem.x > 0 && getFirstCollision(compareWith, currentItem) == null) {
      currentItem = currentItem.copyWith(x: currentItem.x - 1);
    }

    // 2. Resolve collisions AND overflows
    while (true) {
      final collidesWith = getFirstCollision(compareWith, currentItem);

      if (collidesWith != null) {
        // Collision: Push right
        currentItem = resolveCompactionCollision(
          fullLayout,
          currentItem,
          collidesWith.x + collidesWith.w,
          'x',
        );
      }

      // Check Overflow (Always check, even if no collision yet)
      if (currentItem.x + currentItem.w > cols) {
        // Wrap to next row, reset X to 0
        currentItem = currentItem.copyWith(x: 0, y: currentItem.y + 1);

        // Since we moved to a new position (new row), we must re-check collisions.
        // We continue the loop.
        continue;
      }

      // If we are here, it means:
      // 1. We fit within bounds.
      // 2. We didn't collide in this iteration (or we resolved it and fit).
      if (collidesWith == null) {
        break;
      }
    }

    return currentItem.copyWith(x: max(currentItem.x, 0));
  }
}

/// No compaction (Free movement), but resolves overlaps.
class NoCompactor extends CompactorDelegate {
  /// Creates a new [NoCompactor].
  const NoCompactor();

  @override
  List<LayoutItem> compact(
    List<LayoutItem> layout,
    int cols, {
    bool allowOverlap = false,
  }) {
    // In "None" mode, we don't pull items back.
    // We just ensure no overlaps if requested.
    if (allowOverlap) return List.from(layout);

    // We use vertical resolution by default for "None" to prevent stacking
    return _resolveCollisionsDefault(layout, CompactType.vertical);
  }

  @override
  List<LayoutItem> resolveCollisions(List<LayoutItem> layout, int cols) {
    return _resolveCollisionsDefault(layout, CompactType.vertical);
  }
}

/// A high-performance vertical compactor using the "Rising Tide" (Skyline) algorithm.
/// Complexity: O(N) roughly, instead of O(N^2).
class FastVerticalCompactor extends CompactorDelegate {
  /// Creates a new [FastVerticalCompactor].
  const FastVerticalCompactor();

  @override
  List<LayoutItem> compact(
    List<LayoutItem> layout,
    int cols, {
    bool allowOverlap = false,
  }) {
    // 1. Clone and Sort
    // We need a mutable list to sort, but items remain immutable until we replace them.
    final sorted = List<LayoutItem>.from(layout)
      ..sort((a, b) {
        // Sort by Y, then X
        if (a.y != b.y) return a.y.compareTo(b.y);
        if (a.x != b.x) return a.x.compareTo(b.x);
        // Static first to act as anchors
        if (a.isStatic && !b.isStatic) return -1;
        if (!a.isStatic && b.isStatic) return 1;
        return 0;
      });

    // 2. Initialize Tide (Skyline)
    // tide[x] = the lowest free Y coordinate in column x
    final tide = List<int>.filled(cols, 0);

    final out = <LayoutItem>[];

    // Separate statics for collision check optimization
    final statics = sorted.where((i) => i.isStatic).toList();
    // Index tracker for statics (optimization from the TS algo)
    var staticOffset = 0;

    for (final item in sorted) {
      // If item is static, it stays put, but updates the tide.
      if (item.isStatic) {
        _updateTide(tide, item, cols);
        out.add(item);
        staticOffset++; // Advance static cursor
        continue;
      }

      // --- DYNAMIC ITEM PLACEMENT ---

      // 1. Find the highest point in the tide for the item's width
      var y = 0;
      final xEnd = min(item.x + item.w, cols);

      for (var x = item.x; x < xEnd; x++) {
        if (tide[x] > y) {
          y = tide[x];
        }
      }

      // "y" is now the candidate position (snapped to the tide)

      // 2. Resolve collisions with Static items
      // The TS algo moves the item DOWN if it hits a static item.
      if (!allowOverlap) {
        // We iterate through statics that are potentially below our candidate Y
        var j = staticOffset;
        while (j < statics.length) {
          final staticItem = statics[j];

          // Check collision manually since we haven't created the object yet
          if (collidesWithCoords(item, y, staticItem)) {
            // Collision! Push below the static item
            y = staticItem.y + staticItem.h;

            // Reset search because by moving down, we might now collide
            // with a static item we previously skipped or haven't reached.
            j = staticOffset;
          } else {
            j++;
          }
        }
      }

      // 3. Create the moved item
      final newItem = item.copyWith(y: y, moved: false); // Reset moved flag
      out.add(newItem);

      // 4. Update Tide
      _updateTide(tide, newItem, cols);
    }

    return out;
  }

  void _updateTide(List<int> tide, LayoutItem item, int cols) {
    final bottom = item.y + item.h;
    final xEnd = min(item.x + item.w, cols);
    for (var x = item.x; x < xEnd; x++) {
      // In Rising Tide, the tide always goes UP (or stays same).
      // We set the tide to the bottom of this item.
      if (tide[x] < bottom) {
        tide[x] = bottom;
      }
    }
  }

  /// Helper to check collision without creating a LayoutItem instance
  bool collidesWithCoords(LayoutItem dynamicItem, int dynamicY, LayoutItem staticItem) {
    if (dynamicItem.x + dynamicItem.w <= staticItem.x) return false;
    if (dynamicItem.x >= staticItem.x + staticItem.w) return false;
    if (dynamicY + dynamicItem.h <= staticItem.y) return false;
    if (dynamicY >= staticItem.y + staticItem.h) return false;
    return true;
  }

  @override
  List<LayoutItem> resolveCollisions(List<LayoutItem> layout, int cols) {
    // For drag operations, we can keep the default implementation
    // or implement a "Fast Push" if needed.
    // For now, let's reuse the default one as it's robust for user interaction.
    return const VerticalCompactor().resolveCollisions(layout, cols);
  }
}

/// A high-performance horizontal compactor using the "Rising Tide" (Skyline) algorithm.
/// Gravity pulls items to the LEFT.
class FastHorizontalCompactor extends CompactorDelegate {
  /// Creates a new [FastHorizontalCompactor].
  const FastHorizontalCompactor();

  @override
  List<LayoutItem> compact(
    List<LayoutItem> layout,
    int rows, {
    // 'cols' param actually means 'crossAxisCount', so here it is rows
    bool allowOverlap = false,
  }) {
    // 1. Clone and Sort
    final sorted = List<LayoutItem>.from(layout)
      ..sort((a, b) {
        // Sort by X (Main Axis), then Y (Cross Axis)
        if (a.x != b.x) return a.x.compareTo(b.x);
        if (a.y != b.y) return a.y.compareTo(b.y);

        // Static first
        if (a.isStatic && !b.isStatic) return -1;
        if (!a.isStatic && b.isStatic) return 1;
        return 0;
      });

    // 2. Initialize Tide (Skyline)
    // tide[y] = the lowest free X coordinate in row y
    final tide = List<int>.filled(rows, 0);

    final out = <LayoutItem>[];
    final statics = sorted.where((i) => i.isStatic).toList();
    var staticOffset = 0;

    for (final item in sorted) {
      if (item.isStatic) {
        _updateTide(tide, item, rows);
        out.add(item);
        staticOffset++;
        continue;
      }

      // --- DYNAMIC ITEM PLACEMENT ---

      // 1. Find the furthest X in the tide for the item's height (rows spanned)
      var x = 0;
      // We check rows from item.y to item.y + item.h
      final yEnd = min(item.y + item.h, rows);

      for (var y = item.y; y < yEnd; y++) {
        if (tide[y] > x) {
          x = tide[y];
        }
      }

      // "x" is now the candidate position

      // 2. Resolve collisions with Static items (Push Right)
      if (!allowOverlap) {
        var j = staticOffset;
        while (j < statics.length) {
          final staticItem = statics[j];

          if (collidesWithCoords(item, x, staticItem)) {
            // Collision! Push to the right of the static item
            x = staticItem.x + staticItem.w;
            j = staticOffset; // Reset search
          } else {
            j++;
          }
        }
      }

      // 3. Create the moved item
      final newItem = item.copyWith(x: x, moved: false);
      out.add(newItem);

      // 4. Update Tide
      _updateTide(tide, newItem, rows);
    }

    return out;
  }

  void _updateTide(List<int> tide, LayoutItem item, int rows) {
    final right = item.x + item.w;
    final yEnd = min(item.y + item.h, rows);

    for (var y = item.y; y < yEnd; y++) {
      // The tide always goes RIGHT (increases X).
      if (tide[y] < right) {
        tide[y] = right;
      }
    }
  }

  /// Helper to check collision (Horizontal logic: we test candidate X)
  bool collidesWithCoords(LayoutItem dynamicItem, int dynamicX, LayoutItem staticItem) {
    if (dynamicX + dynamicItem.w <= staticItem.x) return false;
    if (dynamicX >= staticItem.x + staticItem.w) return false;
    if (dynamicItem.y + dynamicItem.h <= staticItem.y) return false;
    if (dynamicItem.y >= staticItem.y + staticItem.h) return false;
    return true;
  }

  @override
  List<LayoutItem> resolveCollisions(List<LayoutItem> layout, int cols) {
    // Reuse standard resolution for drag interactions
    return const HorizontalCompactor().resolveCollisions(layout, cols);
  }
}

// ============================================================================
// SHARED LOGIC & HELPERS (Exposed for Custom Compactors)
// ============================================================================

/// Returns the bottom-most coordinate of the layout.
int bottom(Layout layout) {
  var max = 0;
  for (final item in layout) {
    final bottomY = item.y + item.h;
    if (bottomY > max) {
      max = bottomY;
    }
  }
  return max;
}

/// Sorts layout items based on the compaction type.
List<LayoutItem> sortLayoutItems(Layout layout, CompactType compactType) {
  final newLayout = List<LayoutItem>.from(layout);
  if (compactType == CompactType.horizontal) {
    newLayout.sort((a, b) {
      if (a.x > b.x || (a.x == b.x && a.y > b.y)) {
        return 1;
      } else if (a.x == b.x && a.y == b.y) {
        return 0;
      }
      return -1;
    });
  } else {
    newLayout.sort((a, b) {
      if (a.y > b.y || (a.y == b.y && a.x > b.x)) {
        return 1;
      } else if (a.y == b.y && a.x == b.x) {
        return 0;
      }
      return -1;
    });
  }
  return newLayout;
}

/// Checks if two layout items collide.
bool collides(LayoutItem l1, LayoutItem l2) {
  if (l1.id == l2.id) return false;
  if (l1.x + l1.w <= l2.x) return false;
  if (l1.x >= l2.x + l2.w) return false;
  if (l1.y + l1.h <= l2.y) return false;
  if (l1.y >= l2.y + l2.h) return false;
  return true;
}

/// Gets the first item in the layout that collides with the given item.
LayoutItem? getFirstCollision(Layout layout, LayoutItem layoutItem) {
  for (final item in layout) {
    if (collides(item, layoutItem)) {
      return item;
    }
  }
  return null;
}

/// Gets all items in the layout that collide with the given item.
List<LayoutItem> getAllCollisions(Layout layout, LayoutItem layoutItem) {
  final collisions = <LayoutItem>[];
  final targetLeft = layoutItem.x;
  final targetRight = layoutItem.x + layoutItem.w;
  final targetTop = layoutItem.y;
  final targetBottom = layoutItem.y + layoutItem.h;
  final targetId = layoutItem.id;

  for (final item in layout) {
    if (item.id == targetId) continue;
    if (targetRight <= item.x) continue;
    if (targetLeft >= item.x + item.w) continue;
    if (targetBottom <= item.y) continue;
    if (targetTop >= item.y + item.h) continue;
    collisions.add(item);
  }
  return collisions;
}

/// Returns a list of all static items in the layout.
List<LayoutItem> getStatics(Layout layout) {
  return layout.where((item) => item.isStatic).toList();
}

/// Recursively resolves collisions during compaction by moving items down/right.
/// Exposed for custom compactors.
LayoutItem resolveCompactionCollision(
  Layout layout,
  LayoutItem item,
  int moveToCoord,
  String axis,
) {
  var currentItem = item;
  final sizeProp = axis == 'x' ? currentItem.w : currentItem.h;
  currentItem = currentItem.copyWith(
    x: axis == 'x' ? currentItem.x + 1 : currentItem.x,
    y: axis == 'y' ? currentItem.y + 1 : currentItem.y,
  );

  final itemIndex = layout.indexWhere((element) => element.id == currentItem.id);

  for (var i = itemIndex + 1; i < layout.length; i++) {
    final otherItem = layout[i];
    if (otherItem.isStatic) continue;

    if (collides(currentItem, otherItem)) {
      resolveCompactionCollision(layout, otherItem, moveToCoord + sizeProp, axis);
    }
  }

  return currentItem.copyWith(
    x: axis == 'x' ? moveToCoord : currentItem.x,
    y: axis == 'y' ? moveToCoord : currentItem.y,
  );
}

// --- Internal Helper for Default Collision Resolution ---
List<LayoutItem> _resolveCollisionsDefault(List<LayoutItem> layout, CompactType compactType) {
  final items = List<LayoutItem>.from(layout);
  final isHorizontal = compactType == CompactType.horizontal;

  items.sort((a, b) {
    if (isHorizontal) {
      if (a.x != b.x) return a.x.compareTo(b.x);
      return a.y.compareTo(b.y);
    } else {
      if (a.y != b.y) return a.y.compareTo(b.y);
      return a.x.compareTo(b.x);
    }
  });

  final processed = <LayoutItem>[];

  for (var i = 0; i < items.length; i++) {
    var current = items[i];
    if (current.isStatic) {
      processed.add(current);
      continue;
    }

    var hasCollision = true;
    var safety = 0;

    while (hasCollision && safety < 1000) {
      hasCollision = false;
      for (final obstacle in processed) {
        if (collides(current, obstacle)) {
          if (isHorizontal) {
            current = current.copyWith(x: obstacle.x + obstacle.w);
          } else {
            current = current.copyWith(y: obstacle.y + obstacle.h);
          }
          hasCollision = true;
          break;
        }
      }
      safety++;
    }
    processed.add(current);
  }
  return processed;
}

// ============================================================================
// LEGACY API (Forwarding to Delegates)
// ============================================================================

/// Compacts the layout.
///
/// This function now delegates to the appropriate [CompactorDelegate].
List<LayoutItem> compact(
  List<LayoutItem> layout,
  CompactType compactType,
  int cols, {
  bool allowOverlap = false,
}) {
  final delegate = _getDelegate(compactType);
  return delegate.compact(layout, cols, allowOverlap: allowOverlap);
}

/// Resolves collisions.
///
/// This function now delegates to the appropriate [CompactorDelegate].
List<LayoutItem> resolveCollisions(List<LayoutItem> layout, CompactType compactType) {
  final delegate = _getDelegate(compactType);
  return delegate.resolveCollisions(layout, 10000);
}

CompactorDelegate _getDelegate(CompactType type) {
  switch (type) {
    case CompactType.vertical:
      return const VerticalCompactor();
    case CompactType.horizontal:
      return const HorizontalCompactor();
    case CompactType.none:
      return const NoCompactor();
  }
}

/// Compact a single item within the layout.
///
/// @deprecated Use compact() instead, which handles the full layout.
LayoutItem compactItem(
  List<LayoutItem> compareWith,
  LayoutItem l,
  CompactType compactType,
  int cols,
  List<LayoutItem> fullLayout,
) {
  final delegate = _getDelegate(compactType);
  if (delegate is VerticalCompactor) {
    return delegate._compactItemVertical(compareWith, l, cols, fullLayout);
  } else if (delegate is HorizontalCompactor) {
    return delegate._compactItemHorizontal(compareWith, l, cols, fullLayout);
  }
  return l;
}

/*
/// Compacts a single item in the layout.
///
/// This function moves the item up as much as possible without colliding with
/// other items.
LayoutItem compactItem(
  Layout compareWith,
  LayoutItem l,
  CompactType compactType,
  int cols,
  Layout fullLayout,
) {
  var currentItem = l;
  final compactV = compactType == CompactType.vertical;
  final compactH = compactType == CompactType.horizontal;

  if (compactV) {
    while (currentItem.y > 0 && getFirstCollision(compareWith, currentItem) == null) {
      currentItem = currentItem.copyWith(y: currentItem.y - 1);
    }
  } else if (compactH) {
    while (currentItem.x > 0 && getFirstCollision(compareWith, currentItem) == null) {
      currentItem = currentItem.copyWith(x: currentItem.x - 1);
    }
  }

  LayoutItem? collidesWith;
  while ((collidesWith = getFirstCollision(compareWith, currentItem)) != null) {
    if (compactH) {
      currentItem = resolveCompactionCollision(
        fullLayout,
        currentItem,
        collidesWith!.x + collidesWith.w,
        'x',
      );
    } else {
      currentItem = resolveCompactionCollision(
        fullLayout,
        currentItem,
        collidesWith!.y + collidesWith.h,
        'y',
      );
    }
    if (compactH && currentItem.x + currentItem.w > cols) {
      currentItem = currentItem.copyWith(x: cols - currentItem.w, y: currentItem.y + 1);
    }
  }

  return currentItem.copyWith(y: max(currentItem.y, 0), x: max(currentItem.x, 0));
}
*/

/// Corrects the bounds of the layout items to ensure they fit within the
/// specified number of columns.
Layout correctBounds(Layout layout, int cols) {
  final collidesWith = getStatics(layout).toList();
  final newLayout = <LayoutItem>[];

  for (final l in layout) {
    var currentL = l;
    if (currentL.x + currentL.w > cols) {
      currentL = currentL.copyWith(x: cols - currentL.w);
    }
    if (currentL.x < 0) {
      currentL = currentL.copyWith(x: 0, w: cols);
    }

    if (!currentL.isStatic) {
      collidesWith.add(currentL);
    } else {
      while (getFirstCollision(collidesWith, currentL) != null) {
        currentL = currentL.copyWith(y: currentL.y + 1);
      }
    }
    newLayout.add(currentL);
  }
  return newLayout;
}

/// Moves a single element in the layout.
///
/// This function is the core of the drag and drop logic. It moves the specified
/// item to the new coordinates and then resolves any collisions by pushing
/// other items down.
Layout moveElement(
  Layout layout,
  LayoutItem l,
  int? x,
  int? y, {
  required int cols,
  required CompactType compactType,
  bool isUserAction = false,
  bool preventCollision = false,
  bool force = false,
}) {
  if (l.isStatic) return layout;

  final oldX = l.x;
  final oldY = l.y;
  final newX = x ?? oldX;
  final newY = y ?? oldY;

  final movingItemInLayout = layout.firstWhereOrNull((item) => item.id == l.id) ?? l;

  if (!force &&
      oldX == newX &&
      oldY == newY &&
      l.w == movingItemInLayout.w &&
      l.h == movingItemInLayout.h) {
    return layout;
  }

  final itemWithNewPos = movingItemInLayout.copyWith(x: newX, y: newY, moved: true);

  // Use a Map for O(1) access
  final layoutMap = {for (final item in layout) item.id: item};
  layoutMap[l.id] = itemWithNewPos;

  final queue = ListQueue<LayoutItem>.from([itemWithNewPos]);
  final processed = <String>{itemWithNewPos.id};

  // SAFETY: Prevent infinite loops.
  // We allow visiting every item at least once, plus a safety margin.
  // If the loop exceeds this, it means we have a circular dependency bug.
  var safetyLoop = 0;
  final maxLoops = max(5000, layout.length * 2);

  // check AABB (Axis-Aligned Bounding Box).
  while (queue.isNotEmpty) {
    if (safetyLoop++ > maxLoops) {
      // Dart only, don't import flutter foundation
      // ignore_for_file: avoid_print
      print('SliverDashboard: Collision resolution limit reached ($maxLoops).');
      break;
    }

    final currentItem = queue.removeFirst();

    // Calc edges to avoid to repeat access to props
    final l = currentItem.x;
    final r = currentItem.x + currentItem.w;
    final t = currentItem.y;
    final b = currentItem.y + currentItem.h;

    final collisions = <LayoutItem>[];

    for (final other in layoutMap.values) {
      if (other.id == currentItem.id) continue;

      // Check AABB Inlined : If no overlap, continue
      if (r <= other.x || l >= other.x + other.w || b <= other.y || t >= other.y + other.h) {
        continue;
      }
      collisions.add(other);
    }

    // Sort required for stability (pushed from top to bottom)
    collisions.sort((a, b) => a.y.compareTo(b.y));

    for (final collision in collisions) {
      if (processed.contains(collision.id)) continue;

      if (collision.isStatic) {
        // Jump static
        final newY = collision.y + collision.h;
        final updatedCurrentItem = currentItem.copyWith(y: newY, moved: true);
        layoutMap[currentItem.id] = updatedCurrentItem;
        queue.addFirst(updatedCurrentItem);
        continue;
      }

      final itemToPush = layoutMap[collision.id];
      if (itemToPush == null) continue;

      processed.add(collision.id);

      // Push collided item to bottom
      final newY = currentItem.y + currentItem.h;
      if (collision.y >= newY) continue; // Already on bottom

      final pushedItem = itemToPush.copyWith(y: newY, moved: true);
      layoutMap[collision.id] = pushedItem;
      queue.add(pushedItem);
    }
  }

  final resultLayout = layoutMap.values.toList();

  // Prevent secondary overlaps while moving
  if (preventCollision) {
    // return resolveCollisions(resultLayout, compactType);
    return resolveCollisions(
      resultLayout,
      compactType == CompactType.none ? CompactType.vertical : compactType,
    );
  }

  return resultLayout;
}

/// A private helper function that attempts to resolve collisions by shrinking
/// the colliding items.
///
/// Returns the new layout if shrinking is successful, otherwise returns `null`.
Layout? _tryShrinkCollisions(
  Layout layout,
  LayoutItem resizedItem,
  List<LayoutItem> collisions,
) {
  final layoutMap = {for (final item in layout) item.id: item};

  for (final collision in collisions) {
    // This logic primarily handles horizontal shrinking.
    // A is resizing, B is the collision.
    // Case 1: A expands right, pushing B right.
    if (resizedItem.x < collision.x) {
      final overlap = (resizedItem.x + resizedItem.w) - collision.x;
      final newCollisionWidth = collision.w - overlap;

      if (newCollisionWidth >= collision.minW) {
        layoutMap[collision.id] = collision.copyWith(
          x: collision.x + overlap,
          w: newCollisionWidth,
        );
      } else {
        return null; // Shrink failed, minWidth violation.
      }
    }
    // Case 2: A expands left, shrinking B from the right.
    else {
      final overlap = (collision.x + collision.w) - resizedItem.x;
      final newCollisionWidth = collision.w - overlap;

      if (newCollisionWidth >= collision.minW) {
        layoutMap[collision.id] = collision.copyWith(w: newCollisionWidth);
      } else {
        return null; // Shrink failed, minWidth violation.
      }
    }
  }

  return layoutMap.values.toList();
}

/// Resize item. Implements the "try shrink, fallback to push" logic.
Layout resizeItem(
  Layout layout,
  LayoutItem itemToResize, {
  required ResizeBehavior behavior,
  required int cols,
  bool preventCollision = false,
}) {
  // Create a layout with the item at its new, desired size.
  final newLayout = layout.map((i) => i.id == itemToResize.id ? itemToResize : i).toList();

  // Find what collides with the item in its new, larger state.
  final otherItems = newLayout.where((i) => i.id != itemToResize.id).toList();
  final collisions = getAllCollisions(otherItems, itemToResize);

  // If no collisions, the resize is valid.
  if (collisions.isEmpty) {
    return newLayout;
  }

  // If collisions exist, handle based on behavior.
  if (behavior == ResizeBehavior.shrink) {
    // First, attempt to shrink the colliding items.
    final shrunkLayout = _tryShrinkCollisions(newLayout, itemToResize, collisions);

    // If shrinking was successful, return the result.
    if (shrunkLayout != null) {
      return shrunkLayout;
    }
    // If shrinking failed (returned null), we fall through to the push logic below.
  }

  // --- PUSH LOGIC (Default and Fallback) ---
  // If behavior is push, or if shrink failed, we push.
  // We must prevent collision for the drag/move, but not for the final placement
  if (preventCollision) {
    final pushedLayout = moveElement(
      newLayout,
      itemToResize,
      itemToResize.x,
      itemToResize.y,
      cols: cols,
      preventCollision: false, // Allow push to resolve collision
      compactType: CompactType.vertical,
      force: true,
    );

    // After pushing, check if the resized item itself illegally overlaps a static item.
    final finalResizedItem = pushedLayout.firstWhere((item) => item.id == itemToResize.id);
    final finalCollisions = getAllCollisions(pushedLayout, finalResizedItem);

    // If the resized item collides with any static item after the push, revert.
    if (finalCollisions.any((collision) => collision.isStatic)) {
      return layout; // Revert to original layout
    }

    // -------------------------------------------------------------------------
    // Resolve secondary overlaps.
    // When expanding, multiple items might be pushed to the exact same Y coordinate
    // (e.g. items 1 and 13 both pushed to y=2).
    // We run a compaction pass to force them to stack properly.
    // -------------------------------------------------------------------------
    return compact(
      pushedLayout,
      CompactType.vertical,
      cols,
      allowOverlap: false,
    );
  }

  return moveElement(
    newLayout,
    itemToResize,
    itemToResize.x,
    itemToResize.y,
    cols: cols,
    preventCollision: false,
    compactType: CompactType.vertical,
    force: true,
  );
}

/// Calculates valid positions for new items (where x or y is -1) by appending them
/// to the bottom of the existing layout.
///
/// This function is **pure** and suitable for use in Isolates or background threads.
/// It does not modify the input lists but returns a new list containing the merged result.
///
/// [existingLayout] The list of items already placed on the dashboard.
/// [newItems] The list of items to add. Some may already have positions, others may be -1.
/// [cols] The number of columns in the grid.
///
/// Returns a new list containing all items from [existingLayout] and [newItems],
/// with valid coordinates for everyone.
List<LayoutItem> placeNewItems({
  required List<LayoutItem> existingLayout,
  required List<LayoutItem> newItems,
  required int cols,
}) {
  // Separate items that need placement from those that don't
  final itemsToPlace = newItems.where((i) => i.x == -1 || i.y == -1).toList();
  final alreadyPlacedNewItems = newItems.where((i) => i.x != -1 && i.y != -1).toList();

  // Start with the existing layout plus any new items that already had fixed positions
  final finalLayout = <LayoutItem>[...existingLayout, ...alreadyPlacedNewItems];

  if (itemsToPlace.isEmpty) {
    return finalLayout;
  }

  // Start searching for space from the bottom of the current layout.
  // This ensures we append items instead of filling holes in the user's existing arrangement.
  var currentY = bottom(finalLayout);
  var currentX = 0;

  // SAFETY: Allow searching at least 1000 rows down, or 10k iterations minimum.
  final maxIterations = max(10000, cols * 1000);

  for (final item in itemsToPlace) {
    var placed = false;
    var safetyLoop = 0;

    // Try to find the first valid spot
    while (!placed && safetyLoop < maxIterations) {
      // 1. Check grid boundaries (Wrap to next row if needed)
      if (currentX + item.w > cols) {
        currentX = 0;
        currentY++;
        continue; // Retry at the start of the new row
      }

      // 2. Create a candidate item at the current position
      final candidate = item.copyWith(x: currentX, y: currentY);

      // 3. Check for collisions with all currently placed items
      var hasCollision = false;
      for (final existing in finalLayout) {
        if (collides(existing, candidate)) {
          hasCollision = true;
          break;
        }
      }

      if (!hasCollision) {
        // Valid spot found
        finalLayout.add(candidate);
        placed = true;
        // Advance cursor by the item's width to optimize the next search
        currentX += item.w;
      } else {
        // Collision detected, move cursor one slot to the right
        currentX++;
      }

      safetyLoop++;
    }
  }

  return finalLayout;
}

/// Optimizes the layout by compacting items to remove gaps,
/// respecting the visual order (top-left to bottom-right).
/// Static items act as obstacles and are not moved.
List<LayoutItem> optimizeLayout(List<LayoutItem> layout, int columns) {
  // 1. Separate Statics and Dynamics
  final statics = layout.where((i) => i.isStatic).toList();
  final dynamics = layout.where((i) => !i.isStatic).toList()

    // 2. Sort Dynamics by visual order (Row-major: Y then X)
    // This ensures we place the top-left-most items first, preserving the logical flow.
    ..sort((a, b) {
      if (a.y != b.y) return a.y.compareTo(b.y);
      return a.x.compareTo(b.x);
    });

  // 3. Initialize placed items with statics (obstacles)
  final placedItems = List<LayoutItem>.from(statics);

  // 4. Place each dynamic item in the first available spot
  for (final item in dynamics) {
    var placed = false;
    var y = 0;

    // Safety limit to prevent infinite loops if an item is wider than columns
    while (!placed && y < 10000) {
      // Try every column in this row
      for (var x = 0; x <= columns - item.w; x++) {
        final candidate = item.copyWith(x: x, y: y);

        // Check collision with ALL already placed items (statics + previously placed dynamics)
        var hasCollision = false;
        for (final obstacle in placedItems) {
          if (collides(candidate, obstacle)) {
            hasCollision = true;
            break;
          }
        }

        if (!hasCollision) {
          // Found a spot!
          placedItems.add(candidate);
          placed = true;
          break; // Stop checking X, move to next item
        }
      }
      if (!placed) {
        y++; // Try next row
      }
    }

    // Edge case: If item was too wide for the grid, it wasn't placed.
    // We add it at the end to avoid losing data, even if layout is broken.
    if (!placed) {
      placedItems.add(item.copyWith(y: bottom(placedItems)));
    }
  }

  // Safety Pass
  // We run resolveCollisions on the final result.
  // If the optimizer accidentally placed an item on top of a static item (overlap),
  // this function will detect it and push the dynamic item down, ensuring
  // a valid layout with zero overlaps.
  return resolveCollisions(placedItems, CompactType.vertical);
}

/// Calculates the bounding box of a group of items.
/// Returns a virtual [LayoutItem] that encompasses all items.
LayoutItem calculateBoundingBox(List<LayoutItem> items) {
  if (items.isEmpty) {
    return const LayoutItem(id: 'empty_cluster', x: 0, y: 0, w: 0, h: 0);
  }

  var minX = 100000; // Arbitrary large number
  var minY = 100000;
  var maxX = -100000;
  var maxY = -100000;

  for (final item in items) {
    if (item.x < minX) minX = item.x;
    if (item.y < minY) minY = item.y;
    if (item.x + item.w > maxX) maxX = item.x + item.w;
    if (item.y + item.h > maxY) maxY = item.y + item.h;
  }

  return LayoutItem(
    id: 'cluster_bbox',
    x: minX,
    y: minY,
    w: maxX - minX,
    h: maxY - minY,
    isDraggable: true, // Virtual item is draggable
  );
}

/// Moves a group of items (cluster) together.
///
/// [layout] The full layout.
/// [clusterIds] The IDs of the items to move.
/// [targetX] The target X coordinate for the *top-left* of the bounding box.
/// [targetY] The target Y coordinate for the *top-left* of the bounding box.
Layout moveCluster(
  Layout layout,
  Set<String> clusterIds,
  int targetX,
  int targetY, {
  required int cols,
  required CompactType compactType,
  bool preventCollision = false,
}) {
  if (clusterIds.isEmpty) return layout;

  // 1. Separate Cluster and Obstacles
  final cluster = layout.where((i) => clusterIds.contains(i.id)).toList();
  final obstacles = layout.where((i) => !clusterIds.contains(i.id)).toList();

  if (cluster.isEmpty) return layout;

  // 2. Calculate Bounding Box
  final bbox = calculateBoundingBox(cluster);

  // 3. Move the Bounding Box against Obstacles
  // We treat the bbox as a single item being moved in a layout consisting of obstacles.
  // We add the bbox to the obstacles list for the moveElement function to work.
  final layoutForMove = [...obstacles, bbox];

  final resultLayoutWithBBox = moveElement(
    layoutForMove,
    bbox,
    targetX,
    targetY,
    cols: cols,
    compactType: compactType,
    preventCollision: preventCollision,
    force: true, // Force move to trigger collision resolution
  );

  // 4. Extract the new Bounding Box position
  // It might have been pushed by static items or boundaries
  final newBBox = resultLayoutWithBBox.firstWhere((i) => i.id == bbox.id);

  // 5. Calculate Delta (Movement vector)
  final dx = newBBox.x - bbox.x;
  final dy = newBBox.y - bbox.y;

  // 6. Apply Delta to Cluster Items
  final movedCluster = cluster.map((item) {
    return item.copyWith(
      x: item.x + dx,
      y: item.y + dy,
      moved: true, // Mark as moved
    );
  }).toList();

  // 7. Reconstruct Final Layout
  // Take the result from moveElement (which has pushed obstacles),
  // remove the virtual bbox, and add moved cluster items.
  final finalLayout = resultLayoutWithBBox
      .where((i) => i.id != bbox.id) // Remove virtual bbox
      .toList()
    ..addAll(movedCluster);

  return finalLayout;
}
