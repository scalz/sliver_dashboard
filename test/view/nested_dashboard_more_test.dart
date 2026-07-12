import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

void main() {
  Future<void> runOnDesktop(Future<void> Function() body) async {
    final original = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = original;
    }
  }

  late DashboardController parent;
  late DashboardController child;

  setUp(() {
    parent = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'group', x: 0, y: 0, w: 4, h: 3),
        LayoutItem(id: 'p1', x: 0, y: 3, w: 2, h: 1),
      ],
    )..setEditMode(true);
    child = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'c1', x: 0, y: 0, w: 1, h: 1),
      ],
    )..setEditMode(true);
  });

  tearDown(() {
    parent.dispose();
    child.dispose();
  });

  Widget buildNested({
    required DashboardNestedCoordinator coordinator,
    bool autoSlotCount = false,
    bool sizeToContent = false,
    int? sizeToContentMax,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: DashboardNestedScope(
          coordinator: coordinator,
          child: Dashboard<String>(
            controller: parent,
            itemBuilder: (context, item) {
              if (item.id == 'group') {
                return NestedDashboard(
                  controller: child,
                  parentItemId: 'group',
                  autoSlotCount: autoSlotCount,
                  sizeToContent: sizeToContent,
                  sizeToContentMax: sizeToContentMax,
                  itemBuilder: (context, item) =>
                      ColoredBox(color: Colors.orange, child: Text('C-${item.id}')),
                );
              }
              return ColoredBox(color: Colors.blue, child: Text('P-${item.id}'));
            },
          ),
        ),
      ),
    );
  }

  testWidgets(
      'a layout stashed before mount is applied on first mount '
      '(slotCount + items, autoSlotCount off)', (tester) async {
    await runOnDesktop(() async {
      final coordinator = DashboardNestedCoordinator();
      addTearDown(coordinator.dispose);

      coordinator.stashChildGrid(
        'group',
        const NestedGridData(
          slotCount: 3,
          items: [
            LayoutItem(id: 'n1', x: 0, y: 0, w: 1, h: 1),
            LayoutItem(id: 'n2', x: 1, y: 0, w: 1, h: 1),
          ],
        ),
      );

      await tester.pumpWidget(buildNested(coordinator: coordinator));
      await tester.pumpAndSettle();

      expect(child.slotCount.value, 3);
      expect(
        child.layout.value.map((i) => i.id).toSet(),
        {'n1', 'n2'},
      );
      // Consumed: nothing left in the stash.
      expect(coordinator.takeStashedChildGrid('group'), isNull);
    });
  });

  testWidgets('swapping the controller relinks the child grid', (tester) async {
    await runOnDesktop(() async {
      final coordinator = DashboardNestedCoordinator();
      addTearDown(coordinator.dispose);
      final child2 = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [LayoutItem(id: 'z1', x: 0, y: 0, w: 1, h: 1)],
      )..setEditMode(true);
      addTearDown(child2.dispose);

      // Mount the NestedDashboard directly under the provider. Inside a real
      // Dashboard the item content is cached by design (builder changes are
      // deliberately ignored), so a swap would never reach didUpdateWidget —
      // here we exercise the widget's own update path, which is what this
      // test targets.
      Widget direct(DashboardController c) => MaterialApp(
            home: DashboardNestedScope(
              coordinator: coordinator,
              child: DashboardControllerProvider(
                controller: parent,
                child: SizedBox(
                  width: 400,
                  height: 300,
                  child: NestedDashboard(
                    controller: c,
                    parentItemId: 'group',
                    autoSlotCount: false,
                    itemBuilder: (context, item) =>
                        ColoredBox(color: Colors.orange, child: Text('C-${item.id}')),
                  ),
                ),
              ),
            ),
          );

      await tester.pumpWidget(direct(child));
      await tester.pumpAndSettle();
      expect(coordinator.childGridsOf(parent), {'group': child});

      await tester.pumpWidget(direct(child2));
      await tester.pumpAndSettle();

      // Old controller unlinked, new one linked under the same host item.
      expect(coordinator.childGridsOf(parent), {'group': child2});
      expect(coordinator.hasChildGrid(parent, 'group'), isTrue);
    });
  });

  testWidgets('sizeToContentMax caps host growth', (tester) async {
    await runOnDesktop(() async {
      final coordinator = DashboardNestedCoordinator();
      addTearDown(coordinator.dispose);

      await tester.pumpWidget(
        buildNested(
          coordinator: coordinator,
          sizeToContent: true,
          sizeToContentMax: 2,
        ),
      );
      await tester.pumpAndSettle();

      // Content far exceeding what 2 parent slots can show.
      child.addItem(const LayoutItem(id: 'c-tall', x: 0, y: 1, w: 1, h: 10));
      await tester.pumpAndSettle();

      final host = parent.layout.value.firstWhere((i) => i.id == 'group');
      expect(host.h, 2, reason: 'sizeToContent must clamp to sizeToContentMax');
    });
  });
}
