import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';

/// A [CrossGridDragTarget] driven entirely by the test.
///
/// `targetAt` only ever touches `controller`, `canAcceptCrossGridItems`,
/// `isPointInsideSliver` and `itemAtGlobal`, so the remaining members are
/// inert stubs — implementing them for real would test the overlay, not the
/// coordinator.
class FakeGridTarget implements CrossGridDragTarget {
  FakeGridTarget({
    required this.controller,
    required this.bounds,
    this.canAcceptCrossGridItems = true,
    this.canDragItemsOut = true,
    this.hostCellItem,
    this.hostCellBounds,
  });

  @override
  final DashboardController controller;

  /// Area this grid claims, in the same coordinate space the tests probe.
  final Rect bounds;

  @override
  final bool canAcceptCrossGridItems;

  @override
  final bool canDragItemsOut;

  /// What this grid answers when asked which item covers a point. Used to
  /// emulate a parent resolving the host cell of a linked child.
  final LayoutItem? hostCellItem;

  /// Where [hostCellItem] actually sits, in the same coordinate space the
  /// tests probe.
  ///
  /// This must be the host TILE's area, not the whole grid's. A linked child
  /// registration is contained by a point when the PARENT reports its host
  /// item there — `_registrationContains` asks the parent, not the child — so
  /// a fake that answers "host item" everywhere makes the child grid swallow
  /// every point in the parent, and the depth comparison always picks the
  /// child. Defaults to [bounds] for grids that have no linked child.
  final Rect? hostCellBounds;

  int foreignDragLeaveCalls = 0;

  @override
  bool isPointInsideSliver(Offset globalPosition) => bounds.contains(globalPosition);

  @override
  LayoutItem? itemAtGlobal(Offset globalPosition, {String? excludeId}) {
    final item = hostCellItem;
    if (item == null) return null;
    return (hostCellBounds ?? bounds).contains(globalPosition) ? item : null;
  }

  @override
  RenderBox? get overlayRenderBox => null;

  @override
  SlotMetrics? currentSlotMetrics() => null;

  @override
  void foreignDragOver(LayoutItem item, Offset globalPosition) {}

  @override
  void foreignDragLeave() => foreignDragLeaveCalls++;

  @override
  LayoutItem? foreignDrop(LayoutItem item) => null;

  @override
  void setNestHoverHighlight(String? itemId) {}

  @override
  void autoScrollAt(Offset globalPosition) {}

  @override
  void stopAutoScroll() {}
}

void main() {
  late DashboardNestedCoordinator coordinator;
  late DashboardController parentController;
  late DashboardController childController;
  late FakeGridTarget parent;
  late FakeGridTarget child;

  // The child lives inside the "host" tile of the parent, which is the real
  // geometry: both grids contain the probe point, and depth decides.
  const hostItem = LayoutItem(id: 'host', x: 0, y: 0, w: 4, h: 4);
  // The child's viewport, and therefore the area the parent's host tile
  // occupies. Points inside it resolve to the child, points outside to the
  // parent.
  const childBounds = Rect.fromLTWH(100, 100, 200, 200);
  const insideChild = Offset(150, 150);
  const outsideChild = Offset(400, 400);

  const chart = LayoutItem(id: 'chart', x: 0, y: 0, w: 1, h: 1, extra: {'type': 'chart'});
  const note = LayoutItem(id: 'note', x: 1, y: 0, w: 1, h: 1, extra: {'type': 'note'});

  setUp(() {
    coordinator = DashboardNestedCoordinator();
    parentController = DashboardController(
      initialSlotCount: 8,
      initialLayout: const [hostItem],
    );
    childController = DashboardController(initialSlotCount: 4);

    parent = FakeGridTarget(
      controller: parentController,
      bounds: const Rect.fromLTWH(0, 0, 600, 600),
      hostCellItem: hostItem,
      hostCellBounds: childBounds,
    );
    child = FakeGridTarget(
      controller: childController,
      bounds: childBounds,
    );

    coordinator
      ..register(parent, depth: 0)
      ..linkChildGrid(
        parent: parentController,
        parentItemId: 'host',
        child: childController,
      )
      ..register(child, depth: 1);
  });

  tearDown(() => coordinator.dispose());

  group('targetAt — without a filter', () {
    test('resolves the deepest grid under the point', () {
      final reg = coordinator.targetAt(insideChild, draggedItem: chart);
      expect(reg?.target, same(child));
    });

    test('resolves the parent outside the child', () {
      final reg = coordinator.targetAt(outsideChild, draggedItem: chart);
      expect(reg?.target, same(parent));
    });
  });

  group('canAcceptItem — rejection falls back to the parent', () {
    test('a refused child hands the point to its parent', () {
      coordinator.canAcceptItem = (item, target, source) =>
          !identical(target, childController) || item.extra?['type'] == 'chart';

      expect(
        coordinator.targetAt(insideChild, draggedItem: chart)?.target,
        same(child),
        reason: 'accepted items still resolve to the deepest grid',
      );
      expect(
        coordinator.targetAt(insideChild, draggedItem: note)?.target,
        same(parent),
        reason: 'a refused sub-grid must be transparent, not a dead zone',
      );
    });

    test('refusing every grid resolves to nothing', () {
      coordinator.canAcceptItem = (item, target, source) => false;

      expect(coordinator.targetAt(insideChild, draggedItem: chart), isNull);
      expect(coordinator.targetAt(outsideChild, draggedItem: chart), isNull);
    });

    test('the filter is bypassed when no item is supplied', () {
      var calls = 0;
      coordinator.canAcceptItem = (item, target, source) {
        calls++;
        return false;
      };

      // A plain "which grid is under this point?" query is not a drop
      // resolution and must stay unfiltered.
      expect(coordinator.targetAt(insideChild)?.target, same(child));
      expect(calls, 0);
    });

    test('receives the target and the source controllers', () {
      final seen = <({String id, DashboardController target, DashboardController source})>[];
      coordinator
        ..canAcceptItem = (item, target, source) {
          seen.add((id: item.id, target: target, source: source));
          return true;
        }
        ..targetAt(
          insideChild,
          draggedItem: chart,
          sourceController: parentController,
        );

      expect(seen.any((e) => identical(e.target, childController)), isTrue);
      expect(seen.every((e) => identical(e.source, parentController)), isTrue);
      expect(seen.every((e) => e.id == 'chart'), isTrue);
    });

    test('source defaults to the target for a query without a source', () {
      DashboardController? seenSource;
      coordinator
        ..canAcceptItem = (item, target, source) {
          if (identical(target, childController)) seenSource = source;
          return true;
        }
        ..targetAt(insideChild, draggedItem: chart);

      expect(seenSource, same(childController));
    });

    test('runs only for grids that contain the point', () {
      final targets = <DashboardController>[];
      coordinator
        ..canAcceptItem = (item, target, source) {
          targets.add(target);
          return true;
        }

        // Outside the child: the expensive predicate must not be paid for a
        // grid the pointer is nowhere near.
        ..targetAt(outsideChild, draggedItem: chart);

      expect(targets, isNot(contains(childController)));
      expect(targets, contains(parentController));
    });

    test('is not consulted for grids already rejected by acceptingOnly', () {
      final closed = DashboardController(initialSlotCount: 4);
      coordinator.register(
        FakeGridTarget(
          controller: closed,
          bounds: const Rect.fromLTWH(0, 0, 600, 600),
          canAcceptCrossGridItems: false,
        ),
        depth: 0,
      );

      final targets = <DashboardController>[];
      coordinator
        ..canAcceptItem = (item, target, source) {
          targets.add(target);
          return true;
        }
        ..targetAt(outsideChild, draggedItem: chart);

      expect(targets, isNot(contains(closed)));
      closed.dispose();
    });
  });

  group('hasAnyTargetBesides — the same filter', () {
    test('reports nothing available when every other grid refuses the item', () {
      coordinator.canAcceptItem = (item, target, source) => item.extra?['type'] == 'chart';

      expect(coordinator.hasAnyTargetBesides(parent, draggedItem: chart), isTrue);
      expect(
        coordinator.hasAnyTargetBesides(parent, draggedItem: note),
        isFalse,
        reason: 'no valid destination means no exit session should open',
      );
    });

    test('stays unfiltered when no item is supplied', () {
      coordinator.canAcceptItem = (item, target, source) => false;
      expect(coordinator.hasAnyTargetBesides(parent), isTrue);
    });
  });
}
