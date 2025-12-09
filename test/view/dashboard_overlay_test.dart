import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/view/dashboard_feedback_widget.dart';

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
}
