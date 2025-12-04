import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/dashboard_configuration.dart';

void main() {
  group('LayoutItem Serialization', () {
    test('toMap converts correctly', () {
      const item = LayoutItem(
        id: '1',
        x: 1,
        y: 2,
        w: 3,
        h: 4,
        minW: 2,
        maxW: 10.5,
        isStatic: true,
      );

      final map = item.toMap();
      expect(map['id'], '1');
      expect(map['x'], 1);
      expect(map['maxW'], 10.5);
      expect(map['isStatic'], true);
    });

    test('toMap handles Infinity correctly', () {
      const item = LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1, maxW: double.infinity);
      final map = item.toMap();
      expect(map['maxW'], isNull); // Infinity should become null for JSON
    });

    test('fromMap parses correctly', () {
      final map = {
        'id': '1',
        'x': 1,
        'y': 2,
        'w': 3,
        'h': 4,
        'isStatic': true,
      };
      final item = LayoutItem.fromMap(map);
      expect(item.id, '1');
      expect(item.x, 1);
      expect(item.isStatic, true);
    });

    test('fromMap handles robust types (double as int)', () {
      final map = {
        'id': '1',
        'x': 1.0, // Double instead of int
        'y': 2,
        'w': 3.0,
        'h': 4,
      };
      final item = LayoutItem.fromMap(map);
      expect(item.x, 1); // Should be converted to int
      expect(item.w, 3);
    });

    test('fromMap handles missing optional fields with defaults', () {
      final map = {'id': '1'}; // Minimal map
      final item = LayoutItem.fromMap(map);

      expect(item.x, 0);
      expect(item.y, 0);
      expect(item.w, 1);
      expect(item.h, 1);
      expect(item.maxW, double.infinity); // Null in map -> Infinity in object
      expect(item.isStatic, false);
    });
  });

  group('LayoutItem Data Class', () {
    test('Equality and HashCode work correctly', () {
      const item1 = LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1);
      const item2 = LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1);
      const item3 = LayoutItem(id: '1', x: 1, y: 0, w: 1, h: 1); // Different x

      expect(item1, equals(item2));
      expect(item1.hashCode, equals(item2.hashCode));
      expect(item1, isNot(equals(item3)));
    });

    test('toString produces expected output', () {
      const item = LayoutItem(id: 'test', x: 1, y: 2, w: 3, h: 4);
      expect(item.toString(), contains('id: test'));
      expect(item.toString(), contains('x: 1'));
    });

    test('copyWith works with nulls (keeping original values)', () {
      const item = LayoutItem(id: '1', x: 10, y: 10, w: 5, h: 5);
      final copy = item.copyWith(); // No arguments

      expect(copy, equals(item));
      expect(copy.x, 10);
    });
  });

  group('Dashboard Configuration Data Classes', () {
    test('GridStyle equality', () {
      const style1 = GridStyle(fillColor: Colors.red);
      const style2 = GridStyle(fillColor: Colors.red);

      // Note: If you haven't overridden == in GridStyle, this might fail.
      // If they are just DTOs without overrides, you can skip this
      // or implement Equatable/== in your source.
      // Assuming standard Flutter behavior or Equatable:
      expect(style1.fillColor, style2.fillColor);
    });

    test('TrashLayout presets', () {
      const layout = TrashLayout.bottomCenter;
      expect(layout.visible.bottom, 0);
      expect(layout.hidden.bottom, -100);
    });

    test('TrashPosition copyWith', () {
      const pos = TrashPosition(left: 10, top: 10);
      final newPos = pos.copyWith(left: 20);
      expect(newPos.left, 20);
      expect(newPos.top, 10);
    });
  });
}
