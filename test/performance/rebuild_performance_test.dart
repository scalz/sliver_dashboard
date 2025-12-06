import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

/// An utility widget to count rebuilds
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
    //  Increment the counter on every build()
    counters[id] = (counters[id] ?? 0) + 1;
    return child;
  }
}

void main() {
  group('Performance Rebuild Tests', () {
    late DashboardController controller;
    // Map to store build counts by item ID
    late Map<String, int> buildCounts;

    setUp(() {
      buildCounts = {};
      controller = DashboardController(
        initialSlotCount: 10,
        initialLayout: [
          const LayoutItem(id: 'A', x: 0, y: 0, w: 2, h: 2),
          const LayoutItem(id: 'B', x: 2, y: 0, w: 2, h: 2),
          const LayoutItem(id: 'C', x: 0, y: 2, w: 2, h: 2),
        ],
      );
    });

    // Helper to build the dashboard with the tracker
    Widget buildTestApp() {
      return MaterialApp(
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
            // Force desktop mode for mouse tests
            scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
          ),
        ),
      );
    }

    testWidgets('Items should NOT rebuild when dragging another item', (tester) async {
      // 1. Initial Build
      await tester.pumpWidget(buildTestApp());

      // Reset counters after initial build
      buildCounts.clear();

      // Enable edit mode to allow dragging
      controller.isEditing.value = true;
      await tester.pump(); // Rebuild due to mode change (expected)

      // Reset to zero to test dragging specifically
      buildCounts.clear();

      // 2. Start Dragging Item 'A'
      // Tip: use the controller directly to simulate dragging
      controller.internal.onDragStart('A');
      await tester.pump();

      // 3. Move Item 'A' (Update)
      controller.internal.onDragUpdate(
        'A',
        const Offset(10, 10),
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
      );
      await tester.pump();

      // 4. Move Item 'A' to change grid (Collision/Push)
      controller.internal.onDragUpdate(
        'A',
        const Offset(250, 0), // Move to the right (over B)
        slotWidth: 100, slotHeight: 100,
        mainAxisSpacing: 0, crossAxisSpacing: 0,
      );
      await tester.pump();

      // VERIFICATION
      // If buildCounts['B'] is null, it was NEVER rebuilt. This is perfect.
      expect(buildCounts['B'] ?? 0, 0, reason: 'Item B should not rebuild when A moves');
      expect(buildCounts['C'] ?? 0, 0, reason: 'Item C should not rebuild when A moves');
    });

    testWidgets('Items should NOT rebuild when adding a new item', (tester) async {
      await tester.pumpWidget(buildTestApp());
      buildCounts.clear();

      // Action: Add Item D
      controller.addItem(const LayoutItem(id: 'D', x: 0, y: 4, w: 2, h: 2));
      await tester.pump();

      // Verification
      expect(buildCounts['D'], 1, reason: 'New item D should be built once');
      expect(buildCounts['A'] ?? 0, 0, reason: 'Item A should not rebuild on add');
      expect(buildCounts['B'] ?? 0, 0, reason: 'Item B should not rebuild on add');
      expect(buildCounts['C'] ?? 0, 0, reason: 'Item C should not rebuild on add');
    });

    // fix this test + add another one on edit mode switch
    // testWidgets('Items should NOT rebuild when deleting an item', (tester) async {
    //   await tester.pumpWidget(buildTestApp());
    //   buildCounts.clear();
    //
    //   // Action: Remove Item A
    //   controller.removeItem('A');
    //   await tester.pump();
    //
    //   // Verification
    //   expect(buildCounts.containsKey('A'), false, reason: "A shouldn't be built anymore");
    //   expect(buildCounts['B'] ?? 0, 0, reason: 'Item B should not rebuild on delete');
    //   expect(buildCounts['C'] ?? 0, 0, reason: 'Item C should not rebuild on delete');
    // });

    testWidgets('Items should NOT rebuild when dragging external item (Placeholder)',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      buildCounts.clear();

      // Action: Show Placeholder (simulates external drag hover)
      controller.internal.showPlaceholder(x: 3, y: 3, w: 2, h: 2);
      await tester.pump();

      // Verification
      expect(buildCounts['A'] ?? 0, 0, reason: 'Item A should not rebuild on placeholder show');
      expect(buildCounts['B'] ?? 0, 0, reason: 'Item B should not rebuild on placeholder show');

      // Action: Move Placeholder (simulates external drag move)
      controller.internal.showPlaceholder(x: 4, y: 4, w: 2, h: 2);
      await tester.pump();

      expect(buildCounts['A'] ?? 0, 0, reason: 'Item A should not rebuild on placeholder move');
    });
  });
}
