import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/view/dashboard_feedback_widget.dart';
import 'package:sliver_dashboard/src/view/dashboard_item_widget.dart';

import '../test_helpers.dart' show runOnDesktop;

/// Default test window is 800x600. With `slotCount: 8`, no spacing and a 1:1
/// aspect ratio, a slot is exactly 100x100 px and item 'a' occupies the
/// rectangle (0, 0, 200, 200) — so a pixel delta reads directly as a fraction
/// of a slot with no arithmetic in the assertions.
const _layout = [
  LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2, minW: 1, minH: 1),
  LayoutItem(id: 'b', x: 4, y: 0, w: 2, h: 2, minW: 1, minH: 1),
];

/// A point inside the bottom-right resize handle of item 'a'
/// (handle side is 20 px, tile is 200x200 at the origin).
const _handleA = Offset(195, 195);

void main() {
  late DashboardController controller;

  setUp(() {
    controller = DashboardController(
      initialSlotCount: 8,
      initialLayout: _layout,
    )..setEditMode(true);
  });

  tearDown(() => controller.dispose());

  Widget host({
    bool fluidResize = true,
    Duration settle = const Duration(milliseconds: 120),
    EdgeInsets padding = EdgeInsets.zero,
    DragStartGesture gesture = DragStartGesture.tap,
    DashboardItemLayoutBuilder? itemLayoutBuilder,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Dashboard(
          controller: controller,
          slotAspectRatio: 1,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
          padding: padding,
          fluidResize: fluidResize,
          resizeSettleDuration: settle,
          dragStartGesture: gesture,
          itemBuilder: itemLayoutBuilder == null
              ? (context, item) => ColoredBox(
                    color: Colors.blue,
                    child: Text('Item ${item.id}'),
                  )
              : null,
          itemLayoutBuilder: itemLayoutBuilder,
        ),
      ),
    );
  }

  /// The tile as laid out in the grid (never the overlay copy).
  Finder gridItem(String id) => find.byWidgetPredicate(
        (w) => w is DashboardItem && !w.isFeedback && w.item.id == id,
      );

  double opacityOf(WidgetTester tester, String id) {
    final finder = find.descendant(of: gridItem(id), matching: find.byType(Opacity));
    return tester.widget<Opacity>(finder.first).opacity;
  }

  GridBackgroundPainter painterOf(WidgetTester tester) {
    return tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<GridBackgroundPainter>()
        .first;
  }

  group('fluid resize — live phase', () {
    testWidgets('the tile leaves the grid and the overlay draws it at raw pixel size',
        (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();

        expect(opacityOf(tester, 'a'), 1.0);
        expect(find.byType(DashboardFeedbackItem), findsNothing);

        final gesture = await tester.startGesture(_handleA, kind: PointerDeviceKind.mouse);
        await tester.pump();

        // Armed on pointer-down, before any movement: the ghost sits exactly
        // on the tile it replaced, so this frame is a visual no-op.
        expect(controller.internal.resizeGhostId.value, 'a');
        expect(controller.internal.resizeGhostRect.value, isNull);
        expect(opacityOf(tester, 'a'), 0.0);
        expect(
          tester.getRect(find.byType(DashboardFeedbackItem)),
          const Rect.fromLTWH(0, 0, 200, 200),
        );

        // Sub-slot movement: the ghost follows in pixels, the layout does not.
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();

        expect(
          tester.getRect(find.byType(DashboardFeedbackItem)),
          rectMoreOrLessEquals(const Rect.fromLTWH(0, 0, 230, 200)),
        );
        expect(controller.layout.value.firstWhere((i) => i.id == 'a').w, 2);

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('the ghost is a feedback item, so it never steals focus or duplicates the tile',
        (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(_handleA, kind: PointerDeviceKind.mouse);
        await tester.pump();
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();

        final ghost = tester.widget<DashboardFeedbackItem>(find.byType(DashboardFeedbackItem));
        expect(ghost.isResizeGhost, isTrue);
        expect(ghost.isSettling, isFalse);
        expect(gridItem('a'), findsOneWidget);
        expect(find.text('Item a'), findsNWidgets(2)); // grid (hidden) + ghost

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('the snap-target fill is painted from the very first event', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();

        expect(painterOf(tester).draggedItems, isEmpty);

        final gesture = await tester.startGesture(_handleA, kind: PointerDeviceKind.mouse);
        await tester.pump();

        // No cell has been crossed yet, so the layout has not changed. Before
        // DashboardGrid watched `isResizing`, nothing rebuilt the background
        // and the placeholder stayed unpainted for the whole first cell.
        expect(painterOf(tester).draggedItems.map((i) => i.id), ['a']);

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('padding shifts the ghost without changing its content-space rect', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(host(padding: const EdgeInsets.all(20)));
        await tester.pumpAndSettle();

        // slotWidth = (800 - 40) / 8 = 95; tile 'a' is (20, 20, 190, 190).
        final gesture = await tester.startGesture(
          const Offset(205, 205),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();

        final rect = controller.internal.resizeGhostRect.value!;
        expect(rect.left, closeTo(0, 0.001), reason: 'content space excludes padding');
        expect(rect.width, closeTo(220, 0.001)); // 2 * 95 + 30

        expect(
          tester.getRect(find.byType(DashboardFeedbackItem)),
          const Rect.fromLTWH(20, 20, 220, 190),
        );

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('itemLayoutBuilder receives the live pixel size', (tester) async {
      await runOnDesktop(() async {
        final widths = <double>[];
        await tester.pumpWidget(
          host(
            itemLayoutBuilder: (context, item, width, height, slots) {
              if (item.id == 'a') widths.add(width);
              return ColoredBox(color: Colors.blue, child: Text('Item ${item.id}'));
            },
          ),
        );
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(_handleA, kind: PointerDeviceKind.mouse);
        await tester.pump();
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();

        // This is the documented contract of itemLayoutBuilder, and the reason
        // the feature is opt-in: sub-slot widths reach the builder.
        expect(widths, contains(closeTo(230, 0.001)));

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });
  });

  group('fluid resize — settle', () {
    testWidgets('the ghost animates into the snapped slot and clears itself', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(_handleA, kind: PointerDeviceKind.mouse);
        await tester.pump();
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();

        await gesture.up();
        await tester.pump(); // commit + settle armed, tween at t = 0

        expect(controller.internal.isResizing.value, isFalse);
        expect(controller.internal.resizeGhostId.value, 'a');
        expect(
          tester.widget<DashboardFeedbackItem>(find.byType(DashboardFeedbackItem)).isSettling,
          isTrue,
        );
        expect(tester.getRect(find.byType(DashboardFeedbackItem)).width, closeTo(230, 0.5));
        expect(opacityOf(tester, 'a'), 0.0, reason: 'the tile stays hidden until it lands');

        await tester.pump(const Duration(milliseconds: 60));
        final mid = tester.getRect(find.byType(DashboardFeedbackItem)).width;
        expect(mid, lessThan(230));
        expect(mid, greaterThan(200));

        await tester.pumpAndSettle();

        expect(find.byType(DashboardFeedbackItem), findsNothing);
        expect(controller.internal.resizeGhostId.value, isNull);
        expect(controller.internal.resizeGhostRect.value, isNull);
        expect(opacityOf(tester, 'a'), 1.0);
        expect(tester.getRect(gridItem('a')), const Rect.fromLTWH(0, 0, 200, 200));
      });
    });

    testWidgets('no settle is armed when the raw rect already sits on its slot', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(_handleA, kind: PointerDeviceKind.mouse);
        await tester.pump();
        // Exactly one slot: raw and snapped coincide on release.
        await gesture.moveBy(const Offset(100, 0));
        await tester.pump();
        expect(controller.layout.value.firstWhere((i) => i.id == 'a').w, 3);

        await gesture.up();
        await tester.pump();

        // Arming a tween with equal endpoints would never report an end, and
        // the tile would stay hidden forever.
        expect(controller.internal.resizeGhostId.value, isNull);
        expect(find.byType(DashboardFeedbackItem), findsNothing);
        expect(opacityOf(tester, 'a'), 1.0);
      });
    });

    testWidgets('a press that never moves leaves no ghost behind', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(_handleA, kind: PointerDeviceKind.mouse);
        await tester.pump();
        expect(controller.internal.resizeGhostId.value, 'a');

        await gesture.up();
        await tester.pump();

        expect(controller.internal.resizeGhostId.value, isNull);
        expect(opacityOf(tester, 'a'), 1.0);
      });
    });

    testWidgets('resizeSettleDuration: zero releases on the same frame', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(host(settle: Duration.zero));
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(_handleA, kind: PointerDeviceKind.mouse);
        await tester.pump();
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();

        await gesture.up();
        await tester.pump();

        expect(controller.internal.resizeGhostId.value, isNull);
        expect(find.byType(DashboardFeedbackItem), findsNothing);
        expect(opacityOf(tester, 'a'), 1.0);
      });
    });

    testWidgets('a new gesture supersedes a settling ghost', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();

        final resize = await tester.startGesture(_handleA, kind: PointerDeviceKind.mouse);
        await tester.pump();
        await resize.moveBy(const Offset(30, 0));
        await tester.pump();
        await resize.up();
        await tester.pump();

        expect(controller.internal.resizeGhostId.value, 'a');

        // Press item 'b' well before the settle would have completed.
        final drag = await tester.startGesture(
          tester.getCenter(gridItem('b')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();

        expect(
          controller.internal.resizeGhostId.value,
          isNull,
          reason: 'a stale ghost would keep tile a hidden under the new gesture',
        );
        expect(opacityOf(tester, 'a'), 1.0);

        await drag.up();
        await tester.pumpAndSettle();
      });
    });
  });

  group('fluid resize — off', () {
    testWidgets('nothing is lifted and the tile resizes in place', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(host(fluidResize: false));
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(_handleA, kind: PointerDeviceKind.mouse);
        await tester.pump();
        await gesture.moveBy(const Offset(130, 0));
        await tester.pump();

        expect(controller.internal.resizeGhostId.value, isNull);
        expect(find.byType(DashboardFeedbackItem), findsNothing);
        expect(opacityOf(tester, 'a'), 1.0);
        // Quantised, as before: 130 px rounds to one whole slot.
        expect(tester.getRect(gridItem('a')), const Rect.fromLTWH(0, 0, 300, 200));

        await gesture.up();
        await tester.pumpAndSettle();

        expect(controller.layout.value.firstWhere((i) => i.id == 'a').w, 3);
      });
    });
  });

  group('fluid resize — mobile tap path', () {
    testWidgets('tapping a handle with DragStartGesture.tap latches nothing', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // addTearDown(() => debugDefaultTargetPlatformOverride = null);

        await tester.pumpWidget(host());
        await tester.pumpAndSettle();

        // Press and release without moving: this lands in _handleMobileTap,
        // which bypasses _onPointerUp entirely.
        final gesture = await tester.startGesture(_handleA);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(controller.internal.isResizing.value, isFalse);
        expect(controller.internal.resizeGhostId.value, isNull);
        expect(opacityOf(tester, 'a'), 1.0);
        expect(controller.layout.value.firstWhere((i) => i.id == 'a').w, 2);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  testWidgets('Dashboard updates controller.fluidResize on didUpdateWidget', (tester) async {
    final controller = DashboardController();
    expect(controller.fluidResize.value, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Dashboard(
            controller: controller,
            fluidResize: false,
            itemBuilder: (context, item) => const SizedBox(),
          ),
        ),
      ),
    );
    expect(controller.fluidResize.value, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Dashboard(
            controller: controller,
            fluidResize: true,
            itemBuilder: (context, item) => const SizedBox(),
          ),
        ),
      ),
    );

    expect(controller.fluidResize.value, isTrue);
  });
}
