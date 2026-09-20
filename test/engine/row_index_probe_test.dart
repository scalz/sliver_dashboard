import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/src/engine/layout_engine.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';

/// A deterministic dense grid of uniform tiles.
List<LayoutItem> _uniform(int n, int cols, {int w = 2, int h = 2}) {
  final perRow = cols ~/ w;
  return List<LayoutItem>.generate(
    n,
    (i) => LayoutItem(
      id: 'i${i.toString().padLeft(6, '0')}',
      x: (i % perRow) * w,
      y: (i ~/ perRow) * h,
      w: w,
      h: h,
    ),
  );
}

/// The same grid with full-width banners interleaved.
List<LayoutItem> _withBanners(int n, int cols, {int every = 100, int bannerH = 16}) {
  const w = 2;
  const h = 2;
  final items = <LayoutItem>[];
  var y = 0;
  var x = 0;
  for (var i = 0; i < n; i++) {
    if (i > 0 && i % every == 0) {
      if (x != 0) {
        y += h;
        x = 0;
      }
      items.add(
        LayoutItem(id: 'ban${i.toString().padLeft(6, '0')}', x: 0, y: y, w: cols, h: bannerH),
      );
      y += bannerH;
    }
    if (x + w > cols) {
      x = 0;
      y += h;
    }
    items.add(LayoutItem(id: 'i${i.toString().padLeft(6, '0')}', x: x, y: y, w: w, h: h));
    x += w;
  }
  return items;
}

/// Rows walked per probe during one `moveElement` cell crossing.
double _rowsPerProbe(List<LayoutItem> layout, int cols) {
  debugResetRowIndexCounters();
  final item = layout[layout.length ~/ 2];
  moveElement(
    layout,
    item,
    item.x,
    item.y + 1,
    cols: cols,
    compactType: CompactType.vertical,
    preventCollision: true,
    force: true,
  );
  expect(debugRowIndexQueries, greaterThan(0), reason: 'asserts must be on for the counters');
  return debugRowIndexRowVisits / debugRowIndexQueries;
}

void main() {
  const cols = 12;

  // Reset in setUp, not only tearDown: a value left over by another test
  // turns the exact asymmetry this suite hunts into a passing assertion (§1).
  setUp(debugResetRowIndexCounters);
  tearDown(debugResetRowIndexCounters);

  group('_RowIndex probe counters', () {
    test('reset clears both counters', () {
      _rowsPerProbe(_uniform(200, cols), cols);
      expect(debugRowIndexQueries, greaterThan(0));

      debugResetRowIndexCounters();

      expect(debugRowIndexQueries, 0);
      expect(debugRowIndexRowVisits, 0);
    });

    test('a probe always walks at least one row per query', () {
      final ratio = _rowsPerProbe(_uniform(500, cols), cols);
      expect(ratio, greaterThanOrEqualTo(1.0));
    });

    // THE gate for span indexing: the scan range must be a property of the
    // PROBE, never of the layout.
    //
    // Under the previous top-row bucketing a probe started `maxHeight - 1`
    // rows above its own box, in case the tallest item anywhere reached down
    // into it — so a single 16-row banner widened every probe in the grid,
    // including probes nowhere near it: 2.07 rows/probe uniform against 6.65
    // with banners, and a cell crossing costing 2.2 ms against 8.9 ms on
    // dart2js at N=1000. Both fixtures now sit at ~2.0-2.1.
    //
    // Reintroducing a layout-wide lower bound makes this fail. Do not
    // "relax" the factor to make it pass.
    test('the scan range follows the probe, not the tallest tile in the layout', () {
      final uniformRatio = _rowsPerProbe(_uniform(1000, cols), cols);
      final bannerRatio = _rowsPerProbe(_withBanners(1000, cols), cols);

      expect(
        bannerRatio,
        lessThan(uniformRatio * 1.5),
        reason: 'a tall tile elsewhere in the layout must not widen an unrelated probe',
      );
      expect(
        bannerRatio,
        lessThan(4),
        reason: 'a 2-row probe walks ~2 rows whatever else the layout contains',
      );
    });
  });
}
