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
}
