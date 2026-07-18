import 'package:flutter/material.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';

//
// ignore_for_file: cascade_invocations

class MockLayoutChangeListener extends Mock {
  void call(List<LayoutItem> items, int slotCount);
}

class MockCompactorDelegate extends Mock implements CompactorDelegate {}

void main() {
  setUpAll(() {
    registerFallbackValue(<LayoutItem>[]);
  });

  group('DashboardController', () {
    late DashboardControllerImpl controller;
    final initialLayout = [
      const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2, minW: 1, minH: 1),
      const LayoutItem(id: 'b', x: 2, y: 0, w: 1, h: 1),
      const LayoutItem(id: 'static', x: 0, y: 2, w: 1, h: 1, isStatic: true),
    ];

    setUp(() {
      controller = DashboardController(initialLayout: initialLayout, initialSlotCount: 4)
          as DashboardControllerImpl;
    });

    tearDown(() => controller.dispose());

    test('initializes with correct values', () {
      expect(controller.layout.value, equals(initialLayout));
      expect(controller.slotCount.value, 4);
      expect(controller.isEditing.value, isFalse);
      expect(controller.preventCollision.value, isTrue);
    });

    test('setPreventCollision() updates the beacon', () {
      expect(controller.preventCollision.value, isTrue);
      controller.setPreventCollision(false);
      expect(controller.preventCollision.value, isFalse);
    });

    test('setAllowAutoShrink toggles the beacon', () {
      expect(controller.allowAutoShrink.value, isFalse);
      controller.setAllowAutoShrink(allow: true);
      expect(controller.allowAutoShrink.value, isTrue);
      controller.setAllowAutoShrink(allow: false);
      expect(controller.allowAutoShrink.value, isFalse);
    });

    test('setNestTargetHover sets, no-ops on same value, and clears', () {
      final impl = controller.internal;
      expect(impl.hoveredNestTargetId.value, isNull);

      impl.setNestTargetHover('a');
      expect(impl.hoveredNestTargetId.value, 'a');

      // Same value: no-op (peek fast path).
      impl.setNestTargetHover('a');
      expect(impl.hoveredNestTargetId.value, 'a');

      impl.setNestTargetHover(null);
      expect(impl.hoveredNestTargetId.value, isNull);
    });

    test('addItem() adds an item and compacts the layout', () {
      const newItem = LayoutItem(id: 'c', x: 0, y: 99, w: 1, h: 1);
      controller.addItem(newItem);

      expect(controller.layout.value.length, 4);
      expect(controller.layout.value.any((item) => item.id == 'c'), isTrue);

      final addedItem = controller.layout.value.firstWhere((item) => item.id == 'c');
      expect(addedItem.y, lessThan(99));
    });

    test('removeItem() removes an item and compacts the layout', () {
      controller.removeItem('a');
      expect(controller.layout.value.length, 2);
      expect(controller.layout.value.any((item) => item.id == 'a'), isFalse);
    });

    test('setSlotCount returns early if value is unchanged', () {
      controller.setSlotCount(4);
      final initialLayout = controller.layout.value;

      // Call again with same value
      controller.setSlotCount(4);

      expect(controller.slotCount.value, 4);
      expect(controller.layout.value, equals(initialLayout));
    });

    group('Drag Logic', () {
      test('onDragStart() does nothing for a static item', () {
        controller.onDragStart('static');
        expect(controller.activeItem.value, isNull);
        expect(controller.originalLayoutOnStart.value, isEmpty);
      });

      test('onDragUpdate() moves the item and updates the layout beacon', () {
        controller
          ..onDragStart('a')
          ..onDragUpdate(
            'a',
            const Offset(200, 200),
            slotWidth: 100,
            slotHeight: 100,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
          );

        final newLayout = controller.layout.value;
        final movedItem = newLayout.firstWhere((item) => item.id == 'a');

        expect(movedItem.x, 2);
        expect(movedItem.y, 2);
        expect(newLayout, isNot(equals(initialLayout)));
      });

      test('onDragUpdate handles horizontal scrolling logic', () {
        controller
          ..setScrollDirection(Axis.horizontal)
          ..onDragStart('a') // 'a' is at 0,0

          // Drag 1 slot right (Main Axis in horizontal)
          // Drag 1 slot down (Cross Axis in horizontal)
          ..onDragUpdate(
            'a',
            const Offset(100, 100),
            slotWidth: 100,
            slotHeight: 100,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
          );

        final item = controller.layout.value.firstWhere((i) => i.id == 'a');
        // In horizontal:
        // X is Main Axis (calculated from dx) -> 100/100 = 1
        // Y is Cross Axis (calculated from dy) -> 100/100 = 1
        expect(item.x, 1);
        expect(item.y, 1);
      });

      test('onDragEnd does not compact if compactionType is none', () {
        controller.setCompactionType(CompactType.none);

        // Setup: Item A at 0,0. Item B at 0,1.
        controller.layout.value = [
          const LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
          const LayoutItem(id: 'b', x: 0, y: 1, w: 1, h: 1),
        ];

        controller
          ..onDragStart('b')

          // Drag B down to y=3 (pixel 300).
          // Note: onDragUpdate expects absolute content position, not delta.
          // y=3 * 100 = 300.
          ..onDragUpdate(
            'b',
            const Offset(0, 300),
            slotWidth: 100,
            slotHeight: 100,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
          )
          ..onDragEnd('b');

        final itemB = controller.layout.value.firstWhere((i) => i.id == 'b');

        // If compaction was ON, B would snap back to y=1 (below A).
        // Since compaction is NULL, it should stay at y=3.
        expect(itemB.y, 3);
      });
    });

    group('Resize Logic', () {
      // test('onResizeStart() sets initial state for a resizable item', () {
      //   controller.onResizeStart('a');
      //   final activeItem = controller.activeItem.value;
      //   final originalLayout = controller.originalLayoutOnStart.value;
      //
      //   expect(activeItem, isNotNull);
      //   expect(activeItem!.id, 'a');
      //   expect(originalLayout, equals(initialLayout));
      // });

      test('onResizeUpdate() changes item dimensions', () {
        controller
          ..onResizeStart('a')
          ..onResizeUpdate(
            'a',
            ResizeHandle.bottomRight,
            const Offset(100, 100), // Pixel delta
            slotWidth: 100,
            slotHeight: 100,
            crossAxisSpacing: 0,
            mainAxisSpacing: 0,
          );

        final resizedItem = controller.layout.value.firstWhere((item) => item.id == 'a');

        // Initial w:2, h:2. Delta of 100px with slot size 100 should add 1.
        expect(resizedItem.w, 3);
        expect(resizedItem.h, 3);
      });

      test('onResizeUpdate() respects minWidth constraint', () {
        controller
          ..onResizeStart('a') // item 'a' has minW: 1
          ..onResizeUpdate(
            'a',
            ResizeHandle.bottomRight,
            const Offset(-500, 0), // Large negative delta
            slotWidth: 100,
            slotHeight: 100,
            crossAxisSpacing: 0,
            mainAxisSpacing: 0,
          );

        final resizedItem = controller.layout.value.firstWhere((item) => item.id == 'a');

        expect(resizedItem.w, 1); // Should clamp to minW
      });

      test('onResizeUpdate handles side handles (Top, Bottom, Left, Right)', () {
        controller.onResizeStart('a'); // 2x2 item at 0,0
        const slotSize = 100.0;

        // 1. Resize Right (Expand width)
        controller.onResizeUpdate(
          'a',
          ResizeHandle.right,
          const Offset(slotSize, 0),
          slotWidth: slotSize,
          slotHeight: slotSize,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
        );
        var item = controller.layout.value.firstWhere((i) => i.id == 'a');
        expect(item.w, 3); // 2 + 1

        // 2. Resize Bottom (Expand height)
        controller.onResizeUpdate(
          'a',
          ResizeHandle.bottom,
          const Offset(0, slotSize),
          slotWidth: slotSize,
          slotHeight: slotSize,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
        );
        item = controller.layout.value.firstWhere((i) => i.id == 'a');
        expect(item.h, 3); // 2 + 1

        // 3. Resize Left (Expand width leftwards)
        // Reset item to x=2 for room to move left
        controller.layout.value = [const LayoutItem(id: 'a', x: 2, y: 0, w: 2, h: 2)];
        controller
          ..onResizeStart('a')
          ..onResizeUpdate(
            'a',
            ResizeHandle.left,
            const Offset(-slotSize, 0),
            slotWidth: slotSize,
            slotHeight: slotSize,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
          );
        item = controller.layout.value.firstWhere((i) => i.id == 'a');
        expect(item.x, 1); // Moved left
        expect(item.w, 3); // Grew wider

        // 4. Resize Top (Expand height upwards)
        // Reset item to y=2
        controller.layout.value = [const LayoutItem(id: 'a', x: 0, y: 2, w: 2, h: 2)];
        controller
          ..onResizeStart('a')
          ..onResizeUpdate(
            'a',
            ResizeHandle.top,
            const Offset(0, -slotSize),
            slotWidth: slotSize,
            slotHeight: slotSize,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
          );
        item = controller.layout.value.firstWhere((i) => i.id == 'a');
        expect(item.y, 1); // Moved up
        expect(item.h, 3); // Grew taller
      });

      test('onResizeEnd does not compact if compactionType is none', () {
        controller.setCompactionType(CompactType.none);
        controller.layout.value = [
          const LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        ];

        controller
          ..onResizeStart('a')
          ..onResizeEnd('a');

        expect(controller.activeItem.value, isNull);
      });
    });

    group('External Drag Logic', () {
      test('showPlaceholder() adds a placeholder item to the layout', () {
        expect(controller.layout.value.any((i) => i.id == '__placeholder__'), isFalse);

        controller.showPlaceholder(x: 1, y: 1, w: 2, h: 2);

        expect(controller.placeholder.value, isNotNull);
        expect(controller.placeholder.value!.id, '__placeholder__');
        expect(controller.layout.value.any((i) => i.id == '__placeholder__'), isTrue);
        expect(controller.layout.value.length, initialLayout.length + 1);
      });

      test('hidePlaceholder() removes the placeholder item', () {
        controller.showPlaceholder(x: 1, y: 1, w: 2, h: 2);
        expect(controller.layout.value.any((i) => i.id == '__placeholder__'), isTrue);

        controller.hidePlaceholder();

        expect(controller.placeholder.value, isNull);
        expect(controller.layout.value.any((i) => i.id == '__placeholder__'), isFalse);
        expect(controller.layout.value.length, initialLayout.length);
      });

      test('onDropExternal() replaces placeholder with a new permanent item and no compaction', () {
        controller
          ..setCompactionType(CompactType.none)
          ..showPlaceholder(x: 3, y: 3, w: 1, h: 1)
          ..onDropExternal(newId: 'newItem');

        expect(controller.placeholder.value, isNull);
        expect(controller.layout.value.any((i) => i.id == '__placeholder__'), isFalse);

        final newItem = controller.layout.value.firstWhere(
          (i) => i.id == 'newItem',
          orElse: () => throw StateError('New item not found'),
        );
        expect(newItem, isNotNull);
        expect(newItem.x, 3);
        expect(newItem.y, 3);
      });

      test(
          'onDropExternal() replaces placeholder with a new permanent item and vertical compaction',
          () {
        controller
          ..setCompactionType(CompactType.vertical)
          ..showPlaceholder(x: 3, y: 3, w: 1, h: 1)
          ..onDropExternal(newId: 'newItem');

        expect(controller.placeholder.value, isNull);
        expect(controller.layout.value.any((i) => i.id == '__placeholder__'), isFalse);

        final newItem = controller.layout.value.firstWhere(
          (i) => i.id == 'newItem',
          orElse: () => throw StateError('New item not found'),
        );
        expect(newItem, isNotNull);
        expect(newItem.x, 3);
        expect(newItem.y, 0);
      });
    });

    group('Utility Getters', () {
      test('lastRowNumber returns correct bottom of layout', () {
        // With items, bottom is max(y+h) -> static item is at y=2, h=1, so bottom is 3
        expect(controller.lastRowNumber, 3);

        // With empty layout
        final emptyController = DashboardController();
        addTearDown(emptyController.dispose);
        expect(emptyController.lastRowNumber, 0);
      });

      test('availableFreeAreas finds empty spaces correctly', () {
        final freeAreas = controller.availableFreeAreas;

        // Based on initialLayout in a 4-column grid:
        // Occupied:
        // [a, a, b,  ]
        // [a, a,  ,  ]
        // [s,  ,  ,  ]
        // Expected free areas:
        // 1. {x: 3, y: 0, w: 1, h: 1}
        // 2. {x: 2, y: 1, w: 2, h: 1}
        // 3. {x: 1, y: 2, w: 3, h: 1}
        expect(freeAreas, hasLength(3));
        expect(
          freeAreas.any((a) => a.x == 3 && a.y == 0 && a.w == 1 && a.h == 3),
          isTrue,
        );
        expect(
          freeAreas.any((a) => a.x == 2 && a.y == 1 && a.w == 2 && a.h == 2),
          isTrue,
        );
        expect(
          freeAreas.any((a) => a.x == 1 && a.y == 2 && a.w == 3 && a.h == 1),
          isTrue,
        );
      });

      test('availableFreeAreas returns full width for empty layout', () {
        final emptyController = DashboardController(initialSlotCount: 6);
        addTearDown(emptyController.dispose);
        final freeAreas = emptyController.availableFreeAreas;
        expect(freeAreas, hasLength(1));
        expect(freeAreas.first.x, 0);
        expect(freeAreas.first.y, 0);
        expect(freeAreas.first.w, 6);
        expect(freeAreas.first.h, 1);
      });

      test('availableHorizontalFreeAreas finds horizontal empty spaces', () {
        final freeAreas = controller.availableHorizontalFreeAreas;
        // Based on initialLayout in a 4-column grid:
        // Occupied:
        // R0: [a, a, b,  ] -> Free: {x: 3, y: 0, w: 1, h: 1}
        // R1: [a, a,  ,  ] -> Free: {x: 2, y: 1, w: 2, h: 1}
        // R2: [s,  ,  ,  ] -> Free: {x: 1, y: 2, w: 3, h: 1}
        expect(freeAreas, hasLength(3));
        expect(
          freeAreas.any((a) => a.x == 3 && a.y == 0 && a.w == 1 && a.h == 1),
          isTrue,
        );
        expect(
          freeAreas.any((a) => a.x == 2 && a.y == 1 && a.w == 2 && a.h == 1),
          isTrue,
        );
        expect(
          freeAreas.any((a) => a.x == 1 && a.y == 2 && a.w == 3 && a.h == 1),
          isTrue,
        );
      });

      test('availableHorizontalFreeAreas returns full rows for empty layout', () {
        final emptyController = DashboardController(initialLayout: const [], initialSlotCount: 5);
        addTearDown(emptyController.dispose);
        final freeAreas = emptyController.availableHorizontalFreeAreas;
        expect(freeAreas, hasLength(1));
        expect(freeAreas.first.x, 0);
        expect(freeAreas.first.y, 0);
      });

      test('firstFreeArea returns the first available space from top-left', () {
        final first = controller.firstFreeArea;
        expect(first, isNotNull);
        expect(first!.x, 3);
        expect(first.y, 0);
        expect(first.w, 1);
        expect(first.h, 3);

        // Test with a layout that has no gaps in the occupied rows
        final noGapsController = DashboardController(
          initialLayout: [const LayoutItem(id: 'full', x: 0, y: 0, w: 4, h: 2)],
          initialSlotCount: 4,
        );
        addTearDown(noGapsController.dispose);
        // The layout is full, so there should be no available areas.
        expect(noGapsController.firstFreeArea, isNull);
      });

      test('lastRowFreeArea returns correct area in the last occupied row', () {
        final area = controller.lastRowFreeArea;
        // Last item row is y=2. Free area at that row is {x:1, y:2, w:3, h:1}
        expect(area, isNotNull);
        expect(area!.x, 1);
        expect(area.y, 2);
        expect(area.w, 3);
        expect(area.h, 1);
      });

      test('lastRowFreeArea returns null when last row is full', () {
        final newLayout = [
          ...initialLayout,
          const LayoutItem(id: 'filler', x: 1, y: 2, w: 3, h: 1),
        ];
        final newController = DashboardController(initialLayout: newLayout, initialSlotCount: 4);
        addTearDown(newController.dispose);
        expect(newController.lastRowFreeArea, isNull);
      });

      test('canItemFit checks if an item can be placed', () {
        // Free areas allow for these fits:
        expect(
          controller.canItemFit(const LayoutItem(id: '_', x: 0, y: 0, w: 1, h: 1)),
          isTrue,
        );
        expect(
          controller.canItemFit(const LayoutItem(id: '_', x: 0, y: 0, w: 2, h: 2)),
          isTrue,
        );
        expect(
          controller.canItemFit(const LayoutItem(id: '_', x: 0, y: 0, w: 3, h: 1)),
          isTrue,
        );
        expect(
          controller.canItemFit(const LayoutItem(id: '_', x: 0, y: 0, w: 1, h: 3)),
          isTrue,
        );

        // Too wide
        expect(
          controller.canItemFit(const LayoutItem(id: '_', x: 0, y: 0, w: 5, h: 1)),
          isFalse,
        );
        // Too high
        expect(
          controller.canItemFit(const LayoutItem(id: '_', x: 0, y: 0, w: 1, h: 4)),
          isFalse,
        );
      });
    });

    group('DashboardController onResizeUpdate', () {
      late DashboardControllerImpl controller;
      const slotWidth = 100.0;
      const slotHeight = 100.0;
      const crossAxisSpacing = 10.0;
      const mainAxisSpacing = 10.0;

      setUp(() {
        controller = DashboardController(
          initialSlotCount: 10,
          initialLayout: [
            const LayoutItem(id: 'a', x: 2, y: 2, w: 4, h: 4, minW: 2, minH: 2),
          ],
        ) as DashboardControllerImpl
          // Start a resize operation on item 'a'
          ..onResizeStart('a');
      });

      tearDown(() => controller.dispose());

      group('with vertical scroll (default)', () {
        test('should resize from topRight handle correctly', () {
          // Dragging right by 1 slot and up by 1 slot
          const delta = Offset(
            1 * (slotWidth + crossAxisSpacing),
            -1 * (slotHeight + mainAxisSpacing),
          );

          controller.onResizeUpdate(
            'a',
            ResizeHandle.topRight,
            delta,
            slotWidth: slotWidth,
            slotHeight: slotHeight,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
          );

          final resizedItem = controller.layout.value.first;
          expect(resizedItem.w, 5); // w: 4 + 1
          expect(resizedItem.h, 5); // h: 4 + 1
          expect(resizedItem.x, 2); // x should not change
          expect(resizedItem.y, 1); // y: 2 - 1
        });

        test('should resize from bottomLeft handle correctly', () {
          // Dragging left by 1 slot and down by 1 slot
          const delta = Offset(
            -1 * (slotWidth + crossAxisSpacing),
            1 * (slotHeight + mainAxisSpacing),
          );

          controller.onResizeUpdate(
            'a',
            ResizeHandle.bottomLeft,
            delta,
            slotWidth: slotWidth,
            slotHeight: slotHeight,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
          );

          final resizedItem = controller.layout.value.first;
          expect(resizedItem.w, 5); // w: 4 + 1
          expect(resizedItem.h, 5); // h: 4 + 1
          expect(resizedItem.x, 1); // x: 2 - 1
          expect(resizedItem.y, 2); // y should not change
        });

        test('should resize from topLeft handle correctly', () {
          // Dragging left by 1 slot and up by 1 slot
          const delta = Offset(
            -1 * (slotWidth + crossAxisSpacing),
            -1 * (slotHeight + mainAxisSpacing),
          );

          controller.onResizeUpdate(
            'a',
            ResizeHandle.topLeft,
            delta,
            slotWidth: slotWidth,
            slotHeight: slotHeight,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
          );

          final resizedItem = controller.layout.value.first;
          expect(resizedItem.w, 5); // w: 4 + 1
          expect(resizedItem.h, 5); // h: 4 + 1
          expect(resizedItem.x, 1); // x: 2 - 1
          expect(resizedItem.y, 1); // y: 2 - 1
        });

        test('should clamp position and width when resizing past left edge', () {
          // Try dragging left by 3 slots from x=2
          const delta = Offset(-3 * (slotWidth + crossAxisSpacing), 0);

          controller.onResizeUpdate(
            'a',
            ResizeHandle.topLeft,
            delta,
            slotWidth: slotWidth,
            slotHeight: slotHeight,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
          );

          final resizedItem = controller.layout.value.first;
          // Original x was 2. Dragging left by 3 makes temp newX = -1.
          // It should be clamped to 0.
          expect(resizedItem.x, 0);
          // Original width was 4. Dragging left by 3 adds 3 to width = 7.
          // Since newX was clamped from -1 to 0, width should be reduced by 1.
          // So new width should be 6.
          expect(resizedItem.w, 6);
        });

        test(
          'Resizing top edge against a static barrier does not push bottom edge downwards',
          () {
            final controller = DashboardController(
              initialSlotCount: 8,
              initialLayout: [
                const LayoutItem(
                  id: 'barrier',
                  x: 0,
                  y: 0,
                  w: 8,
                  h: 1,
                  isStatic: true,
                ),
                const LayoutItem(
                  id: 'item',
                  x: 0,
                  y: 1,
                  w: 2,
                  h: 2,
                  minH: 1,
                ),
              ],
            );
            addTearDown(controller.dispose);

            controller.setEditMode(true);

            controller.internal
              ..onResizeStart('item')
              ..onResizeUpdate(
                'item',
                ResizeHandle.top,
                const Offset(0, -200),
                slotWidth: 100,
                slotHeight: 100,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              );

            final updatedItem = controller.layout.value.firstWhere((i) => i.id == 'item');

            expect(updatedItem.y, equals(1));
            expect(updatedItem.h, equals(2));
            expect(updatedItem.y + updatedItem.h, equals(3));
          },
        );
      });

      group('with horizontal scroll', () {
        setUp(() {
          controller
            ..setScrollDirection(Axis.horizontal)
            ..onResizeStart('a'); // Re-start resize after changing direction
        });

        test('should clamp position and height when resizing past top edge', () {
          // Try dragging up by 3 slots from y=2
          const delta = Offset(0, -3 * (slotHeight + mainAxisSpacing));

          controller.onResizeUpdate(
            'a',
            ResizeHandle.topLeft,
            delta,
            slotWidth: slotWidth,
            slotHeight: slotHeight,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
          );

          final resizedItem = controller.layout.value.first;
          // Original y was 2. Dragging up by 3 makes temp newY = -1.
          // It should be clamped to 0.
          expect(resizedItem.y, 0);
          // Original height was 4. Dragging up by 3 adds 3 to height = 7.
          // Since newY was clamped from -1 to 0, height should be reduced by 1.
          // So new height should be 6.
          expect(resizedItem.h, 6);
        });

        test('should clamp height when resizing past bottom edge (slotCount)', () {
          // Try dragging down by 5 slots from y=2, h=4
          const delta = Offset(0, 5 * (slotHeight + mainAxisSpacing));

          controller.onResizeUpdate(
            'a',
            ResizeHandle.bottomRight,
            delta,
            slotWidth: slotWidth,
            slotHeight: slotHeight,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
          );

          final resizedItem = controller.layout.value.first;
          // y=2 + newH=9 > slotCount=10.
          // newH should be clamped to slotCount - y = 10 - 2 = 8
          expect(resizedItem.y, 2);
          expect(resizedItem.h, 8);
        });
      });
    });

    test('onDragUpdate handles Horizontal scrolling correctly', () {
      // Setup horizontal controller
      controller.dispose(); // Clean up previous
      controller = DashboardControllerImpl(
        initialSlotCount: 10,
        initialLayout: [const LayoutItem(id: '1', x: 0, y: 0, w: 2, h: 2)],
      )
        ..setScrollDirection(Axis.horizontal)
        ..onDragStart('1')

        // Drag to (200, 0).
        // Assuming slotWidth=100, spacing=0 for simplicity in this mental model,
        // but passing explicit sizes to the method.
        ..onDragUpdate(
          '1',
          const Offset(210, 0), // Move right
          slotWidth: 100,
          slotHeight: 100,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
        );

      // Should have moved to x=2
      expect(controller.layout.value.first.x, 2);
      expect(controller.layout.value.first.y, 0);

      // Drag vertically (should be clamped or handled differently in horizontal mode)
      controller.onDragUpdate(
        '1',
        const Offset(210, 110), // Move down
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
      );

      // In horizontal mode, Y is the cross axis (limited by slotCount), X is main (infinite)
      // Check logic in controller: clampedY = newGridY.clamp(0, slotCount - h)
      expect(controller.layout.value.first.y, 1);
    });

    test('onResizeUpdate handles ALL resize handles', () {
      controller.dispose();
      controller = DashboardControllerImpl(
        initialSlotCount: 10,
        initialLayout: [const LayoutItem(id: '1', x: 2, y: 2, w: 2, h: 2, minW: 1, minH: 1)],
      );

      const double slotSize = 100;

      // Helper to reset and start resize
      void start(ResizeHandle handle) {
        // Reset layout
        controller.layout.value = [
          const LayoutItem(id: '1', x: 2, y: 2, w: 2, h: 2, minW: 1, minH: 1),
        ];
        controller.onResizeStart('1');
      }

      // Test TOP (Should change Y and H)
      start(ResizeHandle.top);
      controller.onResizeUpdate(
        '1',
        ResizeHandle.top,
        const Offset(0, -slotSize), // Drag up 1 slot
        slotWidth: slotSize, slotHeight: slotSize, mainAxisSpacing: 0, crossAxisSpacing: 0,
      );
      var item = controller.layout.value.first;
      expect(item.y, 1, reason: 'Top handle should decrease Y');
      expect(item.h, 3, reason: 'Top handle should increase H');

      // Test LEFT (Should change X and W)
      start(ResizeHandle.left);
      controller.onResizeUpdate(
        '1',
        ResizeHandle.left,
        const Offset(-slotSize, 0), // Drag left 1 slot
        slotWidth: slotSize, slotHeight: slotSize, mainAxisSpacing: 0, crossAxisSpacing: 0,
      );
      item = controller.layout.value.first;
      expect(item.x, 1, reason: 'Left handle should decrease X');
      expect(item.w, 3, reason: 'Left handle should increase W');

      // Test BOTTOM (Should change H only)
      start(ResizeHandle.bottom);
      controller.onResizeUpdate(
        '1',
        ResizeHandle.bottom,
        const Offset(0, slotSize), // Drag down 1 slot
        slotWidth: slotSize, slotHeight: slotSize, mainAxisSpacing: 0, crossAxisSpacing: 0,
      );
      item = controller.layout.value.first;
      expect(item.y, 2, reason: 'Bottom handle should not change Y');
      expect(item.h, 3, reason: 'Bottom handle should increase H');

      // Test RIGHT (Should change W only)
      start(ResizeHandle.right);
      controller.onResizeUpdate(
        '1',
        ResizeHandle.right,
        const Offset(slotSize, 0), // Drag right 1 slot
        slotWidth: slotSize, slotHeight: slotSize, mainAxisSpacing: 0, crossAxisSpacing: 0,
      );
      item = controller.layout.value.first;
      expect(item.x, 2, reason: 'Right handle should not change X');
      expect(item.w, 3, reason: 'Right handle should increase W');
    });

    test('onDragUpdate handles Horizontal scrolling correctly', () {
      // 1. Setup horizontal controller
      controller.dispose();
      controller = DashboardControllerImpl(
        initialSlotCount: 5,
        initialLayout: [const LayoutItem(id: '1', x: 0, y: 0, w: 2, h: 2)],
      )
        ..setScrollDirection(Axis.horizontal)
        ..onDragStart('1')

        // 2. Drag to the right (X increasing) and bottom (Y increasing)
        // Random slot size for test : 100x100
        ..onDragUpdate(
          '1',
          const Offset(210, 110), // +2 slots for X, +1 slot for Y
          slotWidth: 100,
          slotHeight: 100,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
        );

      final item = controller.layout.value.first;

      // Horizontal mode:
      // X is main axis (infinite) -> should be 2
      // Y is cross axis (limited by slotCount) -> should be 1
      expect(item.x, 2, reason: 'Should move along main axis (X)');
      expect(item.y, 1, reason: 'Should move along cross axis (Y)');

      // 3. Clamping test
      controller.onDragUpdate(
        '1',
        const Offset(-50, 600), // Too much on left, too much on bottom
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
      );

      final clampedItem = controller.layout.value.first;
      expect(clampedItem.x, 0, reason: 'Should clamp X to 0');
      // slotCount(5) - h(2) = 3. So max Y is 3.
      expect(clampedItem.y, 3, reason: 'Should clamp Y to slotCount - h');
    });

    test('dispose() disposes all beacons', () async {
      // Although BeaconController handles disposal automatically via B.writable,
      // we explicitly test every beacon here. This acts as a strict anti-regression safeguard
      // in case a contributor accidentally initializes a state with Beacon.writable()
      // instead of B.writable(), which would bypass the mixin and cause a silent memory leak.

      // Explicitly wake up all late beacons
      controller
        ..layout
        ..isEditing
        ..slotCount
        ..preventCollision
        ..compactionType
        ..activeItem
        ..placeholder
        ..resizeBehavior
        ..dragOffset
        ..originalLayoutOnStart
        ..handleColor
        ..scrollDirection
        ..isResizing
        ..resizeHandleSide
        ..activeItemId
        ..selectedItemIds
        ..isDragging;

      final streamClosedExpectation = expectLater(
        controller.internal.scrollToItemRequest,
        emitsDone,
      );

      controller.dispose();

      await streamClosedExpectation;

      expect(controller.layout.isDisposed, isTrue);
      expect(controller.isEditing.isDisposed, isTrue);
      expect(controller.slotCount.isDisposed, isTrue);
      expect(controller.preventCollision.isDisposed, isTrue);
      expect(controller.compactionType.isDisposed, isTrue);
      expect(controller.activeItem.isDisposed, isTrue);
      expect(controller.placeholder.isDisposed, isTrue);
      expect(controller.resizeBehavior.isDisposed, isTrue);
      expect(controller.dragOffset.isDisposed, isTrue);
      expect(controller.originalLayoutOnStart.isDisposed, isTrue);
      expect(controller.handleColor.isDisposed, isTrue);
      expect(controller.scrollDirection.isDisposed, isTrue);
      expect(controller.isResizing.isDisposed, isTrue);
      expect(controller.resizeHandleSide.isDisposed, isTrue);
      expect(controller.activeItemId.isDisposed, isTrue);
    });

    group('Import/Export', () {
      test('exportLayout returns list of maps', () {
        controller.layout.value = [];

        controller.addItem(const LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1));
        final export = controller.exportLayout();

        expect(export, isA<List<Map<String, dynamic>>>());
        expect(export.length, 1);
        expect(export.first['id'], '1');
      });

      test('importLayout updates layout correctly', () {
        final json = [
          {'id': 'imported', 'x': 2, 'y': 2, 'w': 2, 'h': 2},
        ];

        controller.importLayout(json);

        expect(controller.layout.value.length, 1);
        final item = controller.layout.value.first;
        expect(item.id, 'imported');
        expect(item.x, 2);
        // Note: y might change due to compaction if enabled (default is vertical)
        // With default vertical compaction, y=2 becomes y=0
        expect(item.y, 0);
      });

      test('importLayout handles invalid format', () {
        final invalidJson = ['Not a map'];
        expect(
          () => controller.importLayout(invalidJson),
          throwsFormatException,
        );
      });
    });

    group('Auto Layout & Placement', () {
      test('addItem with -1 places item at the end/correctly', () {
        controller.layout.value = [
          const LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2),
        ];

        // Add item with auto placement
        controller.addItem(const LayoutItem(id: 'B', x: -1, y: -1, w: 2, h: 2));

        final b = controller.layout.value.firstWhere((i) => i.id == 'B');

        // Should be placed next to A if it fits, or below.
        // Assuming default compaction is vertical.
        expect(b.x, isNotNull);
        expect(b.y, isNotNull);
        expect(b.x, greaterThanOrEqualTo(0));
        expect(b.y, greaterThanOrEqualTo(0));
      });

      test('addItems mixes fixed and auto placement', () {
        controller.layout.value = [];
        controller
          ..setSlotCount(4)
          ..addItems([
            const LayoutItem(id: 'Fixed', x: 2, y: 0, w: 2, h: 2),
            const LayoutItem(id: 'Auto', x: -1, y: -1, w: 2, h: 2),
          ]);

        final fixed = controller.layout.value.firstWhere((i) => i.id == 'Fixed');
        final auto = controller.layout.value.firstWhere((i) => i.id == 'Auto');

        expect(fixed.x, 2);
        expect(fixed.y, 0);

        expect(auto.x, 0);
        expect(auto.y, 0);
      });

      group('Add Items Logic', () {
        test('addItem delegates to addItems and handles -1 correctly', () {
          // 1. Setup: Clear layout and set fixed width
          controller.layout.value = [];
          controller.setSlotCount(4);

          // 2. 2. Place item A at (0,0) with size 2x2
          controller.layout.value = [
            const LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2),
          ];

          // 3. Action: Add item with -1 (Auto placement)
          controller.addItem(
            const LayoutItem(id: 'B', x: -1, y: -1, w: 2, h: 2),
          );

          final a = controller.layout.value.firstWhere((i) => i.id == 'A');
          final b = controller.layout.value.firstWhere((i) => i.id == 'B');

          // A should not move
          expect(a.x, 0);
          expect(a.y, 0);

          // B should be placed below A
          // A occupies y=0 and y=1. Bottom is at y=2.
          // B is placed at y=2. Compaction cannot move it up because (0,0) is taken.
          expect(b.x, 0);
          expect(b.y, 2);
        });

        test('addItems handles wrapping to next row', () {
          controller.setSlotCount(4);
          controller.layout.value = [];

          controller.addItems([
            const LayoutItem(id: '1', x: -1, y: -1, w: 3, h: 2), // Takes 3 cols
            const LayoutItem(id: '2', x: -1, y: -1, w: 2, h: 2), // Takes 2 cols (3+2 > 4 -> Wrap)
          ]);

          final item1 = controller.layout.value.firstWhere((i) => i.id == '1');
          final item2 = controller.layout.value.firstWhere((i) => i.id == '2');

          // Item 1 at 0,0
          expect(item1.x, 0);
          expect(item1.y, 0);

          // Item 2 should wrap to next line (x=0, y=2)
          expect(item2.x, 0);
          expect(item2.y, 2);
        });

        test('addItems mixes fixed and auto placement', () {
          controller.setSlotCount(4);
          controller.layout.value = [];

          controller.addItems([
            const LayoutItem(id: 'Fixed', x: 2, y: 0, w: 2, h: 2),
            const LayoutItem(id: 'Auto', x: -1, y: -1, w: 2, h: 2),
          ]);

          final fixed = controller.layout.value.firstWhere((i) => i.id == 'Fixed');
          final auto = controller.layout.value.firstWhere((i) => i.id == 'Auto');

          expect(fixed.x, 2);
          expect(fixed.y, 0);

          // Auto logic places it at bottom initially (y=2).
          // Compaction pulls it up.
          // Is (0,0) free? Yes (Fixed is at 2,0).
          // So Auto moves to (0,0).
          expect(auto.x, 0);
          expect(auto.y, 0);
        });
      });
    });

    test('addItem with firstFit strategy fills gaps instead of appending', () {
      // Setup: Clear and configure a 3-column layout with a gap at (1,0)
      controller.setSlotCount(3);
      controller.layout.value = [
        const LayoutItem(id: 'A', x: 0, y: 0, w: 1, h: 1),
        const LayoutItem(id: 'B', x: 2, y: 0, w: 1, h: 1),
      ];

      // Action: Add a new item utilizing the FirstFit strategy
      controller.addItem(
        const LayoutItem(id: 'new', x: -1, y: -1, w: 1, h: 1),
        strategy: AutoPlacementStrategy.firstFit,
      );

      final placed = controller.layout.value.firstWhere((i) => i.id == 'new');

      // Verify it filled the gap at (1,0)
      expect(placed.x, 1);
      expect(placed.y, 0);
    });

    test('addItems with default strategy appends at the bottom', () {
      // Setup: Gap at (1,0)
      controller.setSlotCount(3);
      controller.layout.value = [
        const LayoutItem(id: 'A', x: 0, y: 0, w: 1, h: 1),
        const LayoutItem(id: 'B', x: 2, y: 0, w: 1, h: 1),
      ];

      // Action: Add item without specifying strategy (defaults to appendBottom)
      controller.addItem(
        const LayoutItem(id: 'new', x: -1, y: -1, w: 1, h: 1),
      );

      final placed = controller.layout.value.firstWhere((i) => i.id == 'new');

      // Verify it appended at y=1, keeping backwards-compatibility intact
      expect(placed.y, 1);
      expect(placed.x, 0);
    });

    test('importLayout handles untyped Maps (dynamic)', () {
      final untypedList = [
        <dynamic, dynamic>{'id': '1', 'x': 0, 'y': 0, 'w': 1, 'h': 1},
      ];
      controller.importLayout(untypedList);
      expect(controller.layout.value.first.id, '1');
    });

    test('onResizeUpdate clamps width when expanding past right edge (Vertical)', () {
      // Setup: Item 'b' at x=2, w=1. SlotCount=4.
      // +3 (target w=4).
      // x(2) + w(4) = 6 > 4.
      // Width should be clamped at 4 - 2 = 2.

      controller
        ..onResizeStart('b')
        ..onResizeUpdate(
          'b',
          ResizeHandle.right,
          const Offset(300, 0), // +3 slots
          slotWidth: 100, slotHeight: 100, mainAxisSpacing: 0, crossAxisSpacing: 0,
        );

      final item = controller.layout.value.firstWhere((i) => i.id == 'b');
      expect(item.w, 2); // Clamped
    });

    test('onResizeUpdate clamps height/position in Horizontal mode', () {
      controller
        ..setScrollDirection(Axis.horizontal)
        ..onResizeStart('b') // b is at y=0, h=1. SlotCount=4.

        // 1. Resize TOP (y < 0)
        ..onResizeUpdate(
          'b',
          ResizeHandle.top,
          const Offset(0, -200), // -2 slots
          slotWidth: 100, slotHeight: 100, mainAxisSpacing: 0, crossAxisSpacing: 0,
        );
      var item = controller.layout.value.firstWhere((i) => i.id == 'b');
      expect(item.y, 0); // Clamped to 0

      // 2. Resize BOTTOM (> slotCount)
      // Reset
      controller
        ..onResizeStart('b')
        ..onResizeUpdate(
          'b',
          ResizeHandle.bottom,
          const Offset(0, 500), // +5 slots. Total h=6. y(0)+h(6) > 4.
          slotWidth: 100, slotHeight: 100, mainAxisSpacing: 0, crossAxisSpacing: 0,
        );
      item = controller.layout.value.firstWhere((i) => i.id == 'b');
      expect(item.h, 4); // Clamped to slotCount (4)
    });
  });

  group('A11y Keyboard Control', () {
    late DashboardControllerImpl controller;
    late MockLayoutChangeListener mockListener;

    const initialLayout = [
      LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2),
      LayoutItem(id: 'B', x: 2, y: 0, w: 2, h: 1),
      LayoutItem(id: 'C', x: 0, y: 2, w: 4, h: 1, isStatic: true), // Static item at the bottom
    ];

    const initialSlotCount = 4;

    setUp(() {
      mockListener = MockLayoutChangeListener();
      controller = DashboardControllerImpl(
        initialSlotCount: initialSlotCount,
        initialLayout: initialLayout,
        onLayoutChanged: mockListener.call,
      );
    });

    tearDown(() => controller.dispose());

    test('moveActiveItemBy moves the item and resolves collision', () {
      // 1. Start a drag operation (simulating Grab)
      controller
        ..onDragStart('A')

        // 2. Move item A (2x2) one slot right (x=1, y=0)
        ..moveActiveItemBy(1, 0);

      // Verify layout update
      final newLayout = controller.layout.value;
      final itemA = newLayout.firstWhere((i) => i.id == 'A');

      // Should move to x=1
      expect(itemA.x, 1);
      expect(itemA.y, 0);

      // Item B should be pushed down by A (to y=2) and then by C (to y=3)
      final itemB = newLayout.firstWhere((i) => i.id == 'B');
      expect(itemB.y, 3);
      expect(itemB.x, 2);

      // 3. Move item A one slot down (x=1, y=1)
      // CRITICAL: This move collides with Static Item C at y=2. It should be blocked.
      controller.moveActiveItemBy(0, 1);
      final layoutAfterDown = controller.layout.value;
      final itemAAfterDown = layoutAfterDown.firstWhere((i) => i.id == 'A');

      // Should NOT move from the previous position (x=1, y=0)
      expect(itemAAfterDown.x, 1);
      expect(itemAAfterDown.y, 0);

      // The layout should have reverted to the state *before* the failed move.
      final itemBAfterDown = layoutAfterDown.firstWhere((i) => i.id == 'B');
      expect(itemBAfterDown.y, 3); // B should still be at y=3

      // moveActiveItemBy is an intermediate step (like onDragUpdate)
      // and should NOT trigger the persistence listener.
      verifyNever(() => mockListener.call(any(), initialSlotCount));
    });

    test('moveActiveItemBy clamps movement to grid boundaries', () {
      controller
        ..onDragStart('A') // A is at x=0, w=2, slotCount=4

        // Try to move left past 0
        ..moveActiveItemBy(-5, 0);
      var itemA = controller.layout.value.firstWhere((i) => i.id == 'A');
      expect(itemA.x, 0); // Clamped to 0

      // Try to move right past slotCount - w (4 - 2 = 2)
      controller.moveActiveItemBy(5, 0);
      itemA = controller.layout.value.firstWhere((i) => i.id == 'A');
      expect(itemA.x, 2); // Clamped to 2

      // Try to move up past 0
      controller.moveActiveItemBy(0, -5);
      itemA = controller.layout.value.firstWhere((i) => i.id == 'A');
      expect(itemA.y, 0); // Clamped to 0
    });

    test('cancelInteraction reverts layout and resets state', () {
      // Item A is at (0,0) at the start
      expect(controller.layout.value.firstWhere((i) => i.id == 'A').y, 0);

      // 1. Start drag and make a change
      controller
        ..onDragStart('A')
        ..moveActiveItemBy(1, 0) // Item A moves to (1,0)

        // 2. Cancel interaction
        ..cancelInteraction();

      // 3. Verify layout reverted
      final itemA = controller.layout.value.firstWhere((i) => i.id == 'A');
      expect(itemA.x, 0); // Reverted
      expect(itemA.y, 0); // Reverted
    });

    test('cancelInteraction does nothing if no item is active', () {
      // Ensure no active item
      controller.internal.activeItem.value = null;

      // Try to cancel
      controller.cancelInteraction();

      // Should not throw and state should remain clean
      expect(controller.activeItemId.value, isNull);
    });
  });

  group('DashboardController (Multi-Selection)', () {
    late DashboardControllerImpl controller;
    late MockLayoutChangeListener mockListener;

    final initialLayout = [
      const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2, minW: 1, minH: 1),
      const LayoutItem(id: 'b', x: 2, y: 0, w: 1, h: 1),
      const LayoutItem(id: 'c', x: 0, y: 2, w: 1, h: 1),
      const LayoutItem(id: 'static', x: 3, y: 0, w: 1, h: 1, isStatic: true),
    ];

    const initialSlotCount = 4;

    setUp(() {
      mockListener = MockLayoutChangeListener();
      controller = DashboardControllerImpl(
        initialLayout: initialLayout,
        initialSlotCount: initialSlotCount,
        onLayoutChanged: mockListener.call,
      );
    });

    tearDown(() => controller.dispose());

    test('initializes with correct values', () {
      expect(controller.layout.value, equals(initialLayout));
      expect(controller.selectedItemIds.value, isEmpty);
      expect(controller.activeItemId.value, isNull);
      expect(controller.isDragging.value, isFalse);
    });

    group('Selection Logic', () {
      test('toggleSelection(multi: false) selects single item and clears others', () {
        // Select 'a'
        controller.toggleSelection('a');
        expect(controller.selectedItemIds.value, {'a'});
        expect(controller.activeItemId.value, 'a');

        // Select 'b' (should replace 'a')
        controller.toggleSelection('b');
        expect(controller.selectedItemIds.value, {'b'});
        expect(controller.activeItemId.value, 'b');
      });

      test('toggleSelection(multi: true) adds/removes items', () {
        // Select 'a'
        controller
          ..toggleSelection('a')

          // Add 'b'
          ..toggleSelection('b', multi: true);
        expect(controller.selectedItemIds.value, {'a', 'b'});

        // Active item should be one of them (usually the first or last added depending on impl)
        expect(controller.activeItemId.value, isNotNull);

        // Remove 'a'
        controller.toggleSelection('a', multi: true);
        expect(controller.selectedItemIds.value, {'b'});
      });

      test('clearSelection() empties the set', () {
        controller
          ..toggleSelection('a')
          ..clearSelection();
        expect(controller.selectedItemIds.value, isEmpty);
        expect(controller.activeItemId.value, isNull);
      });
    });

    group('Drag Logic (Cluster)', () {
      test('onDragStart() selects item if not selected', () {
        controller.onDragStart('a');

        expect(controller.selectedItemIds.value, {'a'});
        expect(controller.isDragging.value, isTrue);
        expect(controller.activeItemId.value, 'a');
      });

      test('onDragStart() preserves selection if item is already part of group', () {
        // Select 'a' and 'b' first
        controller
          ..toggleSelection('a')
          ..toggleSelection('b', multi: true)

          // Start dragging 'a'
          ..onDragStart('a');

        // Should still have both selected
        expect(controller.selectedItemIds.value, {'a', 'b'});
        expect(controller.isDragging.value, isTrue);
        // Pivot is 'a'
        expect(controller.activeItemId.value, 'a');
      });

      test('onDragUpdate() moves the whole cluster', () {
        // Setup: A at (0,0), B at (2,0)
        controller
          ..toggleSelection('a')
          ..toggleSelection('b', multi: true)
          ..onDragStart('a') // Pivot is A

          // Move A by 1 slot right (100px) and 1 slot down (100px)
          ..onDragUpdate(
            'a',
            const Offset(100, 100),
            slotWidth: 100,
            slotHeight: 100,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
          );

        final newLayout = controller.layout.value;
        final itemA = newLayout.firstWhere((i) => i.id == 'a');
        final itemB = newLayout.firstWhere((i) => i.id == 'b');

        // A should move to (1,1)
        expect(itemA.x, 1);
        expect(itemA.y, 1);

        // B should move relative to A.
        // Original B was at (2,0). A moved +1,+1.
        // B should be at (3,1).
        expect(itemB.x, 3);
        expect(itemB.y, 1);
      });

      test('onDragEnd() finalizes layout and resets drag state but keeps selection', () {
        controller
          ..onDragStart('a')
          ..onDragUpdate(
            'a',
            const Offset(100, 0),
            slotWidth: 100,
            slotHeight: 100,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
          )
          ..onDragEnd('a');

        expect(controller.isDragging.value, isFalse);
        // Selection should persist after drop (standard UX)
        expect(controller.selectedItemIds.value, {'a'});

        verify(() => mockListener.call(any(), initialSlotCount)).called(1);
      });
    });

    group('Resize Logic (Restricted)', () {
      test('onResizeStart() clears multi-selection and selects only the resized item', () {
        // Select 'a' and 'b'
        controller
          ..toggleSelection('a')
          ..toggleSelection('b', multi: true)

          // Start resizing 'a'
          ..onResizeStart('a');

        // Should force single selection on 'a'
        expect(controller.selectedItemIds.value, {'a'});
        expect(controller.isDragging.value, isFalse);
        expect(controller.isResizing.value, isTrue);
      });

      test('onResizeUpdate() works as before for single item', () {
        controller
          ..onResizeStart('a')
          ..onResizeUpdate(
            'a',
            ResizeHandle.bottomRight,
            const Offset(100, 100),
            slotWidth: 100,
            slotHeight: 100,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
          );

        final itemA = controller.layout.value.firstWhere((i) => i.id == 'a');
        expect(itemA.w, 3); // 2 + 1
        expect(itemA.h, 3); // 2 + 1
      });

      test('moveActiveItemBy clamps to grid in Horizontal mode', () {
        controller
          ..setScrollDirection(Axis.horizontal)
          ..toggleSelection('a') // a is at 0,0

          // 1. Move Left (x < 0) -> Clamped
          ..moveActiveItemBy(-1, 0);
        expect(controller.layout.value.firstWhere((i) => i.id == 'a').x, 0);

        // 2. Move Up (y < 0) -> Clamped
        controller.moveActiveItemBy(0, -1);
        expect(controller.layout.value.firstWhere((i) => i.id == 'a').y, 0);

        // 3. Move Down (y > slotCount) -> Clamped
        // a has h=2. SlotCount=4. Max Y = 2.
        controller.moveActiveItemBy(0, 10);
        expect(controller.layout.value.firstWhere((i) => i.id == 'a').y, 2);
      });

      test('optimizeLayout calls engine and updates layout', () {
        // Setup a layout with a gap
        controller.layout.value = [
          const LayoutItem(id: '1', x: 0, y: 1, w: 1, h: 1), // Gap at 0,0
        ];

        controller.optimizeLayout();

        final item = controller.layout.value.first;
        // Should be moved to 0,0
        expect(item.y, 0);
        // Listener called
        verify(() => mockListener.call(any(), any())).called(1);
      });
    });
  });

  group('Compaction Strategies & Overrides', () {
    late MockLayoutChangeListener mockListener;
    late DashboardControllerImpl controller;
    final initialLayout = [
      const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2, minW: 1, minH: 1),
      const LayoutItem(id: 'b', x: 2, y: 0, w: 1, h: 1),
      const LayoutItem(id: 'static', x: 0, y: 2, w: 1, h: 1, isStatic: true),
    ];

    setUp(() {
      mockListener = MockLayoutChangeListener();
      controller = DashboardController(
        initialLayout: initialLayout,
        initialSlotCount: 4,
        onLayoutChanged: mockListener.call,
      ) as DashboardControllerImpl;
    });

    tearDown(() => controller.dispose());

    test('setCompactionType handles Horizontal type correctly', () {
      controller.setCompactionType(CompactType.horizontal);
      expect(controller.compactionType.value, CompactType.horizontal);

      // Trigger a layout change to ensure the new compactor is used
      controller.addItem(const LayoutItem(id: 'h', x: 0, y: 0, w: 1, h: 1));
      // Horizontal compaction logic would apply here
    });

    test('setCompactor injects custom strategy and triggers re-layout', () {
      final mockCompactor = MockCompactorDelegate();
      final currentLayout = controller.layout.value;

      // Setup mock to return the same layout
      when(() => mockCompactor.compact(any(), any(), allowOverlap: any(named: 'allowOverlap')))
          .thenReturn(currentLayout);

      controller.setCompactor(mockCompactor);

      // Verify the custom compactor was used immediately
      verify(() => mockCompactor.compact(currentLayout, 4)).called(1);
      // Verify layout listener was notified
      verify(() => mockListener.call(currentLayout, 4)).called(1);
    });

    test('addItem uses temporary delegate overrides (Vertical, Horizontal, None)', () {
      // 1. Vertical Override
      controller
        ..addItem(
          const LayoutItem(id: 'v', x: 0, y: 0, w: 1, h: 1),
          overrideCompactType: CompactType.vertical,
        )

        // 2. Horizontal Override
        ..addItem(
          const LayoutItem(id: 'h', x: 0, y: 0, w: 1, h: 1),
          overrideCompactType: CompactType.horizontal,
        )

        // 3. None Override
        ..addItem(
          const LayoutItem(id: 'n', x: 0, y: 0, w: 1, h: 1),
          overrideCompactType: CompactType.none,
        );

      // Verify items were added successfully
      expect(controller.layout.value.any((i) => i.id == 'v'), isTrue);
      expect(controller.layout.value.any((i) => i.id == 'h'), isTrue);
      expect(controller.layout.value.any((i) => i.id == 'n'), isTrue);
    });
  });

  group('Programmatic Scroll Invariants', () {
    test('scrollToItem completes immediately if no overlay is listening (prevents await deadlocks)',
        () async {
      final controller = DashboardController(
        initialLayout: [const LayoutItem(id: 'target', x: 0, y: 0, w: 2, h: 2)],
      );

      // Verification: Calling scrollToItem on a detached controller must not hang the future
      // indefinitely when there is no attached overlay listener.
      await expectLater(
        controller.scrollToItem('target').timeout(const Duration(seconds: 1)),
        completes,
      );
    });
  });

  group('DashboardController — internal paths', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1),
          LayoutItem(id: 'b', x: 2, y: 0, w: 2, h: 1),
        ],
      );
    });

    tearDown(() => controller.dispose());

    test(
        'placeholderHitTestSnapshot: null without a placeholder, pre-push '
        'snapshot while one is active, null again after hiding', () {
      final impl = controller.internal;
      expect(impl.placeholderHitTestSnapshot, isNull);

      final before = List<LayoutItem>.from(controller.layout.value);
      impl.showPlaceholder(x: 0, y: 0, w: 2, h: 1);

      final snapshot = impl.placeholderHitTestSnapshot;
      expect(snapshot, isNotNull);
      // The snapshot is the pre-push layout: same ids and geometry as before
      // the placeholder started shoving items around.
      expect(
        snapshot!.map((i) => '${i.id}:${i.x},${i.y}').toSet(),
        before.map((i) => '${i.id}:${i.x},${i.y}').toSet(),
      );

      impl.hidePlaceholder();
      expect(impl.placeholderHitTestSnapshot, isNull);
      // Layout restored to the pre-drag state.
      expect(
        controller.layout.value.map((i) => i.id).toSet(),
        before.map((i) => i.id).toSet(),
      );
    });

    test(
        'beginCrossGridExit with CompactType.none resolves collisions '
        'instead of compacting', () {
      controller.setCompactionType(CompactType.none);
      final impl = controller.internal;

      final removed = impl.beginCrossGridExit({'a'});
      expect(removed.single.id, 'a');
      // 'b' stays exactly where it was: none-compaction must not pull it left.
      final b = controller.layout.value.single;
      expect(b.id, 'b');
      expect(b.x, 2);

      impl.finishCrossGridExit(outcome: CrossGridExitOutcome.canceled);
      expect(controller.layout.value.length, 2);
    });

    test('scrollToItem completes harmlessly for an unknown item', () async {
      // Must not hang nor throw: the unknown-id branch returns immediately.
      await expectLater(
        controller.scrollToItem('does-not-exist'),
        completes,
      );
    });

    test('scrollToItem completes when no overlay is attached', () async {
      await expectLater(
        controller.scrollToItem('a'),
        completes,
      );
    });
  });

  group('DashboardController - Cross-Grid Protocol', () {
    late DashboardController controller;
    late int layoutChangedCalls;

    setUp(() {
      layoutChangedCalls = 0;
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1),
          const LayoutItem(id: 'b', x: 2, y: 0, w: 2, h: 1),
          const LayoutItem(id: 'c', x: 0, y: 1, w: 2, h: 1),
        ],
        onLayoutChanged: (_, __) => layoutChangedCalls++,
      );
    });

    tearDown(() => controller.dispose());

    test('beginCrossGridExit removes silently and returns pre-drag geometry', () {
      final removed = controller.internal.beginCrossGridExit({'a'});

      expect(removed, hasLength(1));
      expect(removed.first.id, 'a');
      expect(removed.first.w, 2);
      // Temporary removal: the item is gone from the live layout...
      expect(controller.layout.value.any((i) => i.id == 'a'), isFalse);
      // ...but the move is NOT committed yet: no layout-changed event.
      expect(layoutChangedCalls, 0);
      expect(controller.internal.hasPendingCrossGridExit, isTrue);
      // The internal drag state is fully reset.
      expect(controller.isDragging.value, isFalse);
    });

    test('beginCrossGridExit uses the drag-start snapshot when present', () {
      controller.internal.onDragStart('a');
      // Simulate mid-drag pushes by mutating the live layout.
      controller.layout.value = [
        for (final i in controller.layout.value)
          if (i.id == 'b') i.copyWith(y: 5) else i,
      ];

      final removed = controller.internal.beginCrossGridExit({'a'});
      expect(removed.single.x, 0);
      expect(removed.single.y, 0);

      // Cancel must restore the PRE-DRAG layout, not the pushed one.
      controller.internal.finishCrossGridExit(outcome: CrossGridExitOutcome.canceled);
      final b = controller.layout.value.firstWhere((i) => i.id == 'b');
      expect(b.y, 0);
      expect(controller.layout.value.any((i) => i.id == 'a'), isTrue);
      expect(layoutChangedCalls, 0);
    });

    test('finishCrossGridExit(movedAway) commits and fires exactly one event', () {
      controller.internal.beginCrossGridExit({'a'});
      controller.internal.finishCrossGridExit(outcome: CrossGridExitOutcome.movedAway);

      expect(controller.layout.value.any((i) => i.id == 'a'), isFalse);
      expect(layoutChangedCalls, 1);
      expect(controller.internal.hasPendingCrossGridExit, isFalse);

      // Resolving twice is a no-op.
      controller.internal.finishCrossGridExit(outcome: CrossGridExitOutcome.movedAway);
      expect(layoutChangedCalls, 1);
    });

    test('finishCrossGridExit(returned) discards the snapshot silently', () {
      controller.internal.beginCrossGridExit({'a'});
      controller.internal.finishCrossGridExit(outcome: CrossGridExitOutcome.returned);

      // The item stays removed (the external-drop path re-inserted it and
      // already emitted its own event in the real flow).
      expect(controller.layout.value.any((i) => i.id == 'a'), isFalse);
      expect(layoutChangedCalls, 0);
      expect(controller.internal.hasPendingCrossGridExit, isFalse);
    });

    test('onDropExternalItem preserves id, constraints and flags', () {
      const template = LayoutItem(
        id: 'foreign',
        x: 9,
        y: 9,
        w: 2,
        h: 2,
        minW: 2,
        minH: 2,
        maxW: 3,
        maxH: 3,
        isResizable: false,
      );

      controller.internal.showPlaceholder(x: 2, y: 1, w: 2, h: 2);
      final placed = controller.internal.onDropExternalItem(template: template);

      expect(placed, isNotNull);
      expect(placed!.id, 'foreign');
      final inLayout = controller.layout.value.firstWhere((i) => i.id == 'foreign');
      expect(inLayout.minW, 2);
      expect(inLayout.minH, 2);
      expect(inLayout.maxW, 3);
      expect(inLayout.maxH, 3);
      expect(inLayout.isResizable, isFalse);
      expect(inLayout.w, 2);
      expect(inLayout.h, 2);
      // Placeholder fully cleaned up.
      expect(controller.currentDragPlaceholder, isNull);
      expect(controller.layout.value.any((i) => i.id == '__placeholder__'), isFalse);
      expect(layoutChangedCalls, 1);
    });

    test('onDropExternalItem without an active placeholder is a no-op', () {
      final placed = controller.internal.onDropExternalItem(
        template: const LayoutItem(id: 'x', x: 0, y: 0, w: 1, h: 1),
      );
      expect(placed, isNull);
      expect(layoutChangedCalls, 0);
    });

    test('setItemSize resizes, clamps to constraints and fires one event', () {
      controller.internal.layout.value = [
        const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1, minH: 1, maxH: 3),
      ];
      layoutChangedCalls = 0;

      final resized = controller.internal.setItemSize('a', h: 2);
      expect(resized!.h, 2);
      expect(layoutChangedCalls, 1);

      // Clamped to maxH.
      final clamped = controller.internal.setItemSize('a', h: 10);
      expect(clamped!.h, 3);

      // Unchanged size: no event.
      layoutChangedCalls = 0;
      controller.internal.setItemSize('a', h: 3);
      expect(layoutChangedCalls, 0);

      // Unknown id: null, no event.
      expect(controller.internal.setItemSize('zzz', h: 1), isNull);
      expect(layoutChangedCalls, 0);
    });
  });

  // Regressions for two cross-grid UX defects:
  //
  //    `beginCrossGridExit` compacted the source grid immediately, shifting
  //    everything under the pointer while the session was still targeting
  //    grids whose geometry depends on the source layout (a nested child
  //    inside a sibling item "ran away" from the drag). The source now keeps
  //    a frozen hole; compaction runs once at `finishCrossGridExit`.
  group('beginCrossGridExit — frozen hole', () {
    test('the source layout keeps its geometry during the exit window', () {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
          LayoutItem(id: 'b', x: 0, y: 2, w: 2, h: 2),
          LayoutItem(id: 'c', x: 2, y: 0, w: 2, h: 2),
        ],
      )..setCompactionType(CompactType.vertical);
      addTearDown(controller.dispose);

      final removed = controller.internal.beginCrossGridExit({'a'});
      expect(removed.single.id, 'a');

      // 'b' sat below 'a': with the old immediate compaction it was pulled
      // up to (0,0), moving under the pointer mid-session. It must stay put.
      final b = controller.layout.value.firstWhere((i) => i.id == 'b');
      expect(b.y, 2, reason: 'the exit hole must freeze the source geometry');
      expect(controller.layout.value.length, 2);
    });

    test('movedAway collapses the hole exactly once, firing onLayoutChanged', () {
      var events = 0;
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
          LayoutItem(id: 'b', x: 0, y: 2, w: 2, h: 2),
        ],
        onLayoutChanged: (_, __) => events++,
      );
      // NOTE: vertical compaction is the default. Do NOT call
      // setCompactionType here: it has no same-value guard and fires
      // onLayoutChanged unconditionally, which would offset the count below.
      addTearDown(controller.dispose);

      controller.internal
        ..beginCrossGridExit({'a'})
        ..finishCrossGridExit(outcome: CrossGridExitOutcome.movedAway);

      final b = controller.layout.value.single;
      expect(b.id, 'b');
      expect(b.y, 0, reason: 'compaction is deferred to the commit');
      expect(events, 1);
    });

    test('canceled restores the pre-drag snapshot silently', () {
      var events = 0;
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
          LayoutItem(id: 'b', x: 0, y: 2, w: 2, h: 2),
        ],
        onLayoutChanged: (_, __) => events++,
      );
      // Same note as above: vertical is already the default.
      addTearDown(controller.dispose);

      controller.internal
        ..beginCrossGridExit({'a'})
        ..finishCrossGridExit(outcome: CrossGridExitOutcome.canceled);

      expect(controller.layout.value.length, 2);
      final a = controller.layout.value.firstWhere((i) => i.id == 'a');
      expect((a.x, a.y), (0, 0));
      expect(events, 0);
    });
  });

  group('beginCrossGridExit — edge branches', () {
    test('a second begin while an exit is pending is a no-op', () {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
          LayoutItem(id: 'b', x: 2, y: 0, w: 2, h: 2),
        ],
      );
      addTearDown(controller.dispose);

      expect(controller.internal.beginCrossGridExit({'a'}).length, 1);
      expect(controller.internal.beginCrossGridExit({'b'}), isEmpty);
      // 'b' is still in the layout: the second call must not have removed it.
      expect(controller.layout.value.any((i) => i.id == 'b'), isTrue);
      controller.internal.finishCrossGridExit(outcome: CrossGridExitOutcome.canceled);
    });

    test('an unknown id removes nothing and opens no exit window', () {
      var events = 0;
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2)],
        onLayoutChanged: (_, __) => events++,
      );
      addTearDown(controller.dispose);

      expect(controller.internal.beginCrossGridExit({'ghost'}), isEmpty);
      expect(controller.layout.value.length, 1);
      // No snapshot was opened: finishing must be a silent no-op.
      controller.internal.finishCrossGridExit(outcome: CrossGridExitOutcome.movedAway);
      expect(events, 0);
    });

    test('movedAway under CompactType.none resolves collisions, not gravity', () {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
          LayoutItem(id: 'b', x: 0, y: 4, w: 2, h: 2), // floats below a hole
        ],
      )..setCompactionType(CompactType.none);
      addTearDown(controller.dispose);

      controller.internal
        ..beginCrossGridExit({'a'})
        ..finishCrossGridExit(outcome: CrossGridExitOutcome.movedAway);

      final b = controller.layout.value.single;
      expect(b.id, 'b');
      // resolveCollisions must NOT pull the floating item up: free
      // positioning is preserved on commit.
      expect(b.y, 4);
    });
  });

  //    `onDragUpdate` let the drag target grow the grid one row per row
  //    crossed below the content, making the sliver's extent chase the
  //    pointer (a sibling grid below became unreachable). Under main-axis
  //    compaction the target is now capped to the first free row past the
  //    other items.
  group('onDragUpdate — main-axis growth cap', () {
    test('under vertical compaction the drag target is capped past content', () {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
        ],
      )
        ..setCompactionType(CompactType.vertical)
        ..setEditMode(true);
      addTearDown(controller.dispose);

      controller.internal
        ..onDragStart('a')
        // Pointer 8 rows below the content (100 px slots, no spacing).
        ..onDragUpdate(
          'a',
          const Offset(0, 800),
          slotWidth: 100,
          slotHeight: 100,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
        );

      final a = controller.layout.value.firstWhere((i) => i.id == 'a');
      // maxMainOthers = 1 ('b' ends at y=1): the target is capped there
      // instead of y=8, so the grid extent stops chasing the pointer.
      expect(a.y, lessThanOrEqualTo(1));
      controller.internal.cancelInteraction();
    });

    test('CompactType.none keeps free positioning unbounded', () {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
        ],
      )
        ..setCompactionType(CompactType.none)
        ..setEditMode(true);
      addTearDown(controller.dispose);

      controller.internal
        ..onDragStart('a')
        ..onDragUpdate(
          'a',
          const Offset(0, 800),
          slotWidth: 100,
          slotHeight: 100,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
        );

      final a = controller.layout.value.firstWhere((i) => i.id == 'a');
      expect(a.y, 8, reason: 'free positioning is a feature of CompactType.none');
      controller.internal.cancelInteraction();
    });

    test(
        'horizontal scroll + horizontal compaction caps the X target '
        'symmetrically', () {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
        ],
      )
        ..setEditMode(true)
        ..setCompactionType(CompactType.horizontal);
      addTearDown(controller.dispose);
      controller.internal.setScrollDirection(Axis.horizontal);

      controller.internal
        ..onDragStart('a')
        // Pointer 8 columns past the content.
        ..onDragUpdate(
          'a',
          const Offset(800, 0),
          slotWidth: 100,
          slotHeight: 100,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
        );

      final a = controller.layout.value.firstWhere((i) => i.id == 'a');
      // maxMainOthers = 2 ('b' ends at x=2): capped there instead of x=8.
      expect(a.x, lessThanOrEqualTo(2));
      controller.internal.cancelInteraction();
    });
  });

  //    `onDragUpdate` let the drag target grow the grid one row per row
  //    crossed below the content, making the sliver's extent chase the
  //    pointer (a sibling grid below became unreachable). Under main-axis
  //    compaction the target is now capped to the first free row past the
  //    other items.
  /* group('onDragUpdate — main-axis growth cap', () {
    test('under vertical compaction the drag target is capped past content', () {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
        ],
      )
        ..setCompactionType(CompactType.vertical)
        ..setEditMode(true);
      addTearDown(controller.dispose);

      controller.internal
        ..onDragStart('a')
        // Pointer 8 rows below the content (100 px slots, no spacing).
        ..onDragUpdate(
          'a',
          const Offset(0, 800),
          slotWidth: 100,
          slotHeight: 100,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
        );

      final a = controller.layout.value.firstWhere((i) => i.id == 'a');
      // maxMainOthers = 1 ('b' ends at y=1): the target is capped there
      // instead of y=8, so the grid extent stops chasing the pointer.
      expect(a.y, lessThanOrEqualTo(1));
      controller.internal.cancelInteraction();
    });

    test('CompactType.none keeps free positioning unbounded', () {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
        ],
      )
        ..setCompactionType(CompactType.none)
        ..setEditMode(true);
      addTearDown(controller.dispose);

      controller.internal
        ..onDragStart('a')
        ..onDragUpdate(
          'a',
          const Offset(0, 800),
          slotWidth: 100,
          slotHeight: 100,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
        );

      final a = controller.layout.value.firstWhere((i) => i.id == 'a');
      expect(a.y, 8, reason: 'free positioning is a feature of CompactType.none');
      controller.internal.cancelInteraction();
    });
  });*/

  test('updateItem preserves original itemId if transform function attempts to change it', () {
    final controller = DashboardController(
      initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
    );
    addTearDown(controller.dispose);

    // Verify that the debug-time assert safeguards the item ID immutability by throwing
    expect(
      () => controller.updateItem('a', (item) => item.copyWith(id: 'b'), recompact: false),
      throwsA(isA<AssertionError>()),
    );
  });

  test('replaceItem writes through to the active cross-grid exit snapshot', () {
    final controller = DashboardController(
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
      ],
    );
    addTearDown(controller.dispose);

    final impl = controller.internal;
    impl.beginCrossGridExit({'a'}); // Seeds active cross-grid exit snapshot

    // Replace item 'b' (which is in the exit snapshot) with a mutated version
    controller.replaceItem('b', const LayoutItem(id: 'b', x: 1, y: 0, w: 2, h: 2));

    // Cancel the cross-grid exit (restores snapshot)
    impl.finishCrossGridExit(outcome: CrossGridExitOutcome.canceled);

    // Verify the restored item 'b' has the replaced dimensions (w: 2, h: 2)
    final restoredB = controller.layout.value.firstWhere((i) => i.id == 'b');
    expect(restoredB.w, equals(2));
    expect(restoredB.h, equals(2));
  });

  test('onDropExternalItem falls back to current drag placeholder when not in layout', () {
    final controller = DashboardController(
      initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
    );
    addTearDown(controller.dispose);

    final impl = controller.internal;

    // Manually assign a placeholder without invoking the showPlaceholder pipeline
    impl.placeholder.value = const LayoutItem(id: '__placeholder__', x: 1, y: 1, w: 1, h: 1);

    final placed = impl.onDropExternalItem(
      template: const LayoutItem(id: 'b', x: 0, y: 0, w: 1, h: 1),
    );

    expect(placed, isNotNull);
    expect(placed!.x, equals(1));
    expect(placed.y, equals(1));
  });

  test('setItemSize clamps height in horizontal scroll direction', () {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1, minH: 1, maxH: 2),
      ],
    );
    addTearDown(controller.dispose);

    final impl = controller.internal;
    impl.setScrollDirection(Axis.horizontal); // Horizontal scroll

    // Resize height to 10 (exceeds slotCount=4 and maxH=2)
    final resized = impl.setItemSize('a', h: 10);

    // Should be clamped to maxH (2) since maxH < slotCount (4)
    expect(resized!.h, equals(2));
  });
}
