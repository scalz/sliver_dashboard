import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';

import '../test_helpers.dart';

void main() {
  group('Invariant: metrics backchannel is published on every layout pass', () {
    // The _items.isEmpty early return skipped onLayoutMetrics, so
    // the minimap (and DashboardGrid's geometry fallback) kept the metrics of
    // the previous NON-empty layout. Silent state transition.
    testWidgets('an emptied grid publishes its own metrics', (tester) async {
      await runOnDesktop(() async {
        final controller = DashboardController(
          initialSlotCount: 4,
          initialLayout: const [LayoutItem(id: 'i1', x: 0, y: 0, w: 1, h: 2)],
        )..setEditMode(true);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Dashboard<String>(
                controller: controller,
                itemBuilder: (context, item) => const ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final filledExtent = controller.internal.viewMainAxisContentExtent;
        expect(filledExtent, isNotNull);
        expect(filledExtent, greaterThan(0));

        controller.removeItems(['i1']);
        await tester.pumpAndSettle();

        expect(
          controller.internal.viewMainAxisContentExtent,
          isNot(filledExtent),
          reason: 'the backchannel must reflect the empty layout, not the previous one',
        );
        expect(
          controller.internal.viewSlotWidth,
          greaterThan(0),
          reason: 'slot metrics stay meaningful on an empty grid (minimap mapping)',
        );
      });
    });
  });

  group('Invariant: reflow seeding survives an animateReflow toggle', () {
    // updateRenderObject assigned items BEFORE animateReflow, and
    // the items setter latches _reflowSeedPass = _animateReflow. A false→true
    // toggle therefore lost its first seed pass — and that frame is usually
    // also the layout mutation worth animating.
    testWidgets('toggling animateReflow on together with a layout change seeds transitions',
        (tester) async {
      await runOnDesktop(() async {
        final controller = DashboardController(
          initialSlotCount: 4,
          initialLayout: const [
            LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
            LayoutItem(id: 'b', x: 0, y: 1, w: 1, h: 1),
          ],
        )..setEditMode(true);
        addTearDown(controller.dispose);

        Widget build({required bool animate}) => MaterialApp(
              home: Scaffold(
                body: Dashboard<String>(
                  controller: controller,
                  animateReflow: animate,
                  itemBuilder: (context, item) => ColoredBox(
                    color: Colors.blue,
                    child: Text('T-${item.id}'),
                  ),
                ),
              ),
            );

        await tester.pumpWidget(build(animate: false));
        await tester.pumpAndSettle();

        // Flip the flag AND mutate the layout in the same frame.
        controller.internal.setItemSize('a', h: 3);
        await tester.pumpWidget(build(animate: true));
        await tester.pump();

        final render = tester.renderObject<RenderSliverDashboard>(
          find.byType(SliverDashboardLayout),
        );
        expect(
          render.debugActiveReflowTransitionCount,
          greaterThan(0),
          reason: 'the seed pass must not be lost by the property assignment order',
        );
      });
    });
  });

  group('Invariant: key cache survives geometric reordering', () {
    // Reason: the geometric view reorders the layout on every collision push, so
    // the previous "same ID sequence" fast path in _getOrUpdateKeyToIndex missed
    // on exactly the frames where the engine is busiest, and rebuilt N ValueKeys
    // + N string interpolations + one N-entry Map.
    //
    // The layout below is built so the geometric order REVERSES while the id set
    // is unchanged: id order stays [a, b, c], the view goes [a, b, c] -> [c, b, a].
    // That is the in-place-rewrite tier of _getOrUpdateKeyToIndex. A layout whose
    // geometric order happens to match the id order would only exercise the
    // `identical` short-circuit and prove nothing.
    testWidgets('a reorder reuses the key instances and does not remount tiles', (tester) async {
      await runOnDesktop(() async {
        final controller = DashboardController(
          initialSlotCount: 4,
          initialLayout: const [
            LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
            LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
            LayoutItem(id: 'c', x: 2, y: 0, w: 1, h: 1),
          ],
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Dashboard<String>(
                controller: controller,
                itemBuilder: (context, item) => ColoredBox(
                  color: Colors.blue,
                  child: Text('T-${item.id}'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The delegate wraps our KeyedSubtree in a _SaltedValueKey one, which
        // does not compare equal to a plain ValueKey — so this finder resolves
        // to exactly our tile root.
        Finder tile(String id) => find.byKey(ValueKey(id));
        Key keyOf(String id) => tester.widget<KeyedSubtree>(tile(id)).key!;
        Element elementOf(String id) => tester.element(find.text('T-$id'));

        for (final id in ['a', 'b', 'c']) {
          expect(tile(id), findsOneWidget);
        }

        final keysBefore = {
          for (final id in ['a', 'b', 'c']) id: keyOf(id),
        };
        final elementsBefore = {
          for (final id in ['a', 'b', 'c']) id: elementOf(id),
        };

        // Written straight onto the beacon (an established pattern in this
        // suite) so the positions are exact: an engine pass would recompact and
        // could undo the reversal.
        controller.layout.value = const [
          LayoutItem(id: 'a', x: 2, y: 0, w: 1, h: 1),
          LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
          LayoutItem(id: 'c', x: 0, y: 0, w: 1, h: 1),
        ];
        await tester.pumpAndSettle();

        // 1. The allocation claim: same ValueKey INSTANCES. `same` is identity —
        //    ValueKey has value equality, so a freshly built key would still
        //    compare `==`. This assertion is the one that fails if `_keyFor`
        //    stops caching.
        for (final id in ['a', 'b', 'c']) {
          expect(
            keyOf(id),
            same(keysBefore[id]),
            reason: 'ValueKeys are cached per id; a reorder must not reallocate them',
          );
        }

        // 2. What the keys are FOR: the reorder must move elements, not remount
        //    them. (This holds through value equality alone, so it does not test
        //    the cache — it guards the ValueKey + findChildIndexCallback scheme.)
        for (final id in ['a', 'b', 'c']) {
          expect(
            elementOf(id),
            same(elementsBefore[id]),
            reason: 'a geometric reorder must not remount the tile',
          );
        }

        // 3. The correctness claim of the in-place rewrite: the index map now maps
        //    each key to its NEW position in the view. A stale map would place
        //    tiles at each other's coordinates.
        final slotWidth = controller.internal.viewSlotWidth!;
        const spacing = 8.0; // Dashboard default crossAxisSpacing
        final left = tester.getTopLeft(find.byType(Dashboard<String>)).dx;

        // closeTo takes `num` for both arguments, so it cannot mistype the way
        // `within` does: `within(from: 0)` infers T = int from the literal and
        // rejects a double actual before computing any distance.
        expect(
          tester.getTopLeft(tile('a')).dx - left,
          closeTo(2 * (slotWidth + spacing), 0.5),
        );
        expect(
          tester.getTopLeft(tile('c')).dx - left,
          closeTo(0, 0.5),
        );
      });
    });
  });

  group('Invariant: key cache survives geometric reordering', () {
    // The geometric view reorders the layout on every collision push,
    // which made the "same ID sequence" fast path miss and rebuild N ValueKeys
    // + N interpolated strings + one N-entry Map, on the frame where the engine
    // is already at its busiest.
    testWidgets('a reorder reuses the same key instances', (tester) async {
      await runOnDesktop(() async {
        final controller = DashboardController(
          initialSlotCount: 4,
          initialLayout: const [
            LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
            LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
            LayoutItem(id: 'c', x: 2, y: 0, w: 1, h: 1),
          ],
        )..setEditMode(true);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Dashboard<String>(
                controller: controller,
                itemBuilder: (context, item) => ColoredBox(
                  color: Colors.blue,
                  child: Text('T-${item.id}'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Key keyOf(String id) => tester
            .widget<KeyedSubtree>(
              find
                  .ancestor(
                    of: find.text('T-$id'),
                    matching: find.byType(KeyedSubtree),
                  )
                  .first,
            )
            .key!;

        final keyBefore = keyOf('c');

        // Move 'c' so that the geometric order no longer matches the id order.
        controller.internal.setItemSize('a', w: 3);
        await tester.pumpAndSettle();

        expect(
          keyOf('c'),
          same(keyBefore),
          reason: 'ValueKeys are cached per id; a reorder must not reallocate them',
        );
        // Element identity is what the cache protects: the tile must not remount.
        expect(find.text('T-c'), findsOneWidget);
      });
    });
  });

  group('Invariant: the active gesture pivot is never replaced', () {
    // Documents an app-side contract that used to surface as a bare
    // StateError from `newLayout.firstWhere((i) => i.id == itemId)` inside
    // onDragUpdate. Unreachable through the package's own flows.
    testWidgets('replaceItem on the dragged pivot asserts', (tester) async {
      await runOnDesktop(() async {
        final controller = DashboardController(
          initialSlotCount: 4,
          initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
        )..setEditMode(true);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Dashboard<String>(
                controller: controller,
                itemBuilder: (context, item) => ColoredBox(
                  color: Colors.blue,
                  child: Text('T-${item.id}'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(tester.getCenter(find.text('T-a')));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();
        expect(controller.isDragging.value, isTrue);

        expect(
          () => controller.replaceItem(
            'a',
            const LayoutItem(id: 'a2', x: 0, y: 0, w: 1, h: 1),
          ),
          throwsAssertionError,
        );

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('replaceItem on a NON-pivot item during a drag stays allowed', (tester) async {
      await runOnDesktop(() async {
        final controller = DashboardController(
          initialSlotCount: 4,
          initialLayout: const [
            LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
            LayoutItem(id: 'host', x: 2, y: 0, w: 1, h: 1),
          ],
        )..setEditMode(true);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Dashboard<String>(
                controller: controller,
                itemBuilder: (context, item) => ColoredBox(
                  color: Colors.blue,
                  child: Text('T-${item.id}'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(tester.getCenter(find.text('T-a')));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();

        // This is exactly what onNestedGridRequested does: convert the HOST,
        // never the dragged tile.
        controller.replaceItem(
          'host',
          const LayoutItem(id: 'folder', x: 2, y: 0, w: 1, h: 1, hasNestedGrid: true),
        );
        await tester.pump();

        expect(controller.layout.value.any((i) => i.id == 'folder'), isTrue);
        expect(controller.isDragging.value, isTrue);

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });
  });

  group('Invariant: the items identity guard short-circuits', () {
    testWidgets('assigning the same items instance does not dirty the sliver', (tester) async {
      final controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
        ],
      )..setEditMode(true);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Dashboard<String>(
              controller: controller,
              itemBuilder: (context, item) => const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final render = tester.renderObject<RenderSliverDashboard>(
        find.byType(SliverDashboardLayout),
      );
      expect(render.debugNeedsLayout, isFalse, reason: 'sanity: settled');

      final sameInstance = render.items;
      render.items = sameInstance;
      expect(render.debugNeedsLayout, isFalse, reason: 'the identity guard must short-circuit');

      // A different instance with equal CONTENT is still a real change:
      // identity, not equality, is the contract.
      render.items = List<LayoutItem>.of(render.items);
      expect(render.debugNeedsLayout, isTrue);

      await tester.pumpAndSettle();
    });
  });
}
