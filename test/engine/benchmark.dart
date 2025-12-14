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

// ============================================================================
// MEASUREMENT ENGINE
// ============================================================================

String formatTime(double microseconds) {
  if (microseconds < 1000) return '${microseconds.toStringAsFixed(0)} µs';
  if (microseconds < 1000000) return '${(microseconds / 1000).toStringAsFixed(2)} ms';
  return '${(microseconds / 1000000).toStringAsFixed(2)} s';
}

double measure(String label, void Function() operation, {int iterations = 100}) {
  // Warmup (JIT optimization)
  for (var i = 0; i < 5; i++) {
    operation();
  }

  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    operation();
  }
  stopwatch.stop();

  final avgUs = stopwatch.elapsedMicroseconds / iterations;
  return avgUs;
}

// ============================================================================
// RESULTS TABLE
// ============================================================================

class BenchmarkResult {
  BenchmarkResult(this.category, this.name, this.timeUs);
  final String category;
  final String name;
  final double timeUs;
}

final results = <BenchmarkResult>[];

void record(String category, String name, double timeUs) {
  results.add(BenchmarkResult(category, name, timeUs));
  // Uncomment for immediate feedback in console
  // print('$category - $name: ${formatTime(timeUs)}');
}

void printReport() {
  print('');
  print('┌──────────────────────────────────────────────────────────────────────────┐');
  print('│                        📊 BENCHMARK RESULTS                              │');
  print('├──────────────────────────────────────────────────────┬───────────────────┤');
  print('│ Test                                                 │ Time              │');
  print('├──────────────────────────────────────────────────────┼───────────────────┤');

  String? currentCat;
  for (final res in results) {
    if (res.category != currentCat) {
      currentCat = res.category;
      print('│ ${currentCat.toUpperCase().padRight(52)} │                   │');
      print('├──────────────────────────────────────────────────────┼───────────────────┤');
    }
    print('│   ${res.name.padRight(50)} │ ${formatTime(res.timeUs).padLeft(17)} │');
  }
  print('└──────────────────────────────────────────────────────┴───────────────────┘');
}

// ============================================================================
// MAIN
// ============================================================================

void main() {
  const cols = 12;
  final sizes = [100, 500, 1000];

  // Ensure the Fast Strategy is available
  const fastCompactor = FastVerticalCompactor();
  const fastHCompactor = FastHorizontalCompactor();

  print('Running Benchmarks...');

  // 1. COMPACTION ALGORITHMS
  for (final size in sizes) {
    // Pre-generate to avoid measuring generation time.
    final messy = generateMessyLayout(size, cols);

    // A. Standard Vertical (O(N^2))
    // This is the default historical algorithm.
    record(
      'Compaction',
      'Vertical Standard ($size items)',
      measure(
        'Compact V Std',
        () {
          compact(messy, CompactType.vertical, cols);
        },
        iterations: size > 500 ? 10 : 50,
      ),
    );

    // B. Fast Vertical (Rising Tide - O(N))
    // This is the new optimized algorithm.
    record(
      'Compaction',
      'Vertical Fast ($size items)',
      measure(
        'Compact V Fast',
        () {
          fastCompactor.compact(messy, cols);
        },
        iterations: size > 500 ? 50 : 100, // Can run more iterations as it is faster
      ),
    );

    // C. Horizontal
    record(
      'Compaction',
      'Horizontal ($size items)',
      measure(
        'Compact H',
        () {
          compact(messy, CompactType.horizontal, cols);
        },
        iterations: size > 500 ? 10 : 50,
      ),
    );

    // D. Fast Horizontal
    record(
      'Compaction',
      'Horizontal Fast ($size items)',
      measure(
        'Compact H Fast',
        () {
          fastHCompactor.compact(messy, cols);
        },
        iterations: size > 500 ? 50 : 100,
      ),
    );
  }

  // 2. MOVE ELEMENT
  // Test moving an element that causes collisions (cascade effect)
  for (final size in [100, 500]) {
    var layout = generateLayout(size, cols);
    layout = compact(layout, CompactType.vertical, cols); // Start clean
    final item = layout[size ~/ 2]; // Middle item

    record(
      'Move',
      'Move Element ($size items)',
      measure(
        'Move',
        () {
          moveElement(
            layout,
            item,
            0, 0, // Move to top-left to cause cascade
            cols: cols,
            compactType: CompactType.vertical,
            preventCollision: true,
            force: true,
          );
        },
        iterations: 50,
      ),
    );
  }

  // 3. SORT
  for (final size in sizes) {
    final messy = generateMessyLayout(size, cols);
    record(
      'Sort',
      'Sort Layout ($size items)',
      measure('Sort', () {
        sortLayoutItems(messy, CompactType.vertical);
      }),
    );
  }

  // 4. OPTIMIZE (Defrag)
  for (final size in [100, 500]) {
    final messy = generateMessyLayout(size, cols);
    record(
      'Optimize',
      'Defrag ($size items)',
      measure(
        'Optimize',
        () {
          optimizeLayout(messy, cols);
        },
        iterations: 10,
      ),
    );
  }

  printReport();
}
