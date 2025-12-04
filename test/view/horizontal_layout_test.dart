import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';

void main() {
  group('Horizontal Layout Tests', () {
    testWidgets('Dashboard renders correctly with Axis.horizontal', (tester) async {
      final controller = DashboardController(
        initialLayout: [
          const LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 2), // Tall item
          const LayoutItem(id: '2', x: 1, y: 0, w: 1, h: 1),
        ],
        initialSlotCount: 4, // 4 rows in horizontal mode
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400, // Constrain height for horizontal list
              width: 800,
              child: Dashboard(
                controller: controller,
                scrollDirection: Axis.horizontal, // <--- Key for coverage
                slotAspectRatio: 1,
                itemBuilder: (context, item) => Text('Item ${item.id}'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify items are rendered
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);

      // Verify layout logic (Item 1 should be taller than wide in visual terms,
      // but in grid terms w=1, h=2 means 1 column, 2 rows).
      final item1Finder = find.text('Item 1');
      final item1Size = tester.getSize(item1Finder);

      // With aspect ratio 1, and w=1, h=2:
      // Height (Cross axis) should be roughly 2x Width (Main axis)
      expect(item1Size.height, greaterThan(item1Size.width));

      controller.dispose();
    });

    test('SlotMetrics calculates horizontal coordinates correctly', () {
      // Simulate a container of 800x400
      const constraints = BoxConstraints(maxWidth: 800, maxHeight: 400);

      final metrics = SlotMetrics.fromConstraints(
        constraints,
        slotCount: 4, // 4 rows
        slotAspectRatio: 1,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
        padding: EdgeInsets.zero,
        scrollDirection: Axis.horizontal,
      );

      // In horizontal:
      // Height is divided by slotCount: 400 / 4 = 100 per slot height.
      // Width is derived from aspect ratio: 100 * 1.0 = 100.
      expect(metrics.slotHeight, 100.0);
      expect(metrics.slotWidth, 100.0);

      // Test pixelToGrid conversion
      // Point (150, 150) -> x=1, y=1
      final gridPos = metrics.pixelToGrid(const Offset(150, 150), 0);
      expect(gridPos.x, 1);
      expect(gridPos.y, 1);
    });
  });
}
