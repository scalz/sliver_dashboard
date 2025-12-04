import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

void main() {
  group('Dashboard Responsive Tests', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(initialSlotCount: 1);
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('updates slotCount automatically based on width', (tester) async {
      // Use small breakpoints for default window test size (800x600).
      final breakpoints = {
        0.0: 4,
        300.0: 8,
        600.0: 12,
      };

      // 1. Start with small screen (Mobile)
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200, // < 300
              child: Dashboard(
                controller: controller,
                breakpoints: breakpoints,
                itemBuilder: (_, __) => const SizedBox(),
              ),
            ),
          ),
        ),
      );

      // Wait for postFrameCallback
      await tester.pump();
      expect(controller.slotCount.value, 4);

      // 2. Resize to Tablet
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400, // > 300 && < 600
              child: Dashboard(
                controller: controller,
                breakpoints: breakpoints,
                itemBuilder: (_, __) => const SizedBox(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(controller.slotCount.value, 8);

      // 3. Resize to Desktop
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 700, // > 600 (Fits in 800px screen)
              child: Dashboard(
                controller: controller,
                breakpoints: breakpoints,
                itemBuilder: (_, __) => const SizedBox(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(controller.slotCount.value, 12);
    });

    testWidgets('handles unsorted breakpoints correctly', (tester) async {
      // Keys are not sorted
      final breakpoints = {
        600.0: 12,
        0.0: 4,
        300.0: 8,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400, // Should trigger 8 cols
              child: Dashboard(
                controller: controller,
                breakpoints: breakpoints,
                itemBuilder: (_, __) => const SizedBox(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      // Should pick 8 correctly despite map order
      expect(controller.slotCount.value, 8);
    });
  });
}
