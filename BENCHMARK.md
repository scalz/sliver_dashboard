# Sliver Dashboard Benchmarks

This document provides a comprehensive performance breakdown of the `sliver_dashboard` layout engine under extreme loads, along with the methodologies and instructions required to reproduce these results.

---

## Benchmark Setup & Specs

- **Hardware:** AMD Ryzen 5 2600 (6 Cores, 12 Threads @ 3.4 GHz)
- **OS:** Windows 11
- **Execution Mode:** Dart Native Ahead-Of-Time compilation (`dart compile exe`)
- **Measurement:** Median of 7 independent runs (tames run-to-run environment variance)
- **Input Shape:** Deliberately hostile, non-pre-compacted, deep scattered layouts with heavy overlaps to simulate worst-case performance limits.

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
│   Vertical Standard (100 items)                  │       41 µs │       40 µs │
│   Vertical Fast/Tide (100 items)                 │       33 µs │       33 µs │
│   Horizontal Standard (100 items)                │       82 µs │       80 µs │
│   Horizontal Fast/Tide (100 items)               │       34 µs │       33 µs │
│   Vertical Standard (500 items)                  │      271 µs │      269 µs │
│   Vertical Fast/Tide (500 items)                 │      232 µs │      229 µs │
│   Horizontal Standard (500 items)                │      435 µs │      431 µs │
│   Horizontal Fast/Tide (500 items)               │      244 µs │      241 µs │
│   Vertical Standard (1000 items)                 │      532 µs │      510 µs │
│   Vertical Fast/Tide (1000 items)                │      497 µs │      494 µs │
│   Horizontal Standard (1000 items)               │      944 µs │      886 µs │
│   Horizontal Fast/Tide (1000 items)              │      520 µs │      516 µs │
│   Vertical Standard (2000 items)                 │     1.23 ms │     1.22 ms │
│   Vertical Fast/Tide (2000 items)                │     1.11 ms │     1.10 ms │
│   Horizontal Standard (2000 items)               │     2.05 ms │     2.02 ms │
│   Horizontal Fast/Tide (2000 items)              │     1.15 ms │     1.15 ms │
│   Vertical Standard (4000 items)                 │     2.51 ms │     2.48 ms │
│   Vertical Fast/Tide (4000 items)                │     2.49 ms │     2.48 ms │
│   Horizontal Standard (4000 items)               │     4.59 ms │     4.38 ms │
│   Horizontal Fast/Tide (4000 items)              │     2.55 ms │     2.52 ms │
│   Vertical Standard (10000 items)                │     7.23 ms │     7.13 ms │
│   Vertical Fast/Tide (10000 items)               │     6.90 ms │     6.82 ms │
│   Horizontal Standard (10000 items)              │    16.23 ms │    15.92 ms │
│   Horizontal Fast/Tide (10000 items)             │     7.04 ms │     6.92 ms │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│ COMPACTION (ALREADY COMPACT)                     │             │             │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│   Vertical Standard (100 items)                  │       32 µs │       31 µs │
│   Vertical Standard (500 items)                  │      199 µs │      198 µs │
│   Vertical Standard (1000 items)                 │      437 µs │      432 µs │
│   Vertical Standard (2000 items)                 │      973 µs │      932 µs │
│   Vertical Standard (4000 items)                 │     2.09 ms │     2.07 ms │
│   Vertical Standard (10000 items)                │     6.27 ms │     5.91 ms │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│ RESIZE (TOP OF GRID)                             │             │             │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│   resizeItem push at top (500 items)             │     1.03 ms │     1.02 ms │
│   resizeItem push at top (1000 items)            │      749 µs │      742 µs │
│   resizeItem push at top (2000 items)            │      116 µs │      115 µs │
│   resizeItem push at top (4000 items)            │      243 µs │      242 µs │
│   resizeItem push at top (10000 items)           │    26.03 ms │    25.16 ms │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│ MOVE                                             │             │             │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│   Move Element (100 items)                       │       57 µs │       57 µs │
│   Move Element (500 items)                       │      342 µs │      338 µs │
│   Move Element (1000 items)                      │      701 µs │      699 µs │
│   Move Element (2000 items)                      │     1.43 ms │     1.42 ms │
│   Move Element (4000 items)                      │     2.95 ms │     2.88 ms │
│   Move Element (10000 items)                     │     8.48 ms │     8.01 ms │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│ SORT                                             │             │             │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│   Sort Layout (100 items)                        │       14 µs │       14 µs │
│   Sort Layout (500 items)                        │       91 µs │       90 µs │
│   Sort Layout (1000 items)                       │      204 µs │      203 µs │
│   Sort Layout (2000 items)                       │      463 µs │      462 µs │
│   Sort Layout (4000 items)                       │      989 µs │      984 µs │
│   Sort Layout (10000 items)                      │     2.80 ms │     2.76 ms │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│ OPTIMIZE                                         │             │             │
├──────────────────────────────────────────────────┼─────────────┼─────────────┤
│   Defrag (100 items)                             │      172 µs │      171 µs │
│   Defrag (500 items)                             │     1.29 ms │     1.28 ms │
│   Defrag (1000 items)                            │     2.52 ms │     2.49 ms │
│   Defrag (2000 items)                            │     5.57 ms │     5.50 ms │
│   Defrag (4000 items)                            │    13.83 ms │    13.73 ms │
│   Defrag (10000 items)                           │    58.47 ms │    57.60 ms │
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
- Faster on deeply-overlapping horizontal workloads (~5× on the hostile
  benchmark input; interactive workloads compact already-dense layouts,
  where the gap vanishes).
- Trade-off: "tide" placement resolves overlapping input by stacking on the
  water-line rather than the default's first-collider chain — on messy
  inputs, items can land in different (valid, overlap-free) positions than
  the default. Switching an existing app changes how saved messy layouts
  reflow.

### 2. Interaction Hot Paths vs. On-Demand Utilities

Numbers measure the **default engine**: the exact-semantics compactors
every drag/resize/add actually runs. The opt-in `FastVerticalCompactor` /
`FastHorizontalCompactor` ("Rising Tide") delegates trade exact historical
placement semantics for support of out-of-column items and `allowOverlap`;
they now benchmark within ~5% of the default on deep inputs.

It is important to distinguish between real-time gestures (dragging, resizing, scrolling) and occasional tasks:
*   **Hot Path (Drag/Resize/Scroll):** "Resize push at top" is the historical worst case: the grown item pushes every item below it, then the layout recompacts, per pointer event. These operations trigger up to 60 or 120 times per second during interactions. Their budget is strictly bounded by the hardware rendering refresh rate (16.6ms at 60 Hz, 8.33ms at 120 Hz). Which is why their sub-10ms performance is so critical, guaranteeing flawless visual fluidity.
*   **Cold Path (Optimize/Defrag):** The `optimizeLayout` function runs a bin-packing algorithm to completely defragment grid gaps. This is an on-demand, one-off operation typically triggered via a button click by the user. A full defragmentation of 1 000 items completes in **`2.52 ms`**, and even a massive 10 000 items grid, defrags in under **`60 ms`**, causing no visible stutter.

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
