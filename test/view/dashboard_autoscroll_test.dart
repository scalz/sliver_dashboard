import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

void main() {
  group('Dashboard Auto-scroll Interactions', () {
    late DashboardController controller;
    late ScrollController scrollController;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          const LayoutItem(id: '1', x: 0, y: 0, w: 4, h: 2, isResizable: true),
          // Anchor item to ensure scrollable area > viewport
          const LayoutItem(id: 'anchor', x: 0, y: 20, w: 1, h: 1, isStatic: true),
        ],
      );
      scrollController = ScrollController();
    });

    tearDown(() {
      controller.dispose();
      scrollController.dispose();
    });

    Widget buildTestApp({Widget? overlay}) {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: Dashboard<String>(
                  controller: controller,
                  scrollController: scrollController,
                  cacheExtent: 0,
                  itemBuilder: (ctx, item) => ColoredBox(
                    color: Colors.blue,
                    child: Text(item.id),
                  ),
                  onDrop: (data, item) async => 'new_item',
                ),
              ),
              if (overlay != null) overlay,
            ],
          ),
        ),
      );
    }

    testWidgets(
      'Internal Drag at bottom edge triggers auto-scroll',
      (tester) async {
        final originalPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;

        try {
          tester.view.physicalSize = const Size(400, 400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(buildTestApp());
          await tester.pumpAndSettle();

          // Enable editing to allow dragging
          controller.toggleEditing();
          await tester.pump();

          final itemFinder = find.byKey(const ValueKey('1'));

          // Start gesture with mouse
          final gesture = await tester.startGesture(
            tester.getCenter(itemFinder),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();

          // Move slightly to trigger drag start
          await gesture.moveBy(const Offset(0, 10));
          await tester.pump();

          // Move to bottom edge (Hot zone)
          await gesture.moveTo(const Offset(200, 390));
          await tester.pump();

          final initialScroll = scrollController.offset;

          // Wait for auto-scroll
          for (var i = 0; i < 60; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }

          expect(
            scrollController.offset,
            greaterThan(initialScroll),
            reason: 'Scroll offset should increase during internal item drag',
          );

          await gesture.up();
        } finally {
          debugDefaultTargetPlatformOverride = originalPlatform;
        }
      },
    );

    testWidgets(
      'Resize at bottom edge triggers auto-scroll and updates item height correctly',
      (tester) async {
        final originalPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;

        try {
          tester.view.physicalSize = const Size(400, 400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(buildTestApp());
          await tester.pumpAndSettle();

          controller.toggleEditing();
          await tester.pump();

          final itemFinder = find.byKey(const ValueKey('1'));
          final itemRect = tester.getRect(itemFinder);
          final handlePos = itemRect.bottomCenter - const Offset(0, 5);

          final gesture = await tester.startGesture(
            handlePos,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();

          await gesture.moveTo(const Offset(200, 390));
          await tester.pump();

          final initialScroll = scrollController.offset;
          final initialHeight = controller.layout.value.first.h;

          for (var i = 0; i < 60; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }

          expect(
            scrollController.offset,
            greaterThan(initialScroll),
            reason: 'Scroll offset should increase',
          );

          expect(
            controller.layout.value.first.h,
            greaterThan(initialHeight),
            reason: 'Item height should increase during auto-scroll',
          );

          await gesture.up();
        } finally {
          debugDefaultTargetPlatformOverride = originalPlatform;
        }
      },
    );

    testWidgets(
      'External Drag at bottom edge triggers auto-scroll without crashing',
      (tester) async {
        final originalPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;

        try {
          tester.view.physicalSize = const Size(400, 400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            buildTestApp(
              overlay: const Positioned(
                top: 0,
                left: 0,
                child: Draggable<String>(
                  data: 'external_data',
                  feedback: SizedBox(
                    width: 50,
                    height: 50,
                    child: ColoredBox(color: Colors.red),
                  ),
                  child: SizedBox(width: 50, height: 50, child: Text('Drag Me')),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final draggableFinder = find.text('Drag Me');

          final gesture = await tester.startGesture(
            tester.getCenter(draggableFinder),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();

          await gesture.moveBy(const Offset(0, 10));
          await tester.pump();

          await gesture.moveTo(const Offset(200, 390));
          await tester.pump();

          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }

          expect(
            scrollController.offset,
            greaterThan(0),
            reason: 'Should auto-scroll even for external items',
          );

          await gesture.up();
        } finally {
          debugDefaultTargetPlatformOverride = originalPlatform;
        }
      },
    );
  });
}
