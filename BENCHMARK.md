# Sliver Dashboard Benchmarks

This document provides a comprehensive performance breakdown of the `sliver_dashboard` layout engine under extreme loads, along with the methodologies and instructions required to reproduce these results.

---

## Benchmark Setup & Specs

- **Hardware:** AMD Ryzen 5 2600 (6 Cores, 12 Threads @ 3.4 GHz)
- **OS:** Windows 11
- **Execution Mode:** Dart Native Ahead-Of-Time compilation (`dart compile exe`)
- **Measurement:** Median of 7 independent runs (tames run-to-run environment variance)
- **Input Shape:** two families, because they answer different questions.
  `COMPACTION`, `SORT` and `OPTIMIZE` run on deliberately hostile input —
  non-pre-compacted, deeply scattered, heavily overlapping — to probe
  worst-case limits. `CELL CROSSING` runs on **deterministic, id-sorted,
  already-compacted** grids, because that is what a gesture actually hands the
  engine, and because a randomized fixture makes two revisions incomparable.
- **Grid width:** 12 columns throughout.
- **Revision:** the unreleased engine. Against 2.7.0 on this same machine, the
  drag and resize paths are 1.9× to 2.9× faster and the rest is unchanged; the
  `CHANGELOG` has the per-operation before/after.

---

## Benchmark Results

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                            BENCHMARK RESULTS                                 │
├──────────────────────────────────────────────────┬─────────────┬─────────────┤
│ Test                                             │ Median      │ Best        │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│ COMPACTION (DEEP INPUT)                          │             │             │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│   Vertical Standard (100 items)                  │       41 µs │       41 µs │
│   Vertical Fast/Tide (100 items)                 │       33 µs │       33 µs │
│   Horizontal Standard (100 items)                │       82 µs │       81 µs │
│   Horizontal Fast/Tide (100 items)               │       35 µs │       34 µs │
│   Vertical Standard (500 items)                  │      264 µs │      262 µs │
│   Vertical Fast/Tide (500 items)                 │      228 µs │      227 µs │
│   Horizontal Standard (500 items)                │      439 µs │      436 µs │
│   Horizontal Fast/Tide (500 items)               │      245 µs │      243 µs │
│   Vertical Standard (1000 items)                 │      538 µs │      521 µs │
│   Vertical Fast/Tide (1000 items)                │      499 µs │      498 µs │
│   Horizontal Standard (1000 items)               │      918 µs │      907 µs │
│   Horizontal Fast/Tide (1000 items)              │      526 µs │      522 µs │
│   Vertical Standard (2000 items)                 │     1.20 ms │     1.20 ms │
│   Vertical Fast/Tide (2000 items)                │     1.14 ms │     1.14 ms │
│   Horizontal Standard (2000 items)               │     2.05 ms │     2.04 ms │
│   Horizontal Fast/Tide (2000 items)              │     1.18 ms │     1.17 ms │
│   Vertical Standard (4000 items)                 │     2.77 ms │     2.61 ms │
│   Vertical Fast/Tide (4000 items)                │     2.58 ms │     2.52 ms │
│   Horizontal Standard (4000 items)               │     4.88 ms │     4.63 ms │
│   Horizontal Fast/Tide (4000 items)              │     2.57 ms │     2.53 ms │
│   Vertical Standard (10000 items)                │     7.89 ms │     7.61 ms │
│   Vertical Fast/Tide (10000 items)               │     7.21 ms │     7.08 ms │
│   Horizontal Standard (10000 items)              │    17.27 ms │    16.89 ms │
│   Horizontal Fast/Tide (10000 items)             │     7.34 ms │     7.16 ms │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│ COMPACTION (ALREADY COMPACT)                     │             │             │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│   Vertical Standard (100 items)                  │       31 µs │       31 µs │
│   Vertical Standard (500 items)                  │      201 µs │      199 µs │
│   Vertical Standard (1000 items)                 │      477 µs │      441 µs │
│   Vertical Standard (2000 items)                 │      957 µs │      951 µs │
│   Vertical Standard (4000 items)                 │     2.11 ms │     2.07 ms │
│   Vertical Standard (10000 items)                │     6.22 ms │     5.96 ms │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│ RESIZE (TOP OF GRID)                             │             │             │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│   resizeItem push at top (500 items)             │      380 µs │      373 µs │
│   resizeItem push at top (1000 items)            │      262 µs │      260 µs │
│   resizeItem push at top (2000 items)            │      112 µs │      112 µs │
│   resizeItem push at top (4000 items)            │      248 µs │      246 µs │
│   resizeItem push at top (10000 items)           │    10.74 ms │     8.84 ms │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│ MOVE                                             │             │             │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│   Move Element (100 items)                       │       33 µs │       33 µs │
│   Move Element (500 items)                       │      178 µs │      177 µs │
│   Move Element (1000 items)                      │      359 µs │      355 µs │
│   Move Element (2000 items)                      │      726 µs │      717 µs │
│   Move Element (4000 items)                      │     1.55 ms │     1.46 ms │
│   Move Element (10000 items)                     │     4.64 ms │     4.29 ms │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│ CELL CROSSING (DRAG HOT PATH)                    │             │             │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│   moveElement +1 row, uniform (500 items)        │      163 µs │      161 µs │
│   moveElement +1 row, banner (500 items)         │      255 µs │      251 µs │
│   moveElement +1 row, uniform (1000 items)       │      325 µs │      323 µs │
│   moveElement +1 row, banner (1000 items)        │      309 µs │      305 µs │
│   moveElement +1 row, uniform (4000 items)       │     1.31 ms │     1.30 ms │
│   moveElement +1 row, banner (4000 items)        │     2.22 ms │     2.19 ms │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│ SLIVER LAYOUT PASS                               │             │             │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│   geometry loop, N=1000 (step 3)                 │        5 µs │        5 µs │
│   window scan, N=1000 (step 5)                   │        2 µs │        2 µs │
│   geometry loop, N=4000 (step 3)                 │       22 µs │       22 µs │
│   window scan, N=4000 (step 5)                   │        7 µs │        7 µs │
│   geometry loop, N=10000 (step 3)                │       62 µs │       61 µs │
│   window scan, N=10000 (step 5)                  │       17 µs │       17 µs │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│ SORT                                             │             │             │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│   Sort Layout (100 items)                        │       14 µs │       14 µs │
│   Sort Layout (500 items)                        │       93 µs │       93 µs │
│   Sort Layout (1000 items)                       │      209 µs │      208 µs │
│   Sort Layout (2000 items)                       │      478 µs │      474 µs │
│   Sort Layout (4000 items)                       │     1.05 ms │     1.04 ms │
│   Sort Layout (10000 items)                      │     2.96 ms │     2.91 ms │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│ OPTIMIZE                                         │             │             │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│   Defrag (100 items)                             │      156 µs │      155 µs │
│   Defrag (500 items)                             │     1.18 ms │     1.16 ms │
│   Defrag (1000 items)                            │     2.41 ms │     2.28 ms │
│   Defrag (2000 items)                            │     5.16 ms │     5.03 ms │
│   Defrag (4000 items)                            │    13.11 ms │    13.04 ms │
│   Defrag (10000 items)                           │    58.21 ms │    56.89 ms │
└──────────────────────────────────────────────────┴─────────────┴─────────────┘
```

---

## Algorithmic Deep Dive & Analysis

### 1. Default Compactors vs. Rising Tide (`Fast*Compactor`) Delegates

The numbers above measure the **default engine** — what every drag, resize,
add and defrag actually runs. The opt-in `FastVerticalCompactor` /
`FastHorizontalCompactor` delegates implement a different algorithm with
different placement semantics; pick deliberately:

**Default (Standard) compactors** — the right choice for almost everyone:
- Exact, deterministic placement semantics, stable across releases: saved
  layouts always reflow identically. The entire test suite (including
  randomized equivalence oracles) pins these semantics.
- Within ~10% of the Tide on vertical workloads since the skyline rewrite.

**Rising Tide (Fast) delegates** — opt in when you need what only they offer:
- Native support for items beyond the column range (horizontally-scrolling
  vertical grids) and an `allowOverlap` mode.
- Faster on deeply-overlapping horizontal workloads (~1.8× at N=1000 and
  ~2.4× at N=10000 on the hostile benchmark input; interactive workloads
  compact already-dense layouts, where the gap vanishes).
- Trade-off: "tide" placement resolves overlapping input by stacking on the
  water-line rather than the default's first-collider chain — on messy
  inputs, items can land in different (valid, overlap-free) positions than
  the default. Switching an existing app changes how saved messy layouts
  reflow.

### 2. Which rows are the interactive budget

The engine call behind a gesture runs **once per cell crossing**, not once per
pointer event: `onDragUpdate` / `onResizeUpdate` return early while the
dragged bounding box stays in the same cell. A 2-second drag therefore issues
a handful of engine calls, not 120 — but each one has to fit inside a frame
alongside layout, paint and raster.

*   **`CELL CROSSING (DRAG HOT PATH)`** is the controlled measure of that
    call: one tile moved by one row into an already-compacted, deterministic
    grid. Two fixtures, because the cost depends on the *shape* of the layout
    and not only on its size: `uniform` is a dense grid of equal tiles;
    `banner` interleaves full-width 16-row tiles, which is what a real
    dashboard with section headers or charts looks like. Both fixtures are
    id-sorted, like every layout the engine actually receives.
*   **`RESIZE (TOP OF GRID)`** is the historical worst case — the grown item
    pushes everything below it, then the layout recompacts. Read it for the
    order of magnitude only: its fixture is randomized per size, so whether
    the top item collides at all varies, which is why the row is not monotonic
    in `N` (112 µs at 2000 against 380 µs at 500). The `CELL CROSSING` rows
    replaced it as the comparable hot-path metric.
*   **`SLIVER LAYOUT PASS`** replicates steps 3 and 5 of
    `RenderSliverDashboard.performLayout` — the geometry buffer fill and the
    visible-window scan — so the render pass can be measured without a Flutter
    binding. They are here to document a decision: memoizing the buffer and
    replacing the scan with a binary search is sound but **not worth it**, at
    7 µs combined for N=1000 and 79 µs for N=10000.
*   **Cold path (`OPTIMIZE`):** `optimizeLayout` runs a bin-packing pass that
    fully defragments grid gaps. It is an on-demand, one-off operation, usually
    behind a button. 1,000 items defragment in **`2.41 ms`**, and even a
    10,000-item grid in under **`60 ms`** — no visible stutter.

### 3. Compiling to the web

AOT is the fastest target and the one the table above uses, but it is not the
one most exposed: on the web, allocation churn and megamorphic calls cost
noticeably more. The same benchmark, compiled with `dart compile js -O2` and
with `dart compile wasm -O2` and run in Chromium on the same machine:

| Operation | AOT | dart2js | wasm |
|---|---|---|---|
| Cell crossing, uniform, N = 1000 | 0.33 ms | 0.89 ms | 0.36 ms |
| Cell crossing, banners, N = 1000 | 0.31 ms | 0.82 ms | 0.34 ms |
| Cell crossing, uniform, N = 4000 | 1.31 ms | 3.33 ms | 1.46 ms |
| Cell crossing, banners, N = 4000 | 2.22 ms | 6.00 ms | 2.28 ms |
| Resize push at the top, N = 1000 | 0.26 ms | 0.97 ms | 0.26 ms |
| Resize push at the top, N = 10000 | 10.7 ms | 24.0 ms | 8.31 ms |
| Move onto an occupied slot, N = 1000 | 0.36 ms | 0.90 ms | 0.38 ms |

dart2js costs roughly **2.5×** AOT on this workload; **WebAssembly closes that
gap almost entirely** and matches AOT within noise. If you ship a large grid to
the web, `flutter build web --wasm` is the single highest-leverage change
available to you — it needs no code change on your side.

---

## How to Run the Benchmarks

You can compile and run this benchmark natively on your own machine to verify these figures.

### 1. Compilation (AOT Mode)
Compile the benchmark script into a highly optimized, native machine-code executable using Dart's AOT compiler:

```bash
# Compile to a native binary
dart compile exe test/benchmark/benchmark.dart -o test/benchmark/benchmark.exe
```

### 2. Execution
Run the compiled binary directly from your terminal:

```bash
# Execute the native benchmark
./test/benchmark/benchmark.exe
```

### 3. Web targets

The benchmark imports no Flutter code, so it compiles to JavaScript and to
WebAssembly as-is. The JS build runs under Node; the wasm build needs a
browser (WasmGC), served with the right MIME types for `.mjs` and `.wasm`.

```bash
dart compile js -O2 -o bench.js test/benchmark/benchmark.dart && node bench.js
```

```bash
dart compile wasm -O2 -o bench.wasm test/benchmark/benchmark.dart
```

### 4. Collision-probe counts

Beyond timings, the engine exposes `debugRowIndexQueries` and
`debugRowIndexRowVisits`. Their ratio is the scan range of an average
collision probe — the number a change to the index's bucketing moves, and one
no timing can isolate, since a faster run may simply have had a shorter
cascade. The counters live inside `assert`s, so they are stripped from AOT and
`-O2` builds and never charge the timings above. Run with the JIT to read
them:

```bash
dart run --enable-asserts test/benchmark/benchmark.dart
```
