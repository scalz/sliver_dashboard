import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';

void main() {
  group('SlotMetrics equality & hashCode', () {
    const base = SlotMetrics(
      slotWidth: 100,
      slotHeight: 50,
      mainAxisSpacing: 8,
      crossAxisSpacing: 4,
      padding: EdgeInsets.all(2),
      scrollDirection: Axis.vertical,
      slotCount: 4,
    );

    test('equal values are == and share a hashCode', () {
      const same = SlotMetrics(
        slotWidth: 100,
        slotHeight: 50,
        mainAxisSpacing: 8,
        crossAxisSpacing: 4,
        padding: EdgeInsets.all(2),
        scrollDirection: Axis.vertical,
        slotCount: 4,
      );
      expect(base, equals(same));
      expect(base.hashCode, same.hashCode);
    });

    test('any differing field breaks equality', () {
      const differing = SlotMetrics(
        slotWidth: 100,
        slotHeight: 50,
        mainAxisSpacing: 8,
        crossAxisSpacing: 4,
        padding: EdgeInsets.all(2),
        scrollDirection: Axis.vertical,
        slotCount: 5, // differs
      );
      expect(base == differing, isFalse);
      expect(base == Object(), isFalse);
    });
  });
}
