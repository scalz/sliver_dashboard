import 'dart:collection';
import 'dart:math';

import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';

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
Layout sortLayoutItems(Layout layout, CompactType compactType) {
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
  if (l1.id == l2.id) return false; // same element
  if (l1.x + l1.w <= l2.x) return false; // l1 is left of l2
  if (l1.x >= l2.x + l2.w) return false; // l1 is right of l2
  if (l1.y + l1.h <= l2.y) return false; // l1 is above l2
  if (l1.y >= l2.y + l2.h) return false; // l1 is below l2
  return true; // boxes overlap
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

  // Avoid unnecessary props access
  final targetLeft = layoutItem.x;
  final targetRight = layoutItem.x + layoutItem.w;
  final targetTop = layoutItem.y;
  final targetBottom = layoutItem.y + layoutItem.h;
  final targetId = layoutItem.id;

  for (final item in layout) {
    if (item.id == targetId) continue;

    // Check AABB (Axis-Aligned Bounding Box) inlined for performance
    // Same as collides() without calling function
    if (targetRight <= item.x) continue; // Left target
    if (targetLeft >= item.x + item.w) continue; // Right target
    if (targetBottom <= item.y) continue; // Top target
    if (targetTop >= item.y + item.h) continue; // Bottom target

    collisions.add(item);
  }
  return collisions;
}

/// Returns a list of all static items in the layout.
Layout getStatics(Layout layout) {
  return layout.where((item) => item.isStatic).toList();
}

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

/// Recursively resolves collisions during compaction by moving items down.
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
    if (otherItem.y > currentItem.y + currentItem.h) break;
    if (collides(currentItem, otherItem)) {
      resolveCompactionCollision(layout, otherItem, moveToCoord + sizeProp, axis);
    }
  }

  return currentItem.copyWith(
    x: axis == 'x' ? moveToCoord : currentItem.x,
    y: axis == 'y' ? moveToCoord : currentItem.y,
  );
}

/// Compacts the layout by moving all items up as much as possible.
///
/// This function sorts the layout items and then compacts each one, ensuring
/// that there are no unnecessary gaps in the layout.
Layout compact(Layout layout, CompactType compactType, int cols, {bool allowOverlap = false}) {
  if (allowOverlap) return layout;

  final compareWith = getStatics(layout).toList();
  final sorted = sortLayoutItems(layout, compactType);
  final out = List<LayoutItem?>.filled(layout.length, null);

  for (final l in sorted) {
    var newL = l;
    if (!l.isStatic) {
      newL = compactItem(compareWith, l, compactType, cols, sorted);
      compareWith.add(newL);
    }

    final index = layout.indexWhere((item) => item.id == l.id);
    // if item didn't move (same x, y) and 'moved' flag is already false
    // just return instance to avoid unnecessary copy
    if (newL.x == l.x && newL.y == l.y && !l.moved) {
      out[index] = l;
    } else {
      out[index] = newL.copyWith(moved: false);
    }
  }

  return out.whereType<LayoutItem>().toList();
}

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

  // check AABB (Axis-Aligned Bounding Box).
  while (queue.isNotEmpty) {
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

  return layoutMap.values.toList();
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

    return pushedLayout;
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

  for (final item in itemsToPlace) {
    var placed = false;
    var safetyLoop = 0;

    // Try to find the first valid spot
    while (!placed && safetyLoop < 10000) {
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
