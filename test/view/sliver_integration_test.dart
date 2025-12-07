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
    required DashboardController controller,
    ScrollController? scrollController,
    void Function(Duration)? onPerformLayout,
  }) {
    final items = controller.layout.value;

    return MaterialApp(
      home: Scaffold(
        // Use DashboardOverlay to provide DashboardControllerProvider
        body: DashboardOverlay(
          controller: controller,
          scrollController: scrollController ?? ScrollController(),
          itemBuilder: (context, item) {
            final index = items.indexWhere((i) => i.id == item.id);
            if (index == -1) return const SizedBox.shrink();

            return ColoredBox(
              key: ValueKey(item.id),
              color: Colors.blue,
              child: Center(child: Text('Item ${item.id}')),
            );
          },
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverDashboard(
                onPerformLayout: onPerformLayout,
                itemBuilder: (context, item) {
                  return ColoredBox(
                    key: ValueKey(item.id),
                    color: Colors.blue,
                    child: Center(child: Text('Item ${item.id}')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  group('SliverDashboard Integration Tests', () {
    late DashboardController controller;
    final testItems = generateItems(100, 4);

    setUp(() {
      controller = DashboardController(initialLayout: testItems, initialSlotCount: 4);
      addTearDown(() => controller.dispose());
    });

    testWidgets('Advanced Item Visibility: Detect disappearing items during scroll',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final localScrollController = ScrollController();
      addTearDown(localScrollController.dispose);

      await tester.pumpWidget(
        buildTestApp(controller: controller, scrollController: localScrollController),
      );
      await tester.pumpAndSettle();

      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Item 99'), findsNothing);

      localScrollController.jumpTo(1000);
      await tester.pumpAndSettle();

      expect(find.text('Item 0'), findsNothing);

      var foundMiddle = false;
      for (var i = 20; i < 35; i++) {
        if (find.text('Item $i').evaluate().isNotEmpty) {
          foundMiddle = true;
          break;
        }
      }
      expect(foundMiddle, isTrue);

      localScrollController.jumpTo(localScrollController.position.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(find.text('Item 99'), findsOneWidget);
    });

    testWidgets('Stress Test: Random scroll patterns', (tester) async {
      final localScrollController = ScrollController();
      addTearDown(localScrollController.dispose);

      await tester.pumpWidget(
        buildTestApp(controller: controller, scrollController: localScrollController),
      );
      await tester.pumpAndSettle();

      final scrollPatterns = [
        const Offset(0, -200),
        const Offset(0, 100),
        const Offset(0, -500),
        const Offset(0, 300),
      ];

      for (final delta in scrollPatterns) {
        final currentOffset = localScrollController.offset;
        final targetOffset = (currentOffset - delta.dy).clamp(
          localScrollController.position.minScrollExtent,
          localScrollController.position.maxScrollExtent,
        );

        unawaited(
          localScrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 100),
            curve: Curves.linear,
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));

        final visibleItems = find.byType(ColoredBox);
        expect(visibleItems, findsWidgets);
      }
    });

    testWidgets('Performance Profiling: performLayout metrics', (tester) async {
      final perfController =
          DashboardController(initialLayout: generateItems(500, 4), initialSlotCount: 4);
      final perfScrollController = ScrollController();
      addTearDown(perfController.dispose);
      addTearDown(perfScrollController.dispose);

      var layoutCount = 0;
      var totalMicroseconds = 0;

      await tester.pumpWidget(
        buildTestApp(
          controller: perfController,
          scrollController: perfScrollController,
          onPerformLayout: (duration) {
            layoutCount++;
            totalMicroseconds += duration.inMicroseconds;
          },
        ),
      );
      await tester.pumpAndSettle();

      layoutCount = 0;
      totalMicroseconds = 0;

      unawaited(
        perfScrollController.animateTo(
          2000,
          duration: const Duration(seconds: 1),
          curve: Curves.linear,
        ),
      );

      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final safeCount = layoutCount == 0 ? 1 : layoutCount;
      final averageTime = totalMicroseconds / safeCount;

      expect(layoutCount, greaterThan(10));
      expect(averageTime, lessThan(2000));
    });
  });
}
