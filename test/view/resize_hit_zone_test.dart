import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

import '../test_helpers.dart';

/// The pre-clamp hit test, kept verbatim as the reference for the
/// "large items are unchanged" gate.
ResizeHandle? legacyResizeHandle(Offset p, Size size, double side) {
  final isTop = p.dy <= side;
  final isBottom = p.dy >= size.height - side;
  final isLeft = p.dx <= side;
  final isRight = p.dx >= size.width - side;
  if (isTop && isLeft) return ResizeHandle.topLeft;
  if (isTop && isRight) return ResizeHandle.topRight;
  if (isBottom && isLeft) return ResizeHandle.bottomLeft;
  if (isBottom && isRight) return ResizeHandle.bottomRight;
  if (isTop && !isLeft && !isRight) return ResizeHandle.top;
  if (isBottom && !isLeft && !isRight) return ResizeHandle.bottom;
  if (isLeft && !isBottom && !isTop) return ResizeHandle.left;
  if (isRight && !isBottom && !isTop) return ResizeHandle.right;
  return null;
}

ResizeHandle? hit(
  double dx,
  double dy,
  Size size, {
  double side = 20,
  Set<ResizeHandle>? enabled,
}) =>
    calculateResizeHandle(
      localPosition: Offset(dx, dy),
      size: size,
      handleSide: side,
      isResizable: true,
      enabledHandles: enabled,
    );

void main() {
  group('calculateResizeHandle — size clamp', () {
    test('large item keeps the full zone, identical to the legacy hit test', () {
      // Every size where each axis is >= 3 x side, sampled every 0.5 px.
      for (final size in const [Size(60, 60), Size(200, 120), Size(61, 400)]) {
        for (var x = 0.0; x <= size.width; x += 0.5) {
          for (var y = 0.0; y <= size.height; y += 0.5) {
            expect(
              hit(x, y, size),
              legacyResizeHandle(Offset(x, y), size, 20),
              reason: 'size $size at ($x, $y)',
            );
          }
        }
      }
    });

    test('large item: zone boundaries sit exactly at handleSide', () {
      const size = Size(200, 200);
      expect(hit(20, 100, size), ResizeHandle.left);
      expect(hit(20.5, 100, size), isNull);
      expect(hit(180, 100, size), ResizeHandle.right);
      expect(hit(100, 20, size), ResizeHandle.top);
      expect(hit(100, 180, size), ResizeHandle.bottom);
      expect(hit(100, 100, size), isNull);
    });

    test('small item (< 2 x handleSide) keeps a draggable centre', () {
      // The issue's case: resizeHandleSide 36 on a ~60 px tile. The legacy
      // hit test returns a handle for every point of it.
      const size = Size(60, 60);
      expect(legacyResizeHandle(const Offset(30, 30), size, 36), isNotNull);

      expect(hit(30, 30, size, side: 36), isNull);
      // The zone shrinks to a third of the extent (20 px) on each axis.
      expect(hit(20, 30, size, side: 36), ResizeHandle.left);
      expect(hit(20.5, 30, size, side: 36), isNull);
      expect(hit(40, 30, size, side: 36), ResizeHandle.right);
      expect(hit(39.5, 30, size, side: 36), isNull);
      expect(hit(0, 0, size, side: 36), ResizeHandle.topLeft);
      expect(hit(60, 60, size, side: 36), ResizeHandle.bottomRight);
    });

    test('the clamp is per axis: a wide, short banner keeps its full side zones', () {
      const size = Size(300, 30);
      // Horizontal axis is long: full 36 px zones.
      expect(hit(36, 15, size, side: 36), ResizeHandle.left);
      expect(hit(264, 15, size, side: 36), ResizeHandle.right);
      // Vertical axis is short: max(30 / 3, 8) = 10 px zones.
      expect(hit(150, 10, size, side: 36), ResizeHandle.top);
      expect(hit(150, 20, size, side: 36), ResizeHandle.bottom);
      expect(hit(150, 15, size, side: 36), isNull);
    });

    test('very small item: the floor keeps it resizable', () {
      // 12 / 3 = 4 is below the floor: zones are 8 px, so the whole item is
      // a resize zone (resizability wins over dragging at this size).
      const size = Size(12, 12);
      for (var x = 0.0; x <= 12; x += 1) {
        for (var y = 0.0; y <= 12; y += 1) {
          expect(hit(x, y, size), isNotNull, reason: '($x, $y)');
        }
      }
      expect(hit(0, 0, size), ResizeHandle.topLeft);
      expect(hit(12, 12, size), ResizeHandle.bottomRight);

      // 21 / 3 = 7 -> floored at 8: a 5 px free centre remains.
      const justAbove = Size(21, 21);
      expect(hit(10.5, 10.5, justAbove), isNull);
      expect(hit(8, 10.5, justAbove), ResizeHandle.left);
      expect(hit(8.5, 10.5, justAbove), isNull);
    });

    test('the floor never widens a zone thinner than itself', () {
      expect(hit(4, 150, const Size(300, 300), side: 4), ResizeHandle.left);
      expect(hit(4.5, 150, const Size(300, 300), side: 4), isNull);
      // Small item, thin zone: still 4 px, not the 8 px floor.
      expect(hit(4, 5, const Size(9, 10), side: 4), ResizeHandle.left);
      expect(hit(4.5, 5, const Size(9, 10), side: 4), isNull);
    });

    test('a custom minHandleSide is honoured', () {
      final handle = calculateResizeHandle(
        localPosition: const Offset(10, 15),
        size: const Size(30, 30),
        handleSide: 20,
        isResizable: true,
        minHandleSide: 12,
      );
      expect(handle, ResizeHandle.left);
    });

    test('isResizable: false never returns a handle', () {
      expect(
        calculateResizeHandle(
          localPosition: Offset.zero,
          size: const Size(100, 100),
          handleSide: 20,
          isResizable: false,
        ),
        isNull,
      );
    });
  });

  group('calculateResizeHandle — enabled handles, per-axis rule', () {
    test('corner only, 60 px tile, side 36: a 30 px corner zone, the rest drags', () {
      const size = Size(60, 60);
      const only = {ResizeHandle.bottomRight};
      // One active side per axis: min(36, 60 / 2) = 30.
      expect(hit(30, 30, size, side: 36, enabled: only), ResizeHandle.bottomRight);
      expect(hit(60, 60, size, side: 36, enabled: only), ResizeHandle.bottomRight);
      expect(hit(29.5, 45, size, side: 36, enabled: only), isNull);
      expect(hit(45, 29.5, size, side: 36, enabled: only), isNull);
      // The right and bottom edges are in a zone, but their handles are off:
      // a drag, never a fallback onto the corner.
      expect(hit(59, 5, size, side: 36, enabled: only), isNull);
      expect(hit(5, 59, size, side: 36, enabled: only), isNull);
      expect(hit(0, 0, size, side: 36, enabled: only), isNull);
      expect(hit(30, 0, size, side: 36, enabled: only), isNull);
    });

    test('one active side keeps the full zone when the axis is long enough', () {
      const only = {ResizeHandle.left};
      expect(hit(20, 100, const Size(200, 200), enabled: only), ResizeHandle.left);
      expect(hit(20.5, 100, const Size(200, 200), enabled: only), isNull);
      // Half of a 30 px axis is 15: the other half still drags.
      expect(hit(15, 15, const Size(30, 30), enabled: only), ResizeHandle.left);
      expect(hit(15.5, 15, const Size(30, 30), enabled: only), isNull);
      // No floor on a single side: 12 / 2 = 6, not 8.
      expect(hit(6, 6, const Size(12, 12), enabled: only), ResizeHandle.left);
      expect(hit(6.5, 6, const Size(12, 12), enabled: only), isNull);
    });

    test('two opposite sides keep the third rule; an axis with no side has no zone', () {
      const size = Size(60, 60);
      const sides = {ResizeHandle.left, ResizeHandle.right};
      expect(hit(20, 30, size, side: 36, enabled: sides), ResizeHandle.left);
      expect(hit(20.5, 30, size, side: 36, enabled: sides), isNull);
      expect(hit(40, 30, size, side: 36, enabled: sides), ResizeHandle.right);
      // The vertical axis has no zone: the side edges run the full height.
      expect(hit(20, 0, size, side: 36, enabled: sides), ResizeHandle.left);
      expect(hit(40, 60, size, side: 36, enabled: sides), ResizeHandle.right);
      expect(hit(30, 0, size, side: 36, enabled: sides), isNull);
    });

    test('a disabled handle inside an active zone starts a drag', () {
      const size = Size(200, 200);
      const corners = {ResizeHandle.topLeft, ResizeHandle.bottomRight};
      expect(hit(0, 0, size, enabled: corners), ResizeHandle.topLeft);
      expect(hit(200, 200, size, enabled: corners), ResizeHandle.bottomRight);
      expect(hit(100, 0, size, enabled: corners), isNull);
      expect(hit(0, 100, size, enabled: corners), isNull);
      expect(hit(200, 0, size, enabled: corners), isNull);
    });

    test('an empty set disables resizing', () {
      for (final p in const [Offset.zero, Offset(100, 0), Offset(200, 200)]) {
        expect(hit(p.dx, p.dy, const Size(200, 200), enabled: const {}), isNull);
      }
    });

    test('all eight handles behave exactly like no set at all', () {
      for (final size in const [Size(200, 120), Size(45, 45), Size(300, 30), Size(12, 12)]) {
        for (var x = 0.0; x <= size.width; x += 1) {
          for (var y = 0.0; y <= size.height; y += 1) {
            expect(
              hit(x, y, size, enabled: ResizeZones.allHandles),
              hit(x, y, size),
              reason: '$size at ($x, $y)',
            );
          }
        }
      }
    });
  });

  group('ResizeZones', () {
    test('defaults: all handles, no side', () {
      const zones = ResizeZones();
      expect(zones.handles, ResizeZones.allHandles);
      expect(zones.handles, hasLength(8));
      expect(zones.side, isNull);
    });

    test('equality laws: order-independent, symmetric, hash-consistent', () {
      const ab = ResizeZones(handles: {ResizeHandle.top, ResizeHandle.left}, side: 12);
      const ba = ResizeZones(handles: {ResizeHandle.left, ResizeHandle.top}, side: 12);
      const otherSide = ResizeZones(handles: {ResizeHandle.top, ResizeHandle.left}, side: 13);
      const otherHandles = ResizeZones(handles: {ResizeHandle.top, ResizeHandle.right}, side: 12);
      const fewer = ResizeZones(handles: {ResizeHandle.top}, side: 12);

      expect(ab == ba && ba == ab, isTrue);
      expect(ab.hashCode, ba.hashCode);
      expect(ab, same(ab));
      for (final other in [otherSide, otherHandles, fewer]) {
        expect(ab == other || other == ab, isFalse, reason: '$other');
      }
      expect(ab.hashCode == otherSide.hashCode, isFalse);
      expect(ab.hashCode == otherHandles.hashCode, isFalse);
      expect(const ResizeZones() == ResizeZones(handles: ResizeZones.allHandles.toSet()), isTrue);
      expect(ab == Object(), isFalse);
    });
  });

  group('Dashboard — resize zones in a live grid', () {
    // 12 columns over 360 px of content -> 30 px slots, no spacing, so a
    // 2x2 tile is 60 px: the issue's "cannot be moved" case at side 36.
    // A non-zero padding guards against any origin mix-up in the hit path.
    const padding = EdgeInsets.all(20);

    Future<({DashboardController controller, List<String> events})> pumpGrid(
      WidgetTester tester, {
      required List<LayoutItem> layout,
      double resizeHandleSide = 36,
      ResizeZoneResolver? resolver,
      DashboardGuidance? guidance,
      double width = 400,
    }) async {
      final controller = DashboardController(initialSlotCount: 12, initialLayout: layout)
        ..setEditMode(true);
      addTearDown(controller.dispose);
      final events = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 600,
              child: Dashboard(
                controller: controller,
                padding: padding,
                mainAxisSpacing: 0,
                crossAxisSpacing: 0,
                resizeHandleSide: resizeHandleSide,
                resizeZoneResolver: resolver,
                guidance: guidance,
                onItemDragStart: (item) => events.add('drag:${item.id}'),
                onItemResizeStart: (item) => events.add('resize:${item.id}'),
                itemBuilder: (_, item) => SizedBox.expand(key: ValueKey('tile-${item.id}')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (controller: controller, events: events);
    }

    Future<void> press(WidgetTester tester, Offset at) async {
      final gesture = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await gesture.up();
      // Frees the mouse device so a later hover gesture can be added.
      await gesture.removePointer();
      await tester.pumpAndSettle();
    }

    Rect tileRect(WidgetTester tester, String id) =>
        tester.getRect(find.byKey(ValueKey('tile-$id')));

    testWidgets('a tile smaller than 2 x resizeHandleSide is dragged from its centre',
        (tester) async {
      await runOnDesktop(() async {
        final grid = await pumpGrid(
          tester,
          layout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2)],
        );
        final rect = tileRect(tester, 'a');
        expect(rect.width, closeTo(60, 0.01));
        expect(rect.topLeft, const Offset(20, 20));

        await press(tester, rect.center);
        // Its edges stay resizable.
        await press(tester, rect.centerLeft + const Offset(5, 0));

        expect(grid.events, ['drag:a', 'resize:a']);
      });
    });

    testWidgets('a large tile keeps the full resizeHandleSide zone', (tester) async {
      await runOnDesktop(() async {
        final grid = await pumpGrid(
          tester,
          layout: const [LayoutItem(id: 'big', x: 0, y: 0, w: 6, h: 6)],
        );
        final rect = tileRect(tester, 'big');

        await press(tester, rect.centerLeft + const Offset(35, 0));
        await press(tester, rect.centerLeft + const Offset(37, 0));

        expect(grid.events, ['resize:big', 'drag:big']);
      });
    });

    testWidgets('resizeZoneResolver replaces resizeHandleSide per item', (tester) async {
      await runOnDesktop(() async {
        final calls = <(String, Size)>[];
        final grid = await pumpGrid(
          tester,
          resizeHandleSide: 20,
          layout: const [
            LayoutItem(id: 'thin', x: 0, y: 0, w: 6, h: 6),
            LayoutItem(id: 'wide', x: 6, y: 0, w: 6, h: 6),
          ],
          resolver: (item, size) {
            calls.add((item.id, size));
            return ResizeZones(side: item.id == 'thin' ? 4 : 40);
          },
        );
        final thin = tileRect(tester, 'thin');
        final wide = tileRect(tester, 'wide');

        // The handles layer also resolves the side; the pointer-down call is
        // the first one after the press, with the tile's own size.
        calls.clear();
        // 10 px from the edge: inside the default 20 px zone, outside 4 px.
        await press(tester, thin.centerLeft + const Offset(10, 0));
        expect(calls.first, ('thin', thin.size));
        calls.clear();
        // 30 px from the edge: outside the default zone, inside 40 px.
        await press(tester, wide.centerLeft + const Offset(30, 0));
        expect(calls.first, ('wide', wide.size));

        expect(grid.events, ['drag:thin', 'resize:wide']);
      });
    });

    testWidgets('resizeZoneResolver chooses the handles: only those react and are drawn',
        (tester) async {
      await runOnDesktop(() async {
        final grid = await pumpGrid(
          tester,
          layout: const [
            LayoutItem(id: 'small', x: 0, y: 0, w: 2, h: 2),
            LayoutItem(id: 'big', x: 4, y: 0, w: 6, h: 6),
          ],
          resolver: (item, size) => size.shortestSide < 100
              ? const ResizeZones(handles: {ResizeHandle.bottomRight})
              : null,
        );
        Finder handlesOf(String id) => find.descendant(
              of: find
                  .ancestor(of: find.byKey(ValueKey('tile-$id')), matching: find.byType(Stack))
                  .first,
              matching: find.byType(ResizeHandleWidget),
            );
        expect(handlesOf('small'), findsOneWidget);
        expect(
          tester.widget<ResizeHandleWidget>(handlesOf('small')).handle,
          ResizeHandle.bottomRight,
        );
        expect(handlesOf('big'), findsNWidgets(8));

        final small = tileRect(tester, 'small');
        await press(tester, small.topLeft + const Offset(3, 3));
        // Right edge, above the 30 px corner zone: that handle is off.
        await press(tester, small.centerRight - const Offset(3, 2));
        await press(tester, small.bottomRight - const Offset(25, 25));

        expect(grid.events, ['drag:small', 'drag:small', 'resize:small']);
      });
    });

    testWidgets('a resolver returning null is identical to no resolver', (tester) async {
      await runOnDesktop(() async {
        const layout = [LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2)];
        final probes = [
          for (var d = 0.0; d <= 60; d += 4) Offset(d, 30),
          const Offset(2, 2),
          const Offset(58, 58),
        ];

        Future<(List<String>, List<Rect>)> run({ResizeZoneResolver? resolver}) async {
          final grid = await pumpGrid(tester, layout: layout, resolver: resolver);
          final tile = tileRect(tester, 'a');
          final drawn = [
            for (final e in find.byType(ResizeHandleWidget).evaluate())
              tester.getRect(find.byWidget(e.widget)),
          ];
          for (final p in probes) {
            await press(tester, tile.topLeft + p);
          }
          return (grid.events, drawn);
        }

        final without = await run();
        final withNull = await run(resolver: (item, size) => null);
        final withDefault = await run(resolver: (item, size) => const ResizeZones());
        expect(withNull.$1, without.$1);
        expect(withNull.$2, without.$2);
        expect(withDefault.$1, without.$1);
        expect(withDefault.$2, without.$2);
        expect(without.$1, contains('drag:a'));
        expect(without.$1, contains('resize:a'));
      });
    });

    testWidgets(
        'a selected tile measures its OUTER size for the resolver, the drawn '
        'handles, the press and the hover', (tester) async {
      await runOnDesktop(() async {
        // 465 px of content / 12 -> 38.75 px slots: a 2x2 tile is 77.5 px,
        // just above the resolver's 72 px threshold. The default focus border
        // (4 px per side) leaves a 69.5 px inner box, just below it.
        const guidance = DashboardGuidance.byDefault;
        final sizes = <Size>[];
        final grid = await pumpGrid(
          tester,
          width: 505,
          resizeHandleSide: 20,
          guidance: guidance,
          layout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2)],
          resolver: (item, size) {
            sizes.add(size);
            return size.shortestSide < 72
                ? const ResizeZones(handles: {ResizeHandle.bottomRight})
                : null;
          },
        );
        final outer = tileRect(tester, 'a');
        expect(outer.size, const Size(77.5, 77.5));

        // A press selects and focuses the tile: the 4 px border appears.
        await press(tester, outer.center);
        expect(tileRect(tester, 'a').size, const Size(69.5, 69.5));

        // One reference size for every caller: the outer tile.
        expect(sizes, isNotEmpty);
        expect(sizes.toSet(), {outer.size});

        // null for 77.5 px -> all eight handles, each inside its own zone
        // measured from the OUTER edges (what the overlay's press uses).
        final drawn = {
          for (final e in find.byType(ResizeHandleWidget).evaluate())
            (e.widget as ResizeHandleWidget).handle: tester.getRect(find.byWidget(e.widget)),
        };
        expect(drawn.keys.toSet(), ResizeZones.allHandles);
        drawn.forEach((handle, rect) {
          final r = rect.deflate(0.5);
          for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
            expect(
              calculateResizeHandle(
                localPosition: p - outer.topLeft,
                size: outer.size,
                handleSide: 20,
                isResizable: true,
              ),
              handle,
              reason: '$handle at ${p - outer.topLeft}',
            );
          }
        });

        // A real press on each drawn handle resizes.
        grid.events.clear();
        for (final rect in drawn.values) {
          await press(tester, rect.center);
        }
        expect(grid.events, List.filled(8, 'resize:a'));

        // The hover reads the same zones: 10 px from the outer left edge is the
        // left zone of a 77.5 px tile (an inner 69.5 px reading would keep the
        // bottom-right corner only and announce a move).
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await tester.pump();
        await mouse.moveTo(outer.topLeft + const Offset(10, 38.75));
        await tester.pump();
        expect(find.text(guidance.resizeX.message), findsOneWidget);
        expect(sizes.toSet(), {outer.size});
      });
    });

    testWidgets('guidance hover follows the clamp and the resolver', (tester) async {
      await runOnDesktop(() async {
        const guidance = DashboardGuidance.byDefault;
        await pumpGrid(
          tester,
          guidance: guidance,
          resolver: (item, size) => switch (item.id) {
            'r' => const ResizeZones(side: 4),
            'h' => const ResizeZones(handles: {ResizeHandle.bottomRight}),
            _ => null,
          },
          layout: const [
            LayoutItem(id: 'small', x: 0, y: 0, w: 2, h: 2),
            LayoutItem(id: 'r', x: 4, y: 0, w: 6, h: 6),
            LayoutItem(id: 'h', x: 0, y: 6, w: 6, h: 6),
          ],
        );

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);

        Future<void> expectHover(Offset at, String message) async {
          await mouse.moveTo(Offset.zero);
          await tester.pump();
          await mouse.moveTo(at);
          await tester.pump();
          expect(find.text(message), findsOneWidget, reason: '$at');
        }

        final small = tileRect(tester, 'small');
        await expectHover(small.center, guidance.move.message);
        await expectHover(small.centerLeft + const Offset(5, 0), guidance.resizeX.message);

        final r = tileRect(tester, 'r');
        await expectHover(r.centerLeft + const Offset(10, 0), guidance.move.message);
        await expectHover(r.centerLeft + const Offset(3, 0), guidance.resizeX.message);

        final h = tileRect(tester, 'h');
        await expectHover(h.centerLeft + const Offset(5, 0), guidance.move.message);
        await expectHover(h.bottomRight - const Offset(3, 3), guidance.resizeXY.message);
      });
    });

    group('drawn handles never promise a resize the press does not start', () {
      Map<ResizeHandle, double> all(double size) => {
            for (final handle in ResizeHandle.values) handle: size,
          };

      // Every point of a drawn handle (cursor region included) must classify
      // as that handle, otherwise the cursor says "resize" where a press drags.
      Future<void> expectHandlesInsideZones(
        WidgetTester tester, {
        required String id,
        required double side,
        required Map<ResizeHandle, double> expectedSizes,
        Set<ResizeHandle>? enabled,
      }) async {
        final tile = tileRect(tester, id);
        final handles = find.descendant(
          of: find
              .ancestor(of: find.byKey(ValueKey('tile-$id')), matching: find.byType(Stack))
              .first,
          matching: find.byType(ResizeHandleWidget),
        );
        expect(
          handles.evaluate().map((e) => (e.widget as ResizeHandleWidget).handle).toSet(),
          expectedSizes.keys.toSet(),
        );
        for (final element in handles.evaluate()) {
          final widget = element.widget as ResizeHandleWidget;
          final rect = tester.getRect(find.byWidget(widget)).deflate(0.5);
          expect(
            rect.width + 1,
            closeTo(expectedSizes[widget.handle]!, 0.01),
            reason: '${widget.handle}',
          );
          for (final p in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
            expect(
              calculateResizeHandle(
                localPosition: p - tile.topLeft,
                size: tile.size,
                handleSide: side,
                isResizable: true,
                enabledHandles: enabled,
              ),
              widget.handle,
              reason: '${widget.handle} at ${p - tile.topLeft} on a ${tile.size} tile',
            );
          }
        }
      }

      testWidgets('clamped tile (45 px, side 20): handles shrink to the 15 px zone',
          (tester) async {
        // 270 px of content / 12 -> 22.5 px slots: a 2x2 tile is 45 px.
        await pumpGrid(
          tester,
          width: 310,
          resizeHandleSide: 20,
          layout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2)],
        );
        expect(tileRect(tester, 'a').width, closeTo(45, 0.01));
        await expectHandlesInsideZones(tester, id: 'a', side: 20, expectedSizes: all(15));
      });

      testWidgets('large tile keeps the 20 px handles', (tester) async {
        await pumpGrid(
          tester,
          resizeHandleSide: 36,
          layout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 6, h: 6)],
        );
        await expectHandlesInsideZones(tester, id: 'a', side: 36, expectedSizes: all(20));
      });

      testWidgets('the resolver drives the drawn size too', (tester) async {
        await pumpGrid(
          tester,
          resolver: (item, size) => const ResizeZones(side: 10),
          layout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 6, h: 6)],
        );
        await expectHandlesInsideZones(tester, id: 'a', side: 10, expectedSizes: all(10));
      });

      testWidgets('only the active handles are drawn, inside their own zone', (tester) async {
        // 60 px tile, side 36. Corner only: 30 px zones, the handle capped at 20.
        // Top + left + topLeft: one side per axis -> 30 px zones; the edge
        // handles sit on the 30 px left over beyond the corner zone.
        const corner = {ResizeHandle.bottomRight};
        const topLeftGroup = {ResizeHandle.top, ResizeHandle.left, ResizeHandle.topLeft};
        // Top alone: no horizontal zone, so the top edge spans the full width.
        const topOnly = {ResizeHandle.top};
        await pumpGrid(
          tester,
          layout: const [
            LayoutItem(id: 'c', x: 0, y: 0, w: 2, h: 2),
            LayoutItem(id: 'g', x: 3, y: 0, w: 2, h: 2),
            LayoutItem(id: 't', x: 6, y: 0, w: 2, h: 2),
          ],
          resolver: (item, size) => ResizeZones(
            handles: switch (item.id) {
              'c' => corner,
              'g' => topLeftGroup,
              _ => topOnly,
            },
          ),
        );
        await expectHandlesInsideZones(
          tester,
          id: 'c',
          side: 36,
          enabled: corner,
          expectedSizes: {ResizeHandle.bottomRight: 20},
        );
        await expectHandlesInsideZones(
          tester,
          id: 'g',
          side: 36,
          enabled: topLeftGroup,
          expectedSizes: {
            ResizeHandle.topLeft: 20,
            ResizeHandle.top: 20,
            ResizeHandle.left: 20,
          },
        );
        await expectHandlesInsideZones(
          tester,
          id: 't',
          side: 36,
          enabled: topOnly,
          expectedSizes: {ResizeHandle.top: 20},
        );
      });

      testWidgets('an empty handle set draws nothing and never resizes', (tester) async {
        await runOnDesktop(() async {
          final grid = await pumpGrid(
            tester,
            layout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 6, h: 6)],
            resolver: (item, size) => const ResizeZones(handles: {}),
          );
          expect(find.byType(ResizeHandleWidget), findsNothing);
          final tile = tileRect(tester, 'a');
          await press(tester, tile.topLeft + const Offset(1, 1));
          await press(tester, tile.centerRight - const Offset(1, 0));
          expect(grid.events, ['drag:a', 'drag:a']);
        });
      });
    });

    testWidgets('NestedDashboard forwards resizeZoneResolver', (tester) async {
      final parent = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [LayoutItem(id: 'host', x: 0, y: 0, w: 2, h: 2)],
      );
      final child = DashboardController(initialSlotCount: 4);
      addTearDown(parent.dispose);
      addTearDown(child.dispose);
      ResizeZones? resolver(LayoutItem item, Size size) => const ResizeZones(side: 12);

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardNestedScope(
            child: DashboardControllerProvider(
              controller: parent,
              child: SizedBox(
                width: 400,
                height: 300,
                child: NestedDashboard(
                  controller: child,
                  parentItemId: 'host',
                  resizeZoneResolver: resolver,
                  itemBuilder: (context, item) => Text(item.id),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inner = tester.widget<Dashboard>(find.byWidgetPredicate((w) => w is Dashboard));
      expect(inner.resizeZoneResolver, resolver);
    });
  });
}
