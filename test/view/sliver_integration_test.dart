import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

void main() {
  // Helper to generate a large layout
  List<LayoutItem> generateItems(int count, int cols) {
    final items = <LayoutItem>[];
    var y = 0;
    var x = 0;
    for (var i = 0; i < count; i++) {
      items.add(
        LayoutItem(
          id: '$i',
          x: x,
          y: y,
          w: 1,
          h: 1,
        ),
      );
      x++;
      if (x >= cols) {
        x = 0;
        y++;
      }
    }
    return items;
  }

  Widget buildTestApp({
    required List<LayoutItem> items,
    ScrollController? scrollController,
    void Function(Duration)? onPerformLayout,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverDashboard(
              items: items,
              slotCount: 4,
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = items[index];

                  return ColoredBox(
                    key: ValueKey(item.id),
                    color: Colors.blue,
                    child: Center(child: Text('Item ${item.id}')),
                  );
                },
                childCount: items.length,
              ),
              onPerformLayout: onPerformLayout,
            ),
          ],
        ),
      ),
    );
  }

  group('SliverDashboard Integration Tests', () {
    testWidgets('Advanced Item Visibility: Detect disappearing items during scroll',
        (tester) async {
      final items = generateItems(100, 4); // 25 rows
      final controller = ScrollController();

      // Set a fixed screen size for deterministic math (800x600 is default, but let's be explicit)
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(buildTestApp(items: items, scrollController: controller));
      await tester.pumpAndSettle();

      // 1. Verify initial items (Row 0-2 are definitely visible)
      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Item 99'), findsNothing);

      // 2. Scroll to 1000px
      // Math:
      // SlotWidth = (800 - 24)/4 = 194.
      // RowHeight = 194 + 8 = 202.
      // Offset 1000 / 202 = ~4.95 rows hidden.
      // Visible start index approx: 5 * 4 = 20.
      controller.jumpTo(1000);
      await tester.pumpAndSettle();

      // Verify top items are gone
      expect(find.text('Item 0'), findsNothing);

      // Verify items around index 25 are visible
      var foundMiddle = false;
      for (var i = 20; i < 35; i++) {
        if (find.text('Item $i').evaluate().isNotEmpty) {
          foundMiddle = true;
          break;
        }
      }
      expect(
        foundMiddle,
        isTrue,
        reason: 'Should find items visible at scroll offset 1000 (approx indices 20-32)',
      );

      // 3. Scroll to end
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(find.text('Item 99'), findsOneWidget);

      // Reset view
      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('Stress Test: Random scroll patterns', (tester) async {
      final items = generateItems(200, 4);
      final controller = ScrollController();

      await tester.pumpWidget(buildTestApp(items: items, scrollController: controller));
      await tester.pumpAndSettle();

      final scrollPatterns = [
        const Offset(0, -200), // Down
        const Offset(0, 100), // Up
        const Offset(0, -500), // Big down
        const Offset(0, 300), // Big up
      ];

      for (final delta in scrollPatterns) {
        final currentOffset = controller.offset;
        final targetOffset = (currentOffset - delta.dy).clamp(
          controller.position.minScrollExtent,
          controller.position.maxScrollExtent,
        );

        // Use animateTo but pump manually to avoid hanging
        unawaited(
          controller.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 100),
            curve: Curves.linear,
          ),
        );

        // Pump frames for the duration of the animation
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));

        // Verification: Ensure no crash and at least one item is visible
        final visibleItems = find.byType(ColoredBox);
        expect(visibleItems, findsWidgets, reason: 'Grid should not be empty after scroll $delta');
      }
    });

    testWidgets('Performance Profiling: performLayout metrics', (tester) async {
      final items = generateItems(500, 4);
      final controller = ScrollController();

      var layoutCount = 0;
      var totalMicroseconds = 0;

      await tester.pumpWidget(
        buildTestApp(
          items: items,
          scrollController: controller,
          onPerformLayout: (duration) {
            layoutCount++;
            totalMicroseconds += duration.inMicroseconds;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Reset counters to ignore the initial "warm-up" layout (which is always expensive)
      layoutCount = 0;
      totalMicroseconds = 0;

      // Perform a smooth scroll simulation
      // We scroll 2000 pixels over 1 second
      unawaited(
        controller.animateTo(
          2000,
          duration: const Duration(seconds: 1),
          curve: Curves.linear,
        ),
      );

      // Pump frames every 16ms (approx 60fps) for 1 second
      // This forces the engine to perform layout multiple times during the scroll
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Calculate stats
      // Avoid division by zero if something went wrong
      final safeCount = layoutCount == 0 ? 1 : layoutCount;
      final averageTime = totalMicroseconds / safeCount;

      debugPrint('\n--- Performance Profile (Scroll Only) ---');
      debugPrint('Total Layouts: $layoutCount');
      debugPrint('Total Time: ${totalMicroseconds / 1000} ms');
      debugPrint('Avg Time per Layout: ${averageTime.toStringAsFixed(2)} µs');

      // Assertions
      expect(
        layoutCount,
        greaterThan(10),
        reason: 'Should have triggered multiple layouts during 1s scroll',
      );

      // 13ms (13000µs) was your initial build time.
      // Scrolling updates should be much faster (typically < 1000µs for simple items).
      // We set a conservative limit of 2ms (2000µs) per layout frame.
      expect(averageTime, lessThan(2000), reason: 'Average scroll layout time exceeded 2ms');
    });
  });
}
