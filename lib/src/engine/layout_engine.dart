import 'dart:collection';
import 'dart:math';

import 'package:sliver_dashboard/src/models/dashboard_policy.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/models/utility.dart';

// sometimes it's better when explicit
// ignore_for_file: omit_local_variable_types

/// Defines the compaction strategy for the layout.
enum CompactType {
  /// No compression
  none,

  /// Compresses the layout vertically.
  vertical,

  /// Compresses the layout horizontally.
  horizontal,
}

/// Defines how a dragged item interacts with the items it lands on.
enum DragMode {
  /// The historical behaviour: obstacles are pushed away in a cascade and the
  /// compactor pulls the layout back together. This is the default.
  cascade,

  /// The dragged item and the item it lands on exchange positions directly.
  ///
  /// Opportunistic: a swap only happens when the drag box covers enough of a
  /// single valid target (see [swapElements]). Any frame that finds no such
  /// target falls back to [cascade], so the drag never feels stuck over empty
  /// space or over an item it only clips.
  swap,
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

    final indexOf = <String, int>{
      for (var i = 0; i < layout.length; i++) layout[i].id: i,
    };

    // Occupancy set + per-column skyline over already-placed items.
    // Soundness (no start-collision test needed): if the skyline max over
    // the item's columns is <= the item's y, then EVERY placed item
    // overlapping those columns has its lower edge at or above that bound —
    // none can overlap the item's start box, and resting on the bound is
    // collision-free. Conversely, any start collision or any static placed
    // BELOW the item forces the skyline max above its y, which routes to
    // the historical resolution verbatim.
    final colHeights = List<int>.filled(max(cols, 1), 0);
    void markPlaced(LayoutItem p) {
      final bottomEdge = p.y + p.h;
      final xEnd = min(p.x + p.w, colHeights.length);
      for (var x = max(p.x, 0); x < xEnd; x++) {
        if (bottomEdge > colHeights[x]) colHeights[x] = bottomEdge;
      }
    }

    compareWith.forEach(markPlaced);

    for (final l in sorted) {
      var newL = l;
      if (!l.isStatic) {
        var restY = 0;
        final xEnd = min(l.x + l.w, colHeights.length);
        for (var x = max(l.x, 0); x < xEnd; x++) {
          if (colHeights[x] > restY) restY = colHeights[x];
        }
        // The fast path additionally requires the item to sit fully inside
        // the tracked columns: an item partially or fully beyond [0, cols)
        // (horizontally-scrolling vertical grids) would get a truncated —
        // or empty — skyline reading and a bogus collision-free verdict.
        // Out-of-range items take the historical, collision-scan path.
        if (restY <= l.y && l.x >= 0 && l.x + l.w <= colHeights.length) {
          // Fast path: every skyline contribution in l's columns sits at or
          // above l, so the per-column max equals the closed-form
          // max-lower-edge rise bound exactly.
          newL = restY < l.y ? l.copyWith(y: restY) : l;
        } else {
          // Historical path. Two cases land here: a colliding start
          // (overlapping input), and restY > l.y — a STATIC placed BELOW l
          // dominates the skyline of its columns, which says nothing about
          // how far l may rise; the verbatim resolution handles both.
          newL = _compactItemVertical(compareWith, l, cols, sorted);
        }
        compareWith.add(newL);
        markPlaced(newL);
      }

      final index = indexOf[l.id]!;
      if (newL.x == l.x && newL.y == l.y && !l.moved) {
        out[index] = l;
      } else {
        out[index] = newL.copyWith(moved: false);
      }
    }
    final resultList = out.whereType<LayoutItem>().toList()..sort((a, b) => a.id.compareTo(b.id));
    return resultList;
  }

  @override
  List<LayoutItem> resolveCollisions(List<LayoutItem> layout, int cols) {
    return _resolveCollisionsDefault(layout, CompactType.vertical, cols);
  }

  LayoutItem _compactItemVertical(
    List<LayoutItem> compareWith,
    LayoutItem l,
    int cols,
    List<LayoutItem> fullLayout,
  ) {
    var currentItem = l;

    // Closed-form rise.
    // When the start position is collision-free, rising stops exactly at the
    // max lower edge among horizontally-overlapping items whose lower edge
    // is at or above the start — a single O(|compareWith|) scan with a
    // provably identical result (any item that could block below that bound
    // would already collide at the start, which the guard excludes). When
    // the start DOES collide, the historical behavior (no rise, then the
    // down-resolution loop) is preserved unchanged.
    if (getFirstCollision(compareWith, currentItem) == null) {
      var restY = 0;
      for (final other in compareWith) {
        if (other.x < currentItem.x + currentItem.w && currentItem.x < other.x + other.w) {
          final bottomEdge = other.y + other.h;
          if (bottomEdge <= currentItem.y && bottomEdge > restY) {
            restY = bottomEdge;
          }
        }
      }
      if (restY < currentItem.y) {
        currentItem = currentItem.copyWith(y: restY);
      }
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

    final indexOf = <String, int>{
      for (var i = 0; i < layout.length; i++) layout[i].id: i,
    };

    // Per-row skyline (max right edge of placed items per row) — mirror of
    // the vertical compactor's colHeights, same soundness argument by
    // symmetry: restX <= l.x guarantees a collision-free slide to restX;
    // start collisions and statics placed RIGHT of the item force
    // restX > l.x and route to the historical resolution verbatim. The fast
    // path additionally requires the item not to overflow the columns,
    // because the historical path owns the wrap-to-next-row semantics.
    var rowRights = List<int>.filled(64, 0);
    void ensureRows(int rowEnd) {
      if (rowEnd <= rowRights.length) return;
      final grown = List<int>.filled(max(rowEnd, rowRights.length * 2), 0)
        ..setRange(0, rowRights.length, rowRights);
      rowRights = grown;
    }

    void markPlaced(LayoutItem p) {
      if (p.y < 0) return;
      ensureRows(p.y + p.h);
      final rightEdge = p.x + p.w;
      for (var y = p.y; y < p.y + p.h; y++) {
        if (rightEdge > rowRights[y]) rowRights[y] = rightEdge;
      }
    }

    // Cell -> index (in compareWith) of the item covering it. Placed items
    // never overlap each other (each is fully resolved before insertion),
    // so every cell has a single owner and "first collision in list order"
    // — the exact contract of getFirstCollision, whose result drives the
    // push-right jumps — is the MINIMUM owner index over the probe's cells:
    // an O(w*h) query. Cells at negative coordinates are not
    // tracked; queries touching them fall back to the legacy scan.
    final cellOwner = <int, int>{};
    void ownCells(LayoutItem p, int index) {
      if (p.y < 0 || p.x < 0) return;
      for (var dy = 0; dy < p.h; dy++) {
        final rowBase = (p.y + dy) << 20;
        for (var dx = 0; dx < p.w; dx++) {
          cellOwner[rowBase | (p.x + dx)] = index;
        }
      }
    }

    for (var i = 0; i < compareWith.length; i++) {
      markPlaced(compareWith[i]);
      ownCells(compareWith[i], i);
    }

    for (final l in sorted) {
      var newL = l;
      if (!l.isStatic) {
        var restX = 0;
        if (l.y >= 0) {
          ensureRows(l.y + l.h);
          for (var y = l.y; y < l.y + l.h; y++) {
            if (rowRights[y] > restX) restX = rowRights[y];
          }
        } else {
          restX = l.x + 1; // negative rows: historical path decides
        }
        if (restX <= l.x && l.x + l.w <= cols) {
          newL = restX < l.x ? l.copyWith(x: restX) : l;
        } else {
          newL = _compactItemHorizontal(
            compareWith,
            l,
            cols,
            sorted,
            cellOwner: cellOwner,
          );
        }
        compareWith.add(newL);
        markPlaced(newL);
        ownCells(newL, compareWith.length - 1);
      }

      final index = indexOf[l.id]!;
      if (newL.x == l.x && newL.y == l.y && !l.moved) {
        out[index] = l;
      } else {
        out[index] = newL.copyWith(moved: false);
      }
    }
    final resultList = out.whereType<LayoutItem>().toList()..sort((a, b) => a.id.compareTo(b.id));
    return resultList;
  }

  @override
  List<LayoutItem> resolveCollisions(List<LayoutItem> layout, int cols) {
    return _resolveCollisionsDefault(layout, CompactType.horizontal, cols);
  }

  LayoutItem _compactItemHorizontal(
    List<LayoutItem> compareWith,
    LayoutItem l,
    int cols,
    List<LayoutItem> fullLayout, {
    Map<int, int>? cellOwner,
  }) {
    // First collision in compareWith list order — via the owner map when
    // available and the probe is fully inside tracked space, else the
    // legacy O(N) scan (also used by the deprecated compactItem helper).
    LayoutItem? firstCollision(LayoutItem probe) {
      if (cellOwner == null || probe.y < 0 || probe.x < 0) {
        return getFirstCollision(compareWith, probe);
      }
      var minIndex = -1;
      for (var dy = 0; dy < probe.h; dy++) {
        final rowBase = (probe.y + dy) << 20;
        for (var dx = 0; dx < probe.w; dx++) {
          final owner = cellOwner[rowBase | (probe.x + dx)];
          if (owner != null && (minIndex == -1 || owner < minIndex)) {
            minIndex = owner;
          }
        }
      }
      return minIndex == -1 ? null : compareWith[minIndex];
    }

    var currentItem = l;

    // 1. Move left as far as possible — closed form, mirror of the vertical
    // compactor's rise (see _compactItemVertical for the equivalence proof
    // and the complexity rationale).
    if (firstCollision(currentItem) == null) {
      var restX = 0;
      for (final other in compareWith) {
        if (other.y < currentItem.y + currentItem.h && currentItem.y < other.y + other.h) {
          final rightEdge = other.x + other.w;
          if (rightEdge <= currentItem.x && rightEdge > restX) {
            restX = rightEdge;
          }
        }
      }
      if (restX < currentItem.x) {
        currentItem = currentItem.copyWith(x: restX);
      }
    }

    // 2. Resolve collisions AND overflows
    while (true) {
      final collidesWith = firstCollision(currentItem);

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

    return resolveCollisions(layout, cols);
  }

  @override
  List<LayoutItem> resolveCollisions(List<LayoutItem> layout, int cols) {
    // We use vertical resolution by default for "None" to prevent stacking
    final resolved = _resolveCollisionsDefault(layout, CompactType.vertical, cols);

    return [
      for (final item in resolved)
        if (item.moved) item.copyWith(moved: false) else item,
    ]..sort((a, b) => a.id.compareTo(b.id));
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
    if (layout.isEmpty) return [];

    // Calculate the actual column count needed for the tide array based on
    // the layout's right-most item. This supports infinite horizontal columns when compacting
    // vertically in a horizontally-scrolling grid.
    var maxCol = cols;
    for (final item in layout) {
      if (item.x + item.w > maxCol) {
        maxCol = item.x + item.w;
      }
    }
    final maxColWithBuffer = maxCol + 10;
    final tide = List<int>.filled(maxColWithBuffer, 0);

    // 1. Clone and Sort
    final sorted = List<LayoutItem>.from(layout)
      ..sort((a, b) {
        // Sort by Y, then X
        if (a.y != b.y) return a.y.compareTo(b.y);
        if (a.x != b.x) return a.x.compareTo(b.x);

        // Tie-breaker. If items have identical coordinates, sort by ID
        // alphabetically to ensure layout determinism across all platforms.
        final idCompare = a.id.compareTo(b.id);
        if (idCompare != 0) return idCompare;

        // Static first to act as anchors
        if (a.isStatic && !b.isStatic) return -1;
        if (!a.isStatic && b.isStatic) return 1;
        return 0;
      });

    final out = <LayoutItem>[];

    // Separate statics for collision check optimization
    final statics = sorted.where((i) => i.isStatic).toList();
    // Index tracker for statics (optimization from the TS algo)
    var staticOffset = 0;

    for (final item in sorted) {
      // If item is static, it stays put, but updates the tide.
      if (item.isStatic) {
        _updateTide(tide, item, maxColWithBuffer);
        out.add(item);
        staticOffset++; // Advance static cursor
        continue;
      }

      // --- DYNAMIC ITEM PLACEMENT ---

      // 1. Find the highest point in the tide for the item's width
      var y = 0;
      final xEnd = min(item.x + item.w, maxColWithBuffer);

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
      _updateTide(tide, newItem, maxColWithBuffer);
    }

    final resultList = out..sort((a, b) => a.id.compareTo(b.id));
    return resultList;
  }

  void _updateTide(List<int> tide, LayoutItem item, int maxCol) {
    final bottom = item.y + item.h;
    final xEnd = min(item.x + item.w, maxCol);
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
    bool allowOverlap = false,
  }) {
    if (layout.isEmpty) return [];

    // Calculate the actual row count needed for the tide array based on
    // the layout's bottom-most item. This supports infinite vertical rows when compacting
    // horizontally in a vertically-scrolling grid.
    final maxRow = max(bottom(layout), rows) + 10;
    final tide = List<int>.filled(maxRow, 0);

    // 1. Clone and Sort
    final sorted = List<LayoutItem>.from(layout)
      ..sort((a, b) {
        // Sort by X (Main Axis), then Y (Cross Axis)
        if (a.x != b.x) return a.x.compareTo(b.x);
        if (a.y != b.y) return a.y.compareTo(b.y);

        // Tie-breaker.
        final idCompare = a.id.compareTo(b.id);
        if (idCompare != 0) return idCompare;

        // Static first
        if (a.isStatic && !b.isStatic) return -1;
        if (!a.isStatic && b.isStatic) return 1;
        return 0;
      });

    final out = <LayoutItem>[];
    final statics = sorted.where((i) => i.isStatic).toList();
    var staticOffset = 0;

    for (final item in sorted) {
      if (item.isStatic) {
        _updateTide(tide, item, maxRow);
        out.add(item);
        staticOffset++;
        continue;
      }

      // --- DYNAMIC ITEM PLACEMENT ---

      // 1. Find the furthest X in the tide for the item's height (rows spanned)
      var x = 0;
      final yEnd = min(item.y + item.h, maxRow);

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
      _updateTide(tide, newItem, maxRow);
    }

    final resultList = out..sort((a, b) => a.id.compareTo(b.id));
    return resultList;
  }

  void _updateTide(List<int> tide, LayoutItem item, int maxRow) {
    final right = item.x + item.w;
    final yEnd = min(item.y + item.h, maxRow);

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
      if (a.x != b.x) return a.x.compareTo(b.x);
      if (a.y != b.y) return a.y.compareTo(b.y);

      return a.id.compareTo(b.id);
    });
  } else {
    newLayout.sort((a, b) {
      if (a.y != b.y) return a.y.compareTo(b.y);
      if (a.x != b.x) return a.x.compareTo(b.x);

      return a.id.compareTo(b.id);
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
  return item.copyWith(
    x: axis == 'x' ? moveToCoord : item.x,
    y: axis == 'y' ? moveToCoord : item.y,
  );
}

// --- Internal Helper for Default Collision Resolution ---
// Row-indexed: each probe only visits rows that can plausibly overlap,
// replacing the previous O(N^2) scan of the whole processed list
// (499,500 collides() calls at N=1000) with O(N*k) work (~16k checks).
/// Pushes every colliding item along the compaction axis until the layout is
/// overlap-free.
///
/// [cols] bounds the horizontal axis. Vertical resolution pushes down a
/// **column count of rows that is unbounded**, so it can always find room;
/// horizontal resolution pushes along a **finite** axis and must wrap to the
/// next row when the push would leave the grid — the same rule
/// [HorizontalCompactor._compactItemHorizontal] already applies. Callers with
/// no meaningful column count pass a large sentinel, which reproduces the
/// historical unbounded behaviour exactly.
List<LayoutItem> _resolveCollisionsDefault(
  List<LayoutItem> layout,
  CompactType compactType,
  int cols,
) {
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
  final index = _RowIndex.empty();

  for (var i = 0; i < items.length; i++) {
    var current = items[i];
    if (current.isStatic) {
      processed.add(current);
      index.insert(current);
      continue;
    }

    var hasCollision = true;
    var safety = 0;

    while (hasCollision && safety < 1000) {
      hasCollision = false;
      final hits = index.query(
        current,
        top: current.y,
        bottom: current.y + current.h,
        left: current.x,
        right: current.x + current.w,
      );
      if (hits.isNotEmpty) {
        // Deterministic: resolve against the top/left-most obstacle first,
        // matching the previous main-axis processing order.
        hits.sort(
          isHorizontal ? (a, b) => a.x.compareTo(b.x) : (a, b) => a.y.compareTo(b.y),
        );
        final obstacle = hits.first;
        current = isHorizontal
            ? current.copyWith(x: obstacle.x + obstacle.w)
            : current.copyWith(y: obstacle.y + obstacle.h);
        hasCollision = true;
      }

      // Overflow check, horizontal only, and checked even when nothing
      // collided this round: the item may have arrived already outside the
      // grid, and the push above may have just carried it out.
      //
      // Wrapping — not clamping — is the correct repair. Clamping to
      // `cols - w` would put the item straight back onto the obstacle it was
      // pushed off, trading a bounds violation for an OVERLAP violation, and
      // overlap is the invariant everything downstream relies on. Wrapping
      // mirrors `_compactItemHorizontal`, which has always resolved
      // overflows this way; the two paths now agree.
      //
      // An item wider than the grid can never fit on any row, so wrapping it
      // would spin until the safety counter. It is left where it is: an
      // out-of-bounds item is a lesser failure than a hung layout pass.
      if (isHorizontal && current.w <= cols && current.x + current.w > cols) {
        current = current.copyWith(x: 0, y: current.y + 1);
        hasCollision = true;
      }

      safety++;
    }
    processed.add(current);
    index.insert(current);
  }

  processed.sort((a, b) => a.id.compareTo(b.id));
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
/// Resolves collisions.
///
/// [cols] is optional only for backward compatibility: omitting it keeps the
/// historical `10000` sentinel, i.e. a horizontal resolution that is free to
/// push items past the last column. Every in-package caller passes the real
/// value; new callers should too.
List<LayoutItem> resolveCollisions(
  List<LayoutItem> layout,
  CompactType compactType, {
  int? cols,
}) {
  final delegate = _getDelegate(compactType);
  return delegate.resolveCollisions(layout, cols ?? 10000);
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

/// Corrects the bounds of the layout items to ensure they fit within the
/// specified number of columns.
Layout correctBounds(Layout layout, int cols) {
  final collidesWith = getStatics(layout).toList();
  final newLayout = <LayoutItem>[];

  for (final l in layout) {
    var currentL = l;

    // Enforce positive dimension bounds. Prevent items configured with zero
    // or negative dimensions from propagating and corrupting engine layout cascades.
    if (currentL.w < 1) {
      currentL = currentL.copyWith(w: 1);
    }
    if (currentL.h < 1) {
      currentL = currentL.copyWith(h: 1);
    }

    // Asset constraint mismatches in debug mode. Alert developers if
    // an item's minimum width exceeds the physical column space of the current breakpoint.
    assert(
      currentL.minW <= cols,
      'LayoutItem constraint (minW: ${currentL.minW}) exceeds grid columns ($cols)!',
    );

    if (currentL.x + currentL.w > cols) {
      currentL = currentL.copyWith(x: cols - currentL.w);
    }
    if (currentL.x < 0) {
      currentL = currentL.copyWith(x: 0, w: min(currentL.w, cols));
    }
    if (currentL.y < 0) {
      currentL = currentL.copyWith(y: 0);
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

/// Moves a single layout item [l] to the target grid coordinates ([x], [y]).
/// Returns a new, mutated, and ID-stabilized [Layout] containing the updated coordinates.
///
/// ### Algorithmic notes
/// - **Monotonic re-push cascade**: an obstacle may be pushed several times,
///   but its `y` strictly increases on every push, so the cascade terminates
///   and — unlike the previous single-push design — leaves no residual
///   overlaps. This removes the need for the unconditional O(N^2)
///   `resolveCollisions` pass on every drag frame.
/// - **Row-indexed collision queries**: each cascade step only visits the
///   rows that can plausibly overlap the probe box (O(k) per step).
/// - **ID-based Index Stability**: the result is sorted by [LayoutItem.id]
///   so sliver child indices stay immutable across drag frames.
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
  DashboardPolicy? policy,
}) {
  if (l.isStatic && !l.isSectionBarrier) return layout;

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
  final movedId = itemWithNewPos.id;

  // O(1) access by id, used to build the final layout and to dedupe.
  final layoutMap = {for (final item in layout) item.id: item};
  layoutMap[movedId] = itemWithNewPos;

  final rowIndex = _RowIndex.fromItems(layoutMap.values);

  // Queue of item IDs, not snapshots: we always re-read the live instance
  // from layoutMap so a re-queued item is processed at its latest position.
  final queue = ListQueue<String>()..add(movedId);

  // SAFETY: Prevent pathological cascades. Every enqueue strictly increases
  // an item's `y` (or the current item's `y` on a static jump), so the loop
  // terminates; the cap is a belt-and-braces guard only.
  var safetyLoop = 0;
  // The real worst case is not 4N: in a dense grid, pushing near the TOP
  // re-enqueues each obstacle once per pusher stacked above it — up to
  // ~N * (N / cols) pops (125k at N=1000, cols=8). Each pop is a
  // cheap row-indexed query, so the bound stays a few ms.
  final maxLoops = max(10000, layout.length * layout.length ~/ max(cols, 1));

  while (queue.isNotEmpty) {
    if (safetyLoop++ > maxLoops) {
      // Always returns true so the assert never fails, making the second message parameter unreachable and uncovered by tests
      // ignore: prefer_asserts_with_message
      assert(
        () {
          // Debug-only diagnostic; never ships in release builds.
          // ignore: avoid_print
          print('SliverDashboard: Collision resolution limit reached ($maxLoops).');
          return true;
        }(),
      );
      break;
    }

    final currentItem = layoutMap[queue.removeFirst()];
    if (currentItem == null) continue;

    final left = currentItem.x;
    final right = currentItem.x + currentItem.w;
    final top = currentItem.y;
    final bottom = currentItem.y + currentItem.h;

    final collisions = rowIndex.query(
      currentItem,
      top: top,
      bottom: bottom,
      left: left,
      right: right,
    )
      // Sort required for stability (pushed from top to bottom).
      ..sort((a, b) => a.y.compareTo(b.y));

    var currentItemJumped = false;

    for (final collision in collisions) {
      // The user-moved item is the anchor of the cascade: it is never
      // pushed away from the position the user requested.
      if (collision.id == movedId && currentItem.id != movedId) continue;

      // Re-read the live instance: an earlier push in this very loop may
      // already have moved this obstacle out of the way.
      final other = layoutMap[collision.id];
      if (other == null) continue;

      final isBlockedByPolicy = policy != null && !policy.canCollide(currentItem, other);

      if (other.isStatic || isBlockedByPolicy) {
        // Jump below the blocking item, then restart resolution for the
        // current item from its NEW position. Continuing through the stale
        // collision list would push neighbours from outdated coordinates.
        final jumpY = other.y + other.h;
        final updatedCurrentItem = currentItem.copyWith(y: jumpY, moved: true);
        layoutMap[currentItem.id] = updatedCurrentItem;
        rowIndex.update(currentItem, updatedCurrentItem);
        queue.addFirst(updatedCurrentItem.id);
        currentItemJumped = true;
        break;
      }

      // Live overlap re-check against the up-to-date instance.
      if (!_overlaps(currentItem, other)) continue;

      // Push collided item below the current item.
      final pushedY = currentItem.y + currentItem.h;
      if (other.y >= pushedY) continue; // Already below.

      final pushedItem = other.copyWith(y: pushedY, moved: true);
      layoutMap[other.id] = pushedItem;
      rowIndex.update(other, pushedItem);
      // Monotonic re-push: the item may be pushed again later, each time
      // strictly downwards, guaranteeing termination and zero overlaps.
      queue.add(pushedItem.id);
    }

    if (currentItemJumped) continue;
  }

  final resultLayout = layoutMap.values.toList()
    // ID-based Index Stability (see doc comment).
    ..sort((a, b) => a.id.compareTo(b.id));

  // The monotonic cascade is overlap-free by construction; keep the legacy
  // full resolution strictly as a fallback, gated behind a cheap O(N*k)
  // verification instead of running the O(N^2) pass on every drag frame.
  if ((preventCollision || compactType == CompactType.horizontal) &&
      _hasResidualOverlap(resultLayout, rowIndex)) {
    return resolveCollisions(
      resultLayout,
      compactType == CompactType.none ? CompactType.vertical : compactType,
      cols: cols,
    );
  }

  return resultLayout;
}

/// AABB overlap check (identical semantics to [collides]).
bool _overlaps(LayoutItem a, LayoutItem b) {
  if (a.id == b.id) return false;
  if (a.x + a.w <= b.x) return false;
  if (a.x >= b.x + b.w) return false;
  if (a.y + a.h <= b.y) return false;
  if (a.y >= b.y + b.h) return false;
  return true;
}

/// O(N*k) overlap verification using the row index maintained by the cascade.
bool _hasResidualOverlap(Layout layout, _RowIndex rowIndex) {
  for (final item in layout) {
    final hits = rowIndex.query(
      item,
      top: item.y,
      bottom: item.y + item.h,
      left: item.x,
      right: item.x + item.w,
    );
    if (hits.isNotEmpty) return true;
  }
  return false;
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

/// A private helper function that attempts to resolve move collisions by shrinking
/// the colliding items along the vertical axis to clear vertical overlaps.
Layout? _tryShrinkMoveCollisions(
  Layout layout,
  LayoutItem movingItem,
  List<LayoutItem> collisions,
) {
  final layoutMap = {for (final item in layout) item.id: item};

  for (final collision in collisions) {
    if (collision.isStatic) return null; // Statics cannot shrink

    // A is the movingItem, B is the collision.
    // We attempt to shrink B vertically to avoid overlaps if possible.
    final overlapY = (movingItem.y + movingItem.h) - collision.y;
    final newCollisionHeight = collision.h - overlapY;

    if (newCollisionHeight >= collision.minH) {
      layoutMap[collision.id] = collision.copyWith(
        y: collision.y + overlapY,
        h: newCollisionHeight,
      );
    } else {
      return null; // Shrink failed, minHeight limit violated
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
  CompactType compactType = CompactType.vertical,
  DashboardPolicy? policy,
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
      compactType: compactType,
      force: true,
      policy: policy,
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
      compactType,
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
    compactType: compactType,
    force: true,
    policy: policy,
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
  AutoPlacementStrategy strategy = AutoPlacementStrategy.appendBottom,
  int? maxRows,
}) {
  // Separate items that need placement from those that don't
  final itemsToPlace = newItems.where((i) => i.x == -1 || i.y == -1).toList();
  // Pre-positioned items are SANITIZED, not trusted: explicit coordinates
  // come straight from app code (an onSlotTap handler adding a 2-wide item
  // on the last column, a tap on the trailing edit row of a maxRows grid…).
  // Width/height are capped to the grid, then the position is clamped so the item
  // lies fully inside; the downstream compaction/collision pass owns any resulting overlap, same
  // as any explicit add onto an occupied spot.
  final alreadyPlacedNewItems = [
    for (final i in newItems.where((i) => i.x != -1 && i.y != -1))
      () {
        final w = i.w.clamp(1, cols);
        final int h = maxRows == null ? i.h : i.h.clamp(1, max(1, maxRows));
        final x = i.x.clamp(0, cols - w);
        final int y = maxRows == null ? max(0, i.y) : i.y.clamp(0, max(0, maxRows - h));
        return (w == i.w && h == i.h && x == i.x && y == i.y)
            ? i
            : i.copyWith(x: x, y: y, w: w, h: h);
      }(),
  ];

  // Start with the existing layout plus any new items that already had fixed positions
  final finalLayout = <LayoutItem>[...existingLayout, ...alreadyPlacedNewItems];

  if (itemsToPlace.isEmpty) {
    return finalLayout;
  }

  // Define starting point for Y search regarding chosen strategy.
  // appendBottom starts searching from the end, while firstFit starts at (0,0)
  final startY = (strategy == AutoPlacementStrategy.appendBottom) ? bottom(finalLayout) : 0;
  var currentX = 0;
  var currentY = startY;

  // SAFETY: Allow searching at least 1000 rows down, or 10k iterations minimum.
  final maxIterations = max(10000, cols * 1000);
  var runningBottom = bottom(finalLayout);

  // Per-row occupied-cell counts (in-range cells only), mirroring
  // optimizeLayout: lets firstFit skip full rows in O(1) instead of
  // attempting every x — the dominant cost on dense boards.
  var rowCounts = List<int>.filled(64, 0);
  void ensureRowCounts(int rowEnd) {
    if (rowEnd <= rowCounts.length) return;
    final grown = List<int>.filled(max(rowEnd, rowCounts.length * 2), 0)
      ..setRange(0, rowCounts.length, rowCounts);
    rowCounts = grown;
  }

  // Occupancy set of covered cells, packed (y << 20) | x (x < 2^20 by
  // construction, safe on dart2js).
  final occupied = <int>{};
  for (final existing in finalLayout) {
    if (existing.y >= 0) ensureRowCounts(existing.y + existing.h);
    for (var dy = 0; dy < existing.h; dy++) {
      final rowBase = (existing.y + dy) << 20;
      for (var dx = 0; dx < existing.w; dx++) {
        occupied.add(rowBase | (existing.x + dx));
        if (existing.y + dy >= 0 && existing.x + dx >= 0 && existing.x + dx < cols) {
          rowCounts[existing.y + dy]++;
        }
      }
    }
  }

  bool cellsFree(int x, int y, int w, int h) {
    for (var dy = 0; dy < h; dy++) {
      final rowBase = (y + dy) << 20;
      for (var dx = 0; dx < w; dx++) {
        if (occupied.contains(rowBase | (x + dx))) return false;
      }
    }
    return true;
  }

  void markCells(int x, int y, int w, int h) {
    if (y >= 0) ensureRowCounts(y + h);
    for (var dy = 0; dy < h; dy++) {
      final rowBase = (y + dy) << 20;
      for (var dx = 0; dx < w; dx++) {
        occupied.add(rowBase | (x + dx));
        if (y + dy >= 0 && x + dx >= 0 && x + dx < cols) {
          rowCounts[y + dy]++;
        }
      }
    }
    if (y + h > runningBottom) runningBottom = y + h;
  }

  for (final item in itemsToPlace) {
    var placed = false;
    var safetyLoop = 0;

    // reset start point search when using firstFit
    if (strategy == AutoPlacementStrategy.firstFit) {
      currentX = 0;
      currentY = 0;
    }

    // Try to find the first valid spot. With [maxRows], the search is
    // bounded to rows where the item fits entirely under the cap; if the
    // bounded area has no free spot, the loop exits and the fallback below
    // places the item past the cap — never losing data, mirroring the
    // historical too-wide fallback semantics.
    final boundedRows = maxRows != null;
    // runningBottom is captured per item: rows [runningBottom, ...) are
    // free, so a placeable item is guaranteed to land by then.
    final searchBottom = runningBottom;
    while (!placed &&
        safetyLoop < maxIterations &&
        currentY <= searchBottom &&
        (!boundedRows || currentY + item.h <= maxRows)) {
      // O(1) full-row skip (firstFit's dominant cost on dense boards).
      if (currentX == 0 && currentY < rowCounts.length && cols - rowCounts[currentY] < item.w) {
        currentY++;
        safetyLoop++;
        continue;
      }
      // 1. Check grid boundaries (Wrap to next row if needed)
      if (currentX + item.w > cols) {
        currentX = 0;
        currentY++;
        // The wrap must consume safety budget too.
        safetyLoop++;
        continue; // Retry at the start of the new row
      }

      // Same scan order as before; the occupancy set answers the
      // collision question in O(w*h).
      if (cellsFree(currentX, currentY, item.w, item.h)) {
        // Valid spot found
        finalLayout.add(item.copyWith(x: currentX, y: currentY));
        markCells(currentX, currentY, item.w, item.h);
        placed = true;
        // Advance cursor by the item's width to optimize the next search
        currentX += item.w;
      } else {
        // Collision detected, move cursor one slot to the right
        currentX++;
      }

      safetyLoop++;
    }

    if (!placed) {
      // Bounded search exhausted (maxRows cap) or safety limit hit: append
      // below the existing content instead of dropping the item.
      final fallback = item.copyWith(x: 0, y: bottom(finalLayout));
      finalLayout.add(fallback);
      markCells(fallback.x, fallback.y, fallback.w, fallback.h);
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

  // Occupancy set of covered cells, packed (y << 20) | x — same technique as
  // placeNewItems and the skyline compactors.
  // The set answers each candidate in O(w*h) with an IDENTICAL
  // scan order, so placements are bit-identical (pinned by the oracle test).
  final occupied = <int>{};
  // In-range occupied-cell count per row: lets the first-fit scan skip a
  // whole row in O(1) when it cannot possibly host the item (free in-range
  // cells < item.w — a necessary condition, so no placeable position is
  // ever skipped and placements stay bit-identical). On a nearly-full board
  // most rows are full.
  var rowCounts = List<int>.filled(64, 0);
  void ensureRowCounts(int rowEnd) {
    if (rowEnd <= rowCounts.length) return;
    final grown = List<int>.filled(max(rowEnd, rowCounts.length * 2), 0)
      ..setRange(0, rowCounts.length, rowCounts);
    rowCounts = grown;
  }

  void markCells(LayoutItem p) {
    if (p.y >= 0) ensureRowCounts(p.y + p.h);
    for (var dy = 0; dy < p.h; dy++) {
      final rowBase = (p.y + dy) << 20;
      for (var dx = 0; dx < p.w; dx++) {
        occupied.add(rowBase | (p.x + dx));
        // Count only cells inside [0, columns): too-wide fallback items spill
        // beyond, and counting their overflow would over-skip rows that
        // still hold a valid slot — breaking placement equality.
        if (p.y + dy >= 0 && p.x + dx >= 0 && p.x + dx < columns) {
          rowCounts[p.y + dy]++;
        }
      }
    }
  }

  bool cellsFree(int x, int y, int w, int h) {
    for (var dy = 0; dy < h; dy++) {
      final rowBase = (y + dy) << 20;
      for (var dx = 0; dx < w; dx++) {
        if (occupied.contains(rowBase | (x + dx))) return false;
      }
    }
    return true;
  }

  placedItems.forEach(markCells);

  // 4. Place each dynamic item in the first available spot
  for (final item in dynamics) {
    var placed = false;
    var y = 0;

    // Safety limit to prevent infinite loops if an item is wider than columns
    while (!placed && y < 10000) {
      // O(1) row skip: not enough free in-range cells for this width.
      if (y < rowCounts.length && columns - rowCounts[y] < item.w) {
        y++;
        continue;
      }
      // Try every column in this row
      for (var x = 0; x <= columns - item.w; x++) {
        if (cellsFree(x, y, item.w, item.h)) {
          // Found a spot!
          final candidate = item.copyWith(x: x, y: y);
          placedItems.add(candidate);
          markCells(candidate);
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
      final fallback = item.copyWith(y: bottom(placedItems));
      placedItems.add(fallback);
      markCells(fallback);
    }
  }

  // Safety Pass
  // We run resolveCollisions on the final result.
  // If the optimizer accidentally placed an item on top of a static item (overlap),
  // this function will detect it and push the dynamic item down, ensuring
  // a valid layout with zero overlaps.
  return resolveCollisions(placedItems, CompactType.vertical, cols: columns);
}

/// Calculates the bounding box of a group of items.
/// Returns a virtual [LayoutItem] that encompasses all items.
LayoutItem calculateBoundingBox(List<LayoutItem> items, {String? id}) {
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
    id: id ?? 'cluster_bbox',
    x: minX,
    y: minY,
    w: maxX - minX,
    h: maxY - minY,
    isDraggable: true, // Virtual item is draggable
  );
}

/// Exchanges the position of [moving] with the item it is landing on.
///
/// Swap is **opportunistic and pure**: it returns `null` when the drop does
/// not qualify, and the caller falls back to [moveCluster] / [moveElement]
/// for that frame. That fallback is not a fallback in the "error" sense, it
/// is the interaction design — a swap-mode drag over empty space, or one that
/// merely clips a neighbour, must still move the item.
///
/// [moving] must be the item **as it exists in [layout]**, i.e. at its
/// pre-drag coordinates: those coordinates are where the swap partner is sent.
/// Passing the item already relocated to the target would swap it with
/// itself. [targetX] / [targetY] are the coordinates the drag is requesting.
///
/// ### Qualification rules
/// A candidate qualifies when the probe box (`moving` placed at the target)
/// covers more than [coverageThreshold] of the candidate's **own area**. The
/// ratio is relative to the candidate, not to the probe, so a small tile
/// dropped onto a large one does not swap until it is genuinely "on" it,
/// while a large tile dropped onto a small one swaps as soon as it engulfs
/// it. Among several qualifying candidates the best coverage wins; ties break
/// on the larger absolute overlap and then on the lower id, so the result is
/// deterministic and does not depend on layout ordering.
///
/// A swap is refused (returns `null`) when the candidate is static and not a
/// section barrier, or when [policy] forbids the two items to interact.
///
/// ### Restoring the 0-overlap invariant
/// A swap can leave overlaps two ways: the partner lands on a slot of a
/// different shape (a 1x1 sending a 2x2 into a quarter of its area), or the
/// probe clips a bystander it did not qualify to swap with — which never
/// moves, and which an EQUAL-size exchange can therefore land on top of.
/// Collision resolution is run whenever the result actually collides, never
/// on a size heuristic. A clean same-size swap collides with nothing and so
/// stays a pure coordinate exchange with no cascade.
///
/// The result is sorted by [LayoutItem.id] like every other engine mutation,
/// keeping sliver child indices immutable across drag frames.
Layout? swapElements(
  Layout layout,
  LayoutItem moving,
  int targetX,
  int targetY, {
  required int cols,
  required CompactType compactType,
  DashboardPolicy? policy,
  double coverageThreshold = 0.5,
}) {
  if (moving.isStatic && !moving.isSectionBarrier) return null;

  final live = layout.firstWhereOrNull((item) => item.id == moving.id);
  if (live == null) return null;

  final probe = live.copyWith(x: targetX, y: targetY);

  LayoutItem? best;
  double bestRatio = 0;
  int bestOverlap = 0;

  for (final other in layout) {
    if (other.id == live.id) continue;

    final probeRight = probe.x + probe.w;
    final otherRight = other.x + other.w;
    final overlapLeft = probe.x > other.x ? probe.x : other.x;
    final overlapRight = probeRight < otherRight ? probeRight : otherRight;
    final overlapW = overlapRight - overlapLeft;
    if (overlapW <= 0) continue;

    final probeBottom = probe.y + probe.h;
    final otherBottom = other.y + other.h;
    final overlapTop = probe.y > other.y ? probe.y : other.y;
    final overlapBottom = probeBottom < otherBottom ? probeBottom : otherBottom;
    final overlapH = overlapBottom - overlapTop;
    if (overlapH <= 0) continue;

    final overlap = overlapW * overlapH;
    final area = other.w * other.h;
    if (area <= 0) continue;
    final ratio = overlap / area;
    if (ratio <= coverageThreshold) continue;

    // Deterministic ordering: coverage, then absolute overlap, then id.
    if (best == null ||
        ratio > bestRatio ||
        (ratio == bestRatio && overlap > bestOverlap) ||
        (ratio == bestRatio && overlap == bestOverlap && other.id.compareTo(best.id) < 0)) {
      best = other;
      bestRatio = ratio;
      bestOverlap = overlap;
    }
  }

  if (best == null) return null;

  // Statics are immovable by definition; a section barrier is static but
  // interactive, and `moveElement` already lets it be dragged.
  if (best.isStatic && !best.isSectionBarrier) return null;

  if (policy != null) {
    if (!policy.canCollide(live, best)) return null;
    if (!policy.canMoveTo(best, live.x, live.y, layout)) return null;
    if (!policy.canMoveTo(live, targetX, targetY, layout)) return null;
  }

  // The partner takes the mover's ORIGINAL slot, clamped into the grid: the
  // two items may have different widths, and `live.x` is only guaranteed
  // valid for `live.w`.
  final maxPartnerX = cols - best.w;
  final clampedX = live.x < maxPartnerX ? live.x : maxPartnerX;
  final partnerX = clampedX < 0 ? 0 : clampedX;
  final partnerY = live.y < 0 ? 0 : live.y;

  final swappedMover = live.copyWith(x: targetX, y: targetY, moved: true);
  final swappedPartner = best.copyWith(x: partnerX, y: partnerY, moved: true);

  final result = <LayoutItem>[];
  for (final item in layout) {
    if (item.id == swappedMover.id) {
      result.add(swappedMover);
    } else if (item.id == swappedPartner.id) {
      result.add(swappedPartner);
    } else {
      result.add(item);
    }
  }

  // Resolve on an ACTUAL collision, never on a size heuristic.
  //
  // Differing sizes are one way a swap leaves an overlap, but not the only
  // one: the probe can cover a partner by more than the threshold while ALSO
  // clipping a bystander it does not qualify to swap with. That bystander
  // never moves, so an equal-size exchange can still land on top of it.
  //
  // Testing the result is both stricter and simpler, and it preserves the
  // "a clean same-size swap is a pure coordinate exchange with no cascade"
  // property for free: such a swap has no collision, so nothing runs.
  //
  // Probing the mover and the partner is sufficient. They are the only two
  // items that moved, so any new overlap must involve one of them, and
  // `collides` skips identity — a swap that resolves cleanly costs two O(N)
  // scans and no relayout.
  if (getFirstCollision(result, swappedMover) != null ||
      getFirstCollision(result, swappedPartner) != null) {
    return resolveCollisions(
      result,
      compactType == CompactType.none ? CompactType.vertical : compactType,
      cols: cols,
    )..sort((a, b) => a.id.compareTo(b.id));
  }

  return result..sort((a, b) => a.id.compareTo(b.id));
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
  DashboardPolicy? policy,
  bool allowAutoShrink = false,
}) {
  if (clusterIds.isEmpty) return layout;

  // 1. Separate Cluster (excluding static items) and Obstacles (including static items)
  final cluster = layout
      .where((i) => clusterIds.contains(i.id) && !(i.isStatic && !i.isSectionBarrier))
      .toList();
  final obstacles = layout
      .where((i) => !clusterIds.contains(i.id) || (i.isStatic && !i.isSectionBarrier))
      .toList();

  if (cluster.isEmpty) return layout;

  // 2. Calculate Bounding Box
  // If the cluster represents a single item, we preserve its original ID
  // to allow the declarative policy to perform precise ID/type lookups during dragging.
  final bboxId = cluster.length == 1 ? cluster.first.id : 'cluster_bbox';
  final bbox = calculateBoundingBox(cluster, id: bboxId);

  // Create virtual moved BBox to calculate pre-collisions
  final targetBBox = bbox.copyWith(x: targetX, y: targetY);
  final directCollisions = getAllCollisions(obstacles, targetBBox);

  // 3. Move the Bounding Box against Obstacles
  // We treat the bbox as a single item being moved in a layout consisting of obstacles.
  // We add the bbox to the obstacles list for the moveElement function to work.
  var layoutForMove = [...obstacles, bbox];

  // If auto-shrink is enabled and collisions are detected with dynamic items,
  // we first try to dynamically contract the size of neighbors to avoid massive layout shifts.
  if (allowAutoShrink && directCollisions.isNotEmpty && !directCollisions.any((i) => i.isStatic)) {
    final shrunk = _tryShrinkMoveCollisions(layoutForMove, targetBBox, directCollisions);
    if (shrunk != null) {
      layoutForMove = shrunk;
    }
  }

  final resultLayoutWithBBox = moveElement(
    layoutForMove,
    bbox,
    targetX,
    targetY,
    cols: cols,
    compactType: compactType,
    preventCollision: preventCollision,
    force: true, // Force move to trigger collision resolution
    policy: policy,
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
    ..addAll(movedCluster)
    // ID-based Index Stability: without this sort the dragged cluster is
    // appended at the tail, its sliver index changes on the first drag frame
    // and again on drop, and Flutter's child manager reorders/deactivates
    // elements (BuildOwner.finalizeTree / _InactiveElements._unmount spikes).
    ..sort((a, b) => a.id.compareTo(b.id));

  return finalLayout;
}

/// A minimal spatial index that groups [LayoutItem]s by their top row
/// (`y`), used internally by [moveElement] to avoid scanning the whole
/// layout on every collision check.
///
/// It only exists to make the cascade-push
/// resolution in [moveElement] scale with the number of items actually
/// affected by a move, instead of with the total size of the layout.
class _RowIndex {
  _RowIndex._(this._rows, this._maxHeight);

  factory _RowIndex.fromItems(Iterable<LayoutItem> items) {
    final rows = SplayTreeMap<int, List<LayoutItem>>();
    var maxHeight = 1;
    for (final item in items) {
      rows.putIfAbsent(item.y, () => <LayoutItem>[]).add(item);
      if (item.h > maxHeight) maxHeight = item.h;
    }
    return _RowIndex._(rows, maxHeight);
  }

  /// An empty index for incremental construction (see _resolveCollisionsDefault).
  factory _RowIndex.empty() => _RowIndex._(SplayTreeMap<int, List<LayoutItem>>(), 1);

  final SplayTreeMap<int, List<LayoutItem>> _rows;

  // Incremental inserts may raise the tallest known item.
  // moveElement's cascade never mutates heights (only `y`), so for that
  // caller the value is still effectively constant.
  int _maxHeight;

  /// Adds a new item to the index (incremental construction).
  void insert(LayoutItem item) {
    _rows.putIfAbsent(item.y, () => <LayoutItem>[]).add(item);
    if (item.h > _maxHeight) _maxHeight = item.h;
  }

  /// Returns every indexed item whose box overlaps
  /// `[left, right) x [top, bottom)`, excluding [currentItem].
  List<LayoutItem> query(
    LayoutItem currentItem, {
    required int top,
    required int bottom,
    required int left,
    required int right,
  }) {
    final result = <LayoutItem>[];
    final lowerBound = top - _maxHeight + 1;

    var key = _rows.containsKey(lowerBound) ? lowerBound : _rows.firstKeyAfter(lowerBound);

    while (key != null && key < bottom) {
      for (final other in _rows[key]!) {
        if (other.id == currentItem.id) continue;
        if (right <= other.x || left >= other.x + other.w) continue;
        if (bottom <= other.y || top >= other.y + other.h) continue;
        result.add(other);
      }
      key = _rows.firstKeyAfter(key);
    }
    return result;
  }

  /// Must be called every time an item's position changes so later
  /// queries in the same cascade see up-to-date rows.
  void update(LayoutItem oldItem, LayoutItem newItem) {
    final bucket = _rows[oldItem.y];
    if (bucket != null) {
      bucket.removeWhere((item) => item.id == oldItem.id);
      if (bucket.isEmpty) _rows.remove(oldItem.y);
    }
    _rows.putIfAbsent(newItem.y, () => <LayoutItem>[]).add(newItem);
  }
}
