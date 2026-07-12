import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

void main() {
  group('DashboardNestedCoordinator.maxNestingDepth', () {
    test('null (default) allows any depth', () {
      final c = DashboardNestedCoordinator();
      addTearDown(c.dispose);
      expect(c.maxNestingDepth, isNull);
      expect(c.canHostAtDepth(0), isTrue);
      expect(c.canHostAtDepth(5), isTrue);
      expect(c.canHostAtDepth(100), isTrue);
    });

    test('0 disables nesting: even the root cannot host', () {
      final c = DashboardNestedCoordinator(maxNestingDepth: 0);
      addTearDown(c.dispose);
      expect(c.canHostAtDepth(0), isFalse);
      expect(c.canHostAtDepth(1), isFalse);
    });

    test('1 allows one level: root hosts, its children do not', () {
      final c = DashboardNestedCoordinator(maxNestingDepth: 1);
      addTearDown(c.dispose);
      // Root grid is depth 0 -> may host (creates depth-1 grids).
      expect(c.canHostAtDepth(0), isTrue);
      // A depth-1 grid may not host (would create depth-2).
      expect(c.canHostAtDepth(1), isFalse);
      expect(c.canHostAtDepth(2), isFalse);
    });

    test('2 allows two levels', () {
      final c = DashboardNestedCoordinator(maxNestingDepth: 2);
      addTearDown(c.dispose);
      expect(c.canHostAtDepth(0), isTrue);
      expect(c.canHostAtDepth(1), isTrue);
      expect(c.canHostAtDepth(2), isFalse);
    });

    test('the limit is mutable at runtime', () {
      final c = DashboardNestedCoordinator(maxNestingDepth: 1);
      addTearDown(c.dispose);
      expect(c.canHostAtDepth(1), isFalse);
      c.maxNestingDepth = null;
      expect(c.canHostAtDepth(1), isTrue);
      c.maxNestingDepth = 2;
      expect(c.canHostAtDepth(1), isTrue);
      expect(c.canHostAtDepth(2), isFalse);
    });

    testWidgets('DashboardNestedScope syncs maxNestingDepth onto the coordinator', (tester) async {
      final coordinator = DashboardNestedCoordinator();
      addTearDown(coordinator.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardNestedScope(
            coordinator: coordinator,
            maxNestingDepth: 1,
            child: const SizedBox(),
          ),
        ),
      );
      expect(coordinator.maxNestingDepth, 1);

      // Rebuild with a different value: the scope must push it through.
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardNestedScope(
            coordinator: coordinator,
            maxNestingDepth: 3,
            child: const SizedBox(),
          ),
        ),
      );
      expect(coordinator.maxNestingDepth, 3);
    });
  });
}
