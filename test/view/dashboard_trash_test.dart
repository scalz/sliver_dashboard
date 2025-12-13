import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

void main() {
  group('Dashboard Trash Feature', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(
        initialLayout: [const LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)],
      );
      // CRITICAL: Enable edit mode
      controller.isEditing.value = true;
    });

    testWidgets(
      'Trash arms after delay and deletes item',
      (tester) async {
        var deleted = false;
        var dragStarted = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Dashboard(
                controller: controller,
                itemBuilder: (_, item) =>
                    Container(key: ValueKey('content_${item.id}'), color: Colors.blue),
                trashHoverDelay: const Duration(milliseconds: 100),
                trashBuilder: (context, hovered, armed, activeItemId) {
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      key: const ValueKey('trash'),
                      width: 100,
                      height: 100,
                      color: armed ? Colors.red : Colors.grey,
                    ),
                  );
                },
                onItemsDeleted: (_) => deleted = true,
                onItemDragStart: (_) => dragStarted = true,
              ),
            ),
          ),
        );

        final itemFinder = find.byKey(const ValueKey('content_1'));

        // 1. Start Drag
        final gesture = await tester.startGesture(tester.getCenter(itemFinder));
        await tester.pump();

        expect(dragStarted, isTrue, reason: 'Drag should have started');

        // Wait for Trash fade-in animation (200ms)
        await tester.pump(const Duration(milliseconds: 500));

        // 2. Get Trash position NOW (after it is fully visible and layout settled)
        final trashFinder = find.byKey(const ValueKey('trash'));
        final trashCenter = tester.getCenter(trashFinder);

        // 3. Move over trash
        await gesture.moveTo(trashCenter);
        await tester.pump(); // Process the move event

        // 4. Wait for arming delay (100ms)
        // We pump frames to allow the timer to fire
        await tester.pump(const Duration(milliseconds: 500));

        // 5. Drop
        await gesture.up();
        await tester.pump(); // Process up event
        await tester.pump(); // Process deletion callback

        // 6. Verify deletion
        expect(deleted, isTrue, reason: 'Item should be deleted');
        expect(controller.layout.value, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'Trash does NOT delete if dropped before delay (Pass-through)',
      (tester) async {
        var deleted = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Dashboard(
                controller: controller,
                itemBuilder: (_, item) =>
                    Container(key: ValueKey('content_${item.id}'), color: Colors.blue),
                trashHoverDelay: const Duration(milliseconds: 500),
                trashBuilder: (context, hovered, armed, activeItemId) {
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      key: const ValueKey('trash'),
                      width: 100,
                      height: 100,
                      color: Colors.grey,
                    ),
                  );
                },
                onItemsDeleted: (_) => deleted = true,
              ),
            ),
          ),
        );

        final itemFinder = find.byKey(const ValueKey('content_1'));

        // 1. Start Drag
        final gesture = await tester.startGesture(tester.getCenter(itemFinder));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500)); // Animation

        // 2. Get Trash position
        final trashFinder = find.byKey(const ValueKey('trash'));
        final trashCenter = tester.getCenter(trashFinder);

        // 3. Move over trash
        await gesture.moveTo(trashCenter);
        await tester.pump();

        // 4. Drop IMMEDIATELY (before 500ms)
        await gesture.up();
        await tester.pump();

        // 5. Verify NO deletion
        expect(deleted, isFalse);
        expect(controller.layout.value, isNotEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  });
}
