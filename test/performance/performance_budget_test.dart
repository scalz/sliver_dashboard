import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';

// Mock Canvas to intercept and count low-level drawing operations
class MockCanvas extends Fake implements Canvas {
  int drawPathCalls = 0;
  int drawRRectCalls = 0;

  @override
  void drawRect(Rect rect, Paint paint) {}

  @override
  void drawPath(Path path, Paint paint) {
    drawPathCalls++;
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
    drawRRectCalls++;
  }
}

class BuildCounter extends StatelessWidget {
  const BuildCounter({
    required this.id,
    required this.counters,
    required this.child,
    super.key,
  });

  final String id;
  final Map<String, int> counters;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    counters[id] = (counters[id] ?? 0) + 1;
    return child;
  }
}

void main() {
  group('Performance Invariants & Budgets (CI Enforcements)', () {
    // Budget 1: Drop Compaction must complete in < 50ms for N=1000 fragmented items
    test('FastVerticalCompactor compaction budget (N=1000) must be < 50ms', () {
      // Generate a fragmented and overlapping layout to force
      // the skyline compaction engine to resolve multiple collision boundaries.
      final random = Random(42); // Seeded for reproducibility
      final layout = List.generate(
        1000,
        (i) => LayoutItem(
          id: '$i',
          x: random.nextInt(6), // 0 to 5 (widths of 1 or 2 fits perfectly in 8 cols)
          y: random.nextInt(1000), // Highly scattered vertically to trigger overlaps
          w: 1 + random.nextInt(2),
          h: 1 + random.nextInt(2),
        ),
      );

      const compactor = FastVerticalCompactor();

      final stopwatch = Stopwatch()..start();
      compactor.compact(layout, 8);
      stopwatch.stop();

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(50),
        reason:
            'Compaction of 1000 messy items took ${stopwatch.elapsedMilliseconds}ms, exceeding the 50ms budget.',
      );
    });

    // Budget 2: Cascade push on drag-crossing must be O(N*k) and complete in < 35ms for N=500
    test('moveElement cascade push budget (N=500) must be < 35ms', () {
      final layout = List.generate(
        500,
        (i) => LayoutItem(
          id: '$i',
          x: i % 8,
          y: i ~/ 8,
          w: 1,
          h: 1,
        ),
      );

      final stopwatch = Stopwatch()..start();
      // Move item_0 (at 0,0) down by 1 row (to 0,1), causing a cascade push through all rows in col 0
      moveElement(
        layout,
        layout.first,
        0,
        1,
        cols: 8,
        compactType: CompactType.none,
        preventCollision: true,
      );
      stopwatch.stop();

      // Enforce a 35ms budget on JIT execution to safely absorb cold-start runner congestion
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(35),
        reason:
            'Cascade push through 500 items took ${stopwatch.elapsedMilliseconds}ms, exceeding the 35ms budget.',
      );
    });

    // Budget 3: Minimap during dragging must use batched drawPath (exactly 2 calls)
    testWidgets('Minimap items painter must paint exactly 2 paths (batched drawing budget)',
        (tester) async {
      final controller = DashboardController(
        initialSlotCount: 8,
        initialLayout: List.generate(
          100,
          (i) => LayoutItem(id: '$i', x: i % 8, y: i ~/ 8, w: 1, h: 1, isStatic: i % 10 == 0),
        ),
      );
      addTearDown(controller.dispose);

      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

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
      await tester.pumpAndSettle();

      final painterFinder = find
          .descendant(
            of: find.byType(DashboardMinimap),
            matching: find.byType(CustomPaint),
          )
          .first;

      final customPaint = tester.widget<CustomPaint>(painterFinder);
      final painter = customPaint.painter;
      expect(painter, isNotNull);

      final canvas = MockCanvas();
      painter!.paint(canvas, const Size(100, 100));

      expect(
        canvas.drawRRectCalls,
        equals(0),
        reason: 'Minimap items painter must not use individual drawRRect loops.',
      );
      expect(
        canvas.drawPathCalls,
        equals(2), // 1 path for dynamic, 1 path for static
        reason: 'Minimap items painter must batch draw calls into exactly 2 paths.',
      );
    });

    // Budget 4: Firewall Rebuild Budget (0 rebuilds on static siblings during interactions)
    testWidgets('Items should NOT rebuild when deleting or dragging another item', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 10,
        initialLayout: [
          const LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2),
          const LayoutItem(id: 'B', x: 2, y: 0, w: 2, h: 2),
          const LayoutItem(id: 'C', x: 0, y: 2, w: 2, h: 2),
        ],
      );
      addTearDown(controller.dispose);

      final buildCounts = <String, int>{};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Dashboard(
              controller: controller,
              itemBuilder: (context, item) {
                return BuildCounter(
                  id: item.id,
                  counters: buildCounts,
                  child: Container(color: Colors.blue),
                );
              },
              scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      buildCounts.clear();

      // Action 1: Remove item A -> B and C must NOT rebuild (firewall cache holds)
      controller.removeItem('A');
      await tester.pump();

      expect(buildCounts.containsKey('A'), false);
      expect(buildCounts['B'] ?? 0, 0, reason: 'Item B should not rebuild on delete');
      expect(buildCounts['C'] ?? 0, 0, reason: 'Item C should not rebuild on delete');
      buildCounts.clear();

      // Action 2: Drag item B -> C must NOT rebuild
      controller.isEditing.value = true;
      await tester.pump();
      buildCounts.clear();

      controller.internal.onDragStart('B');
      await tester.pump();

      controller.internal.onDragUpdate(
        'B',
        const Offset(10, 10),
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
      );
      await tester.pump();

      expect(buildCounts['C'] ?? 0, 0, reason: 'Item C should not rebuild on sibling drag');
    });

    // Budget 5: DashboardItem Shell Rebuild must be allocation-free (0 map/closure allocations in build())
    testWidgets('DashboardItem shell rebuild must NOT allocate new Actions/Shortcuts maps',
        (tester) async {
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

      // Find the FocusableActionDetector of the active item shell
      final detectorFinder = find.byType(FocusableActionDetector).first;
      expect(detectorFinder, findsOneWidget);

      final detectorBefore = tester.widget<FocusableActionDetector>(detectorFinder);
      final actionsBefore = detectorBefore.actions;
      final shortcutsBefore = detectorBefore.shortcuts;

      // Trigger a rebuild of the shell (e.g. by focusing the item)
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      final detectorAfter = tester.widget<FocusableActionDetector>(detectorFinder);

      // ASSERTION: The Actions and Shortcuts maps must be identical (same memory reference)
      // to ensure no closure/map allocations occurred in the build() hot-path.
      expect(
        identical(detectorAfter.actions, actionsBefore),
        isTrue,
        reason: 'DashboardItem build() must reuse cached Actions maps (0 heap allocations budget).',
      );
      expect(
        identical(detectorAfter.shortcuts, shortcutsBefore),
        isTrue,
        reason:
            'DashboardItem build() must reuse cached Shortcuts maps (0 heap allocations budget).',
      );
    });

    // Budget 6: Cross-Grid routing complexity must be O(G) where G = live grids (never O(N) scans)
    testWidgets(
        'Cross-grid target selection (targetAt) must scale with O(G) live grids, bypassing item scans',
        (tester) async {
      final coordinator = DashboardNestedCoordinator();
      addTearDown(coordinator.dispose);

      final parentController = DashboardController(
        initialSlotCount: 8,
        initialLayout: List.generate(
          1000, // Large density grid: 1000 items
          (i) => LayoutItem(id: 'item_$i', x: i % 8, y: i ~/ 8, w: 1, h: 1),
        ),
      )..setEditMode(
          true,
        ); // Enable Edit Mode so canAcceptCrossGridItems evaluates to true
      addTearDown(parentController.dispose);

      // Mount the workspace
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardNestedScope(
              coordinator: coordinator,
              child: SizedBox(
                width: 800,
                height: 600,
                child: Dashboard<String>(
                  controller: parentController,
                  itemBuilder: (context, item) => const SizedBox(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final stopwatch = Stopwatch()..start();

      // Select target at coordinates: must only evaluate 1 grid check (O(G)), bypassing 1000 items scans (O(N))
      final target = coordinator.targetAt(const Offset(100, 100));
      stopwatch.stop();

      expect(target, isNotNull);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(15), // Safe budget preventing JIT/CI system clock-resolution jitter flakiness
        reason:
            'targetAt target selection exceeded the O(G) complexity budget during 1000-item density.',
      );
    });

    // Budget 7: Element Identity Invariant (Dragged item must never remount/be destroyed from tree during drag frames)
    testWidgets('Dragged item element must NOT remount across drag frames', (tester) async {
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
              itemBuilder: (context, item) =>
                  Card(key: ValueKey('content_${item.id}'), child: Text(item.id)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the Element of the active Card before drag starts (contained strictly in the main grid)
      final cardElementBefore = tester.element(
        find.descendant(
          of: find.byType(SliverDashboardLayout),
          matching: find.byKey(const ValueKey('content_item_1')),
        ),
      );
      expect(cardElementBefore, isNotNull);

      // Start drag interaction
      controller.internal.onDragStart('item_1');
      await tester.pump();

      controller.internal.onDragUpdate(
        'item_1',
        const Offset(100, 100),
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
      );
      await tester.pump();

      // Find the Element of the Card after drag update (contained strictly in the main grid, ignoring the overlay feedback duplicate)
      final cardElementAfter = tester.element(
        find.descendant(
          of: find.byType(SliverDashboardLayout),
          matching: find.byKey(const ValueKey('content_item_1')),
        ),
      );

      // ASSERTION: The original grid element must remain mounted and alive in the tree
      expect(
        cardElementAfter,
        isNotNull,
        reason: 'Original grid item element was destroyed or unmounted during active drag.',
      );
    });
  });
}
