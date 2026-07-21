// Dart only benchmark
// ignore_for_file: avoid_print
import 'dart:math';

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
