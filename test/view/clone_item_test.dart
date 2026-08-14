import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

import '../test_helpers.dart';

void main() {
  /// Presses [key], runs [body], and ALWAYS releases the key.
  ///
  /// `HardwareKeyboard.instance` is a process-wide singleton: a key left down
  /// by a failing test leaks into every test that follows (and re-pressing an
  /// already-pressed physical key trips a framework assertion), which would
  /// make the suite order-dependent.
  Future<void> withKey(
    WidgetTester tester,
    LogicalKeyboardKey key,
    Future<void> Function() body,
  ) async {
    await tester.sendKeyDownEvent(key);
    try {
      await body();
    } finally {
      await tester.sendKeyUpEvent(key);
    }
  }

  DashboardController buildController() => DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
          LayoutItem(id: 'b', x: 2, y: 0, w: 2, h: 2),
        ],
      )..setEditMode(true);

  Widget buildApp({
    required DashboardController controller,
    DashboardCloneRequestCallback? onCloneRequested,
    DashboardCloneRequestCallback? scopeOnCloneRequested,
    void Function(LayoutItem item)? onItemDragStart,
    bool withScope = false,
  }) {
    final dashboard = Dashboard<String>(
      controller: controller,
      onCloneRequested: onCloneRequested,
      onItemDragStart: onItemDragStart,
      itemBuilder: (context, item) => ColoredBox(
        color: Colors.blue,
        child: Center(child: Text(item.id)),
      ),
    );

    return MaterialApp(
      home: Scaffold(
        body: withScope
            ? DashboardNestedScope(
                onCloneRequested: scopeOnCloneRequested,
                child: dashboard,
              )
            : dashboard,
      ),
    );
  }

  /// Presses on [finder], moves by [move] (enough to pass the drag
  /// threshold), and returns the live gesture — the caller decides when to
  /// release it.
  Future<TestGesture> startDrag(
    WidgetTester tester,
    Finder finder, {
    Offset move = const Offset(0, 60),
  }) async {
    final gesture = await tester.startGesture(
      tester.getCenter(finder),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(move);
    await tester.pump();
    return gesture;
  }

  group('Alt + drag cloning — happy path', () {
    testWidgets('invokes onCloneRequested once and starts the drag on the clone', (tester) async {
      await runOnDesktop(() async {
        final controller = buildController();
        addTearDown(controller.dispose);

        final sources = <LayoutItem>[];
        final dragStarts = <LayoutItem>[];

        await tester.pumpWidget(
          buildApp(
            controller: controller,
            onItemDragStart: dragStarts.add,
            onCloneRequested: (source, grid) {
              sources.add(source);
              expect(identical(grid, controller), isTrue);
              return source.copyWith(id: 'a_copy');
            },
          ),
        );
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await startDrag(tester, find.text('a'));

          // The callback saw the SOURCE, exactly once.
          expect(sources.length, 1);
          expect(sources.single.id, 'a');

          // The duplicate is on the grid and the source survived untouched in
          // identity and size.
          final ids = controller.layout.value.map((i) => i.id).toList();
          expect(ids, containsAll(['a', 'b', 'a_copy']));
          expect(controller.layout.value.length, 3);
          final source = controller.layout.value.firstWhere((i) => i.id == 'a');
          expect((source.w, source.h), (2, 2));

          // The session runs on the CLONE: it is the pivot and the whole
          // selection, and the drag-start callback reported it, not the source.
          expect(controller.isDragging.value, isTrue);
          expect(controller.selectedItemIds.value, {'a_copy'});
          expect(controller.activeItemId.value, 'a_copy');
          expect(dragStarts.map((i) => i.id).toList(), ['a_copy']);

          // The duplicate materializes UNDER THE CURSOR. The 60 px move is a
          // fraction of one slot stride, so `onDragUpdate` rounds the pivot
          // back to the source's own cell: the clone owns (0,0) and the source
          // is the one the cascade pushed aside.
          final clone = controller.layout.value.firstWhere((i) => i.id == 'a_copy');
          expect((clone.x, clone.y), (0, 0));

          await gesture.up();
          await tester.pumpAndSettle();
        });

        expect(controller.layout.value.length, 3);
        expect(controller.isDragging.value, isFalse);
      });
    });

    testWidgets('the clone carries the business metadata the callback attached', (tester) async {
      await runOnDesktop(() async {
        final controller = buildController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          buildApp(
            controller: controller,
            onCloneRequested: (source, grid) => source.copyWith(
              id: 'a_copy',
              extra: {'clonedFrom': source.id},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await startDrag(tester, find.text('a'));
          final clone = controller.layout.value.firstWhere((i) => i.id == 'a_copy');
          expect(clone.extra, {'clonedFrom': 'a'});
          await gesture.up();
          await tester.pumpAndSettle();
        });
      });
    });

    testWidgets('a clone smaller than its source keeps the drag anchored', (tester) async {
      await runOnDesktop(() async {
        final controller = buildController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          buildApp(
            controller: controller,
            // 1x1 instead of 2x2: exercises the grab-offset re-clamp.
            onCloneRequested: (source, grid) => source.copyWith(id: 'a_small', w: 1, h: 1),
          ),
        );
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await startDrag(tester, find.text('a'));
          final clone = controller.layout.value.firstWhere((i) => i.id == 'a_small');
          expect((clone.w, clone.h), (1, 1));
          expect(controller.activeItemId.value, 'a_small');

          // Keep dragging: the clamped grab offset must not desynchronize the
          // session (the pivot stays the clone for the whole gesture).
          await gesture.moveBy(const Offset(0, 40));
          await tester.pump();
          expect(controller.activeItemId.value, 'a_small');

          await gesture.up();
          await tester.pumpAndSettle();
        });
      });
    });
  });

  group('Alt + drag cloning — refusals and guards', () {
    testWidgets('a plain Alt+CLICK never duplicates anything', (tester) async {
      await runOnDesktop(() async {
        final controller = buildController();
        addTearDown(controller.dispose);

        var calls = 0;
        await tester.pumpWidget(
          buildApp(
            controller: controller,
            onCloneRequested: (source, grid) {
              calls++;
              return source.copyWith(id: 'a_copy');
            },
          ),
        );
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await tester.startGesture(
            tester.getCenter(find.text('a')),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          // Below the 2 px drag tolerance: still a click.
          await gesture.moveBy(const Offset(1, 0));
          await tester.pump();
          await gesture.up();
          await tester.pumpAndSettle();
        });

        expect(calls, 0, reason: 'the callback must not run for a click');
        expect(controller.layout.value.length, 2);
        expect(controller.selectedItemIds.value, isEmpty);
        expect(controller.isDragging.value, isFalse);
      });
    });

    testWidgets('returning null cancels the clone and degrades to a plain move', (tester) async {
      await runOnDesktop(() async {
        final controller = buildController();
        addTearDown(controller.dispose);

        var calls = 0;
        await tester.pumpWidget(
          buildApp(
            controller: controller,
            onCloneRequested: (source, grid) {
              calls++;
              return null;
            },
          ),
        );
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await startDrag(tester, find.text('a'));

          expect(calls, 1);
          expect(controller.layout.value.length, 2, reason: 'nothing was inserted');
          expect(controller.isDragging.value, isTrue, reason: 'the gesture is a plain move');
          expect(controller.activeItemId.value, 'a');

          await gesture.up();
          await tester.pumpAndSettle();
        });

        expect(controller.layout.value.length, 2);
      });
    });

    testWidgets('without a callback the modifier is ignored entirely', (tester) async {
      await runOnDesktop(() async {
        final controller = buildController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(buildApp(controller: controller));
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await startDrag(tester, find.text('a'));
          expect(controller.layout.value.length, 2);
          expect(controller.activeItemId.value, 'a');
          await gesture.up();
          await tester.pumpAndSettle();
        });
      });
    });

    testWidgets('an already-used id is rejected and the drag falls back to the source',
        (tester) async {
      await runOnDesktop(() async {
        debugBypassCloneIdAssert = true;
        addTearDown(() => debugBypassCloneIdAssert = false);

        final controller = buildController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          buildApp(
            controller: controller,
            onCloneRequested: (source, grid) => source.copyWith(id: 'b'),
          ),
        );
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await startDrag(tester, find.text('a'));

          expect(controller.layout.value.length, 2, reason: 'no duplicate id landed');
          expect(controller.activeItemId.value, 'a');

          await gesture.up();
          await tester.pumpAndSettle();
        });
      });
    });

    testWidgets('returning the source id itself is rejected', (tester) async {
      await runOnDesktop(() async {
        debugBypassCloneIdAssert = true;
        addTearDown(() => debugBypassCloneIdAssert = false);

        final controller = buildController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          buildApp(
            controller: controller,
            onCloneRequested: (source, grid) => source,
          ),
        );
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await startDrag(tester, find.text('a'));
          expect(controller.layout.value.length, 2);
          expect(controller.activeItemId.value, 'a');
          await gesture.up();
          await tester.pumpAndSettle();
        });
      });
    });

    testWidgets('a multi-selection modifier wins over the clone modifier', (tester) async {
      await runOnDesktop(() async {
        final controller = buildController();
        addTearDown(controller.dispose);

        var calls = 0;
        await tester.pumpWidget(
          buildApp(
            controller: controller,
            onCloneRequested: (source, grid) {
              calls++;
              return source.copyWith(id: 'a_copy');
            },
          ),
        );
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          await withKey(tester, LogicalKeyboardKey.shiftLeft, () async {
            final gesture = await startDrag(tester, find.text('a'));
            expect(calls, 0);
            expect(controller.layout.value.length, 2);
            expect(controller.selectedItemIds.value, contains('a'));
            await gesture.up();
            await tester.pumpAndSettle();
          });
        });
      });
    });

    testWidgets('dragging a resize handle with the modifier resizes, never clones', (tester) async {
      await runOnDesktop(() async {
        final controller = buildController();
        addTearDown(controller.dispose);

        var calls = 0;
        await tester.pumpWidget(
          buildApp(
            controller: controller,
            onCloneRequested: (source, grid) {
              calls++;
              return source.copyWith(id: 'a_copy');
            },
          ),
        );
        await tester.pumpAndSettle();

        // Handles are mounted in edit mode; take the first one.
        final handle = find.byType(ResizeHandleWidget).first;
        expect(handle, findsOneWidget);

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await tester.startGesture(
            tester.getCenter(handle),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          await gesture.moveBy(const Offset(30, 30));
          await tester.pump();

          expect(calls, 0, reason: 'the modifier must not arm on a resize');
          expect(controller.layout.value.length, 2);
          // A resize, not a drag: the clone path would have opened a drag
          // session (and `isDragging` is the public signal for one).
          expect(controller.isDragging.value, isFalse);

          await gesture.up();
          await tester.pumpAndSettle();
        });
      });
    });

    testWidgets('a static item is never cloned', (tester) async {
      await runOnDesktop(() async {
        final controller = DashboardController(
          initialSlotCount: 4,
          initialLayout: const [
            LayoutItem(id: 'fixed', x: 0, y: 0, w: 2, h: 2, isStatic: true),
            LayoutItem(id: 'b', x: 2, y: 0, w: 2, h: 2),
          ],
        )..setEditMode(true);
        addTearDown(controller.dispose);

        var calls = 0;
        await tester.pumpWidget(
          buildApp(
            controller: controller,
            onCloneRequested: (source, grid) {
              calls++;
              return source.copyWith(id: 'fixed_copy');
            },
          ),
        );
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await startDrag(tester, find.text('fixed'));
          expect(calls, 0);
          expect(controller.layout.value.length, 2);
          await gesture.up();
          await tester.pumpAndSettle();
        });
      });
    });
  });

  group('Alt + drag cloning — layout integrity', () {
    testWidgets('the web throttle never defers the move that created the clone', (tester) async {
      await runOnDesktop(() async {
        // Freeze the throttle clock at zero: every move then falls inside the
        // 16 ms window and would normally be deferred.
        debugOverrideIsWeb = true;
        debugThrottleClock = () => Duration.zero;
        addTearDown(() {
          debugOverrideIsWeb = false;
          debugThrottleClock = null;
        });

        final controller = buildController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          buildApp(
            controller: controller,
            // 'a' < 'a_copy': at insertion time the compactor's alphabetical
            // tie-break leaves the SOURCE on (0,0) and snaps the clone one row
            // down. Only the drag update — which must run in the same pointer
            // event — pulls it back under the cursor.
            onCloneRequested: (source, grid) => source.copyWith(id: 'a_copy'),
          ),
        );
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await startDrag(tester, find.text('a'));

          final clone = controller.layout.value.firstWhere((i) => i.id == 'a_copy');
          expect(
            (clone.x, clone.y),
            (0, 0),
            reason: 'the raw insertion layout must never reach a frame',
          );

          await gesture.up();
          await tester.pumpAndSettle();
        });
      });
    });

    testWidgets('the clone never inherits the displaced marker of its source after drop',
        (tester) async {
      await runOnDesktop(() async {
        final controller = buildController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          buildApp(
            controller: controller,
            // A source carrying a stale cascade marker: the duplicate is a new
            // item, not something a push displaced.
            onCloneRequested: (source, grid) => source.copyWith(
              id: 'a_copy',
              moved: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await startDrag(tester, find.text('a'));
          // Release the drag so compaction/drop finishes
          await gesture.up();
          await tester.pumpAndSettle();

          // After drop, the clone must be clean (moved == false)
          final clone = controller.layout.value.firstWhere((i) => i.id == 'a_copy');
          expect(clone.moved, isFalse);
        });
      });
    });

    testWidgets('an oversized clone is clamped to the grid and stays draggable', (tester) async {
      await runOnDesktop(() async {
        final controller = buildController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          buildApp(
            controller: controller,
            // 9 columns requested on a 4-column grid: placeNewItems clamps it,
            // which is exactly the case where trusting the returned instance
            // instead of re-reading the layout would desynchronize the session.
            onCloneRequested: (source, grid) => source.copyWith(id: 'a_wide', w: 9),
          ),
        );
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await startDrag(tester, find.text('a'));

          final clone = controller.layout.value.firstWhere((i) => i.id == 'a_wide');
          expect(clone.w, 4, reason: 'clamped to the column count');
          expect(clone.x, 0);
          expect(controller.activeItemId.value, 'a_wide');

          await gesture.moveBy(const Offset(0, 40));
          await tester.pump();
          expect(controller.activeItemId.value, 'a_wide');

          await gesture.up();
          await tester.pumpAndSettle();
        });
      });
    });
  });

  group('Alt + drag cloning — configuration', () {
    testWidgets('the modifier is configurable through DashboardShortcuts.cloneKeys',
        (tester) async {
      await runOnDesktop(() async {
        final controller = buildController()
          ..shortcuts = const DashboardShortcuts(
            cloneKeys: [LogicalKeyboardKey.controlLeft],
            // Control is a DEFAULT multi-select key: leaving multiSelectKeys
            // alone would overlap the two sets, which the overlay asserts
            // against. Narrow multi-selection to Shift.
            multiSelectKeys: [
              LogicalKeyboardKey.shiftLeft,
              LogicalKeyboardKey.shiftRight,
            ],
          );
        addTearDown(controller.dispose);

        var calls = 0;
        await tester.pumpWidget(
          buildApp(
            controller: controller,
            onCloneRequested: (source, grid) {
              calls++;
              return source.copyWith(id: 'a_copy_$calls');
            },
          ),
        );
        await tester.pumpAndSettle();

        // Alt is no longer the clone modifier.
        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await startDrag(tester, find.text('a'));
          expect(calls, 0);
          expect(controller.layout.value.length, 2);
          await gesture.up();
          await tester.pumpAndSettle();
        });

        // Control now is.
        await withKey(tester, LogicalKeyboardKey.controlLeft, () async {
          final gesture = await startDrag(tester, find.text('a'));
          expect(calls, 1);
          expect(controller.activeItemId.value, 'a_copy_1');
          expect(controller.layout.value.length, 3);
          await gesture.up();
          await tester.pumpAndSettle();
        });
      });
    });

    testWidgets('the scope-wide callback serves grids that declare none', (tester) async {
      await runOnDesktop(() async {
        final controller = buildController();
        addTearDown(controller.dispose);

        DashboardController? seenGrid;
        await tester.pumpWidget(
          buildApp(
            controller: controller,
            withScope: true,
            scopeOnCloneRequested: (source, grid) {
              seenGrid = grid;
              return source.copyWith(id: 'a_copy');
            },
          ),
        );
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await startDrag(tester, find.text('a'));
          expect(identical(seenGrid, controller), isTrue);
          expect(controller.activeItemId.value, 'a_copy');
          await gesture.up();
          await tester.pumpAndSettle();
        });
      });
    });

    testWidgets('a per-grid callback takes precedence over the scope-wide one', (tester) async {
      await runOnDesktop(() async {
        final controller = buildController();
        addTearDown(controller.dispose);

        var scopeCalls = 0;
        await tester.pumpWidget(
          buildApp(
            controller: controller,
            withScope: true,
            scopeOnCloneRequested: (source, grid) {
              scopeCalls++;
              return source.copyWith(id: 'from_scope');
            },
            onCloneRequested: (source, grid) => source.copyWith(id: 'from_grid'),
          ),
        );
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.altLeft, () async {
          final gesture = await startDrag(tester, find.text('a'));
          expect(scopeCalls, 0);
          expect(controller.activeItemId.value, 'from_grid');
          await gesture.up();
          await tester.pumpAndSettle();
        });
      });
    });

    testWidgets('overlapping cloneKeys and multiSelectKeys trips the assertion', (tester) async {
      await runOnDesktop(() async {
        final controller = buildController()
          // shiftLeft is a default multi-select key.
          ..shortcuts = const DashboardShortcuts(
            cloneKeys: [LogicalKeyboardKey.shiftLeft],
          );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          buildApp(
            controller: controller,
            onCloneRequested: (source, grid) => source.copyWith(id: 'a_copy'),
          ),
        );
        await tester.pumpAndSettle();

        await withKey(tester, LogicalKeyboardKey.shiftLeft, () async {
          final gesture = await tester.startGesture(
            tester.getCenter(find.text('a')),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          await gesture.up();
          await tester.pumpAndSettle();
        });

        expect(tester.takeException(), isAssertionError);
      });
    });
  });

  group('DashboardShortcuts.cloneKeys', () {
    test('defaults to both Alt keys and stays disjoint from multiSelectKeys', () {
      const shortcuts = DashboardShortcuts.defaultShortcuts;
      expect(
        shortcuts.cloneKeys,
        const [LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight],
      );
      expect(
        shortcuts.cloneKeys.any(shortcuts.multiSelectKeys.contains),
        isFalse,
        reason: 'the shipped defaults must never collide',
      );
    });
  });

  testWidgets('mobile tap with DragStartGesture.tap releases armed clone source and pointer claim',
      (tester) async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final controller = buildController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Dashboard<String>(
              controller: controller,
              dragStartGesture: DragStartGesture.tap,
              onCloneRequested: (source, grid) => source.copyWith(id: 'copy'),
              itemBuilder: (context, item) => Text(item.id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await withKey(tester, LogicalKeyboardKey.altLeft, () async {
        await tester.tap(find.text('a'));
        await tester.pumpAndSettle();
      });

      expect(controller.layout.value.length, 2);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });

  testWidgets('policy refusing canDrag on source cancels clone creation on first move',
      (tester) async {
    await runOnDesktop(() async {
      final controller = buildController()..policy = const _NoDragPolicy();
      addTearDown(controller.dispose);

      var calls = 0;
      await tester.pumpWidget(
        buildApp(
          controller: controller,
          onCloneRequested: (source, grid) {
            calls++;
            return source.copyWith(id: 'copy');
          },
        ),
      );
      await tester.pumpAndSettle();

      await withKey(tester, LogicalKeyboardKey.altLeft, () async {
        final gesture = await startDrag(tester, find.text('a'));
        expect(calls, 0, reason: 'policy refusing canDrag must prevent cloning');
        expect(controller.layout.value.length, 2);
        await gesture.up();
        await tester.pumpAndSettle();
      });
    });
  });

  testWidgets('assert in _insertClone throws when duplicate ID is returned in debug mode',
      (tester) async {
    await runOnDesktop(() async {
      final controller = buildController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        buildApp(
          controller: controller,
          onCloneRequested: (source, grid) => source, // Returns source itself (duplicate ID 'a')
        ),
      );
      await tester.pumpAndSettle();

      await withKey(tester, LogicalKeyboardKey.altLeft, () async {
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('a')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveBy(const Offset(0, 60));
        await tester.pump();

        expect(tester.takeException(), isAssertionError);

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });
  });
}

class _NoDragPolicy extends DashboardPolicy {
  const _NoDragPolicy();
  @override
  bool canDrag(LayoutItem item) => item.id != 'a';
}
