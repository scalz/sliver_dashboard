import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';

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

  group('Viewport indicator mapping — numeric contract', () {
    // Canonical numbers: grid segment 4500 px starting at 0, viewport
    // 900 px, minimap 270 px. Expected window length: 900/4500*270 = 54 px.
    test('at top: window starts at 0 with length V/L * minimap', () {
      final m = mapViewportToSegment(
        pixels: 0,
        viewportDimension: 900,
        segmentLeading: 0,
        segmentExtent: 4500,
        minimapMainAxis: 270,
      );
      expect(m, isNotNull);
      expect(m!.$1, 0);
      expect(m.$2, closeTo(54, 0.001));
    });

    test(
        'anti-gauge invariant: scrolling moves the window start, '
        'the length stays constant inside the segment', () {
      final atTop = mapViewportToSegment(
        pixels: 0,
        viewportDimension: 900,
        segmentLeading: 0,
        segmentExtent: 4500,
        minimapMainAxis: 270,
      )!;
      final scrolled = mapViewportToSegment(
        pixels: 1800,
        viewportDimension: 900,
        segmentLeading: 0,
        segmentExtent: 4500,
        minimapMainAxis: 270,
      )!;
      expect(scrolled.$2, closeTo(atTop.$2, 0.001)); // same length
      expect(scrolled.$1, closeTo(1800 / 4500 * 270, 0.001)); // moved start
    });

    test('a preceding app bar shifts the mapping via segmentLeading', () {
      final m = mapViewportToSegment(
        pixels: 200, // exactly the app bar extent scrolled away
        viewportDimension: 900,
        segmentLeading: 200,
        segmentExtent: 4500,
        minimapMainAxis: 270,
      )!;
      expect(m.$1, 0); // grid top aligns with minimap top
      expect(m.$2, closeTo(54, 0.001));
    });

    test('a segment shorter than the viewport clamps to the segment', () {
      final m = mapViewportToSegment(
        pixels: 0,
        viewportDimension: 900,
        segmentLeading: 0,
        segmentExtent: 600,
        minimapMainAxis: 270,
      )!;
      expect(m.$1, 0);
      expect(m.$2, closeTo(270, 0.001)); // full minimap: honest, not a bug
    });

    test('a segment fully scrolled past yields no indicator', () {
      final m = mapViewportToSegment(
        pixels: 5000,
        viewportDimension: 900,
        segmentLeading: 0,
        segmentExtent: 4500,
        minimapMainAxis: 270,
      );
      expect(m, isNull);
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

  group('Minimap — painter branches', () {
    testWidgets('all four marker shapes render, and marker changes repaint', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
          LayoutItem(id: 'b', x: 2, y: 0, w: 2, h: 2),
          LayoutItem(id: 'c', x: 0, y: 2, w: 2, h: 2),
          LayoutItem(id: 'd', x: 2, y: 2, w: 2, h: 2),
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

      // Corner alignments + every shape: exercises each Path branch and the
      // in-rect clamping on all four edges. Two markers share a color to
      // exercise the per-color batching (putIfAbsent hit).
      await tester.pumpWidget(
        host(const [
          MinimapMarker(itemId: 'a', color: Colors.red, alignment: Alignment.topLeft),
          MinimapMarker(
            itemId: 'b',
            color: Colors.red,
            shape: MinimapMarkerShape.square,
            alignment: Alignment.topRight,
          ),
          MinimapMarker(
            itemId: 'c',
            color: Colors.green,
            shape: MinimapMarkerShape.diamond,
            alignment: Alignment.bottomLeft,
          ),
          MinimapMarker(
            itemId: 'd',
            color: Colors.blue,
            shape: MinimapMarkerShape.triangle,
            alignment: Alignment.bottomRight,
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Changing one marker by value exercises the shouldRepaint
      // listEquals-false branch without tearing the layer down.
      await tester.pumpWidget(
        host(const [
          MinimapMarker(itemId: 'a', color: Colors.purple, alignment: Alignment.topLeft),
          MinimapMarker(
            itemId: 'b',
            color: Colors.red,
            shape: MinimapMarkerShape.square,
            alignment: Alignment.topRight,
          ),
          MinimapMarker(
            itemId: 'c',
            color: Colors.green,
            shape: MinimapMarkerShape.diamond,
            alignment: Alignment.bottomLeft,
          ),
          MinimapMarker(
            itemId: 'd',
            color: Colors.blue,
            shape: MinimapMarkerShape.triangle,
            alignment: Alignment.bottomRight,
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'without a mounted grid the minimap falls back to the legacy '
        'derivation (no published metrics) and still renders', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
          LayoutItem(id: 'b', x: 2, y: 2, w: 2, h: 2),
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
                  // A plain scrollable: nothing publishes grid metrics.
                  child: ListView(
                    controller: scrollController,
                    children: [for (var i = 0; i < 40; i++) Text('row $i')],
                  ),
                ),
                SizedBox(
                  width: 120,
                  height: 120,
                  child: DashboardMinimap(
                    controller: controller,
                    scrollController: scrollController,
                    markers: const [
                      MinimapMarker(itemId: 'a', color: Colors.red),
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
      expect(tester.takeException(), isNull);
    });

    testWidgets('a horizontal-direction controller renders and accepts taps', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
          LayoutItem(id: 'b', x: 4, y: 0, w: 2, h: 2),
        ],
      );
      addTearDown(controller.dispose);
      controller.internal.setScrollDirection(Axis.horizontal);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    controller: scrollController,
                    children: [for (var i = 0; i < 40; i++) Text(' col $i ')],
                  ),
                ),
                SizedBox(
                  width: 200,
                  height: 80,
                  child: DashboardMinimap(
                    controller: controller,
                    scrollController: scrollController,
                    markers: const [
                      MinimapMarker(itemId: 'b', color: Colors.amber),
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

      // Tap-to-scroll through the horizontal mapping branch.
      await tester.tapAt(
        tester.getCenter(find.byType(DashboardMinimap)) + const Offset(40, 0),
      );
      await tester.pumpAndSettle();
      expect(scrollController.offset, greaterThanOrEqualTo(0));
    });

    testWidgets('a never-attached scrollController is inert, not a crash', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2)],
      );
      addTearDown(controller.dispose);
      final detached = ScrollController();
      addTearDown(detached.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 120,
                child: DashboardMinimap(
                  controller: controller,
                  scrollController: detached,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Tap: _handleInteraction must bail on !hasClients.
      await tester.tapAt(tester.getCenter(find.byType(DashboardMinimap)));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Minimap — exact published metrics', () {
    testWidgets(
        'the grid sliver publishes leading/content extents and slot sizes '
        'onto the controller at layout time', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          for (var i = 0; i < 12; i++) LayoutItem(id: 'i$i', x: i % 4, y: i ~/ 4, w: 1, h: 1),
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

      final internal = controller.internal;
      // 800 px test viewport, 4 columns, 8 px spacing:
      // slot = (800 - 3*8) / 4 = 194.
      expect(internal.viewSlotWidth, isNotNull);
      expect(internal.viewSlotWidth, closeTo(194, 1));
      expect(internal.viewSlotHeight, closeTo(194, 1));
      // 3 rows of 194 + 2 spacings of 8 = 598 (± edit-mode trailing row).
      expect(internal.viewMainAxisContentExtent, greaterThanOrEqualTo(598 - 1));
      expect(internal.viewMainAxisLeadingExtent, isNotNull);
    });

    group('Minimap — widget markers & item tap (opt-in)', () {
      testWidgets(
          'markerBuilder positions widgets over item rects, skips null, '
          'and mounts no layer when absent', (tester) async {
        final controller = DashboardController(
          initialSlotCount: 4,
          initialLayout: const [
            LayoutItem(id: 'alert', x: 0, y: 0, w: 2, h: 2),
            LayoutItem(id: 'calm', x: 2, y: 0, w: 2, h: 2),
          ],
        );
        addTearDown(controller.dispose);
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        Widget host({Widget? Function(BuildContext, LayoutItem)? builder}) => MaterialApp(
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
                      width: 200,
                      height: 200,
                      child: DashboardMinimap(
                        controller: controller,
                        scrollController: scrollController,
                        markerBuilder: builder,
                      ),
                    ),
                  ],
                ),
              ),
            );

        await tester.pumpWidget(host());
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.warning), findsNothing);

        await tester.pumpWidget(
          host(
            builder: (context, item) => item.id == 'alert'
                ? const Align(child: Icon(Icons.warning, size: 10))
                : null, // 'calm' is skipped
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.warning), findsOneWidget);

        // The icon sits inside the 'alert' half of the minimap (left half).
        final minimapRect = tester.getRect(find.byType(DashboardMinimap));
        final iconCenter = tester.getCenter(find.byIcon(Icons.warning));
        expect(iconCenter.dx, lessThan(minimapRect.center.dx));
      });

      testWidgets(
          'onItemTap fires with the tapped item and suppresses tap-to-scroll; '
          'empty-area taps still scroll', (tester) async {
        final controller = DashboardController(
          initialSlotCount: 4,
          initialLayout: [
            // Enough content to make the scroll view scrollable.
            for (var i = 0; i < 40; i++) LayoutItem(id: 'i$i', x: i % 4, y: i ~/ 4, w: 1, h: 1),
          ],
        );
        addTearDown(controller.dispose);
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);
        final taps = <String>[];

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
                      onItemTap: (item) => taps.add(item.id),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the very top-left of the minimap: item i0's rectangle.
        final minimapTopLeft = tester.getTopLeft(find.byType(DashboardMinimap));
        await tester.tapAt(minimapTopLeft + const Offset(4, 4));
        await tester.pumpAndSettle();
        expect(taps, ['i0']);
        expect(
          scrollController.offset,
          0,
          reason: 'an item hit suppresses the default tap-to-scroll',
        );
      });
    });

    group('Desktop hover — spatial bucket index', () {
      testWidgets(
          'itemAtGlobal resolves via the bucket index on dense layouts '
          '(>= threshold) with identical semantics', (tester) async {
        // 40 items >= threshold (16): the bucket path is exercised.
        final controller = DashboardController(
          initialSlotCount: 4,
          initialLayout: [
            for (var i = 0; i < 40; i++) LayoutItem(id: 'i$i', x: i % 4, y: i ~/ 4, w: 1, h: 1),
          ],
        )..setEditMode(true);
        addTearDown(controller.dispose);
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DashboardOverlay<String>(
                controller: controller,
                scrollController: scrollController,
                itemBuilder: (context, item) => Text(item.id),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverDashboard(
                      itemBuilder: (context, item) => Text(item.id),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final state = tester.state<State<DashboardOverlay<String>>>(
          find.byType(DashboardOverlay<String>),
        );
        final target = state as CrossGridDragTarget;

        // 800 px viewport, 4 columns, 8 px spacing: slot ~194 px, stride 202.
        // (100, 100) lies inside cell (0, 0) -> 'i0'.
        expect(target.itemAtGlobal(const Offset(100, 100))?.id, 'i0');
        // (300, 100) lies inside cell (1, 0) -> 'i1'.
        expect(target.itemAtGlobal(const Offset(300, 100))?.id, 'i1');
        // Excluding the hit id yields null (overlap-free invariant).
        expect(
          target.itemAtGlobal(const Offset(100, 100), excludeId: 'i0'),
          isNull,
        );
        // Far outside any cell: null.
        expect(target.itemAtGlobal(const Offset(-50, -50)), isNull);
      });
    });
  });
}
