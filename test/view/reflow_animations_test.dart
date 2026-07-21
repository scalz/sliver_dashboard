import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

/// Paint-phase reflow animations.
///
/// Contract under test:
///  * layout stays instantaneous and deterministic (the controller's layout
///    beacon holds final coordinates immediately);
///  * only the painted offset interpolates, over `reflowAnimationDuration`;
///  * transitions are seeded only by genuine layout mutations — never by
///    scroll passes or slot-metric changes (those snap);
///  * everything is inert when `enableReflowAnimations` is false (default).
void main() {
  Widget host(
    DashboardController controller,
    ScrollController scrollController, {
    bool animations = true,
    Duration duration = const Duration(milliseconds: 150),
  }) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverDashboard(
              controller: controller,
              animateReflow: animations,
              reflowDuration: duration,
              itemBuilder: (context, item) => Text(item.id),
            ),
          ],
        ),
      ),
    );
  }

  RenderSliverDashboard sliverOf(WidgetTester tester) => tester.renderObject<RenderSliverDashboard>(
        find.byType(SliverDashboardLayout),
      );

  testWidgets('a moved tile slides: painted offset is interpolated mid-flight', (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
      ],
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(host(controller, scrollController));
    await tester.pumpAndSettle();

    final sliver = sliverOf(tester);
    expect(sliver.debugActiveReflowTransitionCount, 0);

    // Mutate the layout: 'b' jumps from (1,0) to (3,0). The single-item
    // mutation entry point keeps snapshots coherent.
    controller.updateItem('b', (i) => i.copyWith(x: 3), recompact: false);
    // Two zero-duration pumps: state_beacon batches effect flushes, so the
    // rebuild triggered by `.watch(context)` can land one frame after the
    // mutation. The second pump is a no-op if the first already relaid out
    // (the items instance is unchanged, so no double seeding can occur).
    await tester.pump();
    await tester.pump(); // relayout: seeds the transition, starts the ticker
    expect(sliver.debugActiveReflowTransitionCount, 1);

    // Baseline tick: a Ticker's first tick always reports elapsed == 0
    // (same one-frame start latency as AnimationController). Time is
    // credited from the SECOND tick onward.
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(milliseconds: 75)); // mid-flight: t=75ms
    final mid = sliver.debugReflowPaintOffsetFor('b');
    expect(mid, isNotNull);
    // Slot width in the 800 px test viewport, 4 columns, 8 px spacing:
    // (800 - 3*8) / 4 = 194; stride = 202. From x=202 to x=606.
    expect(mid!.dx, greaterThan(202));
    expect(mid.dx, lessThan(606));

    // The logical layout is already final (determinism invariant).
    expect(controller.layout.value.firstWhere((i) => i.id == 'b').x, 3);

    await tester.pump(const Duration(milliseconds: 200));
    expect(sliver.debugActiveReflowTransitionCount, 0);
  });

  testWidgets('disabled by default: no transitions are ever seeded', (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
      ],
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(host(controller, scrollController, animations: false));
    await tester.pumpAndSettle();

    controller.updateItem('b', (i) => i.copyWith(x: 3), recompact: false);
    await tester.pump();
    await tester.pump(); // beacon flush may land one frame later
    expect(sliverOf(tester).debugActiveReflowTransitionCount, 0);
  });

  testWidgets('slot-metric change snaps: no mass transition on resize', (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
      ],
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(host(controller, scrollController));
    await tester.pumpAndSettle();

    // A layout mutation whose pass coincides with a metric change must snap:
    // slot count 4 -> 2 changes every slot width.
    controller.setSlotCount(2);
    await tester.pumpAndSettle();
    expect(sliverOf(tester).debugActiveReflowTransitionCount, 0);
  });

  testWidgets('toggling animations off mid-flight clears the transitions', (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
      ],
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(host(controller, scrollController));
    await tester.pumpAndSettle();

    controller.updateItem('b', (i) => i.copyWith(x: 3), recompact: false);
    await tester.pump();
    await tester.pump();
    final sliver = sliverOf(tester);
    expect(sliver.debugActiveReflowTransitionCount, 1);

    // Rebuild with the feature disabled while the slide is in flight:
    // the setter must clear the transitions and stop the ticker.
    await tester.pumpWidget(host(controller, scrollController, animations: false));
    await tester.pump();
    expect(sliverOf(tester).debugActiveReflowTransitionCount, 0);
  });

  testWidgets('retargeting mid-flight mutates the transition in place', (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
      ],
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(host(controller, scrollController));
    await tester.pumpAndSettle();

    controller.updateItem('b', (i) => i.copyWith(x: 3), recompact: false);
    await tester.pump();
    await tester.pump();
    await tester.pump(Duration.zero); // ticker baseline
    await tester.pump(const Duration(milliseconds: 40)); // mid-flight

    // Retarget: 'b' turns back toward x=1 while still sliding.
    controller.updateItem('b', (i) => i.copyWith(x: 1), recompact: false);
    await tester.pump();
    await tester.pump();
    final sliver = sliverOf(tester);
    // Allocation budget: retarget reuses the instance — still ONE transition.
    expect(sliver.debugActiveReflowTransitionCount, 1);

    await tester.pump(const Duration(milliseconds: 400));
    expect(sliver.debugActiveReflowTransitionCount, 0);
  });

  testWidgets('a zero reflow duration snaps: progress is complete instantly', (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
      ],
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      host(controller, scrollController, duration: Duration.zero),
    );
    await tester.pumpAndSettle();

    controller.updateItem('b', (i) => i.copyWith(x: 3), recompact: false);
    await tester.pump();
    await tester.pump();
    final sliver = sliverOf(tester);
    // With durationUs <= 0, progress is 1 immediately: the painted offset
    // never lags behind the final position.
    expect(sliver.debugReflowPaintOffsetFor('b'), isNull);
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(milliseconds: 16));
    expect(sliver.debugActiveReflowTransitionCount, 0);
  });

  testWidgets('debug hooks: unknown id and settled item both yield null', (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(host(controller, scrollController));
    await tester.pumpAndSettle();
    final sliver = sliverOf(tester);
    expect(sliver.debugReflowPaintOffsetFor('ghost'), isNull);
    expect(sliver.debugReflowPaintOffsetFor('a'), isNull);
  });

  testWidgets('tearing the widget down mid-flight disposes cleanly', (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
      ],
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(host(controller, scrollController));
    await tester.pumpAndSettle();
    controller.updateItem('b', (i) => i.copyWith(x: 3), recompact: false);
    await tester.pump();
    await tester.pump();
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(milliseconds: 40)); // in flight

    // Unmount while the ticker is active: detach + dispose must stop and
    // release it without asserts ("Ticker was still active").
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('scroll passes never seed transitions', (tester) async {
    final items = <LayoutItem>[
      for (var i = 0; i < 40; i++) LayoutItem(id: 'i$i', x: i % 4, y: i ~/ 4, w: 1, h: 1),
    ];
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: items,
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(host(controller, scrollController));
    await tester.pumpAndSettle();

    scrollController.jumpTo(400);
    await tester.pump();
    scrollController.jumpTo(0);
    await tester.pump();
    expect(sliverOf(tester).debugActiveReflowTransitionCount, 0);
  });

  testWidgets('changing viewport width during in-flight reflow clears transitions', (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
      ],
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    Widget buildWithWidth(double width) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverDashboard(
                  controller: controller,
                  animateReflow: true,
                  itemBuilder: (context, item) => Text(item.id),
                ),
              ],
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildWithWidth(400));
    await tester.pumpAndSettle();

    // Trigger a reflow transition
    controller.updateItem('b', (i) => i.copyWith(x: 3), recompact: false);
    await tester.pump();
    await tester.pump(); // Relayout to seed transition

    final sliver = sliverOf(tester);
    expect(sliver.debugActiveReflowTransitionCount, 1);

    // Rebuild with different width to trigger metricsChanged in the same render object
    await tester.pumpWidget(buildWithWidth(300));
    await tester.pump();

    expect(sliver.debugActiveReflowTransitionCount, 0);
  });

  testWidgets('RenderSliverDashboard getters and setters coverage', (tester) async {
    final controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
      ],
    );
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(host(controller, scrollController));
    await tester.pumpAndSettle();

    final renderSliver = sliverOf(tester)

      // Verify slotCount setter and getter
      ..slotCount = 6;
    expect(renderSliver.slotCount, 6);

    // Verify standard getters
    expect(renderSliver.animateReflow, isTrue);
    expect(renderSliver.reflowDuration, const Duration(milliseconds: 150));
    expect(renderSliver.vsync, isNotNull);

    // Verify reflowDuration setter
    renderSliver.reflowDuration = const Duration(milliseconds: 300);
    expect(renderSliver.reflowDuration, const Duration(milliseconds: 300));

    // Trigger a transition to make internal transition list non-empty
    controller.updateItem('b', (i) => i.copyWith(x: 3), recompact: false);
    await tester.pump();
    await tester.pump(); // Relayout to seed transition

    expect(renderSliver.debugActiveReflowTransitionCount, 1);

    // Verify vsync setter with active transitions
    final originalVsync = renderSliver.vsync;
    renderSliver.vsync = _DummyTickerProvider();
    expect(renderSliver.vsync, isA<_DummyTickerProvider>());

    // Restore vsync to prevent leaking tickers during teardown
    renderSliver.vsync = originalVsync;
  });
}

class _DummyTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}
