import 'dart:math';

import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart' as engine;
import 'package:sliver_dashboard/src/models/layout_item.dart';

/// Provides access to the internal implementation of [DashboardController].
extension ControllerInternalAccess on DashboardController {
  /// Casts this controller to [DashboardControllerImpl] to access internal members.
  DashboardControllerImpl get internal => this as DashboardControllerImpl;
}

/// An extension on [DashboardController] to provide utility methods and getters
/// for querying the layout state.
extension DashboardControllerUtils on DashboardController {
  /// Gets the Y-coordinate of the bottom-most edge of the layout.
  /// This is useful for adding items to the next available row.
  ///
  /// For example, if the last item has `y=2` and `h=2`, its bottom edge
  /// is at `y=4`. This getter will return `4`, which is the index of
  /// the first fully empty row.
  int get lastRowNumber => engine.bottom(layout.value);

  /// Finds and returns a list of all available free rectangular areas in the grid.
  ///
  /// This can be used to identify empty spaces where new items could be placed.
  /// The areas are returned as [LayoutItem]s with a temporary ID.
  List<LayoutItem> get availableFreeAreas {
    final currentLayout = layout.peek();
    final numCols = slotCount.peek();
    final numRows = engine.bottom(currentLayout);

    if (currentLayout.isEmpty) {
      return [
        LayoutItem(id: 'free_area_0', x: 0, y: 0, w: numCols, h: 1),
      ];
    }

    final grid = List.generate(numRows, (_) => List.filled(numCols, false));
    for (final item in currentLayout) {
      for (var y = item.y; y < item.y + item.h; y++) {
        for (var x = item.x; x < item.x + item.w; x++) {
          if (y < numRows && x < numCols) {
            grid[y][x] = true;
          }
        }
      }
    }

    final heights = List.filled(numCols, 0);
    final allRects = <LayoutItem>{};

    for (var r = 0; r < numRows; r++) {
      for (var c = 0; c < numCols; c++) {
        heights[c] = grid[r][c] ? 0 : heights[c] + 1;
      }

      for (var c = 0; c < numCols; c++) {
        var minHeight = heights[c];
        for (var k = c; k >= 0; k--) {
          minHeight = min(minHeight, heights[k]);
          if (minHeight == 0) break;
          final width = c - k + 1;
          allRects.add(
            LayoutItem(
              id: '',
              x: k,
              y: r - minHeight + 1,
              w: width,
              h: minHeight,
            ),
          );
        }
      }
    }

    if (allRects.isEmpty) return [];

    final maximalRects = <LayoutItem>[];
    for (final rectA in allRects) {
      var isMaximal = true;
      for (final rectB in allRects) {
        if (identical(rectA, rectB)) continue;
        if (rectA.x >= rectB.x &&
            rectA.y >= rectB.y &&
            rectA.x + rectA.w <= rectB.x + rectB.w &&
            rectA.y + rectA.h <= rectB.y + rectB.h) {
          isMaximal = false;
          break;
        }
      }
      if (isMaximal) {
        maximalRects.add(rectA);
      }
    }

    maximalRects.sort((a, b) {
      if (a.y != b.y) return a.y.compareTo(b.y);
      return a.x.compareTo(b.x);
    });

    final result = <LayoutItem>[];
    for (var i = 0; i < maximalRects.length; i++) {
      result.add(maximalRects[i].copyWith(id: 'free_area_$i'));
    }

    return result;
  }

  /// Finds and returns a list of all available free horizontal areas in the grid.
  List<LayoutItem> get availableHorizontalFreeAreas {
    final currentLayout = layout.peek();
    final numCols = slotCount.peek();
    final numRows = engine.bottom(currentLayout);

    if (currentLayout.isEmpty) {
      return [
        LayoutItem(id: 'free_area_0', x: 0, y: 0, w: numCols, h: 1),
      ];
    }

    final grid = List.generate(numRows, (_) => List.filled(numCols, false));
    for (final item in currentLayout) {
      for (var y = item.y; y < item.y + item.h; y++) {
        for (var x = item.x; x < item.x + item.w; x++) {
          if (y < numRows && x < numCols) {
            grid[y][x] = true;
          }
        }
      }
    }

    final freeAreas = <LayoutItem>[];
    var areaIdCounter = 0;
    for (var r = 0; r < numRows; r++) {
      for (var c = 0; c < numCols; c++) {
        if (!grid[r][c]) {
          final startX = c;
          var currentW = 0;
          while (c < numCols && !grid[r][c]) {
            currentW++;
            c++;
          }
          freeAreas.add(
            LayoutItem(
              id: 'free_area_${areaIdCounter++}',
              x: startX,
              y: r,
              w: currentW,
              h: 1,
            ),
          );
        }
      }
    }

    return freeAreas;
  }

  /// Finds and returns the first available free area in the last row that contains items.
  LayoutItem? get lastRowFreeArea {
    final areas = availableFreeAreas;
    if (areas.isEmpty || layout.peek().isEmpty) return null;

    final lastItemRow = layout.peek().map((e) => e.y).reduce(max);
    final freeInLastRow = areas.where((area) => area.y == lastItemRow);

    return freeInLastRow.isEmpty ? null : freeInLastRow.first;
  }

  /// Finds and returns the first available free area in the grid.
  LayoutItem? get firstFreeArea {
    final areas = availableFreeAreas;
    return areas.isEmpty ? null : areas.first;
  }

  /// Checks if a given [LayoutItem] can fit into any of the available free spaces.
  bool canItemFit(LayoutItem item) {
    final freeAreas = availableFreeAreas;
    for (final area in freeAreas) {
      if (item.w <= area.w && item.h <= area.h) {
        return true;
      }
    }
    return false;
  }
}
