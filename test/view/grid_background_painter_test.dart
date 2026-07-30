import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';

import '../test_helpers.dart';

void main() {
  const metrics = SlotMetrics(
    slotWidth: 100,
    slotHeight: 100,
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
    padding: EdgeInsets.zero,
    scrollDirection: Axis.vertical,
    slotCount: 4,
  );

  /// Same geometry, but padded — the configuration no test used to exercise.
  const paddedMetrics = SlotMetrics(
    slotWidth: 100,
    slotHeight: 100,
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
    padding: EdgeInsets.all(20),
    scrollDirection: Axis.vertical,
    slotCount: 4,
  );

  GridBackgroundPainter painter({
    SlotMetrics m = metrics,
    double scrollOffset = 0,
    double sliverLayoutStart = 0,
    double sliverContentExtent = 500,
    List<LayoutItem> draggedItems = const [],
    LayoutItem? placeholder,
    bool fillViewport = false,
  }) =>
      GridBackgroundPainter(
        metrics: m,
        scrollOffset: scrollOffset,
        sliverLayoutStart: sliverLayoutStart,
        sliverContentExtent: sliverContentExtent,
        draggedItems: draggedItems,
        placeholder: placeholder,
        fillViewport: fillViewport,
      );

  group('GridBackgroundPainter — content origin (INVARIANT)', () {
    // Anti regression gate test for padded-grid. The main-axis
    // origin is `sliverLayoutStart - scrollOffset` and NOTHING else:
    // `precedingScrollExtent` already carries the enclosing SliverPadding's
    // leading extent. The cross axis is not part of the scroll extent and IS
    // added manually. An error of exactly one padding on one axis means a site
    // added the main-axis padding twice, or resolved the origin as zero.
    test('origin is (padding.left, sliverLayoutStart) at rest', () {
      final canvas = RecordingCanvas();
      painter(m: paddedMetrics, sliverLayoutStart: 20).paint(canvas, const Size(400, 1000));

      expect(canvas.translations, hasLength(1));
      expect(canvas.translations.single, const Offset(20, 20));
    });

    test('the main-axis origin follows the scroll, the cross axis does not', () {
      final canvas = RecordingCanvas();
      painter(m: paddedMetrics, sliverLayoutStart: 20, scrollOffset: 350)
          .paint(canvas, const Size(400, 1000));

      expect(canvas.translations.single, const Offset(20, -330));
    });

    test('a zero padding keeps the historical origin', () {
      final canvas = RecordingCanvas();
      painter(sliverLayoutStart: 0).paint(canvas, const Size(400, 1000));

      expect(canvas.translations.single, Offset.zero);
    });

    test('horizontal scrolling swaps the two axes', () {
      const horizontal = SlotMetrics(
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 10,
        crossAxisSpacing: 30,
        padding: EdgeInsets.all(20),
        scrollDirection: Axis.horizontal,
        slotCount: 4,
      );

      final canvas = RecordingCanvas();
      painter(m: horizontal, sliverLayoutStart: 20).paint(canvas, const Size(1000, 400));

      expect(canvas.translations.single, const Offset(20, 20));
      expect(canvas.saveCalls, 1);
      expect(canvas.restoreCalls, 1);
    });
  });

  group('GridBackgroundPainter — clipping', () {
    test('fillViewport: false clips to the content extent', () {
      final canvas = RecordingCanvas();
      painter(m: paddedMetrics, sliverLayoutStart: 20, sliverContentExtent: 500)
          .paint(canvas, const Size(400, 1000));

      expect(canvas.clipRects, hasLength(1));
      expect(canvas.clipRects.single, const Rect.fromLTRB(0, 20, 400, 520));
    });

    test('fillViewport: true clips to the remaining viewport', () {
      final canvas = RecordingCanvas();
      painter(
        m: paddedMetrics,
        sliverLayoutStart: 20,
        sliverContentExtent: 500,
        fillViewport: true,
      ).paint(canvas, const Size(400, 1000));

      expect(canvas.clipRects.single, const Rect.fromLTRB(0, 20, 400, 1000));
    });

    test('horizontal scrolling clips along the horizontal axis', () {
      const horizontal = SlotMetrics(
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        padding: EdgeInsets.zero,
        scrollDirection: Axis.horizontal,
        slotCount: 4,
      );

      final canvas = RecordingCanvas();
      painter(m: horizontal, sliverContentExtent: 500).paint(canvas, const Size(1000, 400));

      expect(canvas.clipRects.single, const Rect.fromLTRB(0, 0, 500, 400));
    });
  });

  group('GridBackgroundPainter — grid lines', () {
    test('column separators sit in the middle of the cross-axis gutters', () {
      final canvas = RecordingCanvas();
      painter(m: paddedMetrics, sliverLayoutStart: 20, sliverContentExtent: 500)
          .paint(canvas, const Size(400, 1000));

      // slotCount 4 => 3 separators, at i*slotW + (i-1)*spacing + spacing/2.
      expect(canvas.verticalLines.map((l) => l.$1.dx).toList(), [105.0, 215.0, 325.0]);
      // Bounded by the content extent when fillViewport is false.
      expect(canvas.verticalLines.first.$2.dy, 500.0);
    });

    test('row separators start after the first row and stop at the content extent', () {
      final canvas = RecordingCanvas();
      painter(m: paddedMetrics, sliverLayoutStart: 20, sliverContentExtent: 500)
          .paint(canvas, const Size(400, 1000));

      // firstLineY = slotHeight + mainAxisSpacing/2 = 105 ; stride = 110.
      expect(canvas.horizontalLines.map((l) => l.$1.dy).toList(), [105.0, 215.0, 325.0, 435.0]);
    });

    test('fillViewport: true extends the rows to the bottom of the viewport', () {
      final canvas = RecordingCanvas();
      painter(
        m: paddedMetrics,
        sliverLayoutStart: 20,
        sliverContentExtent: 500,
        fillViewport: true,
      ).paint(canvas, const Size(400, 1000));

      expect(canvas.horizontalLines.length, 8, reason: 'up to 980 in content coordinates');
      expect(canvas.horizontalLines.last.$1.dy, 875.0);
    });

    test('rows scrolled above the viewport are skipped, not drawn and clipped', () {
      // The loop is bounded by the clip rect instead of a hard-coded
      // 10,000 px extent. With the content scrolled 200 px up, the first VISIBLE
      // separator is the second one, and the first must never be emitted.
      final canvas = RecordingCanvas();
      painter(scrollOffset: 200, sliverContentExtent: 2000).paint(canvas, const Size(400, 1000));

      expect(canvas.horizontalLines.first.$1.dy, 215.0);
      expect(
        canvas.horizontalLines.map((l) => l.$1.dy),
        isNot(contains(105.0)),
        reason: 'the off-screen leading separator must be skipped',
      );
    });

    test('a fully scrolled-past grid emits no row separator', () {
      final canvas = RecordingCanvas();
      painter(scrollOffset: 5000, sliverContentExtent: 500).paint(canvas, const Size(400, 1000));

      expect(canvas.horizontalLines, isEmpty);
      expect(canvas.verticalLines, hasLength(3), reason: 'columns are drawn before the guard');
    });

    test('a non-positive stride bails out instead of looping forever', () {
      const degenerate = SlotMetrics(
        slotWidth: 100,
        slotHeight: 0,
        mainAxisSpacing: 0,
        crossAxisSpacing: 10,
        padding: EdgeInsets.zero,
        scrollDirection: Axis.vertical,
        slotCount: 4,
      );

      final canvas = RecordingCanvas();
      painter(m: degenerate).paint(canvas, const Size(400, 1000));

      expect(canvas.horizontalLines, isEmpty);
    });

    test('horizontal scrolling: separators use the mirrored spacings', () {
      const horizontal = SlotMetrics(
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 10,
        crossAxisSpacing: 30,
        padding: EdgeInsets.zero,
        scrollDirection: Axis.horizontal,
        slotCount: 4,
      );

      final canvas = RecordingCanvas();
      painter(m: horizontal, sliverContentExtent: 500).paint(canvas, const Size(1000, 400));

      // Cross-axis (rows) use mainAxisSpacing here: i*100 + (i-1)*10 + 5.
      expect(canvas.horizontalLines.map((l) => l.$1.dy).toList(), [105.0, 215.0, 325.0]);
      // Main-axis (columns) use crossAxisSpacing: first at 100 + 15 = 115, stride 130.
      expect(canvas.verticalLines.first.$1.dx, 115.0);
    });

    test('a degenerate main-axis stride bails out (horizontal)', () {
      const degenerate = SlotMetrics(
        slotWidth: 0,
        slotHeight: 100,
        mainAxisSpacing: 10,
        crossAxisSpacing: 0,
        padding: EdgeInsets.zero,
        scrollDirection: Axis.horizontal,
        slotCount: 4,
      );

      final canvas = RecordingCanvas();
      painter(m: degenerate).paint(canvas, const Size(1000, 400));

      expect(canvas.verticalLines, isEmpty);
    });

    test('a fully scrolled-past grid emits no column separator (horizontal)', () {
      const horizontal = SlotMetrics(
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        padding: EdgeInsets.zero,
        scrollDirection: Axis.horizontal,
        slotCount: 4,
      );

      final canvas = RecordingCanvas();
      painter(m: horizontal, scrollOffset: 5000, sliverContentExtent: 500)
          .paint(canvas, const Size(1000, 400));

      expect(canvas.verticalLines, isEmpty);
    });

    test('the off-screen leading column is skipped (horizontal)', () {
      const horizontal = SlotMetrics(
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        padding: EdgeInsets.zero,
        scrollDirection: Axis.horizontal,
        slotCount: 4,
      );

      final canvas = RecordingCanvas();
      painter(m: horizontal, scrollOffset: 200, sliverContentExtent: 2000)
          .paint(canvas, const Size(1000, 400));

      expect(canvas.verticalLines.first.$1.dx, 215.0);
    });
  });

  group('GridBackgroundPainter — highlights', () {
    test('the dragged item rect uses the vertical axis mapping', () {
      const vertical = SlotMetrics(
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 10,
        crossAxisSpacing: 30,
        padding: EdgeInsets.zero,
        scrollDirection: Axis.vertical,
        slotCount: 4,
      );

      final canvas = RecordingCanvas();
      painter(
        m: vertical,
        draggedItems: const [LayoutItem(id: 'a', x: 1, y: 1, w: 1, h: 1)],
      ).paint(canvas, const Size(400, 1000));

      // x stride uses crossAxisSpacing (30), y stride uses mainAxisSpacing (10).
      expect(canvas.rects, hasLength(1));
      expect(canvas.rects.single, const Rect.fromLTWH(130, 110, 100, 100));
    });

    test('the dragged item rect uses the horizontal axis mapping', () {
      const horizontal = SlotMetrics(
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 10,
        crossAxisSpacing: 30,
        padding: EdgeInsets.zero,
        scrollDirection: Axis.horizontal,
        slotCount: 4,
      );

      final canvas = RecordingCanvas();
      painter(
        m: horizontal,
        draggedItems: const [LayoutItem(id: 'a', x: 1, y: 1, w: 1, h: 1)],
      ).paint(canvas, const Size(1000, 400));

      // Mirrored: x stride uses mainAxisSpacing (10), y stride crossAxisSpacing (30).
      expect(canvas.rects.single, const Rect.fromLTWH(110, 130, 100, 100));
    });

    test('the placeholder is highlighted alongside the dragged items', () {
      final canvas = RecordingCanvas();
      painter(
        draggedItems: const [LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1)],
        placeholder: const LayoutItem(id: 'p', x: 2, y: 0, w: 1, h: 1),
      ).paint(canvas, const Size(400, 1000));

      expect(canvas.rects, hasLength(2));
    });

    test('nothing is filled when neither is present', () {
      final canvas = RecordingCanvas();
      painter().paint(canvas, const Size(400, 1000));

      expect(canvas.rects, isEmpty);
    });
  });

  group('GridBackgroundPainter — shouldRepaint', () {
    final base = painter(
      draggedItems: const [LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)],
    );

    // One case per clause of shouldRepaint. `sliverLayoutStart` and
    // `sliverContentExtent` replaced the `renderSliver` reference precisely
    // because a RenderObject reference is STABLE across mutations of its own
    // constraints/geometry — the painter could not detect them, and a stale
    // sliver kept the background one padding too high indefinitely.
    final _ = <String, GridBackgroundPainter>{
      'metrics': painter(
        m: paddedMetrics,
        draggedItems: const [LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)],
      ),
      'scrollOffset': painter(
        scrollOffset: 10,
        draggedItems: const [LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)],
      ),
      'sliverLayoutStart': painter(
        sliverLayoutStart: 20,
        draggedItems: const [LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)],
      ),
      'sliverContentExtent': painter(
        sliverContentExtent: 900,
        draggedItems: const [LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)],
      ),
      'draggedItems': painter(
        draggedItems: const [LayoutItem(id: '2', x: 0, y: 0, w: 1, h: 1)],
      ),
      'placeholder': painter(
        draggedItems: const [LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)],
        placeholder: const LayoutItem(id: 'p', x: 0, y: 0, w: 1, h: 1),
      ),
      'fillViewport': painter(
        fillViewport: true,
        draggedItems: const [LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)],
      ),
    }..forEach((name, candidate) {
        test('repaints when $name changes', () {
          expect(candidate.shouldRepaint(base), isTrue);
        });
      });

    test('repaints when a style property changes', () {
      const items = [LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)];

      GridBackgroundPainter styled({Color? line, double? width, Color? fill}) =>
          GridBackgroundPainter(
            metrics: metrics,
            scrollOffset: 0,
            sliverLayoutStart: 0,
            sliverContentExtent: 500,
            draggedItems: items,
            lineColor: line ?? const Color(0x1F000000),
            lineWidth: width ?? 1.0,
            fillColor: fill ?? const Color(0x1F000000),
          );

      final reference = styled();
      expect(styled(line: const Color(0xFFFF0000)).shouldRepaint(reference), isTrue);
      expect(styled(width: 2).shouldRepaint(reference), isTrue);
      expect(styled(fill: const Color(0xFF00FF00)).shouldRepaint(reference), isTrue);
    });

    test('does not repaint when nothing changed', () {
      final twin = painter(
        draggedItems: const [LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)],
      );
      expect(twin.shouldRepaint(base), isFalse);
    });

    test('deep-compares draggedItems', () {
      const itemA = LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1);
      const itemB = LayoutItem(id: '2', x: 0, y: 0, w: 1, h: 1);

      final reference = painter(draggedItems: const [itemA]);

      // Same instance.
      expect(
        painter(draggedItems: reference.draggedItems).shouldRepaint(reference),
        isFalse,
      );
      // Different instance, same content.
      expect(painter(draggedItems: const [itemA]).shouldRepaint(reference), isFalse);
      // Different content.
      expect(painter(draggedItems: const [itemB]).shouldRepaint(reference), isTrue);
      // Different length.
      expect(
        painter(draggedItems: const [itemA, itemB]).shouldRepaint(reference),
        isTrue,
      );
    });

    test('listEquals handles the nullable cases', () {
      // Not reachable through shouldRepaint (draggedItems is non-nullable), but
      // the helper is public on the painter and its null branches are real code.
      final p = painter();
      expect(p.listEquals<int>(null, null), isTrue);
      expect(p.listEquals<int>(null, const []), isFalse);
      expect(p.listEquals<int>(const [], null), isFalse);
      expect(p.listEquals<int>(const [1], const [1]), isTrue);
    });
  });
}
