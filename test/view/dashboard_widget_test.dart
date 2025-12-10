import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/view/dashboard_item_widget.dart';

class MockInteractionCallback extends Mock {
  void call(LayoutItem item);
}

void main() {
  setUpAll(() {
    registerFallbackValue(const LayoutItem(id: '_', x: 0, y: 0, w: 0, h: 0));
  });

  group('Dashboard Widget Tests', () {
    late DashboardController controller;

    final testLayout = [
      const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
      const LayoutItem(id: 'b', x: 2, y: 0, w: 1, h: 1),
      const LayoutItem(id: 'static', x: 0, y: 2, w: 1, h: 1, isStatic: true),
    ];

    setUp(() {
      controller = DashboardController(initialLayout: testLayout, initialSlotCount: 4);
    });

    Widget buildTestableWidget(
      DashboardController ctrl, {
      Widget? externalDraggable,
      Axis scrollDirection = Axis.vertical,
      DashboardGuidance? guidance,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: Dashboard<String>(
                  controller: ctrl,
                  scrollDirection: scrollDirection,
                  onDrop: (data, layoutItem) => data,
                  guidance: guidance,
                  itemBuilder: (context, item) {
                    return ColoredBox(
                      color: item.id == '__placeholder__'
                          ? Colors.red.withValues(alpha: 0.5)
                          : Colors.blue,
                      child: Center(child: Text(item.id)),
                    );
                  },
                ),
              ),
              if (externalDraggable != null) externalDraggable,
            ],
          ),
        ),
      );
    }

    testWidgets('renders items from the controller', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestableWidget(controller));
      await tester.pumpAndSettle();

      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.text('static'), findsOneWidget);
    });

    testWidgets('onInteractionStart callback is fired on mobile', (WidgetTester tester) async {
      final originalPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final mockCallback = MockInteractionCallback();
        controller = DashboardController(
          initialLayout: testLayout,
          initialSlotCount: 4,
          onInteractionStart: mockCallback.call,
        )..toggleEditing();
        await tester.pumpWidget(buildTestableWidget(controller));
        await tester.pumpAndSettle();

        final draggableItemFinder = find.widgetWithText(DashboardItemWrapper, 'a');

        await tester.longPress(draggableItemFinder);
        await tester.pump();

        final captured = verify(() => mockCallback.call(captureAny())).captured;
        expect((captured.first as LayoutItem).id, 'a');
      } finally {
        debugDefaultTargetPlatformOverride = originalPlatform;
      }
    });

    testWidgets('tapping a static item does not start an operation', (WidgetTester tester) async {
      controller.toggleEditing();
      await tester.pumpWidget(buildTestableWidget(controller));
      await tester.pumpAndSettle();

      final staticItemFinder = find.widgetWithText(DashboardItemWrapper, 'static');

      await tester.longPress(staticItemFinder);
      await tester.pump();

      expect(controller.internal.activeItem.value, isNull);
    });

    testWidgets('dragging from center starts a drag operation', (WidgetTester tester) async {
      final originalPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        controller.toggleEditing();
        await tester.pumpWidget(buildTestableWidget(controller));
        await tester.pumpAndSettle();

        final draggableItemFinder = find.widgetWithText(DashboardItemWrapper, 'a');
        final gesture = await tester.startGesture(tester.getCenter(draggableItemFinder));
        await tester.pump(); // Process down event

        // Move slightly to trigger pan
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();

        expect(controller.internal.activeItem.value, isNotNull);
        expect(controller.internal.activeItem.value?.id, 'a');

        await gesture.up();
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = originalPlatform;
      }
    });

    testWidgets('dragging from bottom-right corner starts a resize operation', (
      WidgetTester tester,
    ) async {
      final originalPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        controller.toggleEditing();
        await tester.pumpWidget(buildTestableWidget(controller));
        await tester.pumpAndSettle();

        final resizableItemFinder = find.widgetWithText(DashboardItemWrapper, 'a');

        final itemRect = tester.getRect(resizableItemFinder);
        final gesture = await tester.startGesture(itemRect.bottomRight - const Offset(5, 5));
        await tester.pump();

        expect(
          controller.internal.activeItem.value,
          isNotNull,
          reason: 'Controller did not register an active item on resize start.',
        );
        expect(controller.internal.activeItem.value?.id, 'a');

        await gesture.moveBy(const Offset(150, 150));
        await tester.pump();

        final resizedItem = controller.layout.value.firstWhere((i) => i.id == 'a');
        expect(resizedItem.w, greaterThan(2), reason: 'Width did not increase after resize.');
        expect(resizedItem.h, greaterThan(2), reason: 'Height did not increase after resize.');

        await gesture.up();
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = originalPlatform;
      }
    });

    testWidgets('renders and drags correctly in horizontal mode', (WidgetTester tester) async {
      final originalPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        controller.layout.value = [
          const LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 2),
          const LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
        ];
        controller.toggleEditing();
        await tester.pumpWidget(buildTestableWidget(controller, scrollDirection: Axis.horizontal));
        await tester.pumpAndSettle();

        final itemBFinder = find.widgetWithText(DashboardItemWrapper, 'b');
        final gesture = await tester.startGesture(tester.getCenter(itemBFinder));
        await tester.pump();

        // Move slightly to trigger pan
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump();

        await gesture.moveBy(const Offset(150, 0));
        await tester.pump();

        final movedItem = controller.layout.value.firstWhere((i) => i.id == 'b');
        expect(movedItem.x, greaterThan(1), reason: 'Item "b" should have moved horizontally.');

        await gesture.up();
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = originalPlatform;
      }
    });

    testWidgets('onPointerCancel gracefully ends a drag operation', (WidgetTester tester) async {
      final originalPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        controller.toggleEditing();
        await tester.pumpWidget(buildTestableWidget(controller));
        await tester.pumpAndSettle();

        final draggableItemFinder = find.widgetWithText(DashboardItemWrapper, 'a');
        final gesture = await tester.startGesture(tester.getCenter(draggableItemFinder));
        await tester.pump();

        // Move slightly to trigger pan
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();

        expect(controller.internal.activeItem.value?.id, 'a');

        await gesture.cancel();
        await tester.pump();

        expect(
          controller.internal.activeItem.value,
          isNull,
          reason: 'Controller should not have an active item after gesture cancellation.',
        );
      } finally {
        debugDefaultTargetPlatformOverride = originalPlatform;
      }
    });
  });

  group('Dashboard Widget Tests (External DragTarget)', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(initialLayout: [], initialSlotCount: 4);
    });

    Widget buildTestableWidget(
      DashboardController ctrl, {
      Widget? externalDraggable,
      Axis scrollDirection = Axis.vertical,
      DashboardDropCallback<String>? onDrop,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: Dashboard<String>(
                  controller: ctrl,
                  scrollDirection: scrollDirection,
                  onDrop: onDrop ?? (data, layoutItem) => data,
                  itemBuilder: (context, item) {
                    return ColoredBox(
                      color: item.id == '__placeholder__'
                          ? Colors.red.withValues(alpha: 0.5)
                          : Colors.blue,
                      child: Center(child: Text(item.id)),
                    );
                  },
                ),
              ),
              if (externalDraggable != null) externalDraggable,
            ],
          ),
        ),
      );
    }

    testWidgets('onLeave hides placeholder when external draggable leaves the target', (
      WidgetTester tester,
    ) async {
      const draggable = Draggable<String>(
        data: 'new_item',
        feedback: SizedBox(width: 20, height: 20, child: Text('Drag')),
        child: SizedBox(width: 20, height: 20, child: Text('Source')),
      );

      await tester.pumpWidget(
        buildTestableWidget(
          controller,
          externalDraggable: const Align(
            alignment: Alignment.topLeft,
            child: draggable,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dragGesture = await tester.startGesture(tester.getCenter(find.text('Source')));
      await tester.pump();

      await dragGesture.moveTo(tester.getCenter(find.byType(Dashboard<String>)));
      await tester.pump();

      expect(find.text('__placeholder__'), findsOneWidget);
      expect(controller.layout.value.any((i) => i.id == '__placeholder__'), isTrue);

      // Move to negative coordinates to guarantee exit
      await dragGesture.moveTo(const Offset(-20, -20));
      await tester.pump();

      // Wait + pump to be sure widget is updated
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('__placeholder__'), findsNothing);
      expect(controller.layout.value.any((i) => i.id == '__placeholder__'), isFalse);

      await dragGesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('hides placeholder when onDrop returns null', (WidgetTester tester) async {
      const draggable = Draggable<String>(
        data: 'new_item',
        feedback: SizedBox(width: 20, height: 20, child: Text('Drag')),
        child: SizedBox(width: 20, height: 20, child: Text('Source')),
      );

      await tester.pumpWidget(
        buildTestableWidget(
          controller,
          onDrop: (data, layoutItem) => null,
          externalDraggable: const Align(
            alignment: Alignment.topLeft,
            child: draggable,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dragGesture = await tester.startGesture(tester.getCenter(find.text('Source')));
      await tester.pump();

      await dragGesture.moveTo(tester.getCenter(find.byType(Dashboard<String>)));
      await dragGesture.up();
      await tester.pumpAndSettle();

      expect(find.text('__placeholder__'), findsNothing);
      expect(controller.layout.value.isEmpty, isTrue);
    });
  });

  group('Dashboard Guidance Tests', () {
    late DashboardController controller;
    const guidance = DashboardGuidance(
      move: InteractionGuidance(
        SystemMouseCursors.grab,
        'Custom Move',
      ),
      tapToMove: 'Custom Tap',
    );

    final testLayout = [const LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2, isResizable: false)];

    setUp(() {
      controller = DashboardController(initialLayout: testLayout, initialSlotCount: 4);
    });

    Widget buildTestableWidget({
      DashboardGuidance? guidance,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Dashboard<String>(
            controller: controller,
            guidance: guidance,
            itemBuilder: (context, item) {
              return Center(child: Text(item.id));
            },
          ),
        ),
      );
    }

    testWidgets('shows hover message on desktop', (tester) async {
      final originalPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        controller.toggleEditing();

        await tester.pumpWidget(buildTestableWidget(guidance: guidance));
        await tester.pumpAndSettle();

        final itemFinder = find.byType(DashboardItemWrapper);
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer();
        await gesture.moveTo(tester.getCenter(itemFinder));
        await tester.pumpAndSettle();

        expect(find.text('Custom Move'), findsOneWidget);

        // Move to negative coordinates to guarantee exit
        await gesture.moveTo(const Offset(-20, -20));
        await tester.pumpAndSettle();

        expect(find.text('Custom Move'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = originalPlatform;
      }
    });

    testWidgets('shows tap message on mobile', (tester) async {
      final originalPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        controller.toggleEditing();

        await tester.pumpWidget(buildTestableWidget(guidance: guidance));
        await tester.pumpAndSettle();

        final itemFinder = find.byType(DashboardItemWrapper);
        await tester.tap(itemFinder);
        await tester.pump();

        expect(find.text('Custom Tap'), findsOneWidget);

        await tester.pump(const Duration(seconds: 3));

        expect(find.text('Custom Tap'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = originalPlatform;
      }
    });
  });

  group('Dashboard Robustness Tests', () {
    testWidgets('Dashboard handles missing active item gracefully', (tester) async {
      final controller = DashboardController(
        initialLayout: [const LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Dashboard(
              controller: controller,
              itemBuilder: (_, item) => Container(key: ValueKey(item.id), color: Colors.red),
            ),
          ),
        ),
      );

      // 1. Start dragging item '1'
      // We simulate this by manually setting the controller state,
      // bypassing the gesture detector to create the "race condition" state.
      controller.internal.onDragStart('1');
      await tester.pump();

      // 2. FORCE remove the item from layout while drag is active
      // This simulates the item being deleted by an external event or race condition
      controller.removeItem('1');

      // NOTE: Normally removeItem recompresses layout.
      // We want to ensure activeItem.value is still '1' but layout doesn't have '1'.
      // The controller logic might clear activeItem on remove, so we might need to force it back
      // to simulate the exact crash scenario in the View's build method.
      // However, simply pumping might trigger the Builder with the inconsistent state.

      await tester.pump();

      // If the try/catch blocks in Dashboard.build work, this should NOT throw an exception.
      // If they fail, tester.pump() will throw "Bad state: No element".
      expect(tester.takeException(), isNull);
    });

    testWidgets('SliverDashboard updates render object properties', (tester) async {
      final controller = DashboardController(
        initialLayout: [],
        initialSlotCount: 4,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Dashboard(
            controller: controller,
            itemBuilder: (_, __) => Container(),
            scrollDirection: Axis.vertical,
          ),
        ),
      );

      // Change slot count -> Trigger updateRenderObject -> Trigger setter
      controller.setSlotCount(5);
      await tester.pump();

      // Change scroll direction -> Trigger setter
      await tester.pumpWidget(
        MaterialApp(
          home: Dashboard(
            controller: controller,
            itemBuilder: (_, __) => Container(),
            scrollDirection: Axis.horizontal, // Change here
          ),
        ),
      );
    });
  });

  group('DashboardItem Widget', () {
    Widget buildTestWrapper({
      required Widget child,
      required DashboardController controller,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: DashboardControllerProvider(
            controller: controller,
            child: child,
          ),
        ),
      );
    }

    testWidgets('Updates content only when signature changes', (tester) async {
      var buildCount = 0;
      final controller = DashboardController();

      // Not needed
      // ignore: avoid_positional_boolean_parameters
      Widget buildApp(LayoutItem item, bool isEditing) {
        return buildTestWrapper(
          controller: controller,
          child: DashboardItem(
            item: item,
            isEditing: isEditing,
            itemStyle: DashboardItemStyle.defaultStyle,
            builder: (ctx, i) {
              buildCount++;
              return Text('Build $buildCount');
            },
          ),
        );
      }

      var item = const LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1);

      // 1. Initial Build
      await tester.pumpWidget(buildApp(item, false));
      expect(buildCount, 1);

      // 2. Update with SAME content signature
      item = item.copyWith(x: 1);
      await tester.pumpWidget(buildApp(item, false));
      expect(buildCount, 1);

      // 3. Update with DIFFERENT content signature
      item = item.copyWith(w: 2);
      await tester.pumpWidget(buildApp(item, false));
      expect(buildCount, 2);

      controller.dispose();
    });
  });

  testWidgets('Drag interaction triggers feedback and hit testing', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = DashboardController(
        initialLayout: [
          const LayoutItem(id: 'item1', x: 0, y: 0, w: 2, h: 2),
        ],
      )..toggleEditing();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: Dashboard(
                controller: controller,
                itemBuilder: (ctx, item) => Container(
                  key: ValueKey('child_${item.id}'),
                  color: Colors.blue,
                ),
                itemFeedbackBuilder: (ctx, item, child) => Container(
                  key: const ValueKey('feedback'),
                  color: Colors.red,
                  width: 50,
                  height: 50,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final itemFinder = find.byKey(const ValueKey('child_item1'));

      // Simulate mouse gesture
      final gesture = await tester.startGesture(
        tester.getCenter(itemFinder),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      // Move enough to trigger drag
      await gesture.moveBy(const Offset(50, 50));
      await tester.pump();

      // Verify Feedback
      expect(find.byKey(const ValueKey('feedback')), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();

      controller.dispose();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('Dashboard Widget Updates', () {
    testWidgets('updates controller properties and scroll controller on widget update',
        (tester) async {
      final controller = DashboardController(initialSlotCount: 4);

      // 1. Initial build with internal default scroll controller
      await tester.pumpWidget(
        MaterialApp(
          home: Dashboard(
            controller: controller,
            itemBuilder: (_, __) => Container(),
            resizeBehavior: ResizeBehavior.push,
            resizeHandleSide: 10,
            guidance: DashboardGuidance.byDefault,
          ),
        ),
      );

      // 2. Rebuild with new props
      final newScrollController = ScrollController();
      const newGuidance = DashboardGuidance(tapToMove: 'New Message');

      await tester.pumpWidget(
        MaterialApp(
          home: Dashboard(
            controller: controller,
            itemBuilder: (_, __) => Container(),
            // Change: pass an external controller.
            // This should dispose the internal one.
            scrollController: newScrollController,
            // Change: ResizeBehavior
            resizeBehavior: ResizeBehavior.shrink,
            // Change: HandleSide
            resizeHandleSide: 20,
            // Change: Guidance
            guidance: newGuidance,
          ),
        ),
      );

      // Check if controller got updated
      expect(controller.resizeBehavior.value, ResizeBehavior.shrink);
      expect(controller.resizeHandleSide.value, 20.0);
      expect(controller.guidance, newGuidance);
    });
  });

  group('Dashboard Configuration Models', () {
    test('TrashPosition copyWith updates properties correctly', () {
      const original = TrashPosition(left: 10, top: 10, right: 10, bottom: 10);

      // 1. Update 'left'
      final updateLeft = original.copyWith(left: 20);
      expect(updateLeft.left, 20);
      expect(updateLeft.top, 10); // Verify others remain unchanged

      // 2. Update 'top'
      final updateTop = original.copyWith(top: 20);
      expect(updateTop.left, 10);
      expect(updateTop.top, 20);

      // 3. Update 'right'
      final updateRight = original.copyWith(right: 20);
      expect(updateRight.right, 20);

      // 4. Update 'bottom'
      final updateBottom = original.copyWith(bottom: 20);
      expect(updateBottom.bottom, 20);
    });

    test('DashboardItemStyle copyWith updates properties correctly', () {
      const original = DashboardItemStyle(
        focusColor: Colors.red,
        borderRadius: BorderRadius.zero,
      );

      final updated = original.copyWith(
        focusColor: Colors.blue,
        borderRadius: BorderRadius.circular(10),
      );

      expect(updated.focusColor, Colors.blue);
      expect(updated.borderRadius, BorderRadius.circular(10));
      // Verify focusDecoration is still null (default)
      expect(updated.focusDecoration, isNull);

      // Test keeping original values
      final kept = original.copyWith();
      expect(kept.focusColor, Colors.red);
    });
  });
}
