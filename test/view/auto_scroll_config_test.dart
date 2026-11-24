import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

/// Edge auto-scroll: configurable zone and speed, driven by frames (a Ticker)
/// rather than a 16 ms Timer, so the travel is speed x elapsed time and every
/// frame moves, whatever the refresh rate.
void main() {
  late DashboardController controller;
  late ScrollController scroll;

  setUp(() {
    controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: '1', x: 0, y: 0, w: 4, h: 1),
        // Keeps the content far taller than the 400 px viewport.
        LayoutItem(id: 'anchor', x: 0, y: 30, w: 1, h: 1, isStatic: true),
      ],
    )..setEditMode(true);
    scroll = ScrollController();
  });

  tearDown(() {
    controller.dispose();
    scroll.dispose();
  });

  /// Mounts a 400 x 400 grid (padding 20), drags tile `1` with a mouse and
  /// parks the pointer at [edgeY]. Returns the live gesture.
  Future<TestGesture> dragTo(WidgetTester tester, double edgeY) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Dashboard(
          controller: controller,
          scrollController: scroll,
          padding: const EdgeInsets.all(20),
          itemBuilder: (context, item) => Text(item.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('1')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    await gesture.moveTo(Offset(200, edgeY));
    await tester.pump();
    return gesture;
  }

  Future<void> run(Future<void> Function() body) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  }

  testWidgets('every frame scrolls at 120 Hz (no skipped frames)', (tester) async {
    await run(() async {
      final gesture = await dragTo(tester, 390);
      var last = scroll.offset;
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(microseconds: 8333));
        expect(scroll.offset, greaterThan(last), reason: 'frame $frame did not scroll');
        last = scroll.offset;
      }
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  for (final frame in const [Duration(microseconds: 8333), Duration(milliseconds: 16)]) {
    testWidgets('travel is speed x time at a ${frame.inMicroseconds} us frame', (tester) async {
      await run(() async {
        // Pointer 40 px into a 50 px zone: 0.8 x 500 = 400 px/s.
        controller.autoScroll = const AutoScrollConfig(maxSpeed: 500);
        final gesture = await dragTo(tester, 390);
        final start = scroll.offset;
        final frames =
            (const Duration(milliseconds: 500).inMicroseconds / frame.inMicroseconds).round();
        for (var i = 0; i < frames; i++) {
          await tester.pump(frame);
        }
        final seconds = frames * frame.inMicroseconds / 1e6;
        // One frame of tolerance: the ticker's first tick has no elapsed time.
        expect(scroll.offset - start, closeTo(400 * seconds, 400 * frame.inMicroseconds / 1e6 + 1));
        await gesture.up();
        await tester.pumpAndSettle();
      });
    });
  }

  testWidgets('edgeExtent sets the depth of the hot zone', (tester) async {
    await run(() async {
      // 30 px from the bottom edge: outside a 20 px zone.
      controller.autoScroll = const AutoScrollConfig(edgeExtent: 20);
      final gesture = await dragTo(tester, 370);
      final start = scroll.offset;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scroll.offset, start);

      // Same position with the default 50 px zone scrolls.
      controller.autoScroll = AutoScrollConfig.byDefault;
      await gesture.moveBy(const Offset(0, 1));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scroll.offset, greaterThan(start));
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  testWidgets('AutoScrollConfig.off never scrolls', (tester) async {
    await run(() async {
      controller.autoScroll = AutoScrollConfig.off;
      final gesture = await dragTo(tester, 399);
      final start = scroll.offset;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scroll.offset, start);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  testWidgets('the ticker stops on drop: the scroll settles and stays put', (tester) async {
    await run(() async {
      final gesture = await dragTo(tester, 390);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      // pumpAndSettle would time out with a ticker still scheduling frames.
      await tester.pumpAndSettle();
      final settled = scroll.offset;
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.offset, settled);
    });
  });

  test('AutoScrollConfig equality laws and copyWith', () {
    const a = AutoScrollConfig(edgeExtent: 40, maxSpeed: 800);
    const b = AutoScrollConfig(edgeExtent: 40, maxSpeed: 800);
    expect(a, b);
    expect(b, a);
    expect(a.hashCode, b.hashCode);
    expect(a == a.copyWith(enabled: false), isFalse);
    expect(a.copyWith(), a);
    expect(a.copyWith(maxSpeed: 1).maxSpeed, 1);
    expect(AutoScrollConfig.off.enabled, isFalse);
    // The defaults reproduce the historical 15 px every 16 ms, 50 px zone.
    const d = AutoScrollConfig.byDefault;
    expect((d.enabled, d.edgeExtent, d.maxSpeed), (true, 50.0, 937.5));
  });
}
