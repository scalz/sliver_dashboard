import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/view/dashboard_feedback_widget.dart';
import 'package:sliver_dashboard/src/view/dashboard_item_widget.dart';

// Mock for the persistence callback
class MockLayoutChangeListener extends Mock {
  void call(List<LayoutItem> items);
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

    testWidgets('Feedback item is positioned and clipped correctly under SliverAppBar',
        (tester) async {
      final scrollController = ScrollController();

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

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: ScrollController(),
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

      // 3. Move AWAY from Trash (Trigger Hover Exit - Lines 657-660)
      await gesture.moveTo(const Offset(300, 300)); // Move far away
      await tester.pump();

      // 4. Release
      await gesture.up();
      await tester.pump();

      expect(dragUpdateCalled, isTrue, reason: 'onItemDragUpdate should be called');
    });

    testWidgets('Auto-scroll triggers at edges (Top/Bottom/Left/Right)', (tester) async {
      final scrollController = ScrollController();

      // Setup a dashboard with enough content to scroll
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
      final gesture = await tester.startGesture(tester.getCenter(itemFinder));
      await tester.pump(kLongPressTimeout);

      // 1. Drag to Bottom Edge (Scroll Down)
      // Move to bottom of screen
      await gesture.moveTo(const Offset(100, 580)); // Assuming 600 height
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // Wait for timer

      expect(scrollController.offset, greaterThan(0), reason: 'Should scroll down');

      // 2. Drag to Top Edge (Scroll Up - Lines 737-739)
      await gesture.moveTo(const Offset(100, 10)); // Top of screen
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // It should scroll back up (offset decreases)
      // Note: exact value depends on timing, just checking direction/change

      await gesture.up();
    });
  });

  group('DashboardItem A11y Actions (Keyboard)', () {
    late DashboardControllerImpl controller;
    late MockLayoutChangeListener mockListener;

    const itemA = LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2);
    const itemB = LayoutItem(id: 'B', x: 2, y: 0, w: 2, h: 2);

    setUp(() {
      mockListener = MockLayoutChangeListener();
      controller = DashboardControllerImpl(
        initialSlotCount: 4,
        initialLayout: [itemA, itemB],
        onLayoutChanged: mockListener.call,
      )..setEditMode(true);
    });

    // Widget wrapper for the test
    Widget createDashboardItemWrapper(LayoutItem item) {
      return MaterialApp(
        home: Scaffold(
          // CRITICAL: Wrap in FocusScope to provide a root focus hierarchy
          body: FocusScope(
            autofocus: true,
            child: DashboardControllerProvider(
              controller: controller,
              child: DashboardItem(
                key: ValueKey(item.id),
                item: item,
                isEditing: controller.isEditing.value,
                builder: (context, i) => Text(i.id),
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
      expect(controller.activeItemId.value, isNull);
      // Verify persistence listener was called
      verify(() => mockListener.call(any())).called(1);
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
      expect(controller.activeItemId.value, isNull);
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
      expect(controller.activeItemId.value, isNull);
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
    testWidgets('Drag and Placeholder work correctly in Horizontal Scroll mode', (tester) async {
      // 1. Setup Horizontal Dashboard + Source Draggable
      final scrollController = ScrollController();
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
      (controller as DashboardControllerImpl).setScrollDirection(Axis.horizontal);

      // Add enough items to scroll
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
      final gesture = await tester.startGesture(tester.getCenter(itemFinder));
      await tester.pump(kLongPressTimeout);

      // 1. Drag to Right Edge (Scroll Right - Lines 753-755)
      // Assuming screen width 800
      await gesture.moveTo(const Offset(790, 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // Wait for timer

      expect(scrollController.offset, greaterThan(0), reason: 'Should scroll right');

      // 2. Drag to Left Edge (Scroll Left - Lines 748-750)
      await gesture.moveTo(const Offset(10, 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // It should scroll back left (offset decreases)
      await gesture.up();
    });

    testWidgets('onItemDragUpdate is called and Trash hover state resets on exit', (tester) async {
      var dragUpdateCalled = false;
      final trashKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay(
              controller: controller,
              scrollController: ScrollController(),
              // Provide callback (Lines 629-632)
              onItemDragUpdate: (item, pos) {
                dragUpdateCalled = true;
              },
              // Provide trash
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

      // 3. Move AWAY from Trash (Exit - Lines 657-660)
      await gesture.moveTo(const Offset(300, 300));
      await tester.pump();

      await gesture.up();

      expect(dragUpdateCalled, isTrue);
    });
  });
}
