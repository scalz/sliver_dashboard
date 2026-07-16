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

    tearDown(() {
      controller.dispose();
      scrollController.dispose();
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
                  Container(height: 1000, color: Colors.red),
                ],
              ),
            ),
          ),
        ),
      );

      final minimapFinder = find.byType(DashboardMinimap);
      final painterFinder = find.descendant(
        of: minimapFinder,
        matching: find.byType(CustomPaint),
      );

      // Verify that both layered painters (Items + Viewport) are mounted.
      expect(painterFinder, findsNWidgets(2));

      // Verify the size of the overall minimap is correct
      final size = tester.getSize(painterFinder.first);
      expect(size.width, 100.0);
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

      final minimapFinder = find.byType(DashboardMinimap);
      final painterFinder = find.descendant(
        of: minimapFinder,
        matching: find.byType(CustomPaint),
      );

      // Check the background items painter (first CustomPaint)
      final paintBefore = tester.widget(painterFinder.first) as CustomPaint;
      final painterBefore = paintBefore.painter;

      controller.addItem(const LayoutItem(id: '3', x: 0, y: 10, w: 1, h: 1));
      await tester.pump();

      final paintAfter = tester.widget(painterFinder.first) as CustomPaint;
      final painterAfter = paintAfter.painter;

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

      final minimapFinder = find.byType(DashboardMinimap);
      final painterFinder = find.descendant(
        of: minimapFinder,
        matching: find.byType(CustomPaint),
      );

      // Check the foreground viewport painter (second CustomPaint)
      final paintBefore = tester.widget(painterFinder.last) as CustomPaint;
      final painterBefore = paintBefore.painter;

      scrollController.jumpTo(100);
      await tester.pump();

      final paintAfter = tester.widget(painterFinder.last) as CustomPaint;
      final painterAfter = paintAfter.painter;

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

      expect(find.byType(DashboardMinimap), findsOneWidget);

      final painterFinder = find.descendant(
        of: find.byType(DashboardMinimap),
        matching: find.byType(CustomPaint),
      );
      final size = tester.getSize(painterFinder.first);
      expect(size.height, greaterThan(0));
    });

    testWidgets('interaction (tap & drag) updates scroll position', (tester) async {
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

      await tester.tap(find.byType(DashboardMinimap));
      await tester.pump();

      expect(scrollController.offset, greaterThan(0.0));
      final offsetAfterTap = scrollController.offset;

      await tester.drag(find.byType(DashboardMinimap), const Offset(0, -50));
      await tester.pump();

      expect(scrollController.offset, lessThan(offsetAfterTap));
    });

    testWidgets('renders without error even if scroll view has no dimensions yet', (tester) async {
      final emptyController = ScrollController();
      addTearDown(emptyController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardMinimap(
              controller: controller,
              scrollController: emptyController,
              width: 100,
            ),
          ),
        ),
      );

      expect(find.byType(DashboardMinimap), findsOneWidget);
    });

    testWidgets('calculates layout with spacing correctly', (tester) async {
      const spacing = 50.0;

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
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                  ),
                  Container(height: 1000, color: Colors.red),
                ],
              ),
            ),
          ),
        ),
      );

      final painterFinder = find.descendant(
        of: find.byType(DashboardMinimap),
        matching: find.byType(CustomPaint),
      );
      expect(painterFinder, findsNWidgets(2));

      final customPaint = tester.widget<CustomPaint>(painterFinder.first);
      final painter = customPaint.painter;
      expect(painter, isNotNull);
    });

    testWidgets('calculates layout with spacing correctly in Horizontal mode', (tester) async {
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
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  Container(width: 1000, height: 500, color: Colors.red),
                ],
              ),
            ),
          ),
        ),
      );

      final painterFinder = find.descendant(
        of: find.byType(DashboardMinimap),
        matching: find.byType(CustomPaint),
      );
      expect(painterFinder, findsNWidgets(2));

      final customPaint = tester.widget<CustomPaint>(painterFinder.first);
      final painter = customPaint.painter;
      expect(painter, isNotNull);
    });

    testWidgets('calculates layout with spacing correctly in Horizontal mode', (tester) async {
      (controller as DashboardControllerImpl).setScrollDirection(Axis.horizontal);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: scrollController,
                child: Row(
                  children: [
                    DashboardMinimap(
                      controller: controller,
                      scrollController: scrollController,
                      width: 100,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    Container(width: 1000, height: 500, color: Colors.red),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      scrollController.jumpTo(1);
      await tester.pump();

      final painterFinder = find.descendant(
        of: find.byType(DashboardMinimap),
        matching: find.byType(CustomPaint),
      );
      expect(painterFinder, findsNWidgets(2));
    });
  });
}
