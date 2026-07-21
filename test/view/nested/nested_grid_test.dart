import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';

import '../../test_helpers.dart';

void main() {
  group('Cross-grid drag & drop', () {
    late DashboardController gridA;
    late DashboardController gridB;

    setUp(() {
      gridA = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          const LayoutItem(id: 'a1', x: 0, y: 0, w: 2, h: 1, minW: 2, maxW: 3),
          const LayoutItem(id: 'a2', x: 2, y: 0, w: 2, h: 1),
        ],
      )..setEditMode(true);
      gridB = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          const LayoutItem(id: 'b1', x: 0, y: 0, w: 2, h: 1),
        ],
      )..setEditMode(true);
    });

    tearDown(() {
      gridA.dispose();
      gridB.dispose();
    });

    Widget buildTwoGrids({
      DashboardItemMovedToGridCallback? onMoved,
      DashboardNestedCoordinator? coordinator,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: DashboardNestedScope(
            coordinator: coordinator,
            onItemMovedToGrid: onMoved,
            child: Column(
              children: [
                SizedBox(
                  height: 250,
                  child: Dashboard<String>(
                    controller: gridA,
                    itemBuilder: (context, item) =>
                        ColoredBox(color: Colors.blue, child: Text('A-${item.id}')),
                  ),
                ),
                SizedBox(
                  height: 250,
                  child: Dashboard<String>(
                    controller: gridB,
                    itemBuilder: (context, item) =>
                        ColoredBox(color: Colors.green, child: Text('B-${item.id}')),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('dragging a1 from grid A into grid B moves it, preserving constraints',
        (tester) async {
      await runOnDesktop(() async {
        LayoutItem? movedItem;
        DashboardController? movedFrom;
        DashboardController? movedTo;

        await tester.pumpWidget(
          buildTwoGrids(
            onMoved: (item, from, to) {
              movedItem = item;
              movedFrom = from;
              movedTo = to;
            },
          ),
        );
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(tester.getCenter(find.text('A-a1')));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 10)); // engage the drag
        await tester.pump();
        expect(gridA.isDragging.value, isTrue);

        final inB = tester.getCenter(find.text('B-b1')) + const Offset(0, 60);
        await gesture.moveTo(inB);
        await tester.pump();

        expect(gridA.layout.value.any((i) => i.id == 'a1'), isFalse);
        expect(gridB.layout.value.any((i) => i.id == '__placeholder__'), isTrue);

        await gesture.up();
        await tester.pumpAndSettle();

        expect(gridA.layout.value.any((i) => i.id == 'a1'), isFalse);
        final landed = gridB.layout.value.firstWhere((i) => i.id == 'a1');
        expect(landed.minW, 2);
        expect(landed.maxW, 3);
        expect(landed.w, 2);
        expect(gridB.layout.value.any((i) => i.id == '__placeholder__'), isFalse);

        expect(movedItem?.id, 'a1');
        expect(identical(movedFrom, gridA), isTrue);
        expect(identical(movedTo, gridB), isTrue);
      });
    });

    testWidgets('dropping over no grid cancels and restores the source layout', (tester) async {
      await runOnDesktop(() async {
        var movedCalls = 0;
        await tester.pumpWidget(buildTwoGrids(onMoved: (_, __, ___) => movedCalls++));
        await tester.pumpAndSettle();

        final before = List<LayoutItem>.from(gridA.layout.value);

        final gesture = await tester.startGesture(tester.getCenter(find.text('A-a1')));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();

        await gesture.moveTo(tester.getCenter(find.text('B-b1')));
        await tester.pump();
        expect(gridA.layout.value.any((i) => i.id == 'a1'), isFalse);

        await gesture.moveTo(const Offset(400, 560));
        await tester.pump();
        expect(gridB.layout.value.any((i) => i.id == '__placeholder__'), isFalse);

        await gesture.up();
        await tester.pumpAndSettle();

        expect(gridA.layout.value.toSet(), before.toSet());
        expect(gridB.layout.value.any((i) => i.id == 'a1'), isFalse);
        expect(movedCalls, 0);
      });
    });

    testWidgets('multi-selection drags never leave their grid', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(buildTwoGrids());
        await tester.pumpAndSettle();

        gridA
          ..toggleSelection('a1')
          ..toggleSelection('a2', multi: true);

        final gesture = await tester.startGesture(tester.getCenter(find.text('A-a1')));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();

        await gesture.moveTo(tester.getCenter(find.text('B-b1')));
        await tester.pump();

        expect(gridA.layout.value.any((i) => i.id == 'a1'), isTrue);
        expect(gridA.layout.value.any((i) => i.id == 'a2'), isTrue);
        expect(gridB.layout.value.any((i) => i.id == '__placeholder__'), isFalse);

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets(
        'cross-grid drag hover near the bottom edge triggers auto-scroll and re-anchors the placeholder',
        (tester) async {
      await runOnDesktop(() async {
        // Set up a scrollable area for grid B by making it taller with a static item
        gridB.layout.value = [
          const LayoutItem(id: 'b1', x: 0, y: 0, w: 2, h: 1),
          const LayoutItem(id: 'b_anchor', x: 0, y: 15, w: 1, h: 1, isStatic: true),
        ];

        await tester.pumpWidget(buildTwoGrids());
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(tester.getCenter(find.text('A-a1')));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 10)); // engage drag
        await tester.pump();

        // Drag into the bottom hot-zone of grid B
        final gridBFinder = find.byType(Dashboard<String>).last;
        final rect = tester.getRect(gridBFinder);
        final gridBBottomCenter = rect.bottomCenter - const Offset(0, 20);

        await gesture.moveTo(gridBBottomCenter);
        await tester.pump();

        // Wait for auto-scroll timer ticks to trigger the _foreignDragItem re-anchoring branch
        await tester.pump(const Duration(milliseconds: 500));

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });
  });

  group('Nested grid interactions', () {
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
          LayoutItem(id: 'c2', x: 1, y: 0, w: 1, h: 1),
        ],
      )..setEditMode(true);
    });

    tearDown(() {
      parent.dispose();
      child.dispose();
    });

    // Unified builder supporting the properties of both test files
    // (autoSlotCount, sizeToContent, sizeToContentMax, onMoved).
    Widget buildNested({
      DashboardNestedCoordinator? coordinator,
      bool autoSlotCount = false,
      bool sizeToContent = false,
      int? sizeToContentMax,
      DashboardItemMovedToGridCallback? onMoved,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: DashboardNestedScope(
            coordinator: coordinator,
            onItemMovedToGrid: onMoved,
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

    testWidgets('pointer claim: dragging a nested item never drags its host', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(buildNested());
        await tester.pumpAndSettle();

        final parentBefore = List<LayoutItem>.from(parent.layout.value);

        final gesture = await tester.startGesture(tester.getCenter(find.text('C-c1')));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();

        expect(child.isDragging.value, isTrue);
        expect(parent.isDragging.value, isFalse);
        expect(parent.activeItemId.value, isNull);

        await gesture.up();
        await tester.pumpAndSettle();
        expect(parent.layout.value.toSet(), parentBefore.toSet());
      });
    });

    testWidgets('hit-test ownership: parent still drags the host item itself', (tester) async {
      await runOnDesktop(() async {
        child.setEditMode(false);
        await tester.pumpWidget(buildNested());
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(tester.getCenter(find.text('C-c1')));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();

        expect(parent.isDragging.value, isTrue);
        expect(parent.activeItemId.value, 'group');
        expect(child.isDragging.value, isFalse);

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('autoSlotCount follows the host item width (column: auto)', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(buildNested(autoSlotCount: true));
        await tester.pumpAndSettle();

        expect(child.slotCount.value, 4);

        parent.internal.setItemSize('group', w: 3);
        await tester.pumpAndSettle();
        expect(child.slotCount.value, 3);
      });
    });

    testWidgets('sizeToContent grows the host item when child rows grow', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(buildNested(sizeToContent: true));
        await tester.pumpAndSettle();

        final hBefore = parent.layout.value.firstWhere((i) => i.id == 'group').h;

        child.addItem(const LayoutItem(id: 'c-tall', x: 0, y: 1, w: 1, h: 6));
        await tester.pumpAndSettle();

        final hAfter = parent.layout.value.firstWhere((i) => i.id == 'group').h;
        expect(hAfter, greaterThan(hBefore));
      });
    });

    testWidgets('moveItemToGrid moves programmatically between parent and child', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);
        var moves = 0;

        await tester.pumpWidget(
          buildNested(
            coordinator: coordinator,
            onMoved: (_, __, ___) => moves++,
          ),
        );
        await tester.pumpAndSettle();

        final placed = coordinator.moveItemToGrid(
          from: parent,
          to: child,
          itemId: 'p1',
        );
        await tester.pumpAndSettle();

        expect(placed, isNotNull);
        expect(parent.layout.value.any((i) => i.id == 'p1'), isFalse);
        expect(child.layout.value.any((i) => i.id == 'p1'), isTrue);
        expect(moves, 1);
      });
    });

    testWidgets('exportNestedTree / loadNestedTree round-trip', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);

        await tester.pumpWidget(buildNested(coordinator: coordinator));
        await tester.pumpAndSettle();

        final tree = exportNestedTree(coordinator, parent);

        final group = tree.firstWhere((m) => m['id'] == 'group');
        expect(group['hasNestedGrid'], isTrue);
        final sub = group['subGrid'] as Map<String, dynamic>;
        expect(sub['slotCount'], child.slotCount.value);
        expect((sub['items'] as List).length, 2);
        expect(tree.any((m) => m['id'] == 'p1'), isTrue);

        parent.removeItems(['p1']);
        child.removeItems(['c1', 'c2']);
        expect(child.layout.value, isEmpty);

        loadNestedTree(coordinator, parent, tree);
        await tester.pumpAndSettle();

        expect(parent.layout.value.any((i) => i.id == 'p1'), isTrue);
        expect(
          parent.layout.value.firstWhere((i) => i.id == 'group').hasNestedGrid,
          isTrue,
        );
        expect(child.layout.value.map((i) => i.id).toSet(), {'c1', 'c2'});
      });
    });

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

        child.addItem(const LayoutItem(id: 'c-tall', x: 0, y: 1, w: 1, h: 10));
        await tester.pumpAndSettle();

        final host = parent.layout.value.firstWhere((i) => i.id == 'group');
        expect(host.h, 2, reason: 'sizeToContent must clamp to sizeToContentMax');
      });
    });
  });

  group('DashboardNestedCoordinator.maxNestingDepth', () {
    test('null (default) allows any depth', () {
      final c = DashboardNestedCoordinator();
      addTearDown(c.dispose);
      expect(c.maxNestingDepth, isNull);
      expect(c.canHostAtDepth(0), isTrue);
      expect(c.canHostAtDepth(5), isTrue);
      expect(c.canHostAtDepth(100), isTrue);
    });

    test('0 disables nesting: even the root cannot host', () {
      final c = DashboardNestedCoordinator(maxNestingDepth: 0);
      addTearDown(c.dispose);
      expect(c.canHostAtDepth(0), isFalse);
      expect(c.canHostAtDepth(1), isFalse);
    });

    test('1 allows one level: root hosts, its children do not', () {
      final c = DashboardNestedCoordinator(maxNestingDepth: 1);
      addTearDown(c.dispose);
      expect(c.canHostAtDepth(0), isTrue);
      expect(c.canHostAtDepth(1), isFalse);
      expect(c.canHostAtDepth(2), isFalse);
    });

    test('2 allows two levels', () {
      final c = DashboardNestedCoordinator(maxNestingDepth: 2);
      addTearDown(c.dispose);
      expect(c.canHostAtDepth(0), isTrue);
      expect(c.canHostAtDepth(1), isTrue);
      expect(c.canHostAtDepth(2), isFalse);
    });

    test('the limit is mutable at runtime', () {
      final c = DashboardNestedCoordinator(maxNestingDepth: 1);
      addTearDown(c.dispose);
      expect(c.canHostAtDepth(1), isFalse);
      c.maxNestingDepth = null;
      expect(c.canHostAtDepth(1), isTrue);
      c.maxNestingDepth = 2;
      expect(c.canHostAtDepth(1), isTrue);
      expect(c.canHostAtDepth(2), isFalse);
    });

    testWidgets('DashboardNestedScope syncs maxNestingDepth onto the coordinator', (tester) async {
      final coordinator = DashboardNestedCoordinator();
      addTearDown(coordinator.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardNestedScope(
            coordinator: coordinator,
            maxNestingDepth: 1,
            child: const SizedBox(),
          ),
        ),
      );
      expect(coordinator.maxNestingDepth, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardNestedScope(
            coordinator: coordinator,
            maxNestingDepth: 3,
            child: const SizedBox(),
          ),
        ),
      );
      expect(coordinator.maxNestingDepth, 3);
    });
  });
}
