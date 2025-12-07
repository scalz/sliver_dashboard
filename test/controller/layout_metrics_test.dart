import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';

void main() {
  group('SlotMetrics', () {
    const slotCount = 4;
    const slotAspectRatio = 1.0;
    const mainAxisSpacing = 10.0;
    const crossAxisSpacing = 5.0;
    const padding = EdgeInsets.fromLTRB(10, 20, 10, 20); // L=10, T=20

    group('fromConstraints calculation', () {
      test('calculates sizes correctly for Axis.vertical', () {
        const constraints =
            BoxConstraints(maxWidth: 4 * 100 + 3 * 5 + 10 * 2, maxHeight: 600); // MaxW = 435

        final metrics = SlotMetrics.fromConstraints(
          constraints,
          slotCount: slotCount,
          slotAspectRatio: slotAspectRatio,
          mainAxisSpacing: mainAxisSpacing,
          crossAxisSpacing: crossAxisSpacing,
          padding: padding,
          scrollDirection: Axis.vertical,
        );

        // Available Width: 435 - 20 (padding horizontal) = 415
        // slotWidth: (415 - 3 * 5) / 4 = 400 / 4 = 100
        expect(metrics.slotWidth, 100.0);
        expect(metrics.slotHeight, 100.0);
      });

      test('calculates sizes correctly for Axis.horizontal', () {
        const constraints =
            BoxConstraints(maxWidth: 800, maxHeight: 4 * 50 + 3 * 10 + 20 * 2); // MaxH = 270

        final metrics = SlotMetrics.fromConstraints(
          constraints,
          slotCount: slotCount,
          slotAspectRatio: 1,
          mainAxisSpacing: mainAxisSpacing,
          crossAxisSpacing: crossAxisSpacing,
          padding: padding,
          scrollDirection: Axis.horizontal,
        );

        // Available Height: 270 - 40 (padding vertical) = 230
        // slotHeight: (230 - 3 * 10) / 4 = 200 / 4 = 50
        expect(metrics.slotHeight, 50.0);
        expect(metrics.slotWidth, 50.0);
      });
    });

    group('pixelToGrid conversion', () {
      final metrics = SlotMetrics.fromConstraints(
        const BoxConstraints(maxWidth: 4 * 100 + 3 * 5 + 10 * 2, maxHeight: 600),
        slotCount: slotCount,
        slotAspectRatio: slotAspectRatio,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
        padding: padding,
        scrollDirection: Axis.vertical,
      );

      // slotWidth = 100, crossAxisSpacing = 5, padding.left = 10, padding.top = 20

      test('returns correct grid coordinates for Axis.vertical (no scroll)', () {
        // Point: x=115, y=130 (Should be in cell x=1, y=1)
        // dx = 115 (local) - 10 (padding.left) = 105
        // dy = 130 (local) + 0 (scroll) - 20 (padding.top) = 110
        // x = floor(105 / (100 + 5)) = floor(105/105) = 1
        // y = floor(110 / (100 + 10)) = floor(110/110) = 1
        final gridPos = metrics.pixelToGrid(const Offset(115, 130), 0);
        expect(gridPos.x, 1);
        expect(gridPos.y, 1);
      });

      test('returns correct grid coordinates for Axis.vertical (with scroll)', () {
        // Scroll: 220 (2 rows worth of height+spacing)
        // Point: x=115, y=20 (Should be in cell x=1, y=1, which is now scrolled to the top)
        // dy = 20 (local) + 220 (scroll) - 20 (padding.top) = 220
        // y = floor(220 / 110) = 2. But scroll is 2 rows, so index 2 starts at 220.
        // Let's target the exact beginning of y=1 (now index 3): y=20.
        final gridPos = metrics.pixelToGrid(const Offset(115, 20), 220); // 220 = 2 * (100+10)

        // This point is 20px down from top, but scrolled up 220px.
        // Effective Y content position: 20 + 220 - 20 (padding) = 220.
        // 220 / 110 = 2.
        expect(gridPos.x, 1);
        expect(gridPos.y, 2);
      });

      test('returns correct grid coordinates for Axis.horizontal (with scroll)', () {
        final horizontalMetrics = SlotMetrics.fromConstraints(
          const BoxConstraints(maxWidth: 800, maxHeight: 4 * 50 + 3 * 10 + 20 * 2),
          slotCount: 4,
          slotAspectRatio: 1,
          mainAxisSpacing: mainAxisSpacing, // X-axis spacing
          crossAxisSpacing: crossAxisSpacing, // Y-axis spacing
          padding: padding,
          scrollDirection: Axis.horizontal,
        );

        // slotWidth = 50, slotHeight = 50. mainAxisSpacing = 10 (X-spacing), crossAxisSpacing = 5 (Y-spacing)
        // Effective Width = 60, Effective Height = 55. Padding L=10, T=20.

        // Point: x=15, y=75 (Should be x=1, y=1 after scroll)
        // scrollOffset = 60 (1 col)
        // dx = 15 (local) + 60 (scroll) - 10 (padding.left) = 65
        // dy = 75 (local) - 20 (padding.top) = 55
        // x = floor(65 / 60) = 1
        // y = floor(55 / 55) = 1
        final gridPos = horizontalMetrics.pixelToGrid(const Offset(15, 75), 60);
        expect(gridPos.x, 1);
        expect(gridPos.y, 1);
      });
    });
  });
}
