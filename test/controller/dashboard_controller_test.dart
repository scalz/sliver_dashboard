import 'package:flutter/material.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart' show CompactType;
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';

void main() {
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

      test('onDragStart() sets initial state for a draggable item', () {
        controller.onDragStart('a');
        final activeItem = controller.activeItem.value;
        final originalLayout = controller.originalLayoutOnStart.value;

        expect(activeItem, isNotNull);
        expect(activeItem!.id, 'a');
        expect(originalLayout, equals(initialLayout));
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

      test('onDragEnd() finalizes layout and cleans up state', () {
        controller
          ..addItem(const LayoutItem(id: 'c', x: 0, y: 10, w: 1, h: 1))
          ..onDragStart('c')
          ..onDragUpdate(
            'c',
            const Offset(0, 500),
            slotWidth: 100,
            slotHeight: 100,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
          )
          ..onDragEnd('c');

        final finalLayout = controller.layout.value;
        final finalItem = finalLayout.firstWhere((item) => item.id == 'c');
        expect(finalItem.y, lessThan(5));
        expect(controller.activeItem.value, isNull);
        expect(controller.originalLayoutOnStart.value, isEmpty);
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
      test('onResizeStart() sets initial state for a resizable item', () {
        controller.onResizeStart('a');
        final activeItem = controller.activeItem.value;
        final originalLayout = controller.originalLayoutOnStart.value;

        expect(activeItem, isNotNull);
        expect(activeItem!.id, 'a');
        expect(originalLayout, equals(initialLayout));
      });

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

      test('onResizeEnd() finalizes layout and cleans up state', () {
        controller
          ..onResizeStart('a')
          ..onResizeUpdate(
            'a',
            ResizeHandle.bottomRight,
            const Offset(100, 100),
            slotWidth: 100,
            slotHeight: 100,
            crossAxisSpacing: 0,
            mainAxisSpacing: 0,
          )
          ..onResizeEnd('a');

        expect(controller.activeItem.value, isNull);
        expect(controller.originalLayoutOnStart.value, isEmpty);
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

    test('dispose() disposes all beacons', () {
      controller.dispose();
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
  });
}
