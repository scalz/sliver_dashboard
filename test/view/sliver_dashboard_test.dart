import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

void main() {
  testWidgets('SliverDashboard layouts leading children when scrolling up', (tester) async {
    final controller = DashboardController(
      initialSlotCount: 1,
      // Create many items to ensure we can scroll far enough
      initialLayout: List.generate(50, (i) => LayoutItem(id: '$i', x: 0, y: i, w: 1, h: 1)),
    );

    final scrollController = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // FIX: Add Provider here
          body: DashboardControllerProvider(
            controller: controller,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverDashboard(
                  itemBuilder: (context, item) => SizedBox(
                    height: 100, // Fixed height for predictable scrolling
                    child: Text('Item ${item.id}'),
                  ),
                  // Force vertical
                  scrollDirection: Axis.vertical,
                  slotAspectRatio: 5, // Wide aspect ratio
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // 1. Scroll far down (e.g., item 30).
    // This causes items 0-20 to be Garbage Collected (removed from render tree).
    scrollController.jumpTo(3000);
    await tester.pumpAndSettle();

    expect(find.text('Item 0'), findsNothing, reason: 'Item 0 should be GCed');

    // 2. Scroll back up slightly.
    // This forces the Sliver to look for children *before* the current first child.
    // This triggers `insertAndLayoutLeadingChild`.
    scrollController.jumpTo(2800);
    await tester.pumpAndSettle();

    // Just verify no crash and that we are still in a valid state
    expect(find.byType(SliverDashboard), findsOneWidget);
  });
}
