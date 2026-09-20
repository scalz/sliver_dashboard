// Frame-pacing harness for end-to-end profiling on Flutter web.
//
// The example app renders a handful of cards, so neither a fast nor a slow
// collision engine is stressed by it. This entrypoint mounts the shape the
// engine work actually targets — a dense grid with tall banners in it — so a
// real drag in a real browser can be compared across revisions.
//
//   flutter build web --release -t lib/perf_harness.dart
//
// Drive it with a drag and read `window.__frames` (an array of frame
// timestamps recorded by the page).
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
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

class _PerfHarnessAppState extends State<PerfHarnessApp> {
  late DashboardController _controller;
  bool _withBanners = true;

  @override
  void initState() {
    super.initState();
    _build();
  }

  void _build() {
    _controller = DashboardController(
      initialSlotCount: kCols,
      initialLayout: buildLayout(withBanners: _withBanners),
    )..setEditMode(true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
        ),
        body: Dashboard<String>(
          controller: _controller,
          slotAspectRatio: 1,
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
    );
  }
}
