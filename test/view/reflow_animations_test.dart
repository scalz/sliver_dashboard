import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart'
    show DashboardController;
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/sliver_dashboard.dart'
    show RenderSliverDashboard, SliverDashboard, SliverDashboardLayout;

/// Paint-phase reflow animations.
///
/// Contract under test:
///  * layout stays instantaneous and deterministic (the controller's layout
///    beacon holds final coordinates immediately);
///  * only the painted offset interpolates, over `reflowDuration`;
///  * transitions are seeded only by genuine layout mutations — never by
///    scroll passes or slot-metric changes (those snap);
///  * everything is inert when `animateReflow` is false (default).
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
}
