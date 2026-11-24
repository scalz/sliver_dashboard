import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart' as engine;

/// On a horizontally scrolling grid `x` runs along the MAIN axis (unbounded,
/// capped by `maxRows`) and `y` along the CROSS axis (bounded by the slot
/// count) — the convention of the drag clamps, `setItemSize` and `canPlace`.
/// Every path that sanitizes or places items must follow it.
void main() {
  DashboardController horizontal({
    int slots = 4,
    int? maxRows,
    List<LayoutItem> layout = const [],
  }) {
    final c = DashboardController(initialSlotCount: slots, initialLayout: layout)
      ..scrollDirection.value = Axis.horizontal
      ..setCompactionType(CompactType.none)
      ..setMaxRows(maxRows);
    addTearDown(c.dispose);
    return c;
  }

  bool insideHorizontal(LayoutItem i, {required int slots, int? maxRows}) =>
      i.x >= 0 && i.y >= 0 && i.y + i.h <= slots && (maxRows == null || i.x + i.w <= maxRows);

  group('horizontal grid', () {
    test('importLayout keeps an item deep along x', () {
      final c = horizontal()
        ..importLayout([const LayoutItem(id: 'a', x: 9, y: 1, w: 2, h: 1).toMap()]);
      final a = c.layout.value.single;
      expect((a.x, a.y), (9, 1), reason: 'x is the unbounded main axis');
    });

    test('importLayout pulls an item back inside the cross axis (y)', () {
      final c = horizontal()
        ..importLayout([const LayoutItem(id: 'a', x: 0, y: 3, w: 1, h: 2).toMap()]);
      final a = c.layout.value.single;
      expect(a.y + a.h, lessThanOrEqualTo(4));
    });

    test('addItems with explicit coordinates keeps x and bounds y', () {
      final c = horizontal(maxRows: 12)
        ..addItems(const [
          LayoutItem(id: 'a', x: 9, y: 0, w: 2, h: 1),
          LayoutItem(id: 'b', x: 0, y: 3, w: 1, h: 3),
        ]);
      for (final i in c.layout.value) {
        expect(insideHorizontal(i, slots: 4, maxRows: 12), isTrue, reason: '$i');
      }
      expect(c.layout.value.firstWhere((i) => i.id == 'a').x, 9);
    });

    test('auto-placement stays inside the cross axis and under maxRows', () {
      final c = horizontal(
        maxRows: 6,
        layout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 4)],
      )..addItems(const [
          LayoutItem(id: 'n1', x: -1, y: -1, w: 2, h: 2),
          LayoutItem(id: 'n2', x: -1, y: -1, w: 1, h: 4),
        ]);
      for (final i in c.layout.value) {
        expect(insideHorizontal(i, slots: 4, maxRows: 6), isTrue, reason: '$i');
      }
    });

    test('explicit coordinates past maxRows are pulled back along x', () {
      final c = horizontal(maxRows: 3);
      expect(c.tryAddItem(const LayoutItem(id: 'a', x: 5, y: 0, w: 1, h: 1)), isTrue);
      expect(c.layout.value.single.x, 2, reason: 'sanitized inside the ceiling');
    });

    test('tryAddItem refuses when auto-placement must go past maxRows', () {
      // Column 0 is full (h = slot count): a 1x1 has no room under maxRows 1.
      final full =
          horizontal(maxRows: 1, layout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 4)]);
      expect(full.tryAddItem(const LayoutItem(id: 'n', x: -1, y: -1, w: 1, h: 1)), isFalse);

      final roomy =
          horizontal(maxRows: 2, layout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 4)]);
      expect(roomy.tryAddItem(const LayoutItem(id: 'n', x: -1, y: -1, w: 1, h: 1)), isTrue);
      expect(roomy.layout.value.firstWhere((i) => i.id == 'n').x, 1);
    });
  });

  test('transposeItem is an involution and swaps every axis-bound field', () {
    const item = LayoutItem(id: 'a', x: 1, y: 2, w: 3, h: 4, minW: 2, minH: 3, maxW: 5, maxH: 6);
    final t = engine.transposeItem(item);
    expect((t.x, t.y, t.w, t.h, t.minW, t.minH, t.maxW, t.maxH), (2, 1, 4, 3, 3, 2, 6.0, 5.0));
    expect(engine.transposeItem(t), item);
  });

  group('vertical grid (unchanged)', () {
    test('importLayout still bounds x and keeps y', () {
      final c = DashboardController(initialSlotCount: 4)..setCompactionType(CompactType.none);
      addTearDown(c.dispose);
      c.importLayout([const LayoutItem(id: 'a', x: 3, y: 9, w: 2, h: 1).toMap()]);
      final a = c.layout.value.single;
      expect((a.x, a.y), (2, 9));
    });
  });
}
