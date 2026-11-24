import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart' as engine;

// Gesture sequences read better unchained.
// ignore_for_file: cascade_invocations

const double _slot = 100;

/// 4 columns, maxRows 3. The left half is a full column of three 2x1 tiles;
/// `x` sits alone on the right. Dropping `x` on the left pushes the column
/// one row down, i.e. `c` to row 3: past the ceiling.
const _board = [
  LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1),
  LayoutItem(id: 'b', x: 0, y: 1, w: 2, h: 1),
  LayoutItem(id: 'c', x: 0, y: 2, w: 2, h: 1),
  LayoutItem(id: 'x', x: 2, y: 0, w: 2, h: 1),
];

DashboardControllerImpl _build({
  bool strict = true,
  List<LayoutItem> layout = _board,
  Axis axis = Axis.vertical,
  int maxRows = 3,
  void Function()? onChange,
}) {
  final c = DashboardController(
    initialSlotCount: 4,
    initialLayout: layout,
    onLayoutChanged: onChange == null ? null : (_, __) => onChange(),
  ) as DashboardControllerImpl;
  c
    ..scrollDirection.value = axis
    ..setCompactionType(CompactType.none)
    ..setMaxRows(maxRows)
    ..setStrictMaxRows(strict);
  addTearDown(c.dispose);
  return c;
}

void _drag(DashboardControllerImpl c, String id, Offset content) => c.onDragUpdate(
      id,
      content,
      slotWidth: _slot,
      slotHeight: _slot,
      mainAxisSpacing: 0,
      crossAxisSpacing: 0,
    );

LayoutItem _item(DashboardControllerImpl c, String id) =>
    c.layout.value.firstWhere((i) => i.id == id);

int _extent(List<LayoutItem> l, {bool horizontal = false}) =>
    engine.mainAxisExtent(l, horizontal: horizontal);

void main() {
  group('drag', () {
    test('a push past the ceiling is refused, the last accepted layout stays', () {
      final c = _build();
      c.onDragStart('x');
      _drag(c, 'x', const Offset(200, 100)); // (2,1): free, accepted
      expect((_item(c, 'x').x, _item(c, 'x').y), (2, 1));

      _drag(c, 'x', Offset.zero); // (0,0): would push c to row 3
      expect((_item(c, 'x').x, _item(c, 'x').y), (2, 1), reason: 'last accepted cell');
      expect(_extent(c.layout.value), lessThanOrEqualTo(3));

      // The drag offset follows the pointer from the last accepted cell.
      expect(c.dragOffset.value, const Offset(-200, -100));
    });

    test('the same push is accepted without strictMaxRows (2.10 behaviour)', () {
      final c = _build(strict: false);
      c.onDragStart('x');
      _drag(c, 'x', Offset.zero);
      expect((_item(c, 'x').x, _item(c, 'x').y), (0, 0));
      expect(_extent(c.layout.value), 4);
    });

    test('a refused cell becomes accepted again once the pointer leaves it', () {
      final c = _build();
      c.onDragStart('x');
      _drag(c, 'x', Offset.zero);
      _drag(c, 'x', const Offset(200, 200)); // (2,2): free
      expect((_item(c, 'x').x, _item(c, 'x').y), (2, 2));
    });

    test('drop after a refusal commits the last accepted layout', () {
      var events = 0;
      final c = _build(onChange: () => events++);
      events = 0; // _build's setCompactionType emits once
      c.onDragStart('x');
      _drag(c, 'x', const Offset(200, 200));
      _drag(c, 'x', Offset.zero);
      c.onDragEnd('x');
      expect((_item(c, 'x').x, _item(c, 'x').y), (2, 2));
      expect(_extent(c.layout.value), lessThanOrEqualTo(3));
      expect(events, 1);
    });

    test('a layout already past the ceiling may move but not grow', () {
      // c already ends at row 4 > 3.
      final c = _build(
        layout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1),
          LayoutItem(id: 'b', x: 0, y: 1, w: 2, h: 1),
          LayoutItem(id: 'c', x: 0, y: 3, w: 2, h: 1),
          LayoutItem(id: 'x', x: 2, y: 0, w: 2, h: 1),
        ],
      );
      c.onDragStart('x');
      _drag(c, 'x', const Offset(200, 100)); // free cell, extent stays 4
      expect((_item(c, 'x').x, _item(c, 'x').y), (2, 1));
      c.onDragEnd('x');

      c.onDragStart('x');
      _drag(c, 'x', Offset.zero); // pushes a, b: b to row 2, no growth past 4
      expect(_extent(c.layout.value), 4);
    });

    // Both axes, the three compaction modes, random drags: with the ceiling
    // on, no accepted layout ever ends past it. The same drags without the
    // ceiling must cross it at least once, or the test proves nothing.
    for (final axis in Axis.values) {
      for (final mode in CompactType.values) {
        test('fuzz: $axis, $mode', () {
          final rnd = Random(7);
          final horizontal = axis == Axis.horizontal;
          var crossedWithout = false;
          for (var run = 0; run < 40; run++) {
            // A full-ish board: 4 cross slots, maxRows 3.
            final layout = <LayoutItem>[
              for (var i = 0; i < 6; i++)
                () {
                  final main = rnd.nextInt(3);
                  final cross = rnd.nextInt(3);
                  return horizontal
                      ? LayoutItem(id: 'i$i', x: main, y: cross, w: 1, h: 1)
                      : LayoutItem(id: 'i$i', x: cross, y: main, w: 1, h: 1);
                }(),
            ];
            final clean = engine.compact(layout, CompactType.none, 4);
            if (_extent(clean, horizontal: horizontal) > 3) continue;
            for (final strict in [true, false]) {
              final c = _build(strict: strict, layout: clean, axis: axis, maxRows: 3)
                ..setCompactionType(mode);
              if (_extent(c.layout.value, horizontal: horizontal) > 3) continue;
              final id = clean[rnd.nextInt(clean.length)].id;
              c.onDragStart(id);
              for (var step = 0; step < 6; step++) {
                _drag(c, id, Offset(rnd.nextInt(4) * _slot, rnd.nextInt(4) * _slot));
                final ext = _extent(c.layout.value, horizontal: horizontal);
                if (strict) {
                  expect(ext, lessThanOrEqualTo(3), reason: 'run $run step $step');
                } else if (ext > 3) {
                  crossedWithout = true;
                }
              }
              c.onDragEnd(id);
              if (strict) {
                expect(_extent(c.layout.value, horizontal: horizontal), lessThanOrEqualTo(3));
              }
            }
          }
          if (!horizontal) {
            // Reason: on a horizontal grid the engine pushes along the cross
            // axis, so a push never reaches the main-axis ceiling there; only
            // the strict assertions above apply.
            expect(crossedWithout, isTrue, reason: 'fixture never crossed the ceiling');
          }
        });
      }
    }
  });

  test('the ceiling is measured along the main axis of each direction', () {
    // A 1x4 tile: one cross slot wide on a vertical grid, a full column on a
    // horizontal one. With maxRows 1, first-fit finds room next to it only
    // on the vertical grid (whose layout already exceeds the cap and does not
    // grow); on the horizontal grid the 1x1 must go past the ceiling.
    const tall = [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 4)];
    const tile = LayoutItem(id: 'n', x: -1, y: -1, w: 1, h: 1);
    expect(
      _build(layout: tall, maxRows: 1).tryAddItem(tile, strategy: AutoPlacementStrategy.firstFit),
      isTrue,
    );
    expect(
      _build(layout: tall, maxRows: 1, axis: Axis.horizontal)
          .tryAddItem(tile, strategy: AutoPlacementStrategy.firstFit),
      isFalse,
    );
  });

  group('resize', () {
    void resize(DashboardControllerImpl c, ResizeHandle h, Offset d) => c.onResizeUpdate(
          'x',
          h,
          d,
          slotWidth: _slot,
          slotHeight: _slot,
          crossAxisSpacing: 0,
          mainAxisSpacing: 0,
        );

    test('a resize whose push would cross the ceiling is refused', () {
      // x grows left over the column: the push sends c to row 3.
      final c = _build(
        layout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1),
          LayoutItem(id: 'b', x: 0, y: 1, w: 2, h: 1),
          LayoutItem(id: 'c', x: 0, y: 2, w: 2, h: 1),
          LayoutItem(id: 'x', x: 2, y: 0, w: 1, h: 1),
        ],
      );
      c.onResizeStart('x');
      resize(c, ResizeHandle.right, const Offset(100, 0)); // 2 wide, free
      expect(_item(c, 'x').w, 2);
      resize(c, ResizeHandle.left, const Offset(-200, 0)); // over the column
      expect(_extent(c.layout.value), lessThanOrEqualTo(3));
      expect(_item(c, 'x').x, 2);
    });
  });

  group('external / cross-grid placeholder', () {
    test('a refused hover shows no placeholder and the drop is a no-op', () {
      final c = _build();
      c.showPlaceholder(x: 0, y: 0, w: 2, h: 1);
      expect(c.placeholder.value, isNull);
      expect(c.layout.value, _board);
      final dropped = c.onDropExternalItem(
        template: const LayoutItem(id: 'n', x: 0, y: 0, w: 2, h: 1),
      );
      expect(dropped, isNull);
      expect(c.layout.value.any((i) => i.id == 'n'), isFalse);
      expect(c.originalLayoutOnStart.value, isEmpty, reason: 'no snapshot leaked');
    });

    test('a refused hover keeps the last accepted placeholder', () {
      final c = _build(
        layout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1),
          LayoutItem(id: 'b', x: 0, y: 1, w: 2, h: 1),
          LayoutItem(id: 'c', x: 0, y: 2, w: 2, h: 1),
        ],
      );
      c.showPlaceholder(x: 2, y: 1, w: 2, h: 1); // free
      expect(c.placeholder.value?.y, 1);
      c.showPlaceholder(x: 0, y: 0, w: 2, h: 1); // refused
      expect((c.placeholder.value?.x, c.placeholder.value?.y), (2, 1));
      final placed =
          c.onDropExternalItem(template: const LayoutItem(id: 'n', x: 0, y: 0, w: 2, h: 1));
      expect((placed?.x, placed?.y), (2, 1));
      expect(_extent(c.layout.value), lessThanOrEqualTo(3));
    });

    test('hidePlaceholder starts a new hover episode', () {
      final c = _build();
      c.showPlaceholder(x: 0, y: 0, w: 2, h: 1); // refused, cached
      c
        ..hidePlaceholder()
        ..setStrictMaxRows(false)
        ..showPlaceholder(x: 0, y: 0, w: 2, h: 1);
      expect(c.placeholder.value, isNotNull, reason: 'the refusal cache was cleared');
    });
  });

  group('tryAddItems', () {
    test('adds when everything fits', () {
      var events = 0;
      final c = _build(onChange: () => events++);
      events = 0; // _build's setCompactionType emits once
      expect(c.tryAddItem(const LayoutItem(id: 'n', x: 2, y: 1, w: 2, h: 2)), isTrue);
      expect(c.layout.value.any((i) => i.id == 'n'), isTrue);
      expect(events, 1);
    });

    test('refuses without any change when an item would cross the ceiling', () {
      var events = 0;
      final c = _build(onChange: () => events++);
      events = 0; // _build's setCompactionType emits once
      final before = c.layout.value;
      // Auto-placement: no 2x3 room under the ceiling, falls back past it.
      expect(c.tryAddItem(const LayoutItem(id: 'n', x: -1, y: -1, w: 2, h: 3)), isFalse);
      expect(identical(c.layout.value, before), isTrue);
      expect(events, 0);
      expect(c.canUndo.value, isFalse);
    });

    test('is all-or-nothing', () {
      final c = _build();
      final ok = c.tryAddItems(const [
        LayoutItem(id: 'n1', x: 2, y: 1, w: 2, h: 1), // fits
        LayoutItem(id: 'n2', x: -1, y: -1, w: 4, h: 1), // no room
      ]);
      expect(ok, isFalse);
      expect(c.layout.value.map((i) => i.id), isNot(contains('n1')));
    });

    test('ignores strictMaxRows: maxRows alone is the contract', () {
      final c = _build(strict: false);
      expect(c.tryAddItem(const LayoutItem(id: 'n', x: -1, y: -1, w: 2, h: 3)), isFalse);
    });

    test('no maxRows: always adds', () {
      final c = DashboardController(initialSlotCount: 4, initialLayout: _board);
      addTearDown(c.dispose);
      expect(c.tryAddItem(const LayoutItem(id: 'n', x: -1, y: -1, w: 4, h: 9)), isTrue);
    });

    test('addItem keeps its 2.10 overflow behaviour', () {
      final c = _build();
      c.addItem(const LayoutItem(id: 'n', x: -1, y: -1, w: 2, h: 3));
      expect(c.layout.value.any((i) => i.id == 'n'), isTrue);
      expect(_extent(c.layout.value), greaterThan(3));
    });
  });
}
