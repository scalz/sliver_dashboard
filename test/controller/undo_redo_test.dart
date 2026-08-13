import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart' as engine;
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/resize_handle.dart';
import 'package:state_beacon/state_beacon.dart';

/// A 2x1 tile at (x, y).
LayoutItem tile(String id, int x, int y, {int w = 2, int h = 1}) =>
    LayoutItem(id: id, x: x, y: y, w: w, h: h);

/// The layout used by most tests: two non-overlapping tiles on row 0.
List<LayoutItem> baseLayout() => [tile('a', 0, 0), tile('b', 2, 0)];

/// Positions of every item, keyed by id — the value the history round-trips.
Map<String, ({int x, int y, int w, int h})> geometry(List<LayoutItem> items) => {
      for (final i in items) i.id: (x: i.x, y: i.y, w: i.w, h: i.h),
    };

void main() {
  late DashboardControllerImpl controller;

  tearDown(() {
    if (!controller.layout.isDisposed) controller.dispose();
  });

  DashboardControllerImpl build({
    List<LayoutItem>? initialLayout,
    int slots = 8,
    DashboardLayoutChangeListener? onLayoutChanged,
    DashboardHistoryRestoreListener? onUndo,
    DashboardHistoryRestoreListener? onRedo,
    DashboardHistoryVeto? onWillUndo,
    DashboardHistoryVeto? onWillRedo,
    int maxHistoryLength = kDefaultMaxHistoryLength,
  }) {
    return controller = DashboardControllerImpl(
      initialLayout: initialLayout ?? baseLayout(),
      initialSlotCount: slots,
      maxHistoryLength: maxHistoryLength,
      onLayoutChanged: onLayoutChanged,
      onUndo: onUndo,
      onRedo: onRedo,
      onWillUndo: onWillUndo,
      onWillRedo: onWillRedo,
    );
  }

  // -------------------------------------------------------------------------
  group('History — initial state', () {
    test('a fresh controller has one entry and nothing to undo or redo', () {
      final c = build();

      expect(c.canUndo.value, isFalse);
      expect(c.canRedo.value, isFalse);
      expect(c.debugHistoryLength, 1);
      expect(c.debugHistoryIndex, 0);
      expect(c.maxHistoryLength, kDefaultMaxHistoryLength);
      expect(kDefaultMaxHistoryLength, 30);
    });

    test('the seed snapshot carries the initial slot count', () async {
      final c = build(slots: 4, initialLayout: [tile('a', 0, 0)])..addItem(tile('b', 2, 0));
      // Slot count unchanged: the undo is an exact restoration, no recompaction.
      await c.undo();

      expect(c.layout.value.map((i) => i.id), ['a']);
      expect(c.slotCount.value, 4);
    });
  });

  // -------------------------------------------------------------------------
  group('History — recording boundaries', () {
    test('addItem records exactly one entry and flips canUndo', () {
      final c = build();

      expect(c.canUndo.value, isFalse);
      c.addItem(tile('c', 4, 0));

      expect(c.canUndo.value, isTrue);
      expect(c.canRedo.value, isFalse);
      expect(c.debugHistoryLength, 2);
      expect(c.debugHistoryIndex, 1);
    });

    test('removeItems records one entry', () {
      final c = build()..removeItems(['b']);

      expect(c.debugHistoryLength, 2);
      expect(c.canUndo.value, isTrue);
    });

    test('importLayout records one entry', () {
      final c = build()
        ..importLayout([
          tile('x', 0, 0).toMap(),
        ]);

      expect(c.debugHistoryLength, 2);
    });

    test('optimizeLayout records one entry when it changes the layout', () {
      final c = build(initialLayout: [tile('a', 0, 0), tile('b', 0, 5)])..optimizeLayout();

      expect(c.debugHistoryLength, 2);
    });

    test('optimizeLayout on an already tidy layout records nothing', () {
      final c = build()..optimizeLayout();

      expect(c.debugHistoryLength, 1);
      expect(c.canUndo.value, isFalse);
    });

    test('updateItem(recompact: true) records one entry', () {
      final c = build()..updateItem('a', (i) => i.copyWith(w: 3));

      expect(c.debugHistoryLength, 2);
    });

    test('updateItem(recompact: false) is metadata-only and records nothing', () {
      final c = build()
        ..updateItem(
          'a',
          (i) => i.copyWith(extra: const {'tag': 'kpi'}),
          recompact: false,
        );

      expect(c.debugHistoryLength, 1);
      expect(c.layout.value.first.extra, const {'tag': 'kpi'});
    });

    test('updateItem(recompact: true) mid-drag records nothing', () {
      final c = build(initialLayout: [tile('a', 0, 0), tile('b', 4, 0)])
        ..onDragStart('a')
        ..updateItem('b', (i) => i.copyWith(w: 3));

      expect(c.debugHistoryLength, 1);
    });

    test('updateItem on an unknown id records nothing', () {
      final c = build()..updateItem('nope', (i) => i.copyWith(w: 3));

      expect(c.debugHistoryLength, 1);
    });

    test('a transaction whose result is content-equal records nothing', () {
      final c = build()
        // Same width: updateItem short-circuits before touching the layout.
        ..updateItem('a', (i) => i.copyWith(w: 2));

      expect(c.debugHistoryLength, 1);
    });

    test('setSlotCount is deliberately NOT a history boundary', () {
      final c = build()..setSlotCount(4);

      expect(c.debugHistoryLength, 1);
      expect(c.canUndo.value, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('History — gestures are single transactions', () {
    test('a 100-frame drag pushes exactly ONE snapshot', () {
      final c = build(initialLayout: [tile('a', 0, 0), tile('b', 4, 0)]);
      final before = c.debugHistoryLength;

      c.onDragStart('a');
      for (var frame = 0; frame < 100; frame++) {
        c.onDragUpdate(
          'a',
          Offset(frame.toDouble(), frame * 2.0),
          slotWidth: 100,
          slotHeight: 100,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        );
        // The strict prohibition: not a single entry during the gesture.
        expect(c.debugHistoryLength, before, reason: 'frame $frame recorded');
      }
      c.onDragEnd('a');

      expect(c.debugHistoryLength, before + 1);
      expect(c.canUndo.value, isTrue);
    });

    test('a drag that ends where it started records nothing', () {
      final c = build(initialLayout: [tile('a', 0, 0), tile('b', 4, 0)])
        ..onDragStart('a')
        ..onDragUpdate(
          'a',
          Offset.zero,
          slotWidth: 100,
          slotHeight: 100,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        )
        ..onDragEnd('a');

      expect(c.debugHistoryLength, 1);
      expect(c.canUndo.value, isFalse);
    });

    test('onDragEnd without an active drag records nothing', () {
      final c = build()..onDragEnd('a');

      expect(c.debugHistoryLength, 1);
    });

    test('a 100-frame resize pushes exactly ONE snapshot', () {
      final c = build(initialLayout: [tile('a', 0, 0)])..onResizeStart('a');
      for (var frame = 0; frame < 100; frame++) {
        c.onResizeUpdate(
          'a',
          ResizeHandle.bottomRight,
          Offset(frame.toDouble(), frame.toDouble()),
          slotWidth: 100,
          slotHeight: 100,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        );
        expect(c.debugHistoryLength, 1, reason: 'frame $frame recorded');
      }
      c.onResizeEnd('a');

      expect(c.debugHistoryLength, 2);
    });

    test('onResizeEnd without an active resize records nothing', () {
      final c = build()..onResizeEnd('a');

      expect(c.debugHistoryLength, 1);
    });

    test('cancelInteraction leaves the history untouched', () {
      final c = build(initialLayout: [tile('a', 0, 0), tile('b', 4, 0)])
        ..onDragStart('a')
        ..onDragUpdate(
          'a',
          const Offset(400, 200),
          slotWidth: 100,
          slotHeight: 100,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        )
        ..cancelInteraction();

      expect(c.debugHistoryLength, 1);
      expect(c.canUndo.value, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('History — undo / redo semantics', () {
    test('undo restores the previous layout exactly', () async {
      final c = build();
      final before = geometry(c.layout.value);

      c.addItem(tile('c', 4, 0));
      expect(c.layout.value.length, 3);

      expect(await c.undo(), isTrue);
      expect(geometry(c.layout.value), before);
      expect(c.canUndo.value, isFalse);
      expect(c.canRedo.value, isTrue);
    });

    test('redo re-applies the undone layout', () async {
      final c = build()..addItem(tile('c', 4, 0));
      final after = geometry(c.layout.value);

      await c.undo();
      expect(await c.redo(), isTrue);

      expect(geometry(c.layout.value), after);
      expect(c.canRedo.value, isFalse);
      expect(c.canUndo.value, isTrue);
    });

    test('undo returns false when there is nothing to undo', () async {
      final c = build();

      expect(await c.undo(), isFalse);
    });

    test('redo returns false when there is nothing to redo', () async {
      final c = build();

      expect(await c.redo(), isFalse);
    });

    test('a new transaction truncates the redo branch', () async {
      final c = build()
        ..addItem(tile('c', 4, 0))
        ..addItem(tile('d', 6, 0));
      expect(c.debugHistoryLength, 3);

      await c.undo();
      expect(c.canRedo.value, isTrue);
      expect(c.debugHistoryIndex, 1);

      c.addItem(tile('e', 6, 0));

      expect(c.canRedo.value, isFalse);
      expect(c.debugHistoryLength, 3);
      expect(c.debugHistoryIndex, 2);
      expect(c.layout.value.map((i) => i.id), containsAll(['a', 'b', 'c', 'e']));
    });

    test('undo / redo round-trips are stable over many cycles', () async {
      final c = build()..addItem(tile('c', 4, 0));
      final full = geometry(c.layout.value);
      final short = {...full}..remove('c');

      for (var i = 0; i < 5; i++) {
        expect(await c.undo(), isTrue);
        expect(geometry(c.layout.value), short);
        expect(await c.redo(), isTrue);
        expect(geometry(c.layout.value), full);
      }
    });

    test('undo is refused while a drag gesture is in flight', () async {
      final c = build(initialLayout: [tile('a', 0, 0), tile('b', 4, 0)])
        ..addItem(tile('c', 6, 0))
        ..onDragStart('a');

      expect(await c.undo(), isFalse);
      expect(c.layout.value.length, 3);
    });

    test('undo is refused while a resize gesture is in flight', () async {
      final c = build()
        ..addItem(tile('c', 4, 0))
        ..onResizeStart('a');

      expect(await c.undo(), isFalse);
    });

    test('redo is refused while a gesture is in flight', () async {
      final c = build()..addItem(tile('c', 4, 0));
      await c.undo();
      c.onResizeStart('a');

      expect(await c.redo(), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('History — metadata and selection', () {
    test('snapshots preserve the full `extra` metadata map', () async {
      const rich = LayoutItem(
        id: 'rich',
        x: 4,
        y: 0,
        w: 2,
        h: 1,
        extra: {
          'category': 'CPU',
          'thresholds': [1, 2, 3],
        },
      );
      final c = build()
        ..addItem(rich)
        ..removeItems(['a']);

      await c.undo();

      final restored = c.layout.value.firstWhere((i) => i.id == 'rich');
      expect(restored.extra, rich.extra);
      expect(restored.extra!['thresholds'], [1, 2, 3]);
    });

    test('undo prunes selection ids the restored layout no longer contains', () async {
      final c = build()
        ..addItem(tile('c', 4, 0))
        ..toggleSelection('c');
      expect(c.selectedItemIds.value, {'c'});

      await c.undo();

      expect(c.selectedItemIds.value, isEmpty);
      expect(c.activeItemId.value, isNull);
    });

    test('a still-valid selection survives an undo untouched', () async {
      final c = build()
        ..addItem(tile('c', 4, 0))
        ..toggleSelection('a');
      final before = c.selectedItemIds.value;

      await c.undo();

      expect(c.selectedItemIds.value, {'a'});
      expect(identical(c.selectedItemIds.value, before), isTrue);
    });

    test('an empty selection short-circuits the prune', () async {
      final c = build()..addItem(tile('c', 4, 0));

      expect(await c.undo(), isTrue);
      expect(c.selectedItemIds.value, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('History — callbacks', () {
    test('undo fires onLayoutChanged then onUndo, exactly once each', () async {
      final events = <String>[];
      final c = build(
        onLayoutChanged: (_, __) => events.add('changed'),
        onUndo: (_, __) => events.add('undo'),
        onRedo: (_, __) => events.add('redo'),
      )..addItem(tile('c', 4, 0));
      events.clear();

      await c.undo();
      expect(events, ['changed', 'undo']);

      events.clear();
      await c.redo();
      expect(events, ['changed', 'redo']);
    });

    test('onUndo receives the restored layout and the live slot count', () async {
      List<LayoutItem>? seen;
      int? seenSlots;
      final c = build(
        slots: 6,
        onUndo: (items, slots) {
          seen = items;
          seenSlots = slots;
        },
      )..addItem(tile('c', 4, 0));

      await c.undo();

      expect(seen!.map((i) => i.id), ['a', 'b']);
      expect(seenSlots, 6);
    });

    test('a vetoed operation fires no callback at all', () async {
      final events = <String>[];
      final c = build(
        onLayoutChanged: (_, __) => events.add('changed'),
        onUndo: (_, __) => events.add('undo'),
        onWillUndo: (_) => false,
      )..addItem(tile('c', 4, 0));
      events.clear();

      expect(await c.undo(), isFalse);
      expect(events, isEmpty);
    });

    test('undo works with no callbacks registered', () async {
      final c = build()..addItem(tile('c', 4, 0));

      expect(await c.undo(), isTrue);
      expect(await c.redo(), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('History — veto hooks', () {
    test('onWillUndo returning false cancels the operation entirely', () async {
      final c = build(onWillUndo: (_) => false)..addItem(tile('c', 4, 0));
      final before = geometry(c.layout.value);

      expect(await c.undo(), isFalse);
      expect(geometry(c.layout.value), before);
      expect(c.canUndo.value, isTrue);
      expect(c.canRedo.value, isFalse);
      expect(c.debugHistoryIndex, 1);
    });

    test('onWillUndo receives the candidate layout, not the live one', () async {
      List<LayoutItem>? candidate;
      final c = build(
        onWillUndo: (items) {
          candidate = items;
          return true;
        },
      )..addItem(tile('c', 4, 0));

      await c.undo();

      expect(candidate!.map((i) => i.id), ['a', 'b']);
    });

    test('an async veto approving the operation applies it', () async {
      final c = build(
        onWillUndo: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return true;
        },
      )..addItem(tile('c', 4, 0));

      expect(await c.undo(), isTrue);
      expect(c.layout.value.length, 2);
    });

    test('onWillRedo returning false cancels the redo', () async {
      final c = build(onWillRedo: (_) => false)..addItem(tile('c', 4, 0));
      await c.undo();

      expect(await c.redo(), isFalse);
      expect(c.layout.value.length, 2);
      expect(c.canRedo.value, isTrue);
    });

    test('onWillRedo receives the candidate layout', () async {
      List<LayoutItem>? candidate;
      final c = build(
        onWillRedo: (items) {
          candidate = items;
          return true;
        },
      )..addItem(tile('c', 4, 0));
      await c.undo();

      await c.redo();

      expect(candidate!.map((i) => i.id), ['a', 'b', 'c']);
    });

    test('a concurrent undo is rejected while a veto is awaited', () async {
      final c = build(
        onWillUndo: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return true;
        },
      )..addItem(tile('c', 4, 0));

      final first = c.undo();
      final second = c.undo(); // reentrancy guard

      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(c.debugHistoryIndex, 0);
    });

    test('a transaction recorded while the veto is awaited aborts the undo', () async {
      late DashboardControllerImpl self;
      final c = self = build(
        onWillUndo: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          // The world moved: this is exactly the race the re-validation
          // after the await exists for.
          self.addItem(tile('z', 6, 0));
          return true;
        },
      )..addItem(tile('c', 4, 0));

      expect(await c.undo(), isFalse);
      expect(c.layout.value.map((i) => i.id), containsAll(['a', 'b', 'c', 'z']));
    });

    test('a drag started while the veto is awaited aborts the undo', () async {
      late DashboardControllerImpl self;
      final c = self = build(
        initialLayout: [tile('a', 0, 0), tile('b', 4, 0)],
        onWillUndo: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          self.onDragStart('a');
          return true;
        },
      )..addItem(tile('c', 6, 0));

      expect(await c.undo(), isFalse);
      expect(c.layout.value.length, 3);
    });

    test('the history stack cleared while the veto is awaited aborts the undo', () async {
      late DashboardControllerImpl self;
      final c = self = build(
        onWillUndo: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          self.clearHistory();
          return true;
        },
      )..addItem(tile('c', 4, 0));

      expect(await c.undo(), isFalse);
      expect(c.layout.value.length, 3);
    });

    test('a veto that throws releases the reentrancy guard', () async {
      final c = build(
        onWillUndo: (_) => Future<bool>.error(StateError('boom')),
      )..addItem(tile('c', 4, 0));

      await expectLater(c.undo(), throwsStateError);

      // If the guard stayed latched, this second call would short-circuit to
      // `false` instead of reaching the hook again.
      await expectLater(c.undo(), throwsStateError);
      expect(c.debugHistoryIndex, 1);
    });
  });

  // -------------------------------------------------------------------------
  group('History — capacity', () {
    test('the stack never exceeds the default cap of 30 entries', () async {
      final c = build(initialLayout: [tile('a', 0, 0)]);

      for (var i = 0; i < 60; i++) {
        c.addItem(tile('n$i', 0, -1));
      }

      expect(c.debugHistoryLength, 30);
      expect(c.debugHistoryIndex, 29);

      var undos = 0;
      while (c.canUndo.value) {
        expect(await c.undo(), isTrue);
        undos++;
      }
      expect(undos, 29);
      expect(c.debugHistoryIndex, 0);
    });

    test('setMaxHistoryLength shrinks the stack and keeps the newest entries', () async {
      final c = build(initialLayout: [tile('a', 0, 0)]);
      for (var i = 0; i < 10; i++) {
        c.addItem(tile('n$i', 0, -1));
      }
      expect(c.debugHistoryLength, 11);

      c.setMaxHistoryLength(3);

      expect(c.maxHistoryLength, 3);
      expect(c.debugHistoryLength, 3);
      expect(c.debugHistoryIndex, 2);
      // The cursor entry is untouched: the live layout still has 11 items.
      expect(c.layout.value.length, 11);

      await c.undo();
      expect(c.layout.value.length, 10);
      await c.undo();
      expect(c.layout.value.length, 9);
      expect(c.canUndo.value, isFalse);
    });

    test('setMaxHistoryLength grows the cap without losing entries', () {
      final c = build(initialLayout: [tile('a', 0, 0)]);
      for (var i = 0; i < 4; i++) {
        c.addItem(tile('n$i', 0, -1));
      }

      c.setMaxHistoryLength(50);

      expect(c.maxHistoryLength, 50);
      expect(c.debugHistoryLength, 5);
      expect(c.debugHistoryIndex, 4);
    });

    test('setMaxHistoryLength drops the redo branch', () async {
      final c = build()
        ..addItem(tile('c', 4, 0))
        ..addItem(tile('d', 6, 0));
      await c.undo();
      expect(c.canRedo.value, isTrue);

      c.setMaxHistoryLength(10);

      expect(c.canRedo.value, isFalse);
      expect(c.debugHistoryLength, 2);
      expect(c.debugHistoryIndex, 1);
    });

    test('setMaxHistoryLength with the current value is a no-op', () {
      final c = build()
        ..addItem(tile('c', 4, 0))
        ..setMaxHistoryLength(kDefaultMaxHistoryLength);

      expect(c.debugHistoryLength, 2);
      expect(c.debugHistoryIndex, 1);
    });

    test('setMaxHistoryLength(1) keeps only the current state', () {
      final c = build()
        ..addItem(tile('c', 4, 0))
        ..setMaxHistoryLength(1);

      expect(c.debugHistoryLength, 1);
      expect(c.canUndo.value, isFalse);
      expect(c.layout.value.length, 3);
    });

    test('setMaxHistoryLength rejects negative lengths', () {
      final c = build();

      expect(() => c.setMaxHistoryLength(-1), throwsArgumentError);
      expect(() => c.setMaxHistoryLength(-5), throwsArgumentError);
      expect(c.maxHistoryLength, kDefaultMaxHistoryLength);
    });
  });

  // -------------------------------------------------------------------------
  group('History — disabled (maxHistoryLength: 0)', () {
    test('the constructor rejects a negative length', () {
      expect(
        () => DashboardControllerImpl(maxHistoryLength: -1),
        throwsArgumentError,
      );
    });

    test('nothing is recorded and no snapshot is retained', () {
      final c = build(maxHistoryLength: 0)
        ..addItem(tile('c', 4, 0))
        ..removeItems(['b'])
        ..optimizeLayout()
        ..updateItem('a', (i) => i.copyWith(w: 3));

      expect(c.maxHistoryLength, 0);
      expect(c.debugHistoryLength, 0);
      expect(c.debugHistoryIndex, 0);
      expect(c.canUndo.value, isFalse);
      expect(c.canRedo.value, isFalse);
    });

    test('a full drag records nothing', () {
      final c = build(
        maxHistoryLength: 0,
        initialLayout: [tile('a', 0, 0), tile('b', 4, 0)],
      )
        ..onDragStart('a')
        ..onDragUpdate(
          'a',
          const Offset(400, 0),
          slotWidth: 100,
          slotHeight: 100,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        )
        ..onDragEnd('a');

      expect(c.debugHistoryLength, 0);
      expect(c.canUndo.value, isFalse);
    });

    test('undo and redo are no-ops that return false', () async {
      final c = build(maxHistoryLength: 0)..addItem(tile('c', 4, 0));

      expect(await c.undo(), isFalse);
      expect(await c.redo(), isFalse);
      expect(c.layout.value.length, 3);
    });

    test('clearHistory is a no-op', () {
      final c = build(maxHistoryLength: 0)..clearHistory();

      expect(c.debugHistoryLength, 0);
      expect(c.layout.value.length, 2);
    });

    test('onLayoutChanged still fires normally', () {
      var calls = 0;
      build(maxHistoryLength: 0, onLayoutChanged: (_, __) => calls++).addItem(tile('c', 4, 0));

      expect(calls, 1);
    });

    test('dispose is safe with no history beacon', () {
      final c = build(maxHistoryLength: 0)..dispose();

      expect(c.layout.isDisposed, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('History — enabling and disabling at runtime', () {
    test('setMaxHistoryLength(0) drops the stack and publishes the flags', () async {
      final c = build()
        ..addItem(tile('c', 4, 0))
        ..addItem(tile('d', 6, 0));
      await c.undo();
      expect(c.canUndo.value, isTrue);
      expect(c.canRedo.value, isTrue);
      final before = geometry(c.layout.value);

      c.setMaxHistoryLength(0);

      expect(c.maxHistoryLength, 0);
      expect(c.debugHistoryLength, 0);
      expect(c.canUndo.value, isFalse);
      expect(c.canRedo.value, isFalse);
      // The layout itself is untouched.
      expect(geometry(c.layout.value), before);
      expect(await c.undo(), isFalse);
    });

    test('re-enabling starts a fresh stack seeded with the live layout', () async {
      final c = build(maxHistoryLength: 0)
        ..addItem(tile('c', 4, 0))
        ..setMaxHistoryLength(10);

      expect(c.debugHistoryLength, 1);
      expect(c.debugHistoryIndex, 0);
      expect(c.canUndo.value, isFalse);

      // Recording resumes; the pre-enable state is NOT reachable.
      c.addItem(tile('d', 6, 0));
      expect(await c.undo(), isTrue);
      expect(c.layout.value.map((i) => i.id), ['a', 'b', 'c']);
      expect(c.canUndo.value, isFalse);
    });

    test('setMaxHistoryLength(0) twice is a no-op the second time', () {
      final c = build(maxHistoryLength: 0)..setMaxHistoryLength(0);

      expect(c.debugHistoryLength, 0);
    });

    test('disabling while a veto is awaited aborts the undo', () async {
      late DashboardControllerImpl self;
      final c = self = build(
        onWillUndo: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          self.setMaxHistoryLength(0);
          return true;
        },
      )..addItem(tile('c', 4, 0));

      expect(await c.undo(), isFalse);
      expect(c.layout.value.length, 3);
    });

    test('a trim under an unchanged cursor aborts the undo', () async {
      // At capacity the cursor stays pinned at `maxHistoryLength - 1` while
      // every entry shifts down by one, so the cursor check alone would let a
      // stale candidate through. Only comparing the entry itself catches it.
      late DashboardControllerImpl self;
      final c = self = build(
        maxHistoryLength: 3,
        initialLayout: [tile('a', 0, 0)],
        onWillUndo: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          self.addItem(tile('shift', 0, -1));
          return true;
        },
      )
        // Fill the stack to capacity: seed + 2 transactions.
        ..addItem(tile('n0', 0, -1))
        ..addItem(tile('n1', 0, -1));
      expect(c.debugHistoryLength, 3);
      expect(c.debugHistoryIndex, 2);

      expect(await c.undo(), isFalse);
      // The cursor never moved back, and the trim kept it pinned.
      expect(c.debugHistoryIndex, 2);
      expect(c.layout.value.map((i) => i.id), containsAll(['n0', 'n1', 'shift']));
    });
  });

  // -------------------------------------------------------------------------
  group('History — clearHistory', () {
    test('clearHistory resets the flags without touching the layout', () async {
      final c = build()..addItem(tile('c', 4, 0));
      await c.undo();
      expect(c.canUndo.value, isFalse);
      expect(c.canRedo.value, isTrue);
      final before = geometry(c.layout.value);

      c.clearHistory();

      expect(c.canUndo.value, isFalse);
      expect(c.canRedo.value, isFalse);
      expect(c.debugHistoryLength, 1);
      expect(c.debugHistoryIndex, 0);
      expect(geometry(c.layout.value), before);
    });

    test('recording resumes normally after clearHistory', () async {
      final c = build()
        ..addItem(tile('c', 4, 0))
        ..clearHistory()
        ..addItem(tile('d', 6, 0));

      expect(c.debugHistoryLength, 2);
      expect(await c.undo(), isTrue);
      expect(c.layout.value.map((i) => i.id), ['a', 'b', 'c']);
    });
  });

  // -------------------------------------------------------------------------
  group('History — slot-count mismatch', () {
    test('a snapshot taken under more columns is re-projected on restore', () async {
      final c = build(
        slots: 12,
        initialLayout: [tile('a', 0, 0), tile('wide', 8, 0, w: 4)],
      )
        ..addItem(tile('c', 0, 4))

        // Breakpoint change: not a history boundary, but the snapshot recorded
        // above still refers to 12 columns.
        ..setSlotCount(4);

      expect(await c.undo(), isTrue);

      // Every restored item must be inside the 4-column grid.
      for (final item in c.layout.value) {
        expect(item.x, greaterThanOrEqualTo(0));
        expect(item.x + item.w, lessThanOrEqualTo(4));
      }
      expect(c.layout.value.map((i) => i.id), ['a', 'wide']);
    });

    test(
        'an undo across a breakpoint also corrects the archived layout of the '
        'breakpoint the action happened in', () async {
      // Regression: the responsive cache (`_layoutsBySlotCount`) is replayed
      // when the grid returns to a column count it already visited. It used to
      // still hold the state the undo had just reverted, so resizing the
      // window back silently re-applied it — the undo undid itself.
      final c = build(
        slots: 8,
        initialLayout: [tile('a', 0, 0), tile('mem', 2, 0)],
      )

        // 1. Move `mem` from x=2 to x=6 at 8 columns.
        ..updateItem('mem', (i) => i.copyWith(x: 6));
      expect(c.layout.value.firstWhere((i) => i.id == 'mem').x, 6);

      // 2. Shrink: archives the 8-column layout with mem at x=6.
      c.setSlotCount(6);

      // 3. Undo: projected onto 6 columns.
      expect(await c.undo(), isTrue);
      expect(c.layout.value.firstWhere((i) => i.id == 'mem').x, 2);

      // 4. Back to 8 columns: the archive must reflect the undo, not the
      //    state it reverted.
      c.setSlotCount(8);
      expect(c.layout.value.firstWhere((i) => i.id == 'mem').x, 2);
    });

    test('a redo across a breakpoint corrects the archive symmetrically', () async {
      final c = build(
        slots: 8,
        initialLayout: [tile('a', 0, 0), tile('mem', 2, 0)],
      )
        ..updateItem('mem', (i) => i.copyWith(x: 6))
        ..setSlotCount(6);
      await c.undo();
      expect(await c.redo(), isTrue);

      c.setSlotCount(8);
      expect(c.layout.value.firstWhere((i) => i.id == 'mem').x, 6);
    });

    test('an exact restore does not recompact', () async {
      // compactionType.none proves the point: a recompaction would pull the
      // free-floating item back to the top.
      final c = build(
        initialLayout: [tile('a', 0, 0), tile('free', 0, 5)],
      )
        ..setCompactionType(engine.CompactType.none)
        ..clearHistory()
        ..addItem(tile('c', 4, 0));
      await c.undo();

      final free = c.layout.value.firstWhere((i) => i.id == 'free');
      expect(free.y, 5);
    });
  });

  // -------------------------------------------------------------------------
  group('History — lifecycle', () {
    test('dispose releases the history beacon', () {
      final c = build()
        ..addItem(tile('c', 4, 0))
        ..dispose();

      expect(c.canUndo.isDisposed, isTrue);
      expect(c.canRedo.isDisposed, isTrue);
    });

    test('canUndo is a reactive beacon, not a snapshot getter', () {
      final c = build();
      final seen = <bool>[];
      final sub = Beacon.effect(() => seen.add(c.canUndo.value));
      BeaconScheduler.flush();

      c.addItem(tile('c', 4, 0));
      BeaconScheduler.flush();

      expect(seen, [false, true]);
      sub();
    });

    test('assert in _syncHistoryFlags throws when bookkeeping desynchronises', () {
      final c = build()..addItem(tile('c', 4, 0));
      expect(
        () => c.debugForceDesyncHistoryIndex(-1),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
