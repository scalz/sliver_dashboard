import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/view/dashboard_feedback_widget.dart';
import 'package:sliver_dashboard/src/view/dashboard_grid.dart';
import 'package:sliver_dashboard/src/view/dashboard_item_widget.dart';

import '../test_helpers.dart';

//
// ignore_for_file: cascade_invocations

// Mock for the persistence callback
class MockLayoutChangeListener extends Mock {
  void call(List<LayoutItem> items, int slotCount);
}

class ExceptionThrowingScrollController extends ScrollController {
  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) {
    return Future.error(Exception('Scroll animation failed!'));
  }
}

// Utility function to explicitly request focus on a widget
Future<void> _requestFocus(WidgetTester tester, Finder itemFinder) async {
  // 1. Find the specific Semantics widget for our item.
  // We filter by 'container: true' to avoid internal framework Semantics.
  final semanticsFinder = find.descendant(
    of: itemFinder,
    matching: find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.container,
    ),
  );

  // We expect to find exactly one
  expect(
    semanticsFinder,
    findsOneWidget,
    reason: 'Specific Semantics(container: true) widget not found',
  );

  // 2. Get the context
  final BuildContext context = tester.element(semanticsFinder);

  // 3. Find the FocusNode and Request focus
  Focus.of(context).requestFocus();

  await tester.pump();
}

void main() {
  setUpAll(() {
    registerFallbackValue(const LayoutItem(id: '_', x: 0, y: 0, w: 0, h: 0));
  });

  group('DashboardOverlay Sliver Integration', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          const LayoutItem(id: '1', x: 0, y: 0, w: 2, h: 2),
        ],
      )..setEditMode(true);
    });

    tearDown(() => controller.dispose());

    testWidgets('Feedback item is positioned and clipped correctly under SliverAppBar',
        (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              itemBuilder: (context, item) => ColoredBox(
                color: Colors.blue,
                child: Text('Item ${item.id}'),
              ),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  const SliverAppBar(
                    pinned: true,
                    expandedHeight: 200,
                    title: Text('App Bar'),
                  ),
                  SliverDashboard(
                    itemBuilder: (context, item) => Text('Item ${item.id}'),
                  ),
                  // Add filler to allow scrolling
                  SliverToBoxAdapter(
                    child: Container(height: 1000, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // 1. Scroll down to trigger overlap/collapse of the AppBar
      scrollController.jumpTo(100);
      await tester.pumpAndSettle();

      final itemFinder = find.text('Item 1');

      // 2. Start Gesture manually (Down)
      final gesture = await tester.startGesture(tester.getCenter(itemFinder));

      // 3. Wait for Long Press Timeout to trigger Edit Mode
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await tester.pump(); // Build the feedback layer

      // 4. Verify Feedback Item exists
      final feedbackFinder = find.byType(DashboardFeedbackItem);
      expect(feedbackFinder, findsOneWidget);

      // 5. Verify Positioning and Clipping logic
      final feedbackWidget = tester.widget<DashboardFeedbackItem>(feedbackFinder);

      // Check if sliverBounds (clipping) is calculated
      expect(feedbackWidget.sliverBounds, isNotNull);

      // Since we scrolled down 100px, and AppBar is pinned, there should be an overlap.
      // The top of the clip rect should be > 0 (roughly the AppBar height).
      expect(feedbackWidget.sliverBounds!.top, greaterThan(0));

      // 6. Move the item (Drag)
      await gesture.moveBy(const Offset(0, 50));
      await tester.pump();

      // Ensure feedback is still there
      expect(find.byType(DashboardFeedbackItem), findsOneWidget);

      // 7. Release (Up)
      await gesture.up();
      await tester.pump();

      // Feedback should be gone
      expect(find.byType(DashboardFeedbackItem), findsNothing);
    });

    testWidgets('onItemDragUpdate is called and Trash hover state resets', (tester) async {
      var dragUpdateCalled = false;
      final trashKey = GlobalKey();
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              // Provide the callback
              onItemDragUpdate: (item, pos) {
                dragUpdateCalled = true;
              },
              // Provide trash to cover
              trashBuilder: (context, hovered, active, id) {
                return Container(
                  key: trashKey,
                  width: 100,
                  height: 100,
                  color: hovered ? Colors.red : Colors.grey,
                );
              },
              trashLayout: const TrashLayout(
                visible: TrashPosition(bottom: 0, left: 0),
                hidden: TrashPosition(bottom: -100, left: 0),
              ),
              itemBuilder: (context, item) => Container(color: Colors.blue),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverDashboard(
                    itemBuilder: (context, item) => Container(color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final itemFinder = find.byType(DashboardItem).first;

      // 1. Start Drag
      final gesture = await tester.startGesture(tester.getCenter(itemFinder));
      await tester.pump(kLongPressTimeout); // Trigger edit mode
      await tester.pump();

      // 2. Move over Trash (Trigger Hover Enter)
      final trashCenter = tester.getCenter(find.byKey(trashKey));
      await gesture.moveTo(trashCenter);
      await tester.pump();

      // 3. Move AWAY from Trash (Trigger Hover Exit)
      await gesture.moveTo(const Offset(300, 300)); // Move far away
      await tester.pump();

      // 4. Release
      await gesture.up();
      await tester.pump();

      expect(dragUpdateCalled, isTrue, reason: 'onItemDragUpdate should be called');
    });

    testWidgets('Auto-scroll triggers at edges (Top/Bottom/Left/Right)', (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      final items = List.generate(20, (i) => LayoutItem(id: '$i', x: 0, y: i, w: 1, h: 1));
      controller.layout.value = items;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              itemBuilder: (context, item) => Container(color: Colors.blue),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverDashboard(
                    itemBuilder: (context, item) => Container(color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final itemFinder = find.byType(DashboardItem).first; // Top item
      final gesture =
          await tester.startGesture(tester.getCenter(itemFinder), kind: PointerDeviceKind.mouse);
      await tester.pump(kLongPressTimeout);

      // 1. Drag to Bottom Edge (Scroll Down)
      await gesture.moveTo(const Offset(100, 580)); // Assuming 600 height
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // Wait for timer

      final offsetAfterDown = scrollController.offset;
      expect(offsetAfterDown, greaterThan(0), reason: 'Should scroll down');

      // 2. Drag to Top Edge (Scroll Up)
      await gesture.moveTo(const Offset(10, 10)); // Top of screen
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // Wait for timer

      // Verify that it scrolled back up (offset decreased)
      expect(
        scrollController.offset,
        lessThan(offsetAfterDown),
        reason: 'Scroll offset should decrease when dragging near the top edge',
      );

      await gesture.up();
    });

    testWidgets('DashboardOverlay resolves RenderSliverDashboard using sliverKey', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
        ],
      )..setEditMode(true);
      addTearDown(controller.dispose);

      final sliverKey = GlobalKey();
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              sliverKey: sliverKey,
              itemBuilder: (context, item) => SizedBox(child: Text('T-${item.id}')),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverDashboard(
                    key: sliverKey,
                    itemBuilder: (context, item) => SizedBox(child: Text('T-${item.id}')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<State<DashboardOverlay>>(find.byType(DashboardOverlay));
      final target = state as CrossGridDragTarget;

      final metrics = target.currentSlotMetrics();
      expect(metrics, isNotNull);
      expect(metrics!.slotCount, equals(4));
    });

    testWidgets('isPointInsideSliver supports Axis.horizontal scroll direction', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
        ],
      )..setEditMode(true);
      addTearDown(controller.dispose);

      final sliverKey = GlobalKey();
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 500,
              child: DashboardOverlay(
                controller: controller,
                scrollController: scrollController,
                sliverKey: sliverKey,
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, item) => SizedBox(child: Text('T-${item.id}')),
                child: CustomScrollView(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  slivers: [
                    SliverDashboard(
                      key: sliverKey,
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, item) => SizedBox(child: Text('T-${item.id}')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<State<DashboardOverlay>>(find.byType(DashboardOverlay));
      final target = state as CrossGridDragTarget;

      expect(target.isPointInsideSliver(const Offset(50, 50)), isTrue);
      expect(target.isPointInsideSliver(const Offset(999, 50)), isFalse);
    });

    testWidgets('DashboardOverlay invalidates cached render object when sliverKey changes',
        (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
      );
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      final key1 = GlobalKey();
      final key2 = GlobalKey();

      // Pump with key1
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              sliverKey: key1,
              itemBuilder: (context, item) => Text(item.id),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverDashboard(key: key1, itemBuilder: (context, item) => Text(item.id)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Re-pump with key2 to trigger didUpdateWidget key-swap
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              sliverKey: key2,
              itemBuilder: (context, item) => Text(item.id),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverDashboard(key: key2, itemBuilder: (context, item) => Text(item.id)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    });

    testWidgets(
        'onPointerMove falls back to activeItemInitialLayout if item is removed during gesture move',
        (tester) async {
      await runOnDesktop(() async {
        final controller = DashboardController(
          initialSlotCount: 4,
          initialLayout: const [
            LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
          ],
        )..setEditMode(true);
        addTearDown(controller.dispose);

        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        LayoutItem? updatedItem;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DashboardOverlay(
                controller: controller,
                scrollController: scrollController,
                onItemDragUpdate: (item, pos) {
                  updatedItem = item;
                },
                itemBuilder: (context, item) => SizedBox(child: Text(item.id)),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverDashboard(itemBuilder: (context, item) => Text(item.id)),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final itemFinder = find.text('a');
        final gesture =
            await tester.startGesture(tester.getCenter(itemFinder), kind: PointerDeviceKind.mouse);
        await tester.pump(); // Start drag instantly on desktop

        expect(controller.isDragging.value, isTrue);

        // Mutate the layout list by removing the item programmatically while dragging is in flight
        controller.internal.originalLayoutOnStart.value =
            []; // Prevent cancelInteraction from restoring the item
        controller.removeItem('a');
        controller.cancelInteraction(); // Force onDragUpdate to return early, keeping layout empty
        await tester.pump();

        // Move the pointer: this triggers onPointerMove and must resolve through the fallback
        await gesture.moveBy(const Offset(50, 50));
        await tester.pump();

        expect(updatedItem, isNotNull);
        expect(updatedItem!.id, 'a'); // Falls back to the initial layout item 'a'

        await gesture.up();
        await tester.pumpAndSettle();

        expect(controller.isDragging.value, isFalse);
      });
    });
  });

  group('DashboardItem A11y Actions (Keyboard)', () {
    late DashboardControllerImpl controller;
    late MockLayoutChangeListener mockListener;

    const itemA = LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2);
    const itemB = LayoutItem(id: 'B', x: 2, y: 0, w: 2, h: 2);

    const initialSlotCount = 4;

    setUp(() {
      mockListener = MockLayoutChangeListener();
      controller = DashboardControllerImpl(
        initialSlotCount: initialSlotCount,
        initialLayout: [itemA, itemB],
        onLayoutChanged: mockListener.call,
      )..setEditMode(true);
    });

    tearDown(() => controller.dispose());

    // Widget wrapper for the test
    Widget createDashboardItemWrapper(LayoutItem item) {
      return MaterialApp(
        home: Scaffold(
          // Wrap in FocusScope to provide a root focus hierarchy
          body: FocusScope(
            autofocus: true,
            child: DashboardControllerProvider(
              controller: controller,
              child: DashboardItem(
                key: ValueKey(item.id),
                item: item,
                isEditing: controller.isEditing.value,
                itemBuilder: (context, i) => Text(i.id),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Grabbing (Space) calls onDragStart and changes active state', (tester) async {
      await tester.pumpWidget(createDashboardItemWrapper(itemA));

      final itemAFinder = find.byKey(const ValueKey('A'));

      // 1. Request focus
      await _requestFocus(tester, itemAFinder);

      // 2. Simulate Space key press (Grab)
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      // Verify item became active
      expect(controller.activeItemId.value, 'A');
    });

    testWidgets('Dropping (Space) calls onDragEnd and resets state', (tester) async {
      // Prepare initial "Grabbed" state
      controller.onDragStart('A');
      await tester.pumpWidget(createDashboardItemWrapper(itemA));

      final itemAFinder = find.byKey(const ValueKey('A'));

      // 1. Request focus
      await _requestFocus(tester, itemAFinder);

      // 2. Simulate Space key press (Drop)
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      // Verify item is no longer active
      expect(controller.isDragging.value, isFalse);
      // Verify persistence listener was called
      verify(() => mockListener.call(any(), initialSlotCount)).called(1);
    });

    testWidgets('Move (Arrow) calls moveActiveItemBy and updates position', (tester) async {
      // Prepare initial "Grabbed" state
      controller.onDragStart('A');
      await tester.pumpWidget(createDashboardItemWrapper(itemA));

      final itemAFinder = find.byKey(const ValueKey('A'));

      // 1. Request focus
      await _requestFocus(tester, itemAFinder);

      // 2. Simulate Right Arrow
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      // Verify new position (Item A was at x=0)
      expect(controller.layout.value.firstWhere((i) => i.id == 'A').x, 1);
    });

    testWidgets('Cancel (Escape) calls cancelInteraction and reverts layout', (tester) async {
      // Prepare initial "Grabbed" and moved state
      controller
        ..onDragStart('A')
        ..moveActiveItemBy(1, 1);
      await tester.pumpWidget(createDashboardItemWrapper(itemA));

      final itemAFinder = find.byKey(const ValueKey('A'));

      // 1. Request focus
      await _requestFocus(tester, itemAFinder);

      // 2. Simulate Escape
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      // Verify item is no longer active
      expect(controller.isDragging.value, isFalse);
      // Verify position was reset
      expect(controller.layout.value.firstWhere((i) => i.id == 'A').x, 0);
    });

    testWidgets('onFocusChange calls cancelInteraction when focus is lost while active',
        (tester) async {
      // Prepare initial "Grabbed" state
      controller.onDragStart('A');
      await tester.pumpWidget(createDashboardItemWrapper(itemA));

      final itemAFinder = find.byKey(const ValueKey('A'));

      // 1. Request focus
      await _requestFocus(tester, itemAFinder);

      // 2. Simulate focus loss (unfocusing the primary node)
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();

      // Verify item is no longer active (cancelInteraction was called)
      expect(controller.isDragging.value, isFalse);
    });

    testWidgets('onShowFocusHighlight updates visual state', (tester) async {
      await tester.pumpWidget(createDashboardItemWrapper(itemA));

      final itemAFinder = find.byKey(const ValueKey('A'));

      // 1. Request focus
      await _requestFocus(tester, itemAFinder);

      // 2. Simulate a key press to force "Keyboard Mode"
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      // 3. Find the specific Container
      final opacityFinder = find.descendant(
        of: itemAFinder,
        matching: find.byType(Opacity),
      );

      final containerFinder = find
          .descendant(
            of: opacityFinder,
            matching: find.byType(Container),
          )
          .first;

      final container = tester.widget<Container>(containerFinder);

      // 4. Verify decoration
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration, isNotNull);

      // Verify against default style color (BlueAccent)
      expect(decoration!.border!.top.color, DashboardItemStyle.defaultStyle.focusColor);
    });

    testWidgets('Static item blocks Grab action', (tester) async {
      const staticItem = LayoutItem(id: 'S', x: 0, y: 0, w: 1, h: 1, isStatic: true);

      // Reinitialize controller with the static item
      controller = DashboardControllerImpl(
        initialSlotCount: 4,
        initialLayout: [staticItem],
      )..setEditMode(true);

      await tester.pumpWidget(createDashboardItemWrapper(staticItem));

      final staticItemFinder = find.byKey(const ValueKey('S'));

      // 1. Request focus
      await _requestFocus(tester, staticItemFinder);

      // 2. Simulate Space key press (Grab)
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      // Verify item did NOT become active (onDragStart was not called)
      expect(controller.activeItemId.value, isNull);
    });

    testWidgets(
      'Custom multi-select key (Alt) works',
      (tester) async {
        const itemA = LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2);
        controller.layout.value = [itemA];

        controller
          ..shortcuts = const DashboardShortcuts(
            multiSelectKeys: [LogicalKeyboardKey.altLeft],
          )
          ..toggleSelection('A');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DashboardOverlay(
                controller: controller,
                scrollController: ScrollController(),
                itemBuilder: (context, item) => Container(color: Colors.blue),
                child: CustomScrollView(
                  slivers: [
                    SliverDashboard(
                      itemBuilder: (context, item) => Container(color: Colors.blue),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // 4. Simulate ALT Key DOWN
        await simulateKeyDownEvent(
          LogicalKeyboardKey.altLeft,
          physicalKey: PhysicalKeyboardKey.altLeft,
        );

        // Pump. HardwareKeyboard process "Down" event.
        await tester.pump();

        // 5. Tap on 'A'
        final itemFinder = find.byType(DashboardItem).first;
        await tester.tap(itemFinder);

        // 6. Pump to process tap
        await tester.pump();

        // 7. Verify 'A' is unselected
        expect(controller.selectedItemIds.value.contains('A'), isFalse);

        // Cleanup
        await simulateKeyUpEvent(
          LogicalKeyboardKey.altLeft,
          physicalKey: PhysicalKeyboardKey.altLeft,
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  });

  group('DashboardOverlay Edge Cases', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          const LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1),
        ],
      )..setEditMode(true);
    });

    tearDown(() => controller.dispose());

    testWidgets('Drag and Placeholder work correctly in Horizontal Scroll mode', (tester) async {
      // 1. Setup Horizontal Dashboard + Source Draggable
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      controller.setSlotCount(4);
      (controller as DashboardControllerImpl).setScrollDirection(Axis.horizontal);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                // A. The Source (Draggable)
                // We place it outside the dashboard to simulate external drag
                Draggable<String>(
                  data: 'external_item',
                  feedback: Container(width: 50, height: 50, color: Colors.red),
                  child: Container(
                    key: const ValueKey('source_draggable'),
                    width: 50,
                    height: 50,
                    color: Colors.green,
                  ),
                ),

                // B. The Target (Dashboard)
                Expanded(
                  child: DashboardOverlay(
                    controller: controller,
                    scrollController: scrollController,
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, item) => Container(color: Colors.blue),
                    child: CustomScrollView(
                      scrollDirection: Axis.horizontal,
                      controller: scrollController,
                      slivers: [
                        SliverDashboard(
                          itemBuilder: (context, item) => Container(color: Colors.blue),
                          scrollDirection: Axis.horizontal,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // 2. Start Dragging the Source
      final sourceFinder = find.byKey(const ValueKey('source_draggable'));
      final gesture = await tester.startGesture(tester.getCenter(sourceFinder));
      await tester.pump(); // Start drag

      // 3. Move into the Dashboard area
      final dashboardCenter = tester.getCenter(find.byType(CustomScrollView));
      await gesture.moveTo(dashboardCenter);
      await tester.pump();

      // 4. Verify Placeholder is shown
      // This confirms _updatePlaceholderPosition was called and worked in horizontal mode
      expect(controller.currentDragPlaceholder, isNotNull);

      // Optional: Verify coordinates logic (Horizontal logic uses Y for cross-axis)
      // Since we dragged to center, Y should be roughly center row.

      await gesture.up();
    });

    testWidgets('Auto-scroll triggers horizontally at Left/Right edges', (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      (controller as DashboardControllerImpl).setScrollDirection(Axis.horizontal);

      final items = List.generate(20, (i) => LayoutItem(id: '$i', x: i, y: 0, w: 1, h: 1));
      controller.layout.value = items;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, item) => Container(color: Colors.blue),
              child: CustomScrollView(
                scrollDirection: Axis.horizontal,
                controller: scrollController,
                slivers: [
                  SliverDashboard(
                    itemBuilder: (context, item) => Container(color: Colors.blue),
                    scrollDirection: Axis.horizontal,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final itemFinder = find.byType(DashboardItem).first;
      final gesture =
          await tester.startGesture(tester.getCenter(itemFinder), kind: PointerDeviceKind.mouse);
      await tester.pump(kLongPressTimeout);

      // 1. Drag to Right Edge (Scroll Right)
      await gesture.moveTo(const Offset(790, 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // Wait for timer

      final offsetAfterRight = scrollController.offset;
      expect(offsetAfterRight, greaterThan(0), reason: 'Should scroll right');

      // 2. Drag to Left Edge (Scroll Left)
      await gesture.moveTo(const Offset(10, 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // Wait for timer

      // Verify that it scrolled back left (offset decreased)
      expect(
        scrollController.offset,
        lessThan(offsetAfterRight),
        reason: 'Scroll offset should decrease when dragging near the left edge',
      );

      await gesture.up();
    });

    testWidgets('onItemDragUpdate is called and Trash hover state resets on exit', (tester) async {
      var dragUpdateCalled = false;
      final trashKey = GlobalKey();
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              // Provide callback
              onItemDragUpdate: (item, pos) {
                dragUpdateCalled = true;
              },
              // Provide trash
              trashBuilder: (context, hovered, armed, activeItemId) {
                return Container(
                  key: trashKey,
                  width: 100,
                  height: 100,
                  color: hovered ? Colors.red : Colors.grey,
                );
              },
              trashLayout: const TrashLayout(
                visible: TrashPosition(bottom: 0, left: 0),
                hidden: TrashPosition(bottom: -100, left: 0),
              ),
              itemBuilder: (context, item) => Container(color: Colors.blue),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverDashboard(
                    itemBuilder: (context, item) => Container(color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final itemFinder = find.byType(DashboardItem).first;

      // 1. Start Drag
      final gesture = await tester.startGesture(tester.getCenter(itemFinder));
      await tester.pump(kLongPressTimeout);
      await tester.pump();

      // 2. Move over Trash (Enter)
      final trashCenter = tester.getCenter(find.byKey(trashKey));
      await gesture.moveTo(trashCenter);
      await tester.pump();

      // 3. Move AWAY from Trash (Exit)
      await gesture.moveTo(const Offset(300, 300));
      await tester.pump();

      await gesture.up();
      await tester.pump();

      expect(dragUpdateCalled, isTrue);
    });

    testWidgets('backgroundBuilder renders custom widget instead of grid', (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              itemBuilder: (context, item) => Container(),
              // Provide a custom background builder
              backgroundBuilder: (context) => Container(
                key: const ValueKey('custom_bg'),
                color: Colors.yellow,
              ),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [SliverDashboard(itemBuilder: (_, __) => Container())],
              ),
            ),
          ),
        ),
      );

      // Verify custom background is rendered
      expect(find.byKey(const ValueKey('custom_bg')), findsOneWidget);
      // Verify default grid is NOT rendered
      expect(find.byType(DashboardGrid), findsNothing);
    });

    testWidgets('External drop is cancelled if onDrop returns null', (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Draggable<String>(
                  data: 'data',
                  feedback: Container(width: 50, height: 50, color: Colors.red),
                  child: Container(
                    key: const ValueKey('source'),
                    width: 50,
                    height: 50,
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: DashboardOverlay(
                    controller: controller,
                    scrollController: scrollController,
                    itemBuilder: (context, item) => Container(color: Colors.blue),
                    // Return null to cancel drop
                    onDrop: (data, item) => null,
                    child: CustomScrollView(
                      controller: scrollController,
                      slivers: [SliverDashboard(itemBuilder: (_, __) => Container())],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final source = find.byKey(const ValueKey('source'));
      final target = find.byType(DashboardOverlay);

      // 1. Start Drag manually
      final gesture = await tester.startGesture(tester.getCenter(source));
      await tester.pump();

      // 2. Move to target
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();

      // Verify placeholder is active
      expect(controller.currentDragPlaceholder, isNotNull);

      // 3. Drop (Up)
      await gesture.up();
      await tester.pump();

      // Verify placeholder is hidden (cancelled)
      expect(controller.currentDragPlaceholder, isNull);
      expect(controller.layout.value.length, 1);
    });

    testWidgets('Trash deletion can be cancelled via onWillDelete', (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              itemBuilder: (context, item) => Container(key: ValueKey(item.id), color: Colors.blue),
              trashHoverDelay: const Duration(milliseconds: 100),
              // Return false to cancel deletion
              onWillDelete: (items) async => false,
              trashBuilder: (context, hovered, armed, activeItemId) {
                return const Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(key: ValueKey('trash'), width: 100, height: 100),
                );
              },
              child: CustomScrollView(
                slivers: [SliverDashboard(itemBuilder: (_, __) => Container())],
              ),
            ),
          ),
        ),
      );

      final itemFinder = find.byKey(const ValueKey('1')); // Item ID from setup
      final gesture = await tester.startGesture(tester.getCenter(itemFinder));
      await tester.pump(kLongPressTimeout); // Start drag
      await tester.pump();

      // Move to trash
      final trashCenter = tester.getCenter(find.byKey(const ValueKey('trash')));
      await gesture.moveTo(trashCenter);
      await tester.pump(const Duration(milliseconds: 500)); // Wait for arming

      // Drop
      await gesture.up();
      await tester.pump();

      // Verify item was NOT deleted
      expect(controller.layout.value.isNotEmpty, isTrue);
      // Verify drag ended
      expect(controller.isDragging.value, isFalse);
    });

    testWidgets('Drag end handles case where item was removed during drag', (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              itemBuilder: (context, item) => Container(color: Colors.blue),
              child: CustomScrollView(
                slivers: [SliverDashboard(itemBuilder: (_, __) => Container())],
              ),
            ),
          ),
        ),
      );

      final itemFinder = find.byType(DashboardItem).first;
      final gesture = await tester.startGesture(tester.getCenter(itemFinder));
      await tester.pump(kLongPressTimeout); // Start drag

      // Simulate external removal of the item while dragging
      controller.layout.value = [];
      await tester.pump();

      // Drop
      await gesture.up();
      await tester.pump();

      // Should not crash, and state should be reset
      expect(controller.isDragging.value, isFalse);
    });

    testWidgets('scrollToItem scrolls to the exact mathematically correct offset', (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      // Setup tall list
      final items = List.generate(20, (i) => LayoutItem(id: '$i', x: 0, y: i, w: 1, h: 1));
      controller.layout.value = items;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              itemBuilder: (context, item) => const SizedBox(),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverDashboard(
                    itemBuilder: (context, item) => const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Start scroll
      final scrollFuture = controller.scrollToItem(
        '15',
        duration: const Duration(milliseconds: 100),
      );

      // advance time until the end of scrolling
      await tester.pumpAndSettle();

      // make sure Future is done
      await scrollFuture;

      // - Screen width = 800.0
      // - crossAxisSpacing = 8.0. For 4 slots, 3 spaces (24.0)
      // - slotWidth = (800 - 24) / 4 = 194.0
      // - slotHeight = 194.0 (aspect ratio 1.0)
      // - Row height = 194.0 + 8.0 (mainAxisSpacing) = 202.0
      // - Item offset 15 (y=15) = 15 * 202.0 = 3030.0
      expect(
        scrollController.offset,
        closeTo(3030.0, 0.1), // closeTo to avoid rounding errors
        reason: 'The scroll offset should exactly match the calculated position of item 15',
      );
    });

    testWidgets(
        'scrollToItem completes with error if ScrollController is disposed during animation',
        (tester) async {
      final scrollController = ExceptionThrowingScrollController();
      addTearDown(scrollController.dispose);
      final items = List.generate(20, (i) => LayoutItem(id: '$i', x: 0, y: i, w: 1, h: 1));
      controller.layout.value = items;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              itemBuilder: (context, item) => const SizedBox(),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverDashboard(
                    itemBuilder: (context, item) => const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Start scroll animation
      final scrollFuture = controller.scrollToItem(
        '15',
        duration: const Duration(milliseconds: 500),
      );

      expect(scrollFuture, throwsA(isA<Exception>()));
      await tester.pump();
    });

    test('DashboardOverlayController default constructor and methods', () {
      const controller = DashboardOverlayController();
      expect(() => controller.startDragging('1', Offset.zero), returnsNormally);
    });

    testWidgets(
        'DashboardOverlay updates scroll subscription when controller changes in didUpdateWidget',
        (tester) async {
      final controller1 = DashboardController(initialSlotCount: 4);
      final controller2 = DashboardController(initialSlotCount: 4);
      final scrollController = ScrollController();
      addTearDown(controller1.dispose);
      addTearDown(controller2.dispose);
      addTearDown(scrollController.dispose);

      // 1. Build with controller1
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Dashboard(
              controller: controller1,
              scrollController: scrollController,
              itemBuilder: (context, item) => const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 2. Rebuild with controller2 to trigger didUpdateWidget
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Dashboard(
              controller: controller2,
              scrollController: scrollController,
              itemBuilder: (context, item) => const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();

      // Ensure the Provider has been updated with the new controller
      final providerFinder = find.byType(DashboardControllerProvider);
      expect(providerFinder, findsOneWidget);
      final provider = tester.widget<DashboardControllerProvider>(providerFinder);
      expect(
        identical(provider.controller, controller2),
        isTrue,
        reason: 'didUpdateWidget must bind the new controller instance.',
      );
    });

    testWidgets('scrollToItem completes gracefully if RenderSliverDashboard is not found',
        (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      controller.layout.value = [
        const LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              itemBuilder: (context, item) => const SizedBox(),
              // child does NOT contain SliverDashboard to force null RenderSliver
              child: CustomScrollView(
                controller: scrollController,
                slivers: const [
                  SliverToBoxAdapter(child: SizedBox()),
                ],
              ),
            ),
          ),
        ),
      );

      // Request scroll, should return early and complete normally
      final scrollFuture =
          controller.scrollToItem('1', duration: const Duration(milliseconds: 100));

      expect(scrollFuture, completes);
      await tester.pump();
    });

    testWidgets(
        'scrollToItem completes gracefully if item is removed before scroll animation handles',
        (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      controller.layout.value = [
        const LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              itemBuilder: (context, item) => const SizedBox(),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverDashboard(
                    itemBuilder: (context, item) => const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // 1. Request scroll to '1'
      final scrollFuture =
          controller.scrollToItem('1', duration: const Duration(milliseconds: 100));

      // 2. Immediately remove the item before the asynchronous stream executes
      controller.removeItem('1');

      // 3. Process the event loop
      expect(scrollFuture, completes);
      await tester.pump();
    });

    testWidgets('scrollToItem jumps instantly when duration is Duration.zero', (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final items = List.generate(20, (i) => LayoutItem(id: '$i', x: 0, y: i, w: 1, h: 1));
      controller.layout.value = items;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              itemBuilder: (context, item) => const SizedBox(),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverDashboard(
                    itemBuilder: (context, item) => const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Request instant jump (duration: Duration.zero)
      final scrollFuture = controller.scrollToItem(
        '15',
        duration: Duration.zero,
      );

      expect(scrollFuture, completes);
      await tester.pump();

      // Verify that the scroll position updated instantly
      expect(scrollController.offset, greaterThan(0));
    });
  });

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

          // Small move to trigger PanGestureRecognizer
          await gesture.moveBy(const Offset(0, 10));
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

  group('DashboardOverlay - Interactive Gesture', () {
    testWidgets('Should cover resize handles interaction and resize updates', (tester) async {
      await runOnDesktop(() async {
        final controller = DashboardController(
          initialSlotCount: 8,
          initialLayout: const [
            LayoutItem(id: 'item_1', x: 0, y: 0, w: 2, h: 2, isResizable: true),
          ],
        )..setEditMode(true);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Dashboard<String>(
                controller: controller,
                itemBuilder: (context, item) => Card(child: Text(item.id)),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final handleFinder = find.byType(ResizeHandleWidget).first;
        expect(handleFinder, findsOneWidget);

        final gesture = await tester.startGesture(
          tester.getCenter(handleFinder),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(50, 50));
        await tester.pump();

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('Should cover multi-selection selection clear on pointer up', (tester) async {
      await runOnDesktop(() async {
        final controller = DashboardController(
          initialSlotCount: 8,
          initialLayout: const [
            LayoutItem(id: 'item_1', x: 0, y: 0, w: 2, h: 2),
          ],
        )..setEditMode(true);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Dashboard<String>(
                controller: controller,
                itemBuilder: (context, item) => Card(child: Text(item.id)),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        await tester.tap(find.text('item_1'));
        await tester.pumpAndSettle();
        expect(controller.selectedItemIds.value.contains('item_1'), isTrue);

        final gesture = await tester.startGesture(
          tester.getCenter(find.text('item_1')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(controller.selectedItemIds.value.contains('item_1'), isTrue);
      });
    });

    testWidgets('Should trigger edge auto-scrolling when dragging near bounds', (tester) async {
      await runOnDesktop(() async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);
        final controller = DashboardController(
          initialSlotCount: 8,
          initialLayout: List.generate(
            10,
            (index) => LayoutItem(id: 'item_$index', x: 0, y: index * 2, w: 2, h: 2),
          ),
        )..setEditMode(true);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Dashboard<String>(
                controller: controller,
                scrollController: scrollController,
                itemBuilder: (context, item) => Card(child: Text(item.id)),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final itemFinder = find.text('item_0');
        // Ensure mouse input is specified to trigger instant dragging in desktop mode
        final gesture =
            await tester.startGesture(tester.getCenter(itemFinder), kind: PointerDeviceKind.mouse);
        await tester.pump(); // let drag start process

        await gesture.moveTo(const Offset(100, 580)); // 20px from bottom (inside the 50px hot zone)
        await tester.pump(); // let drag move process

        await tester.pump(const Duration(milliseconds: 100)); // wait for auto-scroll timer ticks

        await gesture.up();
        await tester.pumpAndSettle();

        expect(scrollController.offset, greaterThan(0.0));
      });
    });

    testWidgets('Should handle scroll requests horizontally', (tester) async {
      await runOnDesktop(() async {
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);
        final controller = DashboardController(
          initialSlotCount: 8,
          initialLayout: List.generate(
            10,
            (index) => LayoutItem(id: 'item_$index', x: index * 2, y: 0, w: 2, h: 2),
          ),
        );
        addTearDown(controller.dispose);
        controller.scrollDirection.value = Axis.horizontal;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Dashboard<String>(
                controller: controller,
                scrollController: scrollController,
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, item) => Card(child: Text(item.id)),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        await controller.scrollToItem('item_5', duration: Duration.zero);
        await tester.pumpAndSettle();

        expect(scrollController.offset, greaterThan(0.0));
      });
    });

    testWidgets('Should handle non-existent scroll requests gracefully', (tester) async {
      await runOnDesktop(() async {
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);
        final controller = DashboardController(
          initialSlotCount: 8,
          initialLayout: const [
            LayoutItem(id: 'item_1', x: 0, y: 0, w: 2, h: 2),
          ],
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Dashboard<String>(
                controller: controller,
                scrollController: scrollController,
                itemBuilder: (context, item) => Card(child: Text(item.id)),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        await controller.scrollToItem('non_existent', duration: Duration.zero);
        await tester.pumpAndSettle();

        expect(scrollController.offset, equals(0.0));
      });
    });

    testWidgets('Should allow dragging and moving section barriers in edit mode', (tester) async {
      await runOnDesktop(() async {
        final controller = DashboardController(
          initialSlotCount: 8,
          initialLayout: const [
            LayoutItem(
              id: 'sec_sys',
              x: 0,
              y: 0,
              w: 8,
              h: 1,
              isSectionBarrier: true,
              sectionTitle: 'Barrier 1',
            ),
            LayoutItem(id: 'sys_cpu', x: 0, y: 1, w: 2, h: 2),
          ],
        )..setEditMode(true);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Dashboard<String>(
                controller: controller,
                itemBuilder: (context, item) => Card(child: Text(item.id)),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final barrierFinder = find.text('Barrier 1');
        expect(barrierFinder, findsOneWidget);

        // Start mouse gesture
        final gesture = await tester.startGesture(
          tester.getCenter(barrierFinder),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(); // Let PointerDown and drag engagement process!

        // Move 150px down (well past the 101px row height)
        await gesture.moveBy(const Offset(0, 150));
        await tester.pump(); // Let PointerMove and collision pushes process!
        await tester.pumpAndSettle();

        await gesture.up();
        await tester.pumpAndSettle();

        final resultBarrier = controller.layout.value.firstWhere((i) => i.id == 'sec_sys');
        expect(resultBarrier.y, greaterThan(0));
      });
    });

    testWidgets('Should revert deletion if onWillDelete returns false', (tester) async {
      await runOnDesktop(() async {
        final controller = DashboardController(
          initialSlotCount: 8,
          initialLayout: const [
            LayoutItem(id: 'item_1', x: 0, y: 0, w: 2, h: 2),
          ],
        )..setEditMode(true);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Dashboard<String>(
                controller: controller,
                trashBuilder: (ctx, hovered, active, activeId) => const SizedBox(
                  key: ValueKey('trash'),
                  height: 100,
                  child: Text('Trash'),
                ),
                onWillDelete: (items) async => false, // Decline delete
                itemBuilder: (context, item) => Card(child: Text(item.id)),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final itemFinder = find.text('item_1');
        final trashFinder = find.byKey(const ValueKey('trash'));

        final gesture =
            await tester.startGesture(tester.getCenter(itemFinder), kind: PointerDeviceKind.mouse);
        await gesture.moveTo(tester.getCenter(trashFinder));
        await tester.pump();

        await tester.pump(const Duration(seconds: 1)); // Wait for trashHoverDelay
        await gesture.up();
        await tester.pumpAndSettle();

        expect(controller.layout.value.any((i) => i.id == 'item_1'), isTrue);
      });
    });

    testWidgets('Tapping on empty space should clear active selection', (tester) async {
      // Runs on default Android target (no macOS override)
      final controller = DashboardController(
        initialSlotCount: 8,
        initialLayout: const [
          LayoutItem(id: 'item_1', x: 0, y: 0, w: 2, h: 2),
        ],
      )..setEditMode(true);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Dashboard<String>(
              controller: controller,
              itemBuilder: (context, item) => Card(child: Text(item.id)),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('item_1'));
      await tester.pumpAndSettle();
      expect(controller.selectedItemIds.value.contains('item_1'), isTrue);

      await tester.tapAt(const Offset(500, 500)); // Tap empty space
      await tester.pumpAndSettle();

      expect(controller.selectedItemIds.value, isEmpty);
    });

    // While an in-grid drag travels over an item that already hosts a child
    // grid, the collision pushes must be frozen: otherwise the push preview
    // shoves the host — and the child grid mounted inside it — away from the
    // approaching pointer, and entering the child grid is a matter of luck.
    // (The cross-grid exit hole only protects the window AFTER the session has
    // started; this covers the approach BEFORE it.)
    testWidgets(
        'dragging over an item flagged hasNestedGrid freezes the pushes: '
        'the host keeps its pre-drag position while hovered', (tester) async {
      final coordinator = DashboardNestedCoordinator();
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          // 'drag' sits above 'host' in the same columns: with pushes active,
          // moving 'drag' downward would shove 'host' further down.
          LayoutItem(id: 'drag', x: 0, y: 0, w: 2, h: 1),
          LayoutItem(id: 'host', x: 0, y: 1, w: 2, h: 2, hasNestedGrid: true),
          LayoutItem(id: 'other', x: 2, y: 0, w: 2, h: 1),
        ],
      )..setEditMode(true);
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardNestedScope(
              coordinator: coordinator,
              child: DashboardOverlay<String>(
                controller: controller,
                scrollController: scrollController,
                itemBuilder: (context, item) => Text(item.id),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverDashboard(
                      itemBuilder: (context, item) => Text(item.id),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final hostBefore = controller.layout.value.firstWhere((i) => i.id == 'host');
      expect(hostBefore.y, 1);

      // Long-press 'drag', then move the pointer down INTO the host's area.
      final dragCenter = tester.getCenter(find.text('drag'));
      final hostCenter = tester.getCenter(find.text('host'));
      final gesture = await tester.startGesture(dragCenter);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await tester.pump();

      await gesture.moveTo(hostCenter);
      await tester.pump();
      await gesture.moveTo(hostCenter + const Offset(0, 10));
      await tester.pump();

      // Frozen: the host must still sit at its pre-drag slot — not pushed to
      // make room for the dragged tile.
      final hostDuring = controller.layout.value.firstWhere((i) => i.id == 'host');
      expect(
        hostDuring.y,
        1,
        reason: 'approaching a child-grid host must not shove it away',
      );

      // Moving away from the host resumes the pushes.
      final otherArea = tester.getCenter(find.text('other'));
      await gesture.moveTo(otherArea);
      await tester.pump();

      await gesture.up();
      await tester.pumpAndSettle();
    });

    // A nested grid owns its whole internal viewport: the host strip below the
    // painted content must still resolve to the NESTED grid, not to the parent.
    // Regression: with the main-axis growth cap, the drag shadow no longer
    // extends the nested content, so its painted extent can be shorter than the
    // host mid-drag — the strip under the content was misattributed to the
    // parent, which started a spurious session and pushed the host around
    // (placeholder at the top of the parent + flicker while moving back up).
    testWidgets(
        'the host strip below a short nested content belongs to the nested '
        'grid, and root-grid bounds stay strict', (tester) async {
      final coordinator = DashboardNestedCoordinator();
      final root = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'group', x: 0, y: 0, w: 2, h: 4, hasNestedGrid: true),
          LayoutItem(id: 'leaf-1', x: 2, y: 0, w: 2, h: 2),
        ],
      )..setEditMode(true);
      addTearDown(root.dispose);
      // Content = ONE row in a 4-row host: the lower strip is unpainted.
      final child = DashboardController(
        initialSlotCount: 2,
        initialLayout: const [
          LayoutItem(id: 'n1', x: 0, y: 0, w: 1, h: 1),
        ],
      )..setEditMode(true);
      addTearDown(child.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardNestedScope(
              coordinator: coordinator,
              child: DashboardOverlay<String>(
                controller: root,
                scrollController: scrollController,
                itemBuilder: (context, item) => item.hasNestedGrid
                    ? NestedDashboard(
                        controller: child,
                        parentItemId: item.id,
                        itemBuilder: (context, i) => Text(i.id),
                      )
                    : Text(item.id),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverDashboard(
                      itemBuilder: (context, item) => item.hasNestedGrid
                          ? NestedDashboard(
                              controller: child,
                              parentItemId: item.id,
                              itemBuilder: (context, i) => Text(i.id),
                            )
                          : Text(item.id),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Resolve the registered targets through the coordinator.
      final hostRect = tester.getRect(find.text('n1').first);
      // A probe point in the LOWER strip of the host: below the single painted
      // content row, but well inside the host item's area.
      final groupRect = tester.getRect(find.byType(NestedDashboard).first);
      final lowerStrip = Offset(
        groupRect.center.dx,
        groupRect.bottom - 10,
      );
      expect(
        lowerStrip.dy,
        greaterThan(hostRect.bottom),
        reason: 'the probe must sit below the painted nested content',
      );

      final reg = coordinator.targetAt(lowerStrip);
      expect(reg, isNotNull);
      expect(
        identical(reg!.target.controller, child),
        isTrue,
        reason: 'the host strip below short nested content belongs to the '
            'nested grid, not the parent',
      );

      // Control: a point over leaf-1 (root territory) still resolves the root.
      final leafPoint = tester.getCenter(find.text('leaf-1'));
      final rootReg = coordinator.targetAt(leafPoint);
      expect(rootReg, isNotNull);
      expect(identical(rootReg!.target.controller, root), isTrue);
    });
  });

  group('Desktop hover — spatial bucket index', () {
    testWidgets(
        'itemAtGlobal resolves via the bucket index on dense layouts '
        '(>= threshold) with identical semantics', (tester) async {
      // 40 items >= threshold (16): the bucket path is exercised.
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          for (var i = 0; i < 40; i++) LayoutItem(id: 'i$i', x: i % 4, y: i ~/ 4, w: 1, h: 1),
        ],
      )..setEditMode(true);
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay<String>(
              controller: controller,
              scrollController: scrollController,
              itemBuilder: (context, item) => Text(item.id),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverDashboard(
                    itemBuilder: (context, item) => Text(item.id),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<State<DashboardOverlay<String>>>(
        find.byType(DashboardOverlay<String>),
      );
      final target = state as CrossGridDragTarget;

      // 800 px viewport, 4 columns, 8 px spacing: slot ~194 px, stride 202.
      // (100, 100) lies inside cell (0, 0) -> 'i0'.
      expect(target.itemAtGlobal(const Offset(100, 100))?.id, 'i0');
      // (300, 100) lies inside cell (1, 0) -> 'i1'.
      expect(target.itemAtGlobal(const Offset(300, 100))?.id, 'i1');
      // Excluding the hit id yields null (overlap-free invariant).
      expect(
        target.itemAtGlobal(const Offset(100, 100), excludeId: 'i0'),
        isNull,
      );
      // Far outside any cell: null.
      expect(target.itemAtGlobal(const Offset(-50, -50)), isNull);
    });
  });

  group('DashboardOverlay — Visual Anchors, Gating and Fallbacks', () {
    test('DashboardOverlayController non-const instantiation', () {
      // instantiate non-const to force line hit on empty constructor
      // ignore: prefer_const_constructors
      final controller = DashboardOverlayController();
      expect(() => controller.startDragging('1', Offset.zero), returnsNormally);
    });

    testWidgets('onAcceptWithDetails handles drop without prior hover placeholder', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay<String>(
              controller: controller,
              scrollController: ScrollController(),
              itemBuilder: (ctx, item) => const SizedBox(),
              child: CustomScrollView(
                slivers: [SliverDashboard(itemBuilder: (_, __) => const SizedBox())],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state =
          tester.state<State<DashboardOverlay<String>>>(find.byType(DashboardOverlay<String>));
      final overlayState = state as CrossGridDragTarget;

      // Simulate a direct accept event without any prior DragOver trigger
      final dragTarget = find.byType(DragTarget<String>).first;
      final details = DragTargetDetails<String>(data: 'b', offset: const Offset(100, 100));

      final dragTargetWidget = tester.widget<DragTarget<String>>(dragTarget);
      expect(() => dragTargetWidget.onAcceptWithDetails?.call(details), returnsNormally);
      expect(overlayState.overlayRenderBox, isNotNull);
    });

    testWidgets('_findRenderSliver resolves directly when rootObject is RenderSliverDashboard',
        (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
      );
      addTearDown(controller.dispose);

      final sliverKey = GlobalKey();
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      // Create a direct RenderSliverDashboard without the layout builder wrapper
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              sliverKey: sliverKey,
              itemBuilder: (ctx, item) => const SizedBox(),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.zero,
                    sliver: SliverDashboard(
                      key: sliverKey,
                      controller: controller,
                      itemBuilder: (context, item) => const SizedBox(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<State<DashboardOverlay>>(find.byType(DashboardOverlay));
      final overlayState = state as CrossGridDragTarget;

      // Forces re-evaluation of _findRenderSliver with direct RenderSliver as root
      expect(overlayState.currentSlotMetrics(), isNotNull);
    });

    testWidgets('Same-grid pause jitter tolerance debounces micro-noise', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);

        final controller = DashboardController(
          initialSlotCount: 4,
          initialLayout: const [
            LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
            LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
          ],
        )..setEditMode(true);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DashboardNestedScope(
                coordinator: coordinator,
                subGridDynamicSameGrid: true,
                nestHoverDelay: const Duration(milliseconds: 200),
                onNestedGridRequested: (host, dragged, grid) {},
                child: SizedBox(
                  width: 400,
                  height: 400,
                  child: Dashboard<String>(
                    controller: controller,
                    itemBuilder: (context, item) => Text('T-${item.id}'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final aCenter = tester.getCenter(find.text('T-a'));
        final bCenter = tester.getCenter(find.text('T-b'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();
        await gesture.moveTo(bCenter);
        await tester.pump();

        // Pause to trigger same-grid freeze
        await tester.pump(const Duration(milliseconds: 400));
        expect(controller.internal.hoveredNestTargetId.value, 'b');

        // Micro-movement (2px, which is <= sameGridMoveTolerance)
        // This must be ignored by the low-pass jitter filter, keeping the freeze active
        await gesture.moveTo(bCenter + const Offset(2, 0));
        await tester.pump();
        expect(controller.internal.hoveredNestTargetId.value, 'b');

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets(
        'Trash deletion fallback handles case where dragged item is removed from layout before drop',
        (tester) async {
      final controller = DashboardController(
        initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
      )..setEditMode(true);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: ScrollController(),
              trashBuilder: (ctx, hovered, armed, activeItemId) => const SizedBox(
                key: ValueKey('trash'),
                width: 100,
                height: 100,
              ),
              itemBuilder: (context, item) => Card(key: ValueKey(item.id), child: Text(item.id)),
              child: CustomScrollView(
                slivers: [SliverDashboard(itemBuilder: (_, __) => Container())],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final itemFinder = find.byKey(const ValueKey('a'));
      final gesture = await tester.startGesture(tester.getCenter(itemFinder));
      await tester.pump(kLongPressTimeout); // Start drag

      // Move to trash
      final trashCenter = tester.getCenter(find.byKey(const ValueKey('trash')));
      await gesture.moveTo(trashCenter);
      await tester.pump(const Duration(milliseconds: 900)); // Arm trash

      // Programmatically remove 'a' from layout to force empty itemsToDelete list
      controller.removeItem('a');
      await tester.pump();

      // Drop on trash
      await gesture.up();
      await tester.pumpAndSettle();

      // Verify transaction ended cleanly
      expect(controller.isDragging.value, isFalse);
    });

    testWidgets(
        'Resize at bottom edge horizontally triggers auto-scroll and stops cleanly in neutral zone',
        (tester) async {
      await runOnDesktop(() async {
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        final controller = DashboardController(
          initialSlotCount: 4,
          initialLayout: [
            const LayoutItem(id: '1', x: 0, y: 0, w: 2, h: 2, isResizable: true),
            const LayoutItem(id: 'anchor', x: 20, y: 0, w: 1, h: 1, isStatic: true),
          ],
        );
        addTearDown(controller.dispose);
        controller.scrollDirection.value = Axis.horizontal;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 400,
                child: Dashboard<String>(
                  controller: controller,
                  scrollController: scrollController,
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (ctx, item) => ColoredBox(color: Colors.blue, child: Text(item.id)),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        controller.toggleEditing();
        await tester.pump();

        final itemFinder = find.text('1');
        final itemRect = tester.getRect(itemFinder);
        final handlePos = itemRect.centerRight - const Offset(5, 0);

        final gesture = await tester.startGesture(handlePos, kind: PointerDeviceKind.mouse);
        await tester.pump();
        await gesture.moveBy(const Offset(10, 0)); // pan trigger
        await tester.pump();

        // Move to right edge hot zone (Scroll Right)
        await gesture.moveTo(const Offset(390, 200));
        await tester.pump();

        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(scrollController.offset, greaterThan(0.0));

        // Move to center neutral zone (Stop scroll)
        await gesture.moveTo(const Offset(200, 200));
        await tester.pump();

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });
  });

  testWidgets(
      'DashboardOverlay resolves RenderSliverDashboard when rootObject is RenderSliverDashboard directly',
      (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
    );
    addTearDown(controller.dispose);
    final sliverKey = GlobalKey();
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardOverlay(
            controller: controller,
            scrollController: scrollController,
            sliverKey: sliverKey,
            itemBuilder: (ctx, item) => const SizedBox(),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverDashboardLayout(
                  key: sliverKey,
                  items: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
                  slotCount: 4,
                  vsync: tester,
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => const SizedBox(),
                    childCount: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state<State<DashboardOverlay>>(find.byType(DashboardOverlay));
    final target = state as CrossGridDragTarget;
    expect(target.currentSlotMetrics(), isNotNull);
  });

  testWidgets(
      'DashboardOverlay resolves RenderSliverDashboard when rootObject is RenderSliverPadding',
      (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
    );
    addTearDown(controller.dispose);
    final sliverKey = GlobalKey();
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardOverlay(
            controller: controller,
            scrollController: scrollController,
            sliverKey: sliverKey,
            itemBuilder: (ctx, item) => const SizedBox(),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverPadding(
                  key: sliverKey,
                  padding: EdgeInsets.zero,
                  sliver: SliverDashboard(
                    controller: controller,
                    itemBuilder: (context, item) => const SizedBox(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state<State<DashboardOverlay>>(find.byType(DashboardOverlay));
    final target = state as CrossGridDragTarget;
    expect(target.currentSlotMetrics(), isNotNull);
  });

  testWidgets('Trash deletion fallback handles case where selectedItemIds is empty during drag',
      (tester) async {
    await runOnDesktop(() async {
      final controller = DashboardController(
        initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
      )..setEditMode(true);
      addTearDown(controller.dispose);

      var deleted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: ScrollController(),
              onItemsDeleted: (_) => deleted = true,
              trashBuilder: (ctx, hovered, armed, activeItemId) => const SizedBox(
                key: ValueKey('trash'),
                width: 100,
                height: 100,
                child: ColoredBox(color: Colors.red), // Opaque to hit testing
              ),
              itemBuilder: (context, item) => Card(key: ValueKey(item.id), child: Text(item.id)),
              child: CustomScrollView(
                slivers: [SliverDashboard(itemBuilder: (_, __) => Container())],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final itemFinder = find.byKey(const ValueKey('a'));
      final gesture =
          await tester.startGesture(tester.getCenter(itemFinder), kind: PointerDeviceKind.mouse);
      await tester.pump(); // Start drag instantly on desktop

      // Move to trash
      final trashCenter = tester.getCenter(find.byKey(const ValueKey('trash')));
      await gesture.moveTo(trashCenter);
      await tester.pump(const Duration(milliseconds: 900)); // Arm trash

      // Clear selection and remove item from layout programmatically to force itemsToDelete to be empty
      controller.clearSelection();
      controller.layout.value = [];
      await tester.pump();

      // Drop on trash
      await gesture.up();
      await tester.pumpAndSettle();

      expect(deleted, isTrue, reason: 'Fallback should delete the current active item');
      expect(controller.layout.value, isEmpty);
    });
  });

  testWidgets(
      'maybeStartCrossGridSession falls back to activeItemInitialLayout and custom feedbackBuilder if item is removed programmatically',
      (tester) async {
    await runOnDesktop(() async {
      final coordinator = DashboardNestedCoordinator();
      addTearDown(coordinator.dispose);

      final sliverKey1 = GlobalKey();
      final sliverKey2 = GlobalKey();

      final parent = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        ],
      )..setEditMode(true);
      addTearDown(parent.dispose);

      final other = DashboardController(initialSlotCount: 4)..setEditMode(true);
      addTearDown(other.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardNestedScope(
              coordinator: coordinator,
              child: Column(
                children: [
                  SizedBox(
                    height: 200,
                    child: Dashboard<String>(
                      controller: parent,
                      key: sliverKey1,
                      itemFeedbackBuilder: (context, item, child) => Container(
                        key: const ValueKey('custom_cross_proxy'),
                        child: child,
                      ),
                      itemBuilder: (ctx, item) => Text('P-${item.id}'),
                    ),
                  ),
                  SizedBox(
                    height: 200,
                    child: Dashboard<String>(
                      controller: other,
                      key: sliverKey2,
                      itemBuilder: (ctx, item) => Text('O-${item.id}'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Start mouse drag
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('P-a')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(); // Start drag instantly on desktop

      // Remove item programmatically while dragging, restoring selectedItemIds to satisfy the single-item gesture rule
      parent.removeItem('a');
      parent.selectedItemIds.value = {'a'};
      await tester.pump();

      // Move pointer into the second grid area (otherCenter) to trigger cross-grid session start
      final otherCenter = tester.getCenter(find.byType(Dashboard<String>).last);
      await gesture.moveTo(otherCenter);
      await tester.pump();

      expect(find.byKey(const ValueKey('custom_cross_proxy')), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  testWidgets('Web throttle mechanism caches and flushes high-frequency pointer moves',
      (tester) async {
    await runOnDesktop(() async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
      )..setEditMode(true);
      addTearDown(controller.dispose);

      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: scrollController,
              itemBuilder: (ctx, item) => const SizedBox(),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverDashboard(itemBuilder: (_, __) => const SizedBox()),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enable the Web override flag locally for this test
      debugOverrideIsWeb = true;
      addTearDown(() => debugOverrideIsWeb = false);

      final itemFinder = find.byType(DashboardItem).first;
      final gesture =
          await tester.startGesture(tester.getCenter(itemFinder), kind: PointerDeviceKind.mouse);
      await tester.pump(); // Start drag instantly on desktop

      // First move bypasses the throttle but resets the stopwatch to 0
      await gesture.moveBy(const Offset(10, 10));
      await tester.pump();

      // Second move occurs immediately (elapsedTime < 16ms), triggering the throttle branch
      final targetPos = tester.getCenter(itemFinder) + const Offset(50, 50);
      await gesture.moveTo(targetPos);
      await tester.pump();

      // Wait for the 17ms timer to flush the throttled position safely
      await tester.pump(const Duration(milliseconds: 25));

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
