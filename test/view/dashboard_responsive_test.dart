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

    testWidgets('Dashboard renders Section Barriers using default or custom header builders',
        (tester) async {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          const LayoutItem(
            id: 'header1',
            x: 0,
            y: 0,
            w: 4,
            h: 1,
            isSectionBarrier: true,
            sectionTitle: 'Overview',
          ),
          const LayoutItem(id: 'item1', x: 0, y: 1, w: 1, h: 1),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Dashboard<String>(
              controller: controller,
              itemBuilder: (ctx, item) => Text('Card ${item.id}'),
              // Custom builder to verify integration
              sectionHeaderBuilder: (ctx, item) => Container(
                key: const ValueKey('custom_header'),
                child: Text('Custom ${item.sectionTitle}'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify custom section header is drawn correctly
      expect(find.byKey(const ValueKey('custom_header')), findsOneWidget);
      expect(find.text('Custom Overview'), findsOneWidget);
      expect(find.text('Card item1'), findsOneWidget);
    });

    testWidgets('Dashboard renders default section headers when custom header builder is null',
        (tester) async {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          const LayoutItem(
            id: 'header1',
            x: 0,
            y: 0,
            w: 4,
            h: 1,
            isSectionBarrier: true,
            sectionTitle: 'Default Overview',
          ),
          const LayoutItem(
            id: 'header_no_title',
            x: 0,
            y: 1,
            w: 4,
            h: 1,
            isSectionBarrier: true, // sectionTitle is left null to cover fallback branch
          ),
          const LayoutItem(id: 'item1', x: 0, y: 2, w: 1, h: 1),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Dashboard<String>(
              controller: controller,
              itemBuilder: (ctx, item) => Text('Card ${item.id}'),
              // sectionHeaderBuilder is left null to force default rendering
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify both default headers are rendered correctly with their fallback texts
      expect(find.text('Default Overview'), findsOneWidget);
      expect(find.text('Section'), findsOneWidget); // Verifies "item.sectionTitle ?? 'Section'"
      expect(find.text('Card item1'), findsOneWidget);
    });
  });
}
