// Frame-pacing harness for end-to-end profiling, built for Flutter web.
//
// The example app renders a handful of cards, so neither a fast nor a slow
// collision engine is stressed by it. This entrypoint mounts the shape the
// engine work actually targets — a dense grid with tall banners in it — so a
// real drag in a real browser can be compared across revisions.
//
//   flutter build web --release -t lib/perf_harness.dart          (dart2js)
//   flutter build web --release --wasm -t lib/perf_harness.dart   (wasm)
//
// Serve build/web, perform the gesture, and read the frame panel at the
// bottom-right (frames, slowest, p90, frames over 16.7 / 8.3 ms). "Reset"
// clears it before a measured gesture and prints the previous run to the
// console. Profile mode works too: flutter run -d chrome --profile -t ...
//
// The 2.11 options are toggled by the chips in the app bar, or preset from
// the URL query (web): ?banners=0&strict=1&sizes=1&overlay=1&handles=1
// &autoscroll=fast|slow|off
// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

const int kItemCount = 4000;
const int kCols = 12;
const int kBannerEvery = 100;
const int kBannerHeight = 16;

List<LayoutItem> buildLayout({required bool withBanners}) {
  const w = 2;
  const h = 2;
  final items = <LayoutItem>[];
  var y = 0;
  var x = 0;
  for (var i = 0; i < kItemCount; i++) {
    if (withBanners && i > 0 && i % kBannerEvery == 0) {
      if (x != 0) {
        y += h;
        x = 0;
      }
      items.add(
        LayoutItem(
          id: 'ban${i.toString().padLeft(6, '0')}',
          x: 0,
          y: y,
          w: kCols,
          h: kBannerHeight,
        ),
      );
      y += kBannerHeight;
    }
    if (x + w > kCols) {
      x = 0;
      y += h;
    }
    items.add(
      LayoutItem(
        id: 'i${i.toString().padLeft(6, '0')}',
        x: x,
        y: y,
        w: w,
        h: h,
      ),
    );
    x += w;
  }
  // Id-sorted, like every layout the engine ever sees (Index Stability).
  // Interleaving `ban...` and `i...` ids would exercise the engine's
  // unsorted-input fallback — a path production never takes.
  return items..sort((a, b) => a.id.compareTo(b.id));
}

void main() {
  runApp(const PerfHarnessApp());
}

class PerfHarnessApp extends StatefulWidget {
  const PerfHarnessApp({super.key});

  @override
  State<PerfHarnessApp> createState() => _PerfHarnessAppState();
}

/// Three allowed sizes; the banners keep their own size (always accepted).
class _HarnessSizes extends DashboardPolicy {
  const _HarnessSizes();

  @override
  bool isSizeAllowed(LayoutItem item, int w, int h) =>
      const {(1, 1), (2, 2), (4, 2)}.contains((w, h));
}

class _PerfHarnessAppState extends State<PerfHarnessApp> {
  late DashboardController _controller;
  late bool _withBanners;
  late bool _strict;
  late bool _sizes;
  late bool _overlay;
  late bool _handles;
  late String _autoScroll;

  @override
  void initState() {
    super.initState();
    final q = Uri.base.queryParameters;
    bool flag(String key, {bool fallback = false}) =>
        q[key] == null ? fallback : q[key] == '1' || q[key] == 'true';
    _withBanners = flag('banners', fallback: true);
    _strict = flag('strict');
    _sizes = flag('sizes');
    _overlay = flag('overlay');
    _handles = flag('handles');
    _autoScroll = q['autoscroll'] ?? 'default';
    _build();
  }

  void _build() {
    _controller = DashboardController(
      initialSlotCount: kCols,
      initialLayout: buildLayout(withBanners: _withBanners),
    )..setEditMode(true);
    _applyOptions();
  }

  void _applyOptions() {
    // A full board: the ceiling sits right under the last row, so the strict
    // guard has something to refuse on every push past the bottom.
    _controller
      ..setMaxRows(
        _strict ? mainAxisExtent(_controller.layout.value) + 2 : null,
      )
      ..setStrictMaxRows(_strict)
      ..policy = _sizes ? const _HarnessSizes() : null
      ..autoScroll = switch (_autoScroll) {
        'fast' => const AutoScrollConfig(edgeExtent: 90, maxSpeed: 2000),
        'slow' => const AutoScrollConfig(edgeExtent: 40, maxSpeed: 400),
        'off' => AutoScrollConfig.off,
        _ => AutoScrollConfig.byDefault,
      };
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _chip(String label, bool value, ValueChanged<bool> onChanged) =>
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          label: Text(label, style: const TextStyle(fontSize: 11)),
          selected: value,
          onSelected: (v) => setState(() {
            onChanged(v);
            _applyOptions();
          }),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: Text(
            'perf harness — $kItemCount tiles, '
            '${_withBanners ? "with" : "no"} banners',
          ),
          actions: [
            TextButton(
              key: const Key('toggle-banners'),
              onPressed: () {
                final old = _controller;
                setState(() {
                  _withBanners = !_withBanners;
                  _build();
                });
                old.dispose();
              },
              child: const Text('toggle banners'),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  _chip('strictMaxRows', _strict, (v) => _strict = v),
                  _chip('isSizeAllowed', _sizes, (v) => _sizes = v),
                  _chip('editOverlayBuilder', _overlay, (v) => _overlay = v),
                  _chip('resizeHandleBuilder', _handles, (v) => _handles = v),
                  for (final preset in const ['default', 'fast', 'slow', 'off'])
                    _chip(
                      'autoscroll: $preset',
                      _autoScroll == preset,
                      (_) => _autoScroll = preset,
                    ),
                ],
              ),
            ),
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: Dashboard<String>(
                controller: _controller,
                slotAspectRatio: 1,
                editOverlayBuilder: _overlay
                    ? (context, item, actions) => Align(
                        alignment: Alignment.topRight,
                        child: GestureDetector(
                          onTap: actions.delete,
                          child: const Icon(Icons.close, size: 12),
                        ),
                      )
                    : null,
                resizeHandleBuilder: _handles
                    ? (context, item, handle, size) => const DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.teal,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
                itemBuilder: (context, item) => Container(
                  decoration: BoxDecoration(
                    color: item.id.startsWith('ban')
                        ? Colors.deepOrange.shade100
                        : Colors.blueGrey.shade100,
                    border: Border.all(color: Colors.blueGrey.shade400),
                  ),
                  alignment: Alignment.center,
                  child: Text(item.id, style: const TextStyle(fontSize: 9)),
                ),
              ),
            ),
            const Positioned(right: 8, bottom: 8, child: FrameStatsPanel()),
          ],
        ),
      ),
    );
  }
}

/// Live frame statistics from [SchedulerBinding.addTimingsCallback].
///
/// `totalSpan` runs from vsync to the end of rasterization. On the web the
/// raster part is what the engine can measure; compare runs on the same
/// browser and machine only.
class FrameStatsPanel extends StatefulWidget {
  const FrameStatsPanel({super.key});

  @override
  State<FrameStatsPanel> createState() => _FrameStatsPanelState();
}

class _FrameStatsPanelState extends State<FrameStatsPanel> {
  final List<double> _ms = [];

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!mounted) return;
    setState(() {
      for (final t in timings) {
        _ms.add(t.totalSpan.inMicroseconds / 1000);
      }
    });
  }

  String _summary() {
    if (_ms.isEmpty) return 'no frame yet';
    final sorted = [..._ms]..sort();
    final p90 =
        sorted[math.min(sorted.length - 1, (sorted.length * 0.9).floor())];
    final over16 = _ms.where((m) => m > 16.7).length;
    final over8 = _ms.where((m) => m > 8.3).length;
    return '${_ms.length} frames · slowest ${sorted.last.toStringAsFixed(1)} ms'
        ' · p90 ${p90.toStringAsFixed(1)} ms · >16.7 ms: $over16'
        ' · >8.3 ms: $over8';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_summary(), style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            TextButton(
              key: const Key('reset-frames'),
              onPressed: () {
                print('[perf harness] ${_summary()}');
                setState(_ms.clear);
              },
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}
