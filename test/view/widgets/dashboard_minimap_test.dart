import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';

void main() {
  group('DashboardMinimap', () {
    late DashboardController controller;
    late ScrollController scrollController;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          const LayoutItem(id: '1', x: 0, y: 0, w: 2, h: 2),
          const LayoutItem(id: '2', x: 2, y: 2, w: 2, h: 2),
        ],
      );
      scrollController = ScrollController();
    });

    tearDown(() {
      controller.dispose();
      scrollController.dispose();
    });

    testWidgets('renders correctly with finite size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                children: [
                  DashboardMinimap(
                    controller: controller,
                    scrollController: scrollController,
                    width: 100,
                  ),
                  Container(height: 1000, color: Colors.red),
                ],
              ),
            ),
          ),
        ),
      );

      final minimapFinder = find.byType(DashboardMinimap);
      final painterFinder = find.descendant(
        of: minimapFinder,
        matching: find.byType(CustomPaint),
      );

      // Verify that both layered painters (Items + Viewport) are mounted.
      expect(painterFinder, findsNWidgets(2));

      // Verify the size of the overall minimap is correct
      final size = tester.getSize(painterFinder.first);
      expect(size.width, 100.0);
      expect(size.height.isFinite, isTrue, reason: 'Height should be finite');
      expect(size.height, greaterThan(0));
    });

    testWidgets('repaints when layout changes', (tester) async {
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

      final minimapFinder = find.byType(DashboardMinimap);
      final painterFinder = find.descendant(
        of: minimapFinder,
        matching: find.byType(CustomPaint),
      );

      // Check the background items painter (first CustomPaint)
      final paintBefore = tester.widget(painterFinder.first) as CustomPaint;
      final painterBefore = paintBefore.painter;

      controller.addItem(const LayoutItem(id: '3', x: 0, y: 10, w: 1, h: 1));
      await tester.pump();

      final paintAfter = tester.widget(painterFinder.first) as CustomPaint;
      final painterAfter = paintAfter.painter;

      expect(painterAfter, isNot(equals(painterBefore)));
    });

    testWidgets('repaints when scroll changes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                children: [
                  DashboardMinimap(
                    controller: controller,
                    scrollController: scrollController,
                    width: 100,
                  ),
                  Container(height: 2000, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      );

      final minimapFinder = find.byType(DashboardMinimap);
      final painterFinder = find.descendant(
        of: minimapFinder,
        matching: find.byType(CustomPaint),
      );

      // Check the foreground viewport painter (second CustomPaint)
      final paintBefore = tester.widget(painterFinder.last) as CustomPaint;
      final painterBefore = paintBefore.painter;

      scrollController.jumpTo(100);
      await tester.pump();

      final paintAfter = tester.widget(painterFinder.last) as CustomPaint;
      final painterAfter = paintAfter.painter;

      expect(painterAfter, isNot(equals(painterBefore)));
    });

    testWidgets('renders and paints correctly in horizontal scroll mode', (tester) async {
      (controller as DashboardControllerImpl).setScrollDirection(Axis.horizontal);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: scrollController,
              child: Row(
                children: [
                  DashboardMinimap(
                    controller: controller,
                    scrollController: scrollController,
                    width: 100,
                  ),
                  Container(width: 2000, height: 500, color: Colors.blue),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DashboardMinimap), findsOneWidget);

      final painterFinder = find.descendant(
        of: find.byType(DashboardMinimap),
        matching: find.byType(CustomPaint),
      );
      final size = tester.getSize(painterFinder.first);
      expect(size.height, greaterThan(0));
    });

    testWidgets('interaction (tap & drag) updates scroll position', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  height: 100,
                  child: DashboardMinimap(
                    controller: controller,
                    scrollController: scrollController,
                    width: 100,
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Container(height: 2000, color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(scrollController.offset, 0.0);

      await tester.tap(find.byType(DashboardMinimap));
      await tester.pump();

      expect(scrollController.offset, greaterThan(0.0));
      final offsetAfterTap = scrollController.offset;

      await tester.drag(find.byType(DashboardMinimap), const Offset(0, -50));
      await tester.pump();

      expect(scrollController.offset, lessThan(offsetAfterTap));
    });

    testWidgets('renders without error even if scroll view has no dimensions yet', (tester) async {
      final emptyController = ScrollController();
      addTearDown(emptyController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardMinimap(
              controller: controller,
              scrollController: emptyController,
              width: 100,
            ),
          ),
        ),
      );

      expect(find.byType(DashboardMinimap), findsOneWidget);
    });

    testWidgets('calculates layout with spacing correctly', (tester) async {
      const spacing = 50.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                children: [
                  DashboardMinimap(
                    controller: controller,
                    scrollController: scrollController,
                    width: 100,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                  ),
                  Container(height: 1000, color: Colors.red),
                ],
              ),
            ),
          ),
        ),
      );

      final painterFinder = find.descendant(
        of: find.byType(DashboardMinimap),
        matching: find.byType(CustomPaint),
      );
      expect(painterFinder, findsNWidgets(2));

      final customPaint = tester.widget<CustomPaint>(painterFinder.first);
      final painter = customPaint.painter;
      expect(painter, isNotNull);
    });

    testWidgets('calculates layout with spacing correctly in Horizontal mode', (tester) async {
      (controller as DashboardControllerImpl).setScrollDirection(Axis.horizontal);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: scrollController,
              child: Row(
                children: [
                  DashboardMinimap(
                    controller: controller,
                    scrollController: scrollController,
                    width: 100,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  Container(width: 1000, height: 500, color: Colors.red),
                ],
              ),
            ),
          ),
        ),
      );

      final painterFinder = find.descendant(
        of: find.byType(DashboardMinimap),
        matching: find.byType(CustomPaint),
      );
      expect(painterFinder, findsNWidgets(2));

      final customPaint = tester.widget<CustomPaint>(painterFinder.first);
      final painter = customPaint.painter;
      expect(painter, isNotNull);
    });

    testWidgets('calculates layout with spacing correctly in Horizontal mode', (tester) async {
      (controller as DashboardControllerImpl).setScrollDirection(Axis.horizontal);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: scrollController,
                child: Row(
                  children: [
                    DashboardMinimap(
                      controller: controller,
                      scrollController: scrollController,
                      width: 100,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    Container(width: 1000, height: 500, color: Colors.red),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      scrollController.jumpTo(1);
      await tester.pump();

      final painterFinder = find.descendant(
        of: find.byType(DashboardMinimap),
        matching: find.byType(CustomPaint),
      );
      expect(painterFinder, findsNWidgets(2));
    });
  });

  group('Minimap Style & Marker — Value Equality Branch Coverage', () {
    test('MinimapStyle covers all individual property equality branches', () {
      const base = MinimapStyle();
      expect(base == const MinimapStyle(), isTrue);

      // Mutate exactly one property at a time to force evaluation of all && branches
      expect(base == const MinimapStyle(backgroundColor: Colors.red), isFalse);
      expect(base == const MinimapStyle(itemColor: Colors.red), isFalse);
      expect(base == const MinimapStyle(staticItemColor: Colors.red), isFalse);
      expect(base == const MinimapStyle(viewportColor: Colors.red), isFalse);
      expect(base == const MinimapStyle(viewportBorderColor: Colors.red), isFalse);
      expect(base == const MinimapStyle(itemBorderRadius: 10), isFalse);
      expect(base == const MinimapStyle(viewportBorderWidth: 10), isFalse);
    });

    test('MinimapMarker covers all individual property equality branches', () {
      const base = MinimapMarker(itemId: 'a', color: Colors.red);
      expect(base == const MinimapMarker(itemId: 'a', color: Colors.red), isTrue);

      expect(base == const MinimapMarker(itemId: 'b', color: Colors.red), isFalse);
      expect(base == const MinimapMarker(itemId: 'a', color: Colors.blue), isFalse);
      expect(
        base ==
            const MinimapMarker(itemId: 'a', color: Colors.red, shape: MinimapMarkerShape.square),
        isFalse,
      );
      expect(
        base ==
            const MinimapMarker(itemId: 'a', color: Colors.red, alignment: Alignment.bottomLeft),
        isFalse,
      );
      expect(base == const MinimapMarker(itemId: 'a', color: Colors.red, size: 10), isFalse);
    });
  });

  group('Minimap models — equality laws (project rule for painter params)', () {
    test('MinimapMarker: == symmetric and consistent with hashCode', () {
      const a = MinimapMarker(itemId: 'a', color: Colors.red);
      const b = MinimapMarker(itemId: 'a', color: Colors.red);
      const c = MinimapMarker(itemId: 'a', color: Colors.blue);
      expect(a == b, isTrue);
      expect(b == a, isTrue);
      expect(a.hashCode, equals(b.hashCode));
      expect(a == c, isFalse);
    });

    test('ViewportIndicator: value equality with identity-based controller', () {
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final a = ViewportIndicator(scrollController: ctrl, mainAxisLeadingExtent: 10);
      final b = ViewportIndicator(scrollController: ctrl, mainAxisLeadingExtent: 10);
      final c = ViewportIndicator(scrollController: ctrl, mainAxisLeadingExtent: 20);
      expect(a == b, isTrue);
      expect(a.hashCode, equals(b.hashCode));
      expect(a == c, isFalse);
    });

    test('MinimapStyle: value equality (shouldRepaint short-circuit)', () {
      const a = MinimapStyle();
      const b = MinimapStyle();
      const c = MinimapStyle(itemColor: Colors.green);
      expect(a == b, isTrue);
      expect(a.hashCode, equals(b.hashCode));
      expect(a == c, isFalse);
    });
  });

  group('Minimap widget — markers & multiple viewports', () {
    testWidgets('renders a dedicated markers layer only when markers exist', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
          LayoutItem(id: 'b', x: 2, y: 0, w: 2, h: 2),
        ],
      );
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      Widget host(List<MinimapMarker> markers) => MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: Dashboard<String>(
                      controller: controller,
                      scrollController: scrollController,
                      itemBuilder: (context, item) => Text(item.id),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: DashboardMinimap(
                      controller: controller,
                      scrollController: scrollController,
                      markers: markers,
                    ),
                  ),
                ],
              ),
            ),
          );

      await tester.pumpWidget(host(const []));
      await tester.pumpAndSettle();
      final layersWithout = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where((w) => '${w.painter.runtimeType}' == '_MinimapMarkersPainter')
          .length;
      expect(layersWithout, 0);

      await tester.pumpWidget(
        host(const [
          MinimapMarker(itemId: 'a', color: Colors.red),
          MinimapMarker(
            itemId: 'b',
            color: Colors.amber,
            shape: MinimapMarkerShape.triangle,
            alignment: Alignment.bottomLeft,
          ),
          MinimapMarker(itemId: 'ghost', color: Colors.red), // unknown id: ignored
        ]),
      );
      await tester.pumpAndSettle();
      final layersWith = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where((w) => '${w.painter.runtimeType}' == '_MinimapMarkersPainter')
          .length;
      expect(layersWith, 1);
    });

    testWidgets('accepts multiple viewport indicators with segments', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          for (var i = 0; i < 24; i++) LayoutItem(id: 'i$i', x: i % 4, y: i ~/ 4, w: 1, h: 1),
        ],
      );
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Dashboard<String>(
                    controller: controller,
                    scrollController: scrollController,
                    itemBuilder: (context, item) => Text(item.id),
                  ),
                ),
                SizedBox(
                  width: 120,
                  height: 120,
                  child: DashboardMinimap(
                    controller: controller,
                    scrollController: scrollController,
                    viewportIndicators: [
                      ViewportIndicator(scrollController: scrollController),
                      ViewportIndicator(
                        scrollController: scrollController,
                        mainAxisLeadingExtent: 200,
                        mainAxisContentExtent: 400,
                        color: Colors.red.withValues(alpha: 0.2),
                        borderColor: Colors.red,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DashboardMinimap), findsOneWidget);

      // Scrolling still only notifies the viewport layer (behavioral smoke:
      // must not throw and must keep both indicators alive).
      scrollController.jumpTo(50);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Minimap widget — regression fixes', () {
    testWidgets(
        'a marker larger than its tile is capped, not crashing '
        '(regression: inverted clamp bounds threw ArgumentError)', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 8,
        initialLayout: const [
          LayoutItem(id: 'tiny', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'big', x: 1, y: 0, w: 4, h: 3),
        ],
      );
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Dashboard<String>(
                    controller: controller,
                    scrollController: scrollController,
                    itemBuilder: (context, item) => Text(item.id),
                  ),
                ),
                SizedBox(
                  width: 100,
                  height: 100,
                  child: DashboardMinimap(
                    controller: controller,
                    scrollController: scrollController,
                    markers: const [
                      // Far larger than a 1x1 tile on a 100 px minimap.
                      MinimapMarker(itemId: 'tiny', color: Colors.red, size: 60),
                      MinimapMarker(
                        itemId: 'big',
                        color: Colors.amber,
                        shape: MinimapMarkerShape.square,
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'tap-to-scroll maps through the grid segment '
        '(consistent with the item layer and the default indicator)', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          for (var i = 0; i < 40; i++) LayoutItem(id: 'i$i', x: i % 4, y: i ~/ 4, w: 1, h: 1),
        ],
      );
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Dashboard<String>(
                    controller: controller,
                    scrollController: scrollController,
                    itemBuilder: (context, item) => Text(item.id),
                  ),
                ),
                SizedBox(
                  width: 120,
                  height: 160,
                  child: DashboardMinimap(
                    controller: controller,
                    scrollController: scrollController,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scrollController.offset, 0);

      // Tapping the lower part of the minimap must scroll the grid forward.
      final minimap = find.byType(DashboardMinimap);
      final bottom = tester.getBottomLeft(minimap) + const Offset(30, -5);
      await tester.tapAt(bottom);
      await tester.pumpAndSettle();
      expect(scrollController.offset, greaterThan(0));
      expect(
        scrollController.offset,
        lessThanOrEqualTo(scrollController.position.maxScrollExtent),
      );
    });
  });
}
