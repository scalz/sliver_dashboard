import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart' as engine;

/// Overrides an unrelated rule only: isSizeAllowed keeps its default.
class _DragOnly extends DashboardPolicy {
  const _DragOnly();

  @override
  bool canDrag(LayoutItem item) => true;
}

class _SquaresOnly extends DashboardPolicy {
  const _SquaresOnly();

  @override
  bool isSizeAllowed(LayoutItem item, int w, int h) => w == h;
}

void main() {
  // 4 columns: a 2x2 at the origin and a static 1x1 at (3, 0).
  const layout = [
    LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
    LayoutItem(id: 's', x: 3, y: 0, w: 1, h: 1, isStatic: true),
  ];

  bool fits(
    LayoutItem c, {
    int cols = 4,
    int? maxRows,
    bool horizontal = false,
    bool Function(int, int)? allowed,
  }) =>
      engine.canPlace(
        layout,
        c,
        cols: cols,
        maxRows: maxRows,
        horizontal: horizontal,
        isSizeAllowed: allowed,
      );

  group('engine.canPlace', () {
    test('free spot fits, overlap does not, static overlap does not', () {
      expect(fits(const LayoutItem(id: 'n', x: 2, y: 1, w: 2, h: 1)), isTrue);
      expect(fits(const LayoutItem(id: 'n', x: 1, y: 1, w: 2, h: 1)), isFalse);
      expect(fits(const LayoutItem(id: 'n', x: 3, y: 0, w: 1, h: 1)), isFalse);
    });

    test('touching edges is not an overlap', () {
      expect(fits(const LayoutItem(id: 'n', x: 2, y: 0, w: 1, h: 2)), isTrue);
      expect(fits(const LayoutItem(id: 'n', x: 0, y: 2, w: 2, h: 1)), isTrue);
    });

    test('the entry sharing the candidate id is not an obstacle', () {
      // "a" moved one row down overlaps its own old cells only.
      expect(fits(const LayoutItem(id: 'a', x: 0, y: 1, w: 2, h: 2)), isTrue);
      // ...but still collides with the static once widened to it.
      expect(fits(const LayoutItem(id: 'a', x: 0, y: 0, w: 4, h: 2)), isFalse);
    });

    test('cross-axis bounds: cols bounds x on a vertical grid', () {
      expect(fits(const LayoutItem(id: 'n', x: 2, y: 2, w: 2, h: 1)), isTrue);
      expect(fits(const LayoutItem(id: 'n', x: 3, y: 2, w: 2, h: 1)), isFalse);
      expect(fits(const LayoutItem(id: 'n', x: -1, y: 2, w: 1, h: 1)), isFalse);
      expect(fits(const LayoutItem(id: 'n', x: 0, y: -1, w: 1, h: 1)), isFalse);
    });

    test('maxRows bounds the main axis (y on a vertical grid)', () {
      const c = LayoutItem(id: 'n', x: 0, y: 2, w: 1, h: 2);
      expect(fits(c, maxRows: 4), isTrue);
      expect(fits(c, maxRows: 3), isFalse);
      expect(fits(c), isTrue); // unbounded
    });

    test('horizontal grid: cols bounds y, maxRows bounds x', () {
      // Deep along x is fine without maxRows, as long as y stays under cols.
      const deep = LayoutItem(id: 'n', x: 10, y: 3, w: 3, h: 1);
      expect(fits(deep, horizontal: true), isTrue);
      expect(fits(deep, horizontal: true, maxRows: 13), isTrue);
      expect(fits(deep, horizontal: true, maxRows: 12), isFalse);
      // y + h past cols is out of the grid on a horizontal grid.
      expect(
        fits(const LayoutItem(id: 'n', x: 10, y: 3, w: 1, h: 2), horizontal: true),
        isFalse,
      );
      // Same candidate is fine on a vertical grid, where cols bounds x.
      expect(fits(const LayoutItem(id: 'n', x: 0, y: 3, w: 1, h: 2)), isTrue);
    });

    test('own min/max constraints and degenerate sizes', () {
      expect(fits(const LayoutItem(id: 'n', x: 0, y: 2, w: 1, h: 1, minW: 2)), isFalse);
      expect(fits(const LayoutItem(id: 'n', x: 0, y: 2, w: 3, h: 1, maxW: 2)), isFalse);
      expect(fits(const LayoutItem(id: 'n', x: 0, y: 2, w: 1, h: 3, maxH: 2)), isFalse);
      expect(fits(const LayoutItem(id: 'n', x: 0, y: 2, w: 0, h: 1)), isFalse);
    });

    test('isSizeAllowed refuses a size, but never the item own size', () {
      bool squares(int w, int h) => w == h;
      expect(fits(const LayoutItem(id: 'n', x: 0, y: 2, w: 2, h: 1), allowed: squares), isFalse);
      expect(fits(const LayoutItem(id: 'n', x: 0, y: 2, w: 2, h: 2), allowed: squares), isTrue);

      // "a" is 2x2; a policy allowing only 1x1 still lets it move as it is.
      bool unitOnly(int w, int h) => w == 1 && h == 1;
      expect(
        fits(const LayoutItem(id: 'a', x: 0, y: 3, w: 2, h: 2), allowed: unitOnly),
        isTrue,
      );
      // ...but not resize to another refused size.
      expect(
        fits(const LayoutItem(id: 'a', x: 0, y: 3, w: 2, h: 1), allowed: unitOnly),
        isFalse,
      );
    });

    test('isSizeAllowed is not consulted for a geometric refusal', () {
      var calls = 0;
      bool counting(int w, int h) {
        calls++;
        return true;
      }

      fits(const LayoutItem(id: 'n', x: 1, y: 1, w: 2, h: 1), allowed: counting);
      fits(const LayoutItem(id: 'n', x: 3, y: 2, w: 2, h: 1), allowed: counting);
      expect(calls, 0);
      fits(const LayoutItem(id: 'n', x: 2, y: 2, w: 2, h: 1), allowed: counting);
      expect(calls, 1);
    });
  });

  group('DashboardController.canPlace', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(initialSlotCount: 4, initialLayout: layout);
    });

    tearDown(() => controller.dispose());

    test('reads slotCount, maxRows and the policy', () {
      const c = LayoutItem(id: 'n', x: 0, y: 2, w: 2, h: 1);
      expect(controller.canPlace(c), isTrue);

      controller.setMaxRows(2);
      expect(controller.canPlace(c), isFalse);
      controller
        ..setMaxRows(null)
        ..policy = const _SquaresOnly();
      expect(controller.canPlace(c), isFalse);
      expect(controller.canPlace(c.copyWith(h: 2)), isTrue);
    });

    test('a policy that does not override isSizeAllowed allows every size', () {
      controller.policy = const _DragOnly();
      expect(controller.canPlace(const LayoutItem(id: 'n', x: 0, y: 2, w: 3, h: 1)), isTrue);
    });

    test('follows the scroll direction', () {
      // Fits only when cols bounds y (horizontal grid): x = 6 is past 4 columns.
      const c = LayoutItem(id: 'n', x: 6, y: 0, w: 1, h: 1);
      expect(controller.canPlace(c), isFalse);
      controller.scrollDirection.value = Axis.horizontal;
      expect(controller.canPlace(c), isTrue);
    });

    test('is a pure query: no layout change, no event', () {
      var events = 0;
      final c = DashboardController(
        initialSlotCount: 4,
        initialLayout: layout,
        onLayoutChanged: (_, __) => events++,
      );
      addTearDown(c.dispose);
      final before = c.layout.value;
      c
        ..canPlace(const LayoutItem(id: 'n', x: 1, y: 1, w: 2, h: 1))
        ..canPlace(const LayoutItem(id: 'n', x: 2, y: 2, w: 2, h: 1));
      expect(identical(c.layout.value, before), isTrue);
      expect(events, 0);
    });
  });
}
