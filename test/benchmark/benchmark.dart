// Dart only benchmark
// ignore_for_file: avoid_print
import 'dart:math';
import 'dart:typed_data';

// Import your package files
import 'package:sliver_dashboard/src/engine/layout_engine.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';

// ============================================================================
// GENERATORS
// ============================================================================

List<LayoutItem> generateLayout(int n, int cols) {
  final items = <LayoutItem>[];
  for (var i = 0; i < n; i++) {
    items.add(
      LayoutItem(
        id: '$i',
        x: (i * 2) % cols,
        y: (i * 2) ~/ cols * 2,
        w: 2,
        h: 2,
      ),
    );
  }
  return items;
}

/// Deep, heavily-overlapping layout (y scattered over [0, n)).
/// NOTE: with cols=12, x-space (~10 values) is far denser than y-space
/// (n values) — horizontal compaction sees massive overlap here while
/// vertical mostly does not. Keep that asymmetry in mind when reading
/// Vertical-vs-Horizontal numbers on this input.
List<LayoutItem> generateMessyLayout(int n, int cols) {
  final random = Random(42); // Fixed seed for reproducibility
  final items = <LayoutItem>[];
  for (var i = 0; i < n; i++) {
    items.add(
      LayoutItem(
        id: '$i',
        x: random.nextInt(cols - 2),
        y: random.nextInt(n), // Very scattered vertically
        w: 1 + random.nextInt(3),
        h: 1 + random.nextInt(3),
      ),
    );
  }
  return items;
}

/// The COMMON interactive case: an already-compacted dense grid.
/// Every drag/resize pointer event compacts a layout of this shape, so
/// regressions here hit every user gesture even when "deep" numbers improve.
List<LayoutItem> generateCompactLayout(int n, int cols) {
  return compact(generateMessyLayout(n, cols), CompactType.vertical, cols);
}

/// A deterministic dense grid of uniform tiles — no RNG, so the collision
/// structure a probe meets is a known function of `n`.
///
/// The randomized generators above are fine for throughput of a whole
/// compaction, but NOT as a baseline to compare two revisions of the
/// collision index: which tile ends up where, and whether a given move even
/// collides, changes with `n`. That is why `resizeItem push at top` reads
/// 987 µs at n=500 and 106 µs at n=2000 — the shape, not the algorithm.
List<LayoutItem> generateUniformLayout(int n, int cols, {int w = 2, int h = 2}) {
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

/// The same dense grid with full-width banners interleaved.
///
/// This is the shape the CURRENT index is worst at, and the only shape on
/// which the `_maxHeight` lower bound is observable: every probe, anywhere in
/// the layout, starts its walk `bannerH - 1` rows above its own box because
/// one tall tile exists somewhere. A uniform fixture cannot show it, so a
/// baseline built only on `generateUniformLayout` would rate a span-indexed
/// rewrite as worthless by construction.
List<LayoutItem> generateBannerLayout(
  int n,
  int cols, {
  int bannerEvery = 100,
  int bannerH = 16,
}) {
  const w = 2;
  const h = 2;
  final items = <LayoutItem>[];
  var y = 0;
  var x = 0;
  for (var i = 0; i < n; i++) {
    if (i > 0 && i % bannerEvery == 0) {
      if (x != 0) {
        y += h;
        x = 0;
      }
      items.add(
        LayoutItem(
          id: 'ban${i.toString().padLeft(6, '0')}',
          x: 0,
          y: y,
          w: cols,
          h: bannerH,
        ),
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
  // Id-sorted, because the Index Stability invariant means the engine never
  // receives anything else: every layout it returns is id-sorted, and that is
  // what the controller feeds back on the next call. A fixture interleaving
  // `ban...` and `i...` ids measures the engine's unsorted-input fallback —
  // a path production never takes — and hides any work that only the sorted
  // path can skip.
  return items..sort((a, b) => a.id.compareTo(b.id));
}

/// The resize-freeze shape: a compacted grid whose TOP item just grew,
/// pushing everything below (what resizeItem feeds to compact on every
/// pointer event of a top-of-grid resize).
({List<LayoutItem> layout, LayoutItem grownTop}) generateTopResizeCase(
  int n,
  int cols,
) {
  final base = generateCompactLayout(n, cols);
  final top = base.reduce(
    (a, b) => (a.y < b.y || (a.y == b.y && a.x < b.x)) ? a : b,
  );
  return (layout: base, grownTop: top.copyWith(h: top.h + 2));
}

// ============================================================================
// SLIVER LAYOUT PASS (replica)
// ============================================================================
// Steps 3 and 5 of `RenderSliverDashboard.performLayout`, copied verbatim so
// the pass can be timed on dart2js without a Flutter binding. This is the
// entire scope of the "geometry memo + binary window" proposal: the memo
// would skip [sliverGeometryPass] on a scroll pass, and the binary search
// would replace [sliverWindowPass]. Measuring them tells us what that
// proposal is worth BEFORE touching a render object flagged DANGER ZONE.

/// Step 3: fill the reusable geometry buffer, accumulate the scroll extent.
double sliverGeometryPass(
  List<LayoutItem> items,
  Float64List geom, {
  required double slotWidth,
  required double slotHeight,
  required double mainAxisSpacing,
  required double crossAxisSpacing,
}) {
  var maxScrollExtent = 0.0;
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final x = item.x * (slotWidth + crossAxisSpacing);
    final y = item.y * (slotHeight + mainAxisSpacing);
    final w = item.w * (slotWidth + crossAxisSpacing) - crossAxisSpacing;
    final h = item.h * (slotHeight + mainAxisSpacing) - mainAxisSpacing;
    final bottom = y + h;
    if (bottom > maxScrollExtent) maxScrollExtent = bottom;

    final base = i * 4;
    geom[base] = x;
    geom[base + 1] = y;
    geom[base + 2] = w > 0 ? w : 0;
    geom[base + 3] = h > 0 ? h : 0;
  }
  return maxScrollExtent;
}

/// Step 5: linear scan for the visible index range.
int sliverWindowPass(
  int itemCount,
  Float64List geom, {
  required double targetStart,
  required double targetEnd,
}) {
  var minVisibleIndex = itemCount;
  var maxVisibleIndex = -1;
  for (var i = 0; i < itemCount; i++) {
    final base = i * 4;
    final itemStart = geom[base + 1];
    final itemEnd = itemStart + geom[base + 3];
    if (itemEnd >= targetStart && itemStart <= targetEnd) {
      if (i < minVisibleIndex) minVisibleIndex = i;
      if (i > maxVisibleIndex) maxVisibleIndex = i;
    }
  }
  return maxVisibleIndex - minVisibleIndex;
}

// ============================================================================
// MEASUREMENT ENGINE
// ============================================================================

String formatTime(double microseconds) {
  if (microseconds < 1000) return '${microseconds.toStringAsFixed(0)} µs';
  if (microseconds < 1000000) return '${(microseconds / 1000).toStringAsFixed(2)} ms';
  return '${(microseconds / 1000000).toStringAsFixed(2)} s';
}

/// Median of [runs] timed batches of [iterations] calls each.
/// Median tames the run-to-run variance observed on this machine
/// (same-code Sort measured 207 then 324 µs across two sessions); the
/// minimum is also recorded as the "best achievable" floor.
({double median, double best}) measure(
  String label,
  void Function() operation, {
  int iterations = 100,
  int runs = 7,
}) {
  // Warmup (JIT/AOT caches, branch predictors)
  for (var i = 0; i < 5; i++) {
    operation();
  }

  final samples = <double>[];
  for (var r = 0; r < runs; r++) {
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      operation();
    }
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds / iterations);
  }
  samples.sort();
  return (median: samples[samples.length ~/ 2], best: samples.first);
}

// ============================================================================
// INTEGRITY HASH
// ============================================================================
// A cheap order-sensitive hash of a layout's positions. It also pins output
// equivalence: an algorithm change that alters any position changes the hash.
int layoutHash(List<LayoutItem> layout) {
  var h = 17;
  for (final item in layout) {
    h = 0x1fffffff & (h * 31 + item.id.hashCode);
    h = 0x1fffffff & (h * 31 + item.x);
    h = 0x1fffffff & (h * 31 + item.y);
    h = 0x1fffffff & (h * 31 + item.w);
    h = 0x1fffffff & (h * 31 + item.h);
  }
  return h;
}

final integrity = <String, int>{};

/// Collision-probe counts per fixture, for ONE `moveElement` call.
///
/// Timings alone cannot tell a cheaper probe from a shorter cascade; the
/// `rowVisits / queries` ratio isolates the scan range, which is exactly what
/// a change to the index's bucketing moves. Populated only when asserts are
/// live (`dart run`); a `-O2` JS or AOT build reports zeros, which is the
/// point — those runs measure time, this one measures work.
final probeCounts = <String, ({int queries, int rowVisits})>{};

// ============================================================================
// RESULTS TABLE
// ============================================================================

class BenchmarkResult {
  BenchmarkResult(this.category, this.name, this.medianUs, this.bestUs);
  final String category;
  final String name;
  final double medianUs;
  final double bestUs;
}

final results = <BenchmarkResult>[];

void record(String category, String name, ({double median, double best}) t) {
  results.add(BenchmarkResult(category, name, t.median, t.best));
}

void printReport() {
  print('');
  print('┌──────────────────────────────────────────────────────────────────────────────┐');
  print('│                            BENCHMARK RESULTS                                 │');
  print('├──────────────────────────────────────────────────┬─────────────┬─────────────┤');
  print('│ Test                                             │ Median      │ Best        │');
  print('├──────────────────────────────────────────────────┼─────────────┼─────────────┤');

  String? currentCat;
  for (final res in results) {
    if (res.category != currentCat) {
      if (currentCat != null) {
        print('├──────────────────────────────────────────────────┼─────────────┼─────────────┤');
      }
      currentCat = res.category;
      print('│ ${currentCat.toUpperCase().padRight(48)} │             │             │');
      print('├──────────────────────────────────────────────────┼─────────────┼─────────────┤');
    }
    print(
      '│   ${res.name.padRight(46)} │ ${formatTime(res.medianUs).padLeft(11)} │ ${formatTime(res.bestUs).padLeft(11)} │',
    );
  }
  print('└──────────────────────────────────────────────────┴─────────────┴─────────────┘');
  print('');
  if (probeCounts.values.any((c) => c.queries > 0)) {
    print('Collision probes per moveElement call (asserts on; 0 in -O2/AOT):');
    print('  fixture              queries   rowVisits   rows/probe');
    probeCounts.forEach((k, c) {
      final ratio = c.queries == 0 ? 0.0 : c.rowVisits / c.queries;
      print(
        '  ${k.padRight(20)} ${c.queries.toString().padLeft(7)} '
        '${c.rowVisits.toString().padLeft(11)} ${ratio.toStringAsFixed(2).padLeft(12)}',
      );
    });
    print('');
  }

  print('Integrity hashes (change = algorithm output changed; identical across');
  print('a run you expected to differ = STALE BINARY, rebuild your AOT exe):');
  integrity.forEach((k, v) => print('  $k: ${v.toRadixString(16)}'));
}

// ============================================================================
// MAIN
// ============================================================================

void main() {
  const cols = 12;
  final sizes = [100, 500, 1000, 2000, 4000, 10000];

  // Ensure the Fast Strategy is available
  const fastCompactor = FastVerticalCompactor();
  const fastHCompactor = FastHorizontalCompactor();

  print('Running Benchmarks...');

  // 1. COMPACTION — DEEP/OVERLAPPING INPUT (worst case)
  for (final size in sizes) {
    final messy = generateMessyLayout(size, cols);

    record(
      'Compaction (deep input)',
      'Vertical Standard ($size items)',
      measure(
        'Compact V Std',
        () => compact(messy, CompactType.vertical, cols),
        iterations: size > 2000 ? 2 : (size > 500 ? 10 : 50),
      ),
    );
    record(
      'Compaction (deep input)',
      'Vertical Fast/Tide ($size items)',
      measure(
        'Compact V Fast',
        () => fastCompactor.compact(messy, cols),
        iterations: size > 2000 ? 10 : (size > 500 ? 50 : 100),
      ),
    );
    record(
      'Compaction (deep input)',
      'Horizontal Standard ($size items)',
      measure(
        'Compact H',
        () => compact(messy, CompactType.horizontal, cols),
        iterations: size > 2000 ? 2 : (size > 500 ? 10 : 50),
      ),
    );
    record(
      'Compaction (deep input)',
      'Horizontal Fast/Tide ($size items)',
      measure(
        'Compact H Fast',
        () => fastHCompactor.compact(messy, cols),
        iterations: size > 2000 ? 10 : (size > 500 ? 50 : 100),
      ),
    );

    integrity['compactV_deep_$size'] = layoutHash(compact(messy, CompactType.vertical, cols));
    integrity['compactH_deep_$size'] = layoutHash(compact(messy, CompactType.horizontal, cols));
  }

  // 1bis. COMPACTION — ALREADY-COMPACT INPUT (the common interactive case:
  // this exact shape is compacted on EVERY drag/resize pointer event).
  for (final size in sizes) {
    final dense = generateCompactLayout(size, cols);
    record(
      'Compaction (already compact)',
      'Vertical Standard ($size items)',
      measure(
        'Compact V dense',
        () => compact(dense, CompactType.vertical, cols),
        iterations: size > 2000 ? 3 : (size > 500 ? 20 : 100),
      ),
    );
    integrity['compactV_dense_$size'] = layoutHash(compact(dense, CompactType.vertical, cols));
  }

  // 1ter. RESIZE PUSH AT TOP (the historical freeze scenario: moveElement
  // cascade + full compact, per pointer event, everything below moving).
  for (final size in [500, 1000, 2000, 4000, 10000]) {
    final c = generateTopResizeCase(size, cols);
    record(
      'Resize (top of grid)',
      'resizeItem push at top ($size items)',
      measure(
        'ResizeTop',
        () => resizeItem(
          c.layout,
          c.grownTop,
          behavior: ResizeBehavior.push,
          cols: cols,
        ),
        iterations: size > 2000 ? 3 : (size > 500 ? 10 : 30),
      ),
    );
    integrity['resizeTop_$size'] = layoutHash(
      resizeItem(
        c.layout,
        c.grownTop,
        behavior: ResizeBehavior.push,
        cols: cols,
      ),
    );
  }

  // 2. MOVE ELEMENT
  for (final size in [100, 500, 1000, 2000, 4000, 10000]) {
    var layout = generateLayout(size, cols);
    layout = compact(layout, CompactType.vertical, cols); // Start clean
    final item = layout[size ~/ 2]; // Middle item

    record(
      'Move',
      'Move Element ($size items)',
      measure(
        'Move',
        () => moveElement(
          layout,
          item,
          0, 0, // Move to top-left to cause cascade
          cols: cols,
          compactType: CompactType.vertical,
          preventCollision: true,
          force: true,
        ),
        iterations: size > 2000 ? 5 : (size > 500 ? 15 : 50),
      ),
    );
  }

  // 2bis. CELL CROSSING — the drag hot path, and the `_RowIndex` baseline.
  //
  // `moveElement` runs once per CELL CROSSING, not per pointer event, and the
  // real gesture moves a tile by ONE row into an already-compacted grid. The
  // "Move Element" section above moves the middle tile to (0,0) with
  // `force: true`, i.e. the worst case; this is the common one, and the two
  // fixtures differ only by the presence of tall tiles.
  for (final size in [500, 1000, 4000]) {
    for (final shape in ['uniform', 'banner']) {
      final layout =
          shape == 'uniform' ? generateUniformLayout(size, cols) : generateBannerLayout(size, cols);
      final item = layout[layout.length ~/ 2];

      record(
        'Cell crossing (drag hot path)',
        'moveElement +1 row, $shape ($size items)',
        measure(
          'CellCrossing',
          () => moveElement(
            layout,
            item,
            item.x,
            item.y + 1,
            cols: cols,
            compactType: CompactType.vertical,
            preventCollision: true,
            force: true,
          ),
          iterations: size > 2000 ? 5 : (size > 500 ? 15 : 50),
        ),
      );
      integrity['cellCross_${shape}_$size'] = layoutHash(
        moveElement(
          layout,
          item,
          item.x,
          item.y + 1,
          cols: cols,
          compactType: CompactType.vertical,
          preventCollision: true,
          force: true,
        ),
      );

      // Probe counts for ONE call, outside any timed region. Only meaningful
      // when asserts are on (`dart run`); a release/JS build reports 0.
      debugResetRowIndexCounters();
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
      probeCounts['$shape/$size'] = (
        queries: debugRowIndexQueries,
        rowVisits: debugRowIndexRowVisits,
      );
    }
  }

  // 2ter. SLIVER LAYOUT PASS — what a geometry memo + binary window would save.
  for (final size in [1000, 4000, 10000]) {
    final layout = generateUniformLayout(size, cols);
    final geom = Float64List(size * 4);
    const slotW = 90.0;
    const slotH = 90.0;

    record(
      'Sliver layout pass',
      'geometry loop, N=$size (step 3)',
      measure(
        'Geom',
        () => sliverGeometryPass(
          layout,
          geom,
          slotWidth: slotW,
          slotHeight: slotH,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        iterations: 200,
      ),
    );
    sliverGeometryPass(
      layout,
      geom,
      slotWidth: slotW,
      slotHeight: slotH,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
    );
    record(
      'Sliver layout pass',
      'window scan, N=$size (step 5)',
      measure(
        'Window',
        () => sliverWindowPass(size, geom, targetStart: 4000, targetEnd: 4800),
        iterations: 200,
      ),
    );
  }

  // 3. SORT
  for (final size in sizes) {
    final messy = generateMessyLayout(size, cols);
    record(
      'Sort',
      'Sort Layout ($size items)',
      measure('Sort', () => sortLayoutItems(messy, CompactType.vertical)),
    );
  }

  // 4. OPTIMIZE (Defrag)
  for (final size in sizes) {
    final messy = generateMessyLayout(size, cols);
    record(
      'Optimize',
      'Defrag ($size items)',
      measure(
        'Optimize',
        () => optimizeLayout(messy, cols),
        iterations: size > 2000 ? 1 : (size > 500 ? 2 : 10),
      ),
    );
    integrity['defrag_$size'] = layoutHash(optimizeLayout(messy, cols));
  }

  printReport();
}
