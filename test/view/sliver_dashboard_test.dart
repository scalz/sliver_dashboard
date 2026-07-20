import 'dart:async';

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
          // Add Provider here
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

  testWidgets('SliverDashboard updates render object properties and triggers layout cleanly',
      (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: [
        const LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1),
      ],
    );

    // 1. Build initial SliverDashboard
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardControllerProvider(
            controller: controller,
            child: CustomScrollView(
              slivers: [
                SliverDashboard(
                  itemBuilder: (context, item) => const SizedBox(),
                  slotAspectRatio: 1,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Find the RenderSliverDashboard
    final renderSliver =
        tester.renderObject<RenderSliverDashboard>(find.byType(SliverDashboardLayout));

    // Cover isEditing getter
    expect(renderSliver.isEditing, isFalse);

    // 2. Rebuild with DIFFERENT properties to trigger updateRenderObject and all setters
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardControllerProvider(
            controller: controller,
            child: CustomScrollView(
              slivers: [
                SliverDashboard(
                  itemBuilder: (context, item) => const SizedBox(),
                  slotAspectRatio: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Verify that all render object properties updated
    expect(renderSliver.slotAspectRatio, 2.0);
    expect(renderSliver.mainAxisSpacing, 10.0);
    expect(renderSliver.crossAxisSpacing, 10.0);

    // 3. Directly set onPerformLayout and empty items to cover empty performLayout branch
    var layoutCalledOnEmpty = false;
    renderSliver
      ..onPerformLayout = (duration) {
        layoutCalledOnEmpty = true;
      }
      ..items = []
      ..layout(renderSliver.constraints, parentUsesSize: true);

    expect(layoutCalledOnEmpty, isTrue);
    controller.dispose();
  });

  testWidgets('SliverDashboard updates controller dynamically in didUpdateWidget', (tester) async {
    final controller1 = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
    );
    final controller2 = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [LayoutItem(id: 'b', x: 0, y: 0, w: 1, h: 1)],
    );
    addTearDown(controller1.dispose);
    addTearDown(controller2.dispose);

    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    // 1. Render with controller 1
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverDashboard(
                controller: controller1,
                itemBuilder: (context, item) => Text(item.id),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsNothing);

    // 2. Re-render with controller 2 to trigger didUpdateWidget
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverDashboard(
                controller: controller2,
                itemBuilder: (context, item) => Text(item.id),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('SliverDashboard computes metrics using itemLayoutBuilder', (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
      ],
    );
    addTearDown(controller.dispose);

    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    double? capturedW;
    double? capturedH;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverDashboard(
                controller: controller,
                itemLayoutBuilder: (context, item, width, height, slotCount) {
                  capturedW = width;
                  capturedH = height;
                  return Text(item.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(capturedW, isNotNull);
    expect(capturedH, isNotNull);
    expect(capturedW, greaterThan(0));
    expect(capturedH, greaterThan(0));
  });

  // Geometric child ordering (materialization bound).
  //
  // The sliver mounts a CONTIGUOUS child-index window. If children were fed
  // in ID order and ids do not correlate with geometry (uuids, unpadded
  // counters), the visible tiles have scattered indices and the window can
  // span hundreds of children — localized fast-scroll jank. The view layer
  // now feeds a geometrically sorted view, so the window stays tight
  // regardless of id scheme.
  testWidgets(
      'ids anti-correlated with geometry do not inflate the materialized '
      'child window', (tester) async {
    // 300 items, 4 columns, one item per cell; ids DESCEND while y ascends:
    // the worst possible id-vs-geometry scramble.
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: [
        for (var i = 0; i < 300; i++)
          LayoutItem(
            id: 'itm_${(299 - i).toString().padLeft(3, '0')}',
            x: i % 4,
            y: i ~/ 4,
            w: 1,
            h: 1,
          ),
      ],
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Dashboard<String>(
            controller: controller,
            scrollController: scrollController,
            itemBuilder: (context, item) => Text(item.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    int mounted() => find.textContaining('itm_').evaluate().length;

    // 800x600 test viewport, slot ~194 px: ~4 visible rows (+ cache extent).
    // With ID-ordered children this would be ~all 300; the geometric view
    // keeps it near the visible window.
    expect(
      mounted(),
      lessThan(80),
      reason: 'materialized window must track geometry, not id order',
    );
    expect(mounted(), greaterThan(0));

    // Same bound after a deep scroll (different index region).
    scrollController.jumpTo(scrollController.position.maxScrollExtent / 2);
    await tester.pumpAndSettle();
    expect(mounted(), lessThan(80));

    // Items on the first visible row are the geometrically-top ones,
    // regardless of their (high) ids.
    scrollController.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('itm_299'), findsOneWidget); // at (0,0): highest id
  });

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
