import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/view/dashboard_feedback_widget.dart'
    show DashboardFeedbackItem;
import 'package:sliver_dashboard/src/view/dashboard_grid.dart';

import '../test_helpers.dart';

/// Paints [finder]'s [GridBackgroundPainter] into a recording canvas and
/// returns the grid's content origin, in the painter's own local coordinates.
Offset _backgroundOriginOf(WidgetTester tester, Finder finder) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: finder, matching: find.byType(CustomPaint)).first,
  );
  final painter = paint.painter! as GridBackgroundPainter;
  final canvas = RecordingCanvas();
  painter.paint(canvas, tester.getSize(finder));
  expect(
    canvas.translations,
    hasLength(1),
    reason: 'the painter must apply exactly one origin translate',
  );
  return canvas.translations.single;
}

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

  testWidgets('SliverDashboard geometricViewOf handles identical coordinates with ID sorting',
      (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'b_item', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'a_item', x: 0, y: 0, w: 1, h: 1), // Identical coordinates
      ],
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverDashboard(
                controller: controller,
                itemBuilder: (context, item) => Text(item.id),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Under geometric sorting, 'a_item' must be sorted before 'b_item' alphabetically
    expect(find.text('a_item'), findsOneWidget);
  });

  testWidgets('SliverDashboard geometricViewOf handles identical coordinates with ID sorting',
      (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'b_item', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'a_item', x: 0, y: 0, w: 1, h: 1), // Identical coordinates
      ],
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverDashboard(
                controller: controller,
                itemBuilder: (context, item) => Text(item.id),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Under geometric sorting, 'a_item' must be sorted before 'b_item' alphabetically
    expect(find.text('a_item'), findsOneWidget);
  });

  testWidgets('SliverDashboard computes reactive metrics under horizontal scroll direction',
      (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
      ],
    );
    addTearDown(controller.dispose);
    controller.scrollDirection.value = Axis.horizontal;

    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    double? capturedW;
    double? capturedH;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            slivers: [
              SliverDashboard(
                controller: controller,
                scrollDirection: Axis.horizontal,
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

  testWidgets('SliverDashboard handles layout when scrolled completely past all items',
      (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
      ],
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverDashboard(
                controller: controller,
                itemBuilder: (context, item) => Text(item.id),
              ),
              // Add a very tall trailing sliver so we can scroll past the dashboard
              const SliverToBoxAdapter(
                child: SizedBox(height: 2000),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll way past the first item (first item height is approx 200px)
    scrollController.jumpTo(1500);
    await tester.pumpAndSettle();

    // Verify scroll offset updated safely without causing any layout exceptions
    expect(scrollController.offset, 1500);
    expect(find.byType(CustomScrollView), findsOneWidget);
  });

  group('SliverDashboardParentData.paintOffset', () {
    // The paint offset is stored as two doubles — an `Offset` per child
    // per layout pass was ~1.8k short-lived objects/s at 60 Hz with 30 visible
    // tiles. `paintOffset` survives as a convenience VIEW for call sites outside
    // the hot path (and for tests); this pins the grid math it exposes.
    testWidgets('exposes the child grid position in content coordinates', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [LayoutItem(id: 'a', x: 1, y: 2, w: 1, h: 1)],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Dashboard<String>(
              controller: controller,
              itemBuilder: (context, item) => Text('T-${item.id}'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final render = tester.renderObject<RenderSliverDashboard>(
        find.byType(SliverDashboardLayout),
      );
      final parentData = render.firstChild!.parentData! as SliverDashboardParentData;

      // Derived from the metrics the sliver publishes, so the expectation holds
      // whatever the test surface size is.
      final slotWidth = controller.internal.viewSlotWidth!;
      final slotHeight = controller.internal.viewSlotHeight!;

      expect(parentData.hasPaintOffset, isTrue);
      expect(
        parentData.paintOffset,
        within(
          distance: 0.01,
          from: Offset(1 * (slotWidth + 8), 2 * (slotHeight + 8)),
        ),
        reason: 'x stride uses crossAxisSpacing, y stride uses mainAxisSpacing',
      );
      expect(parentData.paintOffset.dx, parentData.paintOffsetX);
      expect(parentData.paintOffset.dy, parentData.paintOffsetY);
    });
  });

  group('SliverDashboard key cache', () {
    // The cached ValueKeys embed `itemGlobalKeySuffix`. Without dropping
    // the cache on a suffix change, `_keyFor` would keep handing out keys built
    // from the OLD suffix, so the item elements would never be re-keyed — a
    // silent divergence between the keys the delegate emits and the suffix the
    // widget was configured with.
    testWidgets('a suffix change re-keys every item', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'i1', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'i2', x: 1, y: 0, w: 1, h: 1),
        ],
      );
      addTearDown(controller.dispose);

      Widget build(String suffix) => MaterialApp(
            home: Scaffold(
              body: Dashboard<String>(
                controller: controller,
                itemGlobalKeySuffix: suffix,
                itemBuilder: (context, item) => Text('T-${item.id}'),
              ),
            ),
          );

      await tester.pumpWidget(build('-v1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('i1-v1')), findsOneWidget);
      expect(find.byKey(const ValueKey('i2-v1')), findsOneWidget);

      // Same widget position and no key change: this is didUpdateWidget, the
      // State (and its caches) survives.
      await tester.pumpWidget(build('-v2'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('i1-v1')),
        findsNothing,
        reason: 'a stale cached key would still be emitted here',
      );
      expect(find.byKey(const ValueKey('i1-v2')), findsOneWidget);
      expect(find.byKey(const ValueKey('i2-v2')), findsOneWidget);
    });
  });

  group('DashboardGrid sliverKey scoping', () {
    setUp(() => debugLastGridGeometrySource = null);
    tearDown(() => debugLastGridGeometrySource = null);

    testWidgets('resolves directly when the key is on the SliverDashboardLayout', (tester) async {
      const items = [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)];
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: items,
      )..setEditMode(true);
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final sliverKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay<String>(
              controller: controller,
              scrollController: scrollController,
              sliverKey: sliverKey,
              gridStyle: const GridStyle(),
              padding: const EdgeInsets.all(20),
              itemBuilder: (context, item) => Text('T-${item.id}'),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(20),
                    sliver: SliverDashboardLayout(
                      key: sliverKey,
                      items: items,
                      slotCount: 4,
                      vsync: tester,
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Text('T-${items[index].id}'),
                        childCount: items.length,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The key's render object IS the RenderSliverDashboard: no walk needed.
      expect(sliverKey.currentContext!.findRenderObject(), isA<RenderSliverDashboard>());
      expect(debugLastGridGeometrySource, GridGeometrySource.liveSliver);

      final overlayOrigin = tester.getTopLeft(find.byType(DashboardOverlay<String>));
      expect(
        _backgroundOriginOf(tester, find.byType(DashboardGrid)),
        within(distance: 0.5, from: tester.getTopLeft(find.text('T-a')) - overlayOrigin),
      );
    });

    testWidgets('walks the subtree when the key is on the SliverDashboard', (tester) async {
      // `SliverDashboard` builds a SliverLayoutBuilder, so the key's render
      // object is NOT the RenderSliverDashboard — the visitor has to walk down.
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
      )..setEditMode(true);
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final sliverKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay<String>(
              controller: controller,
              scrollController: scrollController,
              sliverKey: sliverKey,
              gridStyle: const GridStyle(),
              padding: const EdgeInsets.all(20),
              itemBuilder: (context, item) => Text('T-${item.id}'),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(20),
                    sliver: SliverDashboard(
                      key: sliverKey,
                      controller: controller,
                      itemBuilder: (context, item) => Text('T-${item.id}'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sliverKey.currentContext!.findRenderObject(), isNot(isA<RenderSliverDashboard>()));
      expect(debugLastGridGeometrySource, GridGeometrySource.liveSliver);

      final overlayOrigin = tester.getTopLeft(find.byType(DashboardOverlay<String>));
      expect(
        _backgroundOriginOf(tester, find.byType(DashboardGrid)),
        within(distance: 0.5, from: tester.getTopLeft(find.text('T-a')) - overlayOrigin),
        reason: 'the scoped walk must find THIS grid, at its padded origin',
      );
    });

    testWidgets('two grids sharing one scroll view paint their own origins', (tester) async {
      // The composition sliverKey exists for. Each overlay's Stack covers the
      // whole viewport, so an unscoped lookup cannot tell the two apart.
      final a = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [LayoutItem(id: 'a1', x: 0, y: 0, w: 1, h: 1)],
      )..setEditMode(true);
      final b = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [LayoutItem(id: 'b1', x: 0, y: 0, w: 1, h: 1)],
      )..setEditMode(true);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final keyA = GlobalKey();
      final keyB = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardOverlay<String>(
              controller: a,
              scrollController: scrollController,
              sliverKey: keyA,
              gridStyle: const GridStyle(),
              itemBuilder: (context, item) => Text('A-${item.id}'),
              child: DashboardOverlay<String>(
                controller: b,
                scrollController: scrollController,
                sliverKey: keyB,
                gridStyle: const GridStyle(),
                itemBuilder: (context, item) => Text('B-${item.id}'),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverDashboard(
                      key: keyA,
                      controller: a,
                      itemBuilder: (context, item) => Text('A-${item.id}'),
                    ),
                    SliverDashboard(
                      key: keyB,
                      controller: b,
                      itemBuilder: (context, item) => Text('B-${item.id}'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final grids = find.byType(DashboardGrid);
      expect(grids, findsNWidgets(2));

      // Tree order: the outer overlay's background comes first.
      final originA = _backgroundOriginOf(tester, grids.at(0));
      final originB = _backgroundOriginOf(tester, grids.at(1));

      expect(originA.dy, closeTo(0, 0.5));
      expect(
        originB.dy,
        greaterThan(originA.dy + 100),
        reason: 'grid B starts after grid A content; an unscoped lookup would '
            'give both the same origin',
      );
    });

    testWidgets(
        'an overlay with no SliverDashboard degrades to the padding origin '
        'and retries at most once', (tester) async {
      // Covers the tier-3 fallback AND the `_resolveRetryScheduled`
      // guard. Frame 1 finds nothing and schedules the retry; frame 2 finds
      // nothing again and must NOT schedule another one — the flag is cleared
      // only on success, so this is what bounds the retry to a single extra
      // build instead of an infinite rebuild loop.
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
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
              gridStyle: const GridStyle(),
              padding: const EdgeInsets.all(20),
              itemBuilder: (context, item) => const SizedBox(),
              // No SliverDashboard anywhere: the lookup can never succeed.
              child: CustomScrollView(
                controller: scrollController,
                slivers: const [SliverToBoxAdapter(child: SizedBox(height: 400))],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(debugLastGridGeometrySource, GridGeometrySource.padding);
      expect(
        _backgroundOriginOf(tester, find.byType(DashboardGrid)),
        const Offset(20, 20),
        reason: 'the padding tier is exact for a single-grid composition',
      );

      // A further rebuild must still not resolve, and must not loop.
      controller.toggleSelection('a');
      await tester.pumpAndSettle();
      expect(debugLastGridGeometrySource, GridGeometrySource.padding);
    });
  });

  group('Padded grid geometry (regression: everything is off by padding.top)', () {
    const padding = EdgeInsets.all(20);

    late DashboardController controller;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'i1', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'i2', x: 1, y: 0, w: 1, h: 1),
        ],
      )..setEditMode(true);
    });

    tearDown(() => controller.dispose());

    Widget buildPadded({EdgeInsets? insets}) => MaterialApp(
          home: Scaffold(
            body: Dashboard<String>(
              controller: controller,
              padding: insets ?? padding,
              gridStyle: const GridStyle(),
              itemBuilder: (context, item) =>
                  ColoredBox(color: Colors.blue, child: Text('T-${item.id}')),
            ),
          ),
        );

    testWidgets('background grid origin matches the real tile origin', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(buildPadded());
        await tester.pumpAndSettle();

        final boxOrigin = tester.getTopLeft(find.byType(Dashboard<String>));
        final realTileOrigin = tester.getTopLeft(find.text('T-i1')) - boxOrigin;

        expect(
          _backgroundOriginOf(tester, find.byType(DashboardGrid)),
          within(distance: 0.5, from: realTileOrigin),
          reason: 'grid lines must be anchored on cell (0,0), i.e. at the padding',
        );
      });
    });

    testWidgets('drag feedback stays anchored on the pointer', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(buildPadded());
        await tester.pumpAndSettle();

        final tileOrigin = tester.getTopLeft(find.text('T-i1'));
        const delta = Offset(0, 4); // engage the drag without crossing a cell

        final gesture = await tester.startGesture(tester.getCenter(find.text('T-i1')));
        await tester.pump();
        await gesture.moveBy(delta);
        await tester.pump();

        expect(
          tester.getTopLeft(find.byType(DashboardFeedbackItem)) - tileOrigin,
          within(distance: 0.5, from: delta),
          reason: 'the feedback must follow the pointer delta only; '
              'padding.top must not be counted twice',
        );

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('zero padding keeps the historical geometry (mirror case)', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(buildPadded(insets: EdgeInsets.zero));
        await tester.pumpAndSettle();

        final boxOrigin = tester.getTopLeft(find.byType(Dashboard<String>));
        expect(
          _backgroundOriginOf(tester, find.byType(DashboardGrid)),
          within(distance: 0.5, from: tester.getTopLeft(find.text('T-i1')) - boxOrigin),
        );
      });
    });

    testWidgets('scrollToItem(alignment: 0) is not offset by the padding', (tester) async {
      await runOnDesktop(() async {
        controller.addItems([
          for (var y = 1; y < 30; y++) LayoutItem(id: 'r$y', x: 0, y: y, w: 1, h: 1),
        ]);
        await tester.pumpWidget(buildPadded());
        await tester.pumpAndSettle();

        final viewportTop = tester.getTopLeft(find.byType(Dashboard<String>)).dy;
        await controller.scrollToItem('r20', duration: Duration.zero);
        await tester.pumpAndSettle();

        expect(
          tester.getTopLeft(find.text('T-r20')).dy,
          closeTo(viewportTop, 1),
          reason: 'alignment 0 puts the item top at the viewport top, '
              'not one padding above it',
        );
      });
    });
  });

  group('Nest highlight release', () {
    // `hoveredNestTargetId` is a single-holder slot with three writers
    // (the drop-target branch of _performUpdate, _armSameGridNest, and the
    // coordinator's session hover). Two exit paths used to skip its release.
    late DashboardController gridA;
    late DashboardController gridB;

    setUp(() {
      gridA = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a1', x: 0, y: 0, w: 1, h: 1),
          // A CLOSED host: declared nested, but no child grid is ever mounted.
          LayoutItem(id: 'closed', x: 2, y: 0, w: 1, h: 1, hasNestedGrid: true),
        ],
      )..setEditMode(true);
      gridB = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [LayoutItem(id: 'b1', x: 0, y: 0, w: 1, h: 1)],
      )..setEditMode(true);
    });

    tearDown(() {
      gridA.dispose();
      gridB.dispose();
    });

    Widget buildTwoGrids({DashboardItemDroppedOnHostCallback? onDroppedOnHost}) {
      return MaterialApp(
        home: Scaffold(
          body: DashboardNestedScope(
            onItemDroppedOnHost: onDroppedOnHost ?? (_, __, ___, ____) {},
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 250,
                  width: 400,
                  child: Dashboard<String>(
                    controller: gridA,
                    mainAxisSpacing: 0,
                    crossAxisSpacing: 0,
                    itemBuilder: (context, item) =>
                        ColoredBox(color: Colors.blue, child: Text('A-${item.id}')),
                  ),
                ),
                SizedBox(
                  height: 250,
                  width: 400,
                  child: Dashboard<String>(
                    controller: gridB,
                    mainAxisSpacing: 0,
                    crossAxisSpacing: 0,
                    itemBuilder: (context, item) =>
                        ColoredBox(color: Colors.green, child: Text('B-${item.id}')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('a drop-target hover armed before a cross-grid handoff is released at drag end',
        (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(buildTwoGrids());
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(tester.getCenter(find.text('A-a1')));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();

        // Arm the closed host.
        await gesture.moveTo(tester.getCenter(find.text('A-closed')));
        await tester.pump();
        expect(
          gridA.internal.hoveredNestTargetId.value,
          'closed',
          reason: 'sanity: the drop target must be armed',
        );

        // Leave the sliver: _maybeStartCrossGridSession returns true and
        // _performUpdate returns BEFORE the "left the target" cleanup.
        await gesture.moveTo(tester.getCenter(find.text('B-b1')));
        await tester.pump();

        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          gridA.internal.hoveredNestTargetId.value,
          isNull,
          reason: 'the ring must not survive the gesture that armed it',
        );
      });
    });

    testWidgets('leaving every grid with a target armed clears it and does not swallow the drop',
        (tester) async {
      await runOnDesktop(() async {
        var droppedOnHost = 0;
        await tester.pumpWidget(
          buildTwoGrids(onDroppedOnHost: (_, __, ___, ____) => droppedOnHost++),
        );
        await tester.pumpAndSettle();

        // Drag OUT of B, so the session's hovered grid is A and the closed host
        // belongs to the hovered grid rather than to the source.
        final gesture = await tester.startGesture(tester.getCenter(find.text('B-b1')));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();

        await gesture.moveTo(tester.getCenter(find.text('A-closed')));
        await tester.pump();
        expect(gridA.internal.hoveredNestTargetId.value, 'closed', reason: 'sanity');

        // Into the void, below both grids: `session.over` becomes null, and the
        // early return used to skip _clearDropTarget entirely.
        await gesture.moveTo(const Offset(200, 560));
        await tester.pump();

        expect(
          gridA.internal.hoveredNestTargetId.value,
          isNull,
          reason: 'the ring belongs to a grid the pointer has left',
        );

        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          droppedOnHost,
          0,
          reason: 'a release over no grid must cancel, not resolve as a drop '
              'onto a folder the pointer had already left',
        );
        expect(gridB.layout.value.any((i) => i.id == 'b1'), isTrue);
      });
    });
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
