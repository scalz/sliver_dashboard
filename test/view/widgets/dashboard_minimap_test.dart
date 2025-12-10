import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';

void main() {
  group('DashboardMinimap', () {
    late DashboardController controller;
    late ScrollController scrollController;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          const LayoutItem(id: '1', x: 0, y: 0, w: 2, h: 2),
          const LayoutItem(id: '2', x: 2, y: 2, w: 2, h: 2),
        ],
      );
      scrollController = ScrollController();
    });

    testWidgets('renders correctly with finite size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                children: [
                  DashboardMinimap(
                    controller: controller,
                    scrollController: scrollController,
                    width: 100,
                  ),
                  // Add content to make it scrollable
                  Container(height: 1000, color: Colors.red),
                ],
              ),
            ),
          ),
        ),
      );

      // Find the CustomPaint specifically inside DashboardMinimap
      final minimapFinder = find.byType(DashboardMinimap);
      final painterFinder = find.descendant(
        of: minimapFinder,
        matching: find.byType(CustomPaint),
      );

      expect(painterFinder, findsOneWidget);

      // Verify size is finite (no infinity error)
      final size = tester.getSize(painterFinder);
      expect(size.width, 100.0);

      // Check the boolean property .isFinite
      expect(size.height.isFinite, isTrue, reason: 'Height should be finite');
      expect(size.height, greaterThan(0));
    });

    testWidgets('repaints when layout changes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardMinimap(
              controller: controller,
              scrollController: scrollController,
              width: 100,
            ),
          ),
        ),
      );

      // Specific finder
      final minimapFinder = find.byType(DashboardMinimap);
      final painterFinder = find.descendant(
        of: minimapFinder,
        matching: find.byType(CustomPaint),
      );

      final paintBefore = tester.widget(painterFinder) as CustomPaint;
      final painterBefore = paintBefore.painter;

      // Change layout
      controller.addItem(const LayoutItem(id: '3', x: 0, y: 10, w: 1, h: 1));
      await tester.pump();

      final paintAfter = tester.widget(painterFinder) as CustomPaint;
      final painterAfter = paintAfter.painter;

      // Verify painter instance changed (triggering repaint)
      expect(painterAfter, isNot(equals(painterBefore)));
    });

    testWidgets('repaints when scroll changes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                children: [
                  DashboardMinimap(
                    controller: controller,
                    scrollController: scrollController,
                    width: 100,
                  ),
                  Container(height: 2000, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      );

      // Specific finder
      final minimapFinder = find.byType(DashboardMinimap);
      final painterFinder = find.descendant(
        of: minimapFinder,
        matching: find.byType(CustomPaint),
      );

      final paintBefore = tester.widget(painterFinder) as CustomPaint;
      final painterBefore = paintBefore.painter;

      // Scroll
      scrollController.jumpTo(100);
      await tester.pump();

      final paintAfter = tester.widget(painterFinder) as CustomPaint;
      final painterAfter = paintAfter.painter;

      // Verify painter properties updated
      expect(painterAfter, isNot(equals(painterBefore)));
    });

    testWidgets('renders and paints correctly in horizontal scroll mode', (tester) async {
      (controller as DashboardControllerImpl).setScrollDirection(Axis.horizontal);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: scrollController,
              child: Row(
                children: [
                  DashboardMinimap(
                    controller: controller,
                    scrollController: scrollController,
                    width: 100,
                  ),
                  Container(width: 2000, height: 500, color: Colors.blue),
                ],
              ),
            ),
          ),
        ),
      );

      // Check widget is correctly displayed
      expect(find.byType(DashboardMinimap), findsOneWidget);

      // Check size is calculated
      final painterFinder = find.descendant(
        of: find.byType(DashboardMinimap),
        matching: find.byType(CustomPaint),
      );
      final size = tester.getSize(painterFinder);
      expect(size.height, greaterThan(0));
    });

    testWidgets('interaction (tap & drag) updates scroll position', (tester) async {
      // Setup vertical (default)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  height: 100,
                  child: DashboardMinimap(
                    controller: controller,
                    scrollController: scrollController,
                    width: 100,
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Container(height: 2000, color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(scrollController.offset, 0.0);

      // 1. Test TAP (onTapUp) on center of minimap
      await tester.tap(find.byType(DashboardMinimap));
      await tester.pump();

      // Scroll should be on middle
      // (_handleInteraction logic is called)
      expect(scrollController.offset, greaterThan(0.0));
      final offsetAfterTap = scrollController.offset;

      // 2. Test DRAG (onPanUpdate)
      // Drag to top (scroll up)
      await tester.drag(find.byType(DashboardMinimap), const Offset(0, -50));
      await tester.pump();

      // Scroll should decrease
      expect(scrollController.offset, lessThan(offsetAfterTap));
    });
  });
}
