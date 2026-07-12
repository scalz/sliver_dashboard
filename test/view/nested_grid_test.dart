import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';

/// End-to-end coverage of the v2 nested-grid feature: pointer claiming,
/// hit-test ownership, cross-grid drag & drop, cancellation, programmatic
/// moves, `autoSlotCount` and tree serialization.
void main() {
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
              // Dead zone below both grids for the cancel test.
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> runOnDesktop(Future<void> Function() body) async {
    final original = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = original;
    }
  }

  group('Cross-grid drag & drop', () {
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

        // Enter grid B (its area starts at y=250).
        final inB = tester.getCenter(find.text('B-b1')) + const Offset(0, 60);
        await gesture.moveTo(inB);
        await tester.pump();

        // Temporary removal from A + live placeholder in B.
        expect(gridA.layout.value.any((i) => i.id == 'a1'), isFalse);
        expect(gridB.layout.value.any((i) => i.id == '__placeholder__'), isTrue);

        await gesture.up();
        await tester.pumpAndSettle();

        // Item landed in B with its constraints intact; A committed the removal.
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

        // Pass through B to start a session...
        await gesture.moveTo(tester.getCenter(find.text('B-b1')));
        await tester.pump();
        expect(gridA.layout.value.any((i) => i.id == 'a1'), isFalse);

        // ...then leave every grid (dead zone at the bottom) and release.
        await gesture.moveTo(const Offset(400, 560));
        await tester.pump();
        expect(gridB.layout.value.any((i) => i.id == '__placeholder__'), isFalse);

        await gesture.up();
        await tester.pumpAndSettle();

        // Source restored to its pre-drag layout, no move event, B untouched.
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

        // No temporary removal: the cluster drag stayed in grid A.
        expect(gridA.layout.value.any((i) => i.id == 'a1'), isTrue);
        expect(gridA.layout.value.any((i) => i.id == 'a2'), isTrue);
        expect(gridB.layout.value.any((i) => i.id == '__placeholder__'), isFalse);

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
        initialLayout: [
          const LayoutItem(id: 'group', x: 0, y: 0, w: 4, h: 3),
          const LayoutItem(id: 'p1', x: 0, y: 3, w: 2, h: 1),
        ],
      )..setEditMode(true);
      child = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          const LayoutItem(id: 'c1', x: 0, y: 0, w: 1, h: 1),
          const LayoutItem(id: 'c2', x: 1, y: 0, w: 1, h: 1),
        ],
      )..setEditMode(true);
    });

    tearDown(() {
      parent.dispose();
      child.dispose();
    });

    Widget buildNested({
      DashboardNestedCoordinator? coordinator,
      bool autoSlotCount = false,
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

        // The nested grid handles the drag; the parent grid must not have
        // started one on the 'group' host item (claim + hit-test ownership).
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
        // Child not editable: its overlay never claims the pointer, so the
        // parent must resolve the hit to its own 'group' item (not crash on a
        // foreign nested id).
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

        // Host is 4 slots wide -> child slot count synced to 4.
        expect(child.slotCount.value, 4);

        parent.internal.setItemSize('group', w: 3);
        await tester.pumpAndSettle();
        expect(child.slotCount.value, 3);
      });
    });

    testWidgets('sizeToContent grows the host item when child rows grow', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DashboardNestedScope(
                child: Dashboard<String>(
                  controller: parent,
                  itemBuilder: (context, item) {
                    if (item.id == 'group') {
                      return NestedDashboard(
                        controller: child,
                        parentItemId: 'group',
                        sizeToContent: true,
                        itemBuilder: (context, item) =>
                            ColoredBox(color: Colors.orange, child: Text('C-${item.id}')),
                      );
                    }
                    return ColoredBox(color: Colors.blue, child: Text('P-${item.id}'));
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final hBefore = parent.layout.value.firstWhere((i) => i.id == 'group').h;

        // Grow the child content well beyond the current host capacity.
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

        // Structure: 'group' carries its subGrid with slotCount and items,
        // and the declarative flag is self-healed on export even though the
        // test layout never set it.
        final group = tree.firstWhere((m) => m['id'] == 'group');
        expect(group['hasNestedGrid'], isTrue);
        final sub = group['subGrid'] as Map<String, dynamic>;
        expect(sub['slotCount'], child.slotCount.value);
        expect((sub['items'] as List).length, 2);
        expect(tree.any((m) => m['id'] == 'p1'), isTrue);

        // Mutate everything, then load the saved tree back.
        parent.removeItems(['p1']);
        child.removeItems(['c1', 'c2']);
        expect(child.layout.value, isEmpty);

        loadNestedTree(coordinator, parent, tree);
        await tester.pumpAndSettle();

        expect(parent.layout.value.any((i) => i.id == 'p1'), isTrue);
        // Import normalizes the host flag from the subGrid payload.
        expect(
          parent.layout.value.firstWhere((i) => i.id == 'group').hasNestedGrid,
          isTrue,
        );
        // The child grid is mounted: its payload was delivered immediately.
        expect(child.layout.value.map((i) => i.id).toSet(), {'c1', 'c2'});
      });
    });
  });
}
