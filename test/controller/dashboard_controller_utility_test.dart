import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';

void main() {
  group('DashboardControllerUtils Extension Tests', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 3,
        initialLayout: const [],
      );
    });

    tearDown(() => controller.dispose());

    test('ControllerInternalAccess getter should correctly cast to DashboardControllerImpl', () {
      expect(controller.internal, isA<DashboardControllerImpl>());
    });

    group('lastRowNumber tests', () {
      test('lastRowNumber should return 0 on empty layout', () {
        final controller = DashboardController(
          initialSlotCount: 3,
          initialLayout: const [],
        );
        expect(controller.lastRowNumber, equals(0));
      });

      test('lastRowNumber should return the bottom-most boundary of a non-empty layout', () {
        controller.layout.value = const [
          LayoutItem(id: 'item_1', x: 0, y: 0, w: 1, h: 2),
          LayoutItem(id: 'item_2', x: 1, y: 1, w: 1, h: 3),
        ];
        expect(controller.lastRowNumber, equals(4)); // item_2 ends at y=4
      });
    });

    group('availableFreeAreas tests', () {
      test(
          'availableFreeAreas should return a single free area covering full slot count on empty grid',
          () {
        controller.setSlotCount(4);
        final areas = controller.availableFreeAreas;

        expect(areas.length, equals(1));
        expect(areas.first.id, equals('free_area_0'));
        expect(areas.first.x, equals(0));
        expect(areas.first.y, equals(0));
        expect(areas.first.w, equals(4));
        expect(areas.first.h, equals(1));
      });

      test(
          'availableFreeAreas should trigger the sorting tie-breaker by X when Ys match (Covers Line 98)',
          () {
        // By blocking the center column of a 3-column grid, we generate
        // two maximal free areas (columns 0 and 2) starting at the same top-left row (y=0).
        // This forces maximalRects.sort() to execute the tie-breaker 'return a.x.compareTo(b.x);'
        controller.layout.value = const [
          LayoutItem(id: 'center_blocker', x: 1, y: 0, w: 1, h: 2),
        ];
        final areas = controller.availableFreeAreas;

        expect(areas.length, equals(2));
        // Area 0: Left side of blocker
        expect(areas[0].x, equals(0));
        expect(areas[0].y, equals(0));
        expect(areas[0].w, equals(1));
        expect(areas[0].h, equals(2));

        // Area 1: Right side of blocker
        expect(areas[1].x, equals(2));
        expect(areas[1].y, equals(0));
        expect(areas[1].w, equals(1));
        expect(areas[1].h, equals(2));
      });

      test('availableFreeAreas should handle completely filled grids (Covers allRects.isEmpty)',
          () {
        // Completely filling the grid leaves no candidate free rectangles,
        // making `allRects` empty. This forces the coverage of the `if (allRects.isEmpty) return [];` branch.
        controller
          ..setSlotCount(2)
          ..layout.value = const [
            LayoutItem(id: 'full_width_blocker', x: 0, y: 0, w: 2, h: 1),
          ];
        final areas = controller.availableFreeAreas;

        expect(areas, isEmpty);
      });
    });

    group('availableHorizontalFreeAreas tests', () {
      test('availableHorizontalFreeAreas should return full-width area on empty grid', () {
        final areas = controller.availableHorizontalFreeAreas;

        expect(areas.length, equals(1));
        expect(areas.first.id, equals('free_area_0'));
        expect(areas.first.x, equals(0));
        expect(areas.first.y, equals(0));
        expect(areas.first.w, equals(3));
        expect(areas.first.h, equals(1));
      });

      test(
          'availableHorizontalFreeAreas should correctly divide horizontal runs on a non-empty grid',
          () {
        controller.layout.value = const [
          LayoutItem(id: 'blocker', x: 1, y: 0, w: 1, h: 1),
        ];
        final areas = controller.availableHorizontalFreeAreas;

        // Expect two separate 1-row-high free runs at x=0 (w=1) and x=2 (w=1)
        expect(areas.length, equals(2));
        expect(areas[0].x, equals(0));
        expect(areas[0].w, equals(1));
        expect(areas[1].x, equals(2));
        expect(areas[1].w, equals(1));
      });
    });

    group('lastRowFreeArea tests', () {
      test('lastRowFreeArea should return null on an empty grid', () {
        expect(controller.lastRowFreeArea, isNull);
      });

      test(
          'lastRowFreeArea should find the first available free area on the bottom-most row with items',
          () {
        // By completely filling row 0, we prevent free rectangles on row 1 from expanding upwards.
        // The bottom-most item starts at y=1 (lastItemRow = 1).
        // Since column 2 of Row 1 is empty, the first maximal free area is forced to start at y=1, x=2.
        controller.layout.value = const [
          LayoutItem(id: 'item_row_0', x: 0, y: 0, w: 3, h: 1),
          LayoutItem(id: 'item_row_1', x: 0, y: 1, w: 2, h: 1),
        ];
        final area = controller.lastRowFreeArea;

        expect(area, isNotNull);
        expect(area!.y, equals(1)); // verified correct bottom-most row
        expect(area.x, equals(2));
      });

      test('lastRowFreeArea should return null if the bottom-most row is completely filled', () {
        controller
          ..setSlotCount(2)
          ..layout.value = const [
            LayoutItem(id: 'item_row_0', x: 0, y: 0, w: 2, h: 1),
          ];
        expect(controller.lastRowFreeArea, isNull);
      });
    });

    group('firstFreeArea tests', () {
      test('firstFreeArea should return (0,0) on empty grid', () {
        final area = controller.firstFreeArea;

        expect(area, isNotNull);
        expect(area!.x, equals(0));
        expect(area.y, equals(0));
      });

      test('firstFreeArea should return the first available gap in visual order', () {
        controller.layout.value = const [
          LayoutItem(id: 'blocker', x: 0, y: 0, w: 1, h: 1),
        ];
        final area = controller.firstFreeArea;

        expect(area, isNotNull);
        expect(area!.x, equals(1)); // Gap at (1,0) should be returned first
        expect(area.y, equals(0));
      });
    });

    group('canItemFit tests', () {
      test('canItemFit should return true if item fits inside any calculated maximal free rect',
          () {
        controller.layout.value = const [
          LayoutItem(id: 'center_blocker', x: 1, y: 0, w: 1, h: 2),
        ];
        // Free slots are of size 1x2. A 1x2 item fits perfectly.
        const fittingItem = LayoutItem(id: 'new_item', x: 0, y: 0, w: 1, h: 2);
        expect(controller.canItemFit(fittingItem), isTrue);
      });

      test('canItemFit should return false if item dimensions exceed all available free rectangles',
          () {
        controller.layout.value = const [
          LayoutItem(id: 'center_blocker', x: 1, y: 0, w: 1, h: 2),
        ];
        // Free slots are of size 1x2. A 2x2 item cannot fit anywhere.
        const nonFittingItem = LayoutItem(id: 'new_item', x: 0, y: 0, w: 2, h: 2);
        expect(controller.canItemFit(nonFittingItem), isFalse);
      });
    });
  });
}
