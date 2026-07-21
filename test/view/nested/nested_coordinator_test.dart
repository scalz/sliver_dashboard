import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart'
    show CrossGridExitOutcome;
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';

import '../../test_helpers.dart';

//
// ignore_for_file: cascade_invocations

/// A minimal in-test [CrossGridDragTarget]: geometry comes from a real
/// attached [RenderBox] (pumped by the test), behavior is scripted so the
/// coordinator's own state machine can be exercised without gestures.
class _FakeTarget implements CrossGridDragTarget {
  _FakeTarget(this.controller);

  @override
  final DashboardController controller;

  /// Resolved lazily on every call — exactly like the real overlay does with
  /// its stack key — so a frame that replaces/detaches the render object
  /// between capture and use can never leave the fake holding a stale box.
  RenderBox? Function()? boxProvider;
  bool accept = true;
  bool dragOut = true;
  bool insideSliver = true;

  LayoutItem? hoverItem; // returned by itemAtGlobal
  LayoutItem? dropResult; // returned by foreignDrop
  LayoutItem? lastOverItem;
  int overCalls = 0;
  int leaveCalls = 0;
  String? highlight;
  int autoScrollCalls = 0;
  int stopScrollCalls = 0;

  @override
  bool get canAcceptCrossGridItems => accept;

  @override
  bool get canDragItemsOut => dragOut;

  @override
  RenderBox? get overlayRenderBox => boxProvider?.call();

  @override
  SlotMetrics? currentSlotMetrics() => null;

  @override
  void foreignDragOver(LayoutItem item, Offset globalPosition) {
    lastOverItem = item;
    overCalls++;
  }

  @override
  void foreignDragLeave() => leaveCalls++;

  @override
  LayoutItem? foreignDrop(LayoutItem item) => dropResult;

  @override
  LayoutItem? itemAtGlobal(Offset globalPosition, {String? excludeId}) =>
      hoverItem?.id == excludeId ? null : hoverItem;

  @override
  void setNestHoverHighlight(String? itemId) => highlight = itemId;

  @override
  void autoScrollAt(Offset globalPosition) => autoScrollCalls++;

  @override
  void stopAutoScroll() => stopScrollCalls++;

  @override
  bool isPointInsideSliver(Offset globalPosition) {
    if (!insideSliver) return false;

    final box = overlayRenderBox;
    // If no RenderBox is attached/provided, the target is logically
    // off-grid and cannot contain any global pointer coordinate. Return false.
    if (box == null || !box.attached) return false;

    final local = box.globalToLocal(globalPosition);
    return local.dx >= 0 &&
        local.dy >= 0 &&
        local.dx <= box.size.width &&
        local.dy <= box.size.height;
  }
}

/// Lazy render-box resolver for [_FakeTarget.boxProvider].
RenderBox? Function() boxOf(GlobalKey key) =>
    () => key.currentContext?.findRenderObject() as RenderBox?;

void main() {
  group('DashboardNestedCoordinator - Logical State Machine', () {
    late DashboardController origin;
    late DashboardController other;
    late DashboardNestedCoordinator coordinator;

    setUp(() {
      origin = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'x1', x: 0, y: 0, w: 2, h: 1),
          LayoutItem(id: 'x2', x: 2, y: 0, w: 2, h: 1),
        ],
      )..setEditMode(true);
      other = DashboardController(initialSlotCount: 4)..setEditMode(true);
      coordinator = DashboardNestedCoordinator();
    });

    tearDown(() {
      coordinator.dispose();
      origin.dispose();
      other.dispose();
    });

    test('probePointFor: itemCenter follows the tile center, not the cursor', () {
      coordinator.probe = CrossGridProbe.itemCenter;
      final p = coordinator.probePointFor(
        const Offset(100, 100),
        grabOffset: const Offset(10, 5),
        itemPixelSize: const Size(80, 40),
      );
      expect(p, const Offset(130, 115));

      coordinator.probe = CrossGridProbe.pointer;
      expect(
        coordinator.probePointFor(
          const Offset(100, 100),
          grabOffset: const Offset(10, 5),
          itemPixelSize: const Size(80, 40),
        ),
        const Offset(100, 100),
      );
    });

    test('link / hasChildGrid / childGridsOf / childrenOf / unlink lifecycle', () {
      final childCtrl = DashboardController(initialSlotCount: 2);
      addTearDown(childCtrl.dispose);

      expect(coordinator.hasChildGrid(origin, 'x1'), isFalse);

      coordinator.linkChildGrid(parent: origin, parentItemId: 'x1', child: childCtrl);
      expect(coordinator.hasChildGrid(origin, 'x1'), isTrue);
      expect(coordinator.hasChildGrid(origin, 'x2'), isFalse);
      expect(coordinator.childGridsOf(origin), {'x1': childCtrl});

      final childTarget = _FakeTarget(childCtrl);
      final reg = coordinator.register(childTarget, depth: 1);
      expect(reg.parentController, same(origin));
      expect(reg.parentItemId, 'x1');
      expect(coordinator.childrenOf(origin).map((r) => r.target), [childTarget]);

      coordinator.unlinkChildGrid(childCtrl);
      expect(coordinator.hasChildGrid(origin, 'x1'), isFalse);
      expect(coordinator.childGridsOf(origin), isEmpty);
      expect(reg.parentController, isNull);
      expect(reg.parentItemId, isNull);
      expect(coordinator.childrenOf(origin), isEmpty);

      coordinator.unregister(childTarget);
    });

    test(
        'stashChildGrid / takeStashedChildGrid, and deliverChildGrid falls back '
        'to the stash when no grid is linked for the host item', () {
      const data = NestedGridData(
        items: [LayoutItem(id: 'n1', x: 0, y: 0, w: 1, h: 1)],
        slotCount: 3,
      );

      coordinator.deliverChildGrid('ghost', data);
      final taken = coordinator.takeStashedChildGrid('ghost');
      expect(taken, isNotNull);
      expect(taken!.slotCount, 3);
      expect(taken.items.single.id, 'n1');
      expect(coordinator.takeStashedChildGrid('ghost'), isNull);

      coordinator.stashChildGrid('ghost2', data);
      expect(coordinator.takeStashedChildGrid('ghost2'), isNotNull);
    });

    test('moveItemToGrid honors explicit coordinates and rejects no-ops', () {
      expect(
        coordinator.moveItemToGrid(from: origin, to: origin, itemId: 'x1'),
        isNull,
      );
      expect(
        coordinator.moveItemToGrid(from: origin, to: other, itemId: 'nope'),
        isNull,
      );
      expect(origin.layout.value.length, 2);
      expect(other.layout.value, isEmpty);

      final placed = coordinator.moveItemToGrid(
        from: origin,
        to: other,
        itemId: 'x1',
        x: 1,
        y: 0,
      );
      expect(placed, isNotNull);
      expect(other.layout.value.single.id, 'x1');
      expect(origin.layout.value.any((i) => i.id == 'x1'), isFalse);
      expect(placed!.x, 1);
    });

    test('moveItemToGrid asserts if target grid already contains the item id', () {
      // Add a duplicate item to the target grid beforehand
      other.addItem(const LayoutItem(id: 'x1', x: 0, y: 0, w: 1, h: 1));

      expect(
        () => coordinator.moveItemToGrid(from: origin, to: other, itemId: 'x1'),
        throwsAssertionError,
      );
    });

    testWidgets('session lifecycle: enter, hover, leave, drop into another grid', (tester) async {
      final boxKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(key: boxKey, width: 200, height: 200),
          ),
        ),
      );

      final sourceTarget = _FakeTarget(origin);
      final destTarget = _FakeTarget(other)..boxProvider = boxOf(boxKey);
      coordinator
        ..register(sourceTarget, depth: 0)
        ..register(destTarget, depth: 0);

      var moved = 0;
      coordinator.onItemMovedToGrid = (item, from, to) {
        moved++;
        expect(item.id, 'x1');
        expect(identical(from, origin), isTrue);
        expect(identical(to, other), isTrue);
      };

      final item = origin.layout.value.first; // x1
      coordinator.beginSession(
        source: sourceTarget,
        item: item,
        globalPosition: const Offset(50, 50),
        grabOffset: Offset.zero,
        itemPixelSize: const Size(80, 40),
        overlayContext: boxKey.currentContext!,
        proxyChild: const SizedBox(),
      );
      expect(coordinator.sessionActive, isTrue);
      expect(coordinator.isSessionOwner(sourceTarget), isTrue);
      expect(coordinator.isSessionOwner(destTarget), isFalse);
      expect(origin.layout.value.any((i) => i.id == 'x1'), isFalse);

      coordinator.updateSession(const Offset(50, 50));
      expect(destTarget.overCalls, greaterThan(0));
      expect(destTarget.lastOverItem!.id, 'x1');

      coordinator.updateSession(const Offset(500, 500));
      expect(destTarget.leaveCalls, 1);

      destTarget.dropResult = item.copyWith(x: 0, y: 0);
      final placed = coordinator.dropSession(const Offset(50, 50));
      expect(placed, isNotNull);
      expect(moved, 1);
      expect(coordinator.sessionActive, isFalse);

      coordinator
        ..unregister(sourceTarget)
        ..unregister(destTarget);
    });

    testWidgets('dropSession over no grid cancels and restores the origin layout', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final ctx = tester.element(find.byType(SizedBox));

      final sourceTarget = _FakeTarget(origin);
      coordinator.register(sourceTarget, depth: 0);

      final before = List<LayoutItem>.from(origin.layout.value);
      coordinator.beginSession(
        source: sourceTarget,
        item: origin.layout.value.first,
        globalPosition: Offset.zero,
        grabOffset: Offset.zero,
        itemPixelSize: const Size(10, 10),
        overlayContext: ctx,
        proxyChild: const SizedBox(),
      );
      expect(origin.layout.value.length, before.length - 1);

      final placed = coordinator.dropSession(const Offset(999, 999));
      expect(placed, isNull);
      expect(coordinator.sessionActive, isFalse);
      expect(
        origin.layout.value.map((i) => i.id).toSet(),
        before.map((i) => i.id).toSet(),
      );

      coordinator.unregister(sourceTarget);
    });

    testWidgets('cancelSession restores the origin and clears the session', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final ctx = tester.element(find.byType(SizedBox));

      final sourceTarget = _FakeTarget(origin);
      coordinator
        ..register(sourceTarget, depth: 0)
        ..beginSession(
          source: sourceTarget,
          item: origin.layout.value.first,
          globalPosition: Offset.zero,
          grabOffset: Offset.zero,
          itemPixelSize: const Size(10, 10),
          overlayContext: ctx,
          proxyChild: const SizedBox(),
        );
      expect(origin.layout.value.any((i) => i.id == 'x1'), isFalse);

      coordinator.cancelSession();
      expect(coordinator.sessionActive, isFalse);
      expect(origin.layout.value.any((i) => i.id == 'x1'), isTrue);

      coordinator
        ..cancelSession()
        ..unregister(sourceTarget);
    });

    testWidgets('unregistering the source grid mid-session abandons the session', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final ctx = tester.element(find.byType(SizedBox));

      final sourceTarget = _FakeTarget(origin);
      coordinator
        ..register(sourceTarget, depth: 0)
        ..beginSession(
          source: sourceTarget,
          item: origin.layout.value.first,
          globalPosition: Offset.zero,
          grabOffset: Offset.zero,
          itemPixelSize: const Size(10, 10),
          overlayContext: ctx,
          proxyChild: const SizedBox(),
        );
      expect(coordinator.sessionActive, isTrue);

      coordinator.unregister(sourceTarget);
      expect(coordinator.sessionActive, isFalse);
    });

    testWidgets('dispose with an active session restores the origin (restoreOrigin)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final ctx = tester.element(find.byType(SizedBox));

      final local = DashboardNestedCoordinator();
      final sourceTarget = _FakeTarget(origin);
      local
        ..register(sourceTarget, depth: 0)
        ..beginSession(
          source: sourceTarget,
          item: origin.layout.value.first,
          globalPosition: Offset.zero,
          grabOffset: Offset.zero,
          itemPixelSize: const Size(10, 10),
          overlayContext: ctx,
          proxyChild: const SizedBox(),
        );
      expect(origin.layout.value.any((i) => i.id == 'x1'), isFalse);

      local.dispose();
      expect(origin.layout.value.any((i) => i.id == 'x1'), isTrue);
    });

    testWidgets(
        'subGridDynamic: hovering a plain leaf arms, fires after the delay, '
        'and moving off the leaf disarms', (tester) async {
      final boxKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(key: boxKey, width: 200, height: 200),
          ),
        ),
      );

      final sourceTarget = _FakeTarget(origin);
      final destTarget = _FakeTarget(other)..boxProvider = boxOf(boxKey);
      coordinator
        ..subGridDynamic = true
        ..nestHoverDelay = const Duration(milliseconds: 100)
        ..register(sourceTarget, depth: 0)
        ..register(destTarget, depth: 0);

      LayoutItem? requestedHost;
      LayoutItem? requestedDragged;
      DashboardController? requestedGrid;
      coordinator.onNestedGridRequested = (host, dragged, hostGrid) {
        requestedHost = host;
        requestedDragged = dragged;
        requestedGrid = hostGrid;
      };

      const leaf = LayoutItem(id: 'leaf', x: 0, y: 0, w: 2, h: 2);
      destTarget.hoverItem = leaf;

      coordinator
        ..beginSession(
          source: sourceTarget,
          item: origin.layout.value.first,
          globalPosition: const Offset(50, 50),
          grabOffset: Offset.zero,
          itemPixelSize: const Size(10, 10),
          overlayContext: boxKey.currentContext!,
          proxyChild: const SizedBox(),
        )
        ..updateSession(const Offset(50, 50));
      expect(destTarget.highlight, 'leaf');
      expect(destTarget.leaveCalls, 1);
      expect(destTarget.overCalls, 0);

      await tester.pump(const Duration(milliseconds: 150));
      expect(requestedHost?.id, 'leaf');
      expect(requestedDragged?.id, 'x1');
      expect(identical(requestedGrid, other), isTrue);

      destTarget.hoverItem = null;
      coordinator.updateSession(const Offset(60, 60));
      expect(destTarget.highlight, isNull);
      expect(destTarget.overCalls, greaterThan(0));

      coordinator
        ..cancelSession()
        ..unregister(sourceTarget)
        ..unregister(destTarget);
    });

    testWidgets('a fired request is abandoned when the drop lands elsewhere', (tester) async {
      final boxKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(key: boxKey, width: 200, height: 200),
          ),
        ),
      );

      final sourceTarget = _FakeTarget(origin);
      final destTarget = _FakeTarget(other)..boxProvider = boxOf(boxKey);
      coordinator
        ..subGridDynamic = true
        ..nestHoverDelay = const Duration(milliseconds: 100)
        ..register(sourceTarget, depth: 0)
        ..register(destTarget, depth: 0);

      final abandoned = <(String, DashboardController)>[];
      coordinator
        ..onNestedGridRequested = (h, d, c) {}
        ..onNestedGridRequestAbandoned = (host, grid) => abandoned.add((host.id, grid));

      const leaf = LayoutItem(id: 'leaf', x: 0, y: 0, w: 2, h: 2);
      destTarget.hoverItem = leaf;

      coordinator
        ..beginSession(
          source: sourceTarget,
          item: origin.layout.value.first,
          globalPosition: const Offset(50, 50),
          grabOffset: Offset.zero,
          itemPixelSize: const Size(10, 10),
          overlayContext: boxKey.currentContext!,
          proxyChild: const SizedBox(),
        )
        ..updateSession(const Offset(50, 50));
      await tester.pump(const Duration(milliseconds: 150));

      destTarget.hoverItem = null;
      coordinator.updateSession(const Offset(80, 80));
      destTarget.dropResult = const LayoutItem(id: 'x1', x: 3, y: 3, w: 1, h: 1);
      final placed = coordinator.dropSession(const Offset(80, 80));
      expect(placed, isNotNull);
      expect(abandoned, [('leaf', other)]);

      coordinator
        ..unregister(sourceTarget)
        ..unregister(destTarget);
    });

    testWidgets(
        'a fired request is NOT abandoned when the drop lands in the '
        "requested host's child grid", (tester) async {
      final boxKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(key: boxKey, width: 200, height: 200),
          ),
        ),
      );

      final sourceTarget = _FakeTarget(origin);
      final destTarget = _FakeTarget(other)..boxProvider = boxOf(boxKey);
      final childCtrl = DashboardController(initialSlotCount: 2)..setEditMode(true);
      addTearDown(childCtrl.dispose);

      coordinator
        ..subGridDynamic = true
        ..nestHoverDelay = const Duration(milliseconds: 100)
        ..register(sourceTarget, depth: 0)
        ..register(destTarget, depth: 0);

      final abandoned = <String>[];
      final moved = <(String, DashboardController)>[];
      coordinator
        ..onNestedGridRequested = (h, d, c) {}
        ..onNestedGridRequestAbandoned = (host, grid) => abandoned.add(host.id);
      coordinator.onItemMovedToGrid = (item, from, to) => moved.add((item.id, to));

      const leaf = LayoutItem(id: 'leaf', x: 0, y: 0, w: 2, h: 2);
      destTarget.hoverItem = leaf;

      coordinator
        ..beginSession(
          source: sourceTarget,
          item: origin.layout.value.first,
          globalPosition: const Offset(50, 50),
          grabOffset: Offset.zero,
          itemPixelSize: const Size(10, 10),
          overlayContext: boxKey.currentContext!,
          proxyChild: const SizedBox(),
        )
        ..updateSession(const Offset(50, 50));
      await tester.pump(const Duration(milliseconds: 150));

      final childTarget = _FakeTarget(childCtrl)..boxProvider = boxOf(boxKey);
      coordinator
        ..linkChildGrid(parent: other, parentItemId: 'leaf', child: childCtrl)
        ..register(childTarget, depth: 1)
        ..updateSession(const Offset(50, 50));
      childTarget.dropResult = const LayoutItem(id: 'x1', x: 0, y: 0, w: 1, h: 1);
      final placed = coordinator.dropSession(const Offset(50, 50));

      expect(placed, isNotNull);
      expect(abandoned, isEmpty);
      expect(moved.single.$1, 'x1');
      expect(identical(moved.single.$2, childCtrl), isTrue);

      coordinator
        ..unregister(sourceTarget)
        ..unregister(destTarget)
        ..unregister(childTarget);
    });

    testWidgets('a fired request is abandoned when the session is canceled', (tester) async {
      final boxKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(key: boxKey, width: 200, height: 200),
          ),
        ),
      );

      final sourceTarget = _FakeTarget(origin);
      final destTarget = _FakeTarget(other)..boxProvider = boxOf(boxKey);
      coordinator
        ..subGridDynamic = true
        ..nestHoverDelay = const Duration(milliseconds: 100)
        ..register(sourceTarget, depth: 0)
        ..register(destTarget, depth: 0);

      final abandoned = <String>[];
      coordinator
        ..onNestedGridRequested = (h, d, c) {}
        ..onNestedGridRequestAbandoned = (host, grid) => abandoned.add(host.id);

      destTarget.hoverItem = const LayoutItem(id: 'leaf', x: 0, y: 0, w: 2, h: 2);

      coordinator
        ..beginSession(
          source: sourceTarget,
          item: origin.layout.value.first,
          globalPosition: const Offset(50, 50),
          grabOffset: Offset.zero,
          itemPixelSize: const Size(10, 10),
          overlayContext: boxKey.currentContext!,
          proxyChild: const SizedBox(),
        )
        ..updateSession(const Offset(50, 50));
      await tester.pump(const Duration(milliseconds: 150));

      coordinator.cancelSession();
      expect(abandoned, ['leaf']);

      coordinator
        ..unregister(sourceTarget)
        ..unregister(destTarget);
    });

    testWidgets(
        'hover jitter filter: sub-tolerance host flips at a tile border '
        'neither flicker the highlight nor restart the nest timer', (tester) async {
      final boxKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(key: boxKey, width: 200, height: 200),
          ),
        ),
      );

      final sourceTarget = _FakeTarget(origin);
      final destTarget = _FakeTarget(other)..boxProvider = boxOf(boxKey);
      coordinator
        ..subGridDynamic = true
        ..nestHoverDelay = const Duration(milliseconds: 100)
        ..hoverJitterTolerance = 4.0
        ..register(sourceTarget, depth: 0)
        ..register(destTarget, depth: 0);
      var fired = 0;
      coordinator.onNestedGridRequested = (host, dragged, hostGrid) => fired++;

      const leafA = LayoutItem(id: 'leafA', x: 0, y: 0, w: 2, h: 2);
      const leafB = LayoutItem(id: 'leafB', x: 2, y: 0, w: 2, h: 2);
      destTarget.hoverItem = leafA;

      coordinator
        ..beginSession(
          source: sourceTarget,
          item: origin.layout.value.first,
          globalPosition: const Offset(50, 50),
          grabOffset: Offset.zero,
          itemPixelSize: const Size(10, 10),
          overlayContext: boxKey.currentContext!,
          proxyChild: const SizedBox(),
        )
        ..updateSession(const Offset(50, 50));
      expect(destTarget.highlight, 'leafA');

      // Border noise: the resolved host flips to the neighbor at +2 px
      // (<= 4 px tolerance) and back. Without the filter this would clear the
      // highlight and cancel the timer twice per oscillation.
      destTarget.hoverItem = leafB;
      coordinator.updateSession(const Offset(52, 50));
      expect(destTarget.highlight, 'leafA'); // debounced: freeze untouched
      destTarget.hoverItem = leafA;
      coordinator.updateSession(const Offset(50, 50));
      expect(destTarget.highlight, 'leafA');

      // The timer was never restarted: it fires 100 ms after the FIRST arm.
      await tester.pump(const Duration(milliseconds: 150));
      expect(fired, 1);

      // A genuine move (> tolerance) switches immediately.
      destTarget.hoverItem = leafB;
      coordinator.updateSession(const Offset(80, 50));
      expect(destTarget.highlight, 'leafB');

      coordinator
        ..cancelSession()
        ..unregister(sourceTarget)
        ..unregister(destTarget);
    });

    testWidgets('subGridDynamic does not arm on an item that already hosts a grid', (tester) async {
      final boxKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(key: boxKey, width: 200, height: 200),
          ),
        ),
      );

      final sourceTarget = _FakeTarget(origin);
      final destTarget = _FakeTarget(other)..boxProvider = boxOf(boxKey);
      final childOfLeaf = DashboardController(initialSlotCount: 2);
      addTearDown(childOfLeaf.dispose);

      var fired = 0;
      coordinator.onNestedGridRequested = (h, d, c) => fired++;
      coordinator
        ..subGridDynamic = true
        ..register(sourceTarget, depth: 0)
        ..register(destTarget, depth: 0)
        ..linkChildGrid(parent: other, parentItemId: 'leaf', child: childOfLeaf);

      destTarget.hoverItem = const LayoutItem(id: 'leaf', x: 0, y: 0, w: 2, h: 2);

      coordinator.beginSession(
        source: sourceTarget,
        item: origin.layout.value.first,
        globalPosition: const Offset(50, 50),
        grabOffset: Offset.zero,
        itemPixelSize: const Size(10, 10),
        overlayContext: boxKey.currentContext!,
        proxyChild: const SizedBox(),
      );
      await tester.pump();

      expect(coordinator.registrationOf(other), isNotNull);
      expect(coordinator.targetAt(const Offset(50, 50))?.target, same(destTarget));

      coordinator.updateSession(const Offset(50, 50));

      expect(destTarget.highlight, isNull);
      expect(destTarget.overCalls, greaterThan(0));
      expect(fired, 0);

      await tester.pump(const Duration(milliseconds: 700));
      expect(fired, 0);

      coordinator
        ..cancelSession()
        ..unregister(sourceTarget)
        ..unregister(destTarget);
    });

    testWidgets('dragging a host item is rejected by a depth-limited target', (tester) async {
      final boxKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(key: boxKey, width: 200, height: 200),
          ),
        ),
      );

      final hostOrigin = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'g', x: 0, y: 0, w: 2, h: 2, hasNestedGrid: true),
        ],
      )..setEditMode(true);
      addTearDown(hostOrigin.dispose);

      final sourceTarget = _FakeTarget(hostOrigin);
      final destTarget = _FakeTarget(other)..boxProvider = boxOf(boxKey);
      coordinator
        ..maxNestingDepth = 1
        ..register(sourceTarget, depth: 0)
        ..register(destTarget, depth: 1)
        ..beginSession(
          source: sourceTarget,
          item: hostOrigin.layout.value.first,
          globalPosition: const Offset(50, 50),
          grabOffset: Offset.zero,
          itemPixelSize: const Size(10, 10),
          overlayContext: boxKey.currentContext!,
          proxyChild: const SizedBox(),
        )
        ..updateSession(const Offset(50, 50));

      expect(destTarget.overCalls, 0);

      coordinator
        ..cancelSession()
        ..unregister(sourceTarget)
        ..unregister(destTarget);
    });

    testWidgets('targetAt skips non-accepting grids unless acceptingOnly is false', (tester) async {
      final boxKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(key: boxKey, width: 200, height: 200),
          ),
        ),
      );

      final t = _FakeTarget(other)
        ..boxProvider = boxOf(boxKey)
        ..accept = false;
      coordinator.register(t, depth: 0);

      expect(coordinator.targetAt(const Offset(50, 50)), isNull);
      expect(
        coordinator.targetAt(const Offset(50, 50), acceptingOnly: false)?.target,
        same(t),
      );
      expect(coordinator.targetAt(const Offset(500, 500), acceptingOnly: false), isNull);

      coordinator.unregister(t);
    });
  });

  group('CrossGridDragTarget - Overlay Implementation', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a1', x: 0, y: 0, w: 2, h: 1),
          LayoutItem(id: 'a2', x: 2, y: 0, w: 2, h: 1),
        ],
      )..setEditMode(true);
    });

    tearDown(() => controller.dispose());

    Widget build({bool crossGridDragOut = true}) => MaterialApp(
          home: Scaffold(
            body: DashboardNestedScope(
              child: SizedBox(
                width: 400,
                height: 400,
                child: Dashboard<String>(
                  controller: controller,
                  crossGridDragOut: crossGridDragOut,
                  itemBuilder: (context, item) =>
                      ColoredBox(color: Colors.blue, child: Text('T-${item.id}')),
                ),
              ),
            ),
          ),
        );

    CrossGridDragTarget targetOf(WidgetTester tester) =>
        tester.state(find.byWidgetPredicate((w) => w is DashboardOverlay)) as CrossGridDragTarget;

    testWidgets('canDragItemsOut reflects the crossGridDragOut flag', (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(targetOf(tester).canDragItemsOut, isTrue);

      await tester.pumpWidget(build(crossGridDragOut: false));
      await tester.pumpAndSettle();
      expect(targetOf(tester).canDragItemsOut, isFalse);
    });

    testWidgets(
        'itemAtGlobal resolves the item under a global position, honors '
        'excludeId, and returns null off-grid', (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      final target = targetOf(tester);

      final centerA1 = tester.getCenter(find.text('T-a1'));
      expect(target.itemAtGlobal(centerA1)?.id, 'a1');
      expect(target.itemAtGlobal(centerA1, excludeId: 'a1'), isNull);

      final centerA2 = tester.getCenter(find.text('T-a2'));
      expect(target.itemAtGlobal(centerA2)?.id, 'a2');

      // Far below any item: empty cell.
      expect(target.itemAtGlobal(centerA1 + const Offset(0, 300)), isNull);
    });

    testWidgets('setNestHoverHighlight drives the controller hover beacon', (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      final target = targetOf(tester)..setNestHoverHighlight('a1');
      expect(controller.internal.hoveredNestTargetId.value, 'a1');
      target.setNestHoverHighlight(null);
      expect(controller.internal.hoveredNestTargetId.value, isNull);
    });

    testWidgets('currentSlotMetrics exposes the live sliver metrics', (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      final metrics = targetOf(tester).currentSlotMetrics();
      expect(metrics, isNotNull);
      expect(metrics!.slotCount, 4);
    });
  });

  group('impl primitives: dragOriginSnapshot & freezeDragPushes', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
        ],
      )..setEditMode(true);
    });

    tearDown(() => controller.dispose());

    test('dragOriginSnapshot is null outside a drag and pre-drag during one', () {
      final impl = controller.internal;
      expect(impl.dragOriginSnapshot, isNull);

      impl.onDragStart('a');
      final snapshot = impl.dragOriginSnapshot;
      expect(snapshot, isNotNull);
      expect(snapshot!.firstWhere((i) => i.id == 'b').y, 0);

      impl.onDragEnd('a');
      expect(impl.dragOriginSnapshot, isNull);
    });

    test(
        'freezeDragPushes reverts pushes, keeps the drag alive, and resets '
        'the bbox bypass so the next update re-applies the pushes', () {
      final impl = controller.internal
        ..onDragStart('a')
        ..onDragUpdate(
          'a',
          const Offset(100, 0),
          slotWidth: 100,
          slotHeight: 100,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
        );
      LayoutItem b() => controller.layout.value.firstWhere((i) => i.id == 'b');
      expect(b().y, 1, reason: 'b must be pushed by the drag');

      impl.freezeDragPushes();
      expect(b().y, 0, reason: 'freeze must revert the push');
      expect(controller.isDragging.value, isTrue);

      impl.onDragUpdate(
        'a',
        const Offset(100, 0),
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
      );
      expect(b().y, 1, reason: 'resume must re-apply the push');

      impl.onDragEnd('a');
    });

    test(
        'mid-drag updateItem survives snapshot-based recomputes '
        '(onDragUpdate rebuilds from originalLayoutOnStart)', () {
      final impl = controller.internal..onDragStart('a');

      controller.updateItem(
        'b',
        (i) => i.copyWith(hasNestedGrid: true),
        recompact: false,
      );
      LayoutItem b() => controller.layout.value.firstWhere((i) => i.id == 'b');
      expect(b().hasNestedGrid, isTrue);
      expect(
        impl.originalLayoutOnStart.peek().firstWhere((i) => i.id == 'b').hasNestedGrid,
        isTrue,
        reason: 'the write-through must patch the pre-drag snapshot',
      );

      impl.onDragUpdate(
        'a',
        const Offset(100, 0),
        slotWidth: 100,
        slotHeight: 100,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
      );
      expect(
        b().hasNestedGrid,
        isTrue,
        reason: 'snapshot-derived recompute must not erase the flag',
      );

      impl.onDragEnd('a');
    });

    test(
        'mid-drag updateItem survives the cross-grid exit '
        '(movedAway keeps the flag, canceled restores it too)', () {
      final impl = controller.internal..onDragStart('a');
      controller.updateItem(
        'b',
        (i) => i.copyWith(hasNestedGrid: true),
        recompact: false,
      );
      final removed = impl.beginCrossGridExit({'a'});
      expect(removed.map((i) => i.id), ['a']);
      LayoutItem b() => controller.layout.value.firstWhere((i) => i.id == 'b');
      expect(
        b().hasNestedGrid,
        isTrue,
        reason: 'the exit rebuild from the snapshot must keep the flag',
      );
      impl.finishCrossGridExit(outcome: CrossGridExitOutcome.movedAway);
      expect(b().hasNestedGrid, isTrue);
      expect(controller.layout.value.map((i) => i.id), isNot(contains('a')));

      final c2 = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
        ],
      )..setEditMode(true);
      addTearDown(c2.dispose);
      final impl2 = c2.internal
        ..onDragStart('a')
        ..beginCrossGridExit({'a'});
      c2.updateItem(
        'b',
        (i) => i.copyWith(hasNestedGrid: true),
        recompact: false,
      );
      impl2.finishCrossGridExit(outcome: CrossGridExitOutcome.canceled);
      expect(
        c2.layout.value.firstWhere((i) => i.id == 'b').hasNestedGrid,
        isTrue,
        reason: 'the canceled restore must not erase a post-exit mutation',
      );
      expect(c2.layout.value.map((i) => i.id), contains('a'));
    });

    test('freezeDragPushes is a no-op outside a drag', () {
      final before = controller.layout.value;
      controller.internal.freezeDragPushes();
      expect(controller.layout.value, same(before));
    });
  });

  group('subGridDynamicSameGrid (widget flow)', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'b', x: 1, y: 0, w: 1, h: 1),
        ],
      )..setEditMode(true);
    });

    tearDown(() => controller.dispose());

    Widget build({
      required DashboardNestedCoordinator coordinator,
      required bool sameGrid,
      bool subGridDynamic = true,
      DashboardNestedGridRequestCallback? onRequested,
      DashboardNestedGridAbandonedCallback? onAbandoned,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: DashboardNestedScope(
            coordinator: coordinator,
            subGridDynamic: subGridDynamic,
            subGridDynamicSameGrid: sameGrid,
            nestHoverDelay: const Duration(milliseconds: 200),
            onNestedGridRequested: onRequested ?? (h, d, c) {},
            onNestedGridRequestAbandoned: onAbandoned,
            child: SizedBox(
              width: 400,
              height: 400,
              child: Dashboard<String>(
                controller: controller,
                itemBuilder: (context, item) =>
                    ColoredBox(color: Colors.blue, child: Text('T-${item.id}')),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
        'pause freezes + highlights, delay fires the request, and a '
        'real move disarms and resumes the pushes', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);

        LayoutItem? requestedHost;
        LayoutItem? requestedDragged;
        DashboardController? requestedGrid;

        await tester.pumpWidget(
          build(
            coordinator: coordinator,
            sameGrid: true,
            onRequested: (host, dragged, grid) {
              requestedHost = host;
              requestedDragged = dragged;
              requestedGrid = grid;
            },
          ),
        );
        await tester.pumpAndSettle();

        LayoutItem b() => controller.layout.value.firstWhere((i) => i.id == 'b');
        final aCenter = tester.getCenter(find.text('T-a'));
        final bCenter = tester.getCenter(find.text('T-b'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();
        await gesture.moveTo(bCenter);
        await tester.pump();
        expect(b().y, 1, reason: 'in-grid drag must push b');

        await tester.pump(const Duration(milliseconds: 400));
        expect(controller.internal.hoveredNestTargetId.value, 'b');
        expect(b().y, 0, reason: 'freeze must revert the push');
        expect(requestedHost, isNull, reason: 'not fired yet');

        await tester.pump(const Duration(milliseconds: 250));
        expect(requestedHost?.id, 'b');
        expect(requestedDragged?.id, 'a');
        expect(identical(requestedGrid, controller), isTrue);

        await gesture.moveTo(bCenter + const Offset(40, 0));
        await tester.pump();
        expect(controller.internal.hoveredNestTargetId.value, isNull);

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('moving before the arming delay cancels: no request fires', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);

        var fired = 0;
        await tester.pumpWidget(
          build(
            coordinator: coordinator,
            sameGrid: true,
            onRequested: (h, d, c) => fired++,
          ),
        );
        await tester.pumpAndSettle();

        final aCenter = tester.getCenter(find.text('T-a'));
        final bCenter = tester.getCenter(find.text('T-b'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();
        await gesture.moveTo(bCenter);
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 400));
        expect(controller.internal.hoveredNestTargetId.value, 'b');
        await gesture.moveTo(bCenter + const Offset(40, 0));
        await tester.pump();
        expect(controller.internal.hoveredNestTargetId.value, isNull);

        await tester.pump(const Duration(milliseconds: 400));
        expect(fired, 0, reason: 'disarmed before nestHoverDelay elapsed');

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('flag off: pausing mid-drag never freezes nor fires', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);

        var fired = 0;
        await tester.pumpWidget(
          build(
            coordinator: coordinator,
            sameGrid: false,
            onRequested: (h, d, c) => fired++,
          ),
        );
        await tester.pumpAndSettle();

        LayoutItem b() => controller.layout.value.firstWhere((i) => i.id == 'b');
        final aCenter = tester.getCenter(find.text('T-a'));
        final bCenter = tester.getCenter(find.text('T-b'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();
        await gesture.moveTo(bCenter);
        await tester.pump();

        await tester.pump(const Duration(seconds: 2));
        expect(controller.internal.hoveredNestTargetId.value, isNull);
        expect(b().y, 1, reason: 'pushes must stay applied: no freeze');
        expect(fired, 0);

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('same-grid arming is independent of subGridDynamic', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);

        LayoutItem? requestedHost;
        await tester.pumpWidget(
          build(
            coordinator: coordinator,
            sameGrid: true,
            subGridDynamic: false,
            onRequested: (h, d, c) => requestedHost = h,
          ),
        );
        await tester.pumpAndSettle();

        final aCenter = tester.getCenter(find.text('T-a'));
        final bCenter = tester.getCenter(find.text('T-b'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();
        await gesture.moveTo(bCenter);
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 400));
        expect(
          controller.internal.hoveredNestTargetId.value,
          'b',
          reason: 'the flags are orthogonal: sameGrid alone must arm',
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(requestedHost?.id, 'b');

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets(
        'releasing after the request without dropping into the child '
        'fires onNestedGridRequestAbandoned', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);

        final abandoned = <(String, DashboardController)>[];
        await tester.pumpWidget(
          build(
            coordinator: coordinator,
            sameGrid: true,
            onRequested: (h, d, c) {},
            onAbandoned: (host, grid) => abandoned.add((host.id, grid)),
          ),
        );
        await tester.pumpAndSettle();

        final aCenter = tester.getCenter(find.text('T-a'));
        final bCenter = tester.getCenter(find.text('T-b'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();
        await gesture.moveTo(bCenter);
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 250));
        expect(abandoned, isEmpty, reason: 'not resolved while dragging');

        await gesture.up();
        await tester.pumpAndSettle();

        expect(abandoned.length, 1);
        expect(abandoned.single.$1, 'b');
        expect(identical(abandoned.single.$2, controller), isTrue);
      });
    });

    testWidgets('an already-hosting sibling is not armed', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);
        final childOfB = DashboardController(initialSlotCount: 2);
        addTearDown(childOfB.dispose);

        var fired = 0;
        await tester.pumpWidget(
          build(
            coordinator: coordinator,
            sameGrid: true,
            onRequested: (h, d, c) => fired++,
          ),
        );
        await tester.pumpAndSettle();

        coordinator.linkChildGrid(
          parent: controller,
          parentItemId: 'b',
          child: childOfB,
        );

        final aCenter = tester.getCenter(find.text('T-a'));
        final bCenter = tester.getCenter(find.text('T-b'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();
        await gesture.moveTo(bCenter);
        await tester.pump();

        await tester.pump(const Duration(seconds: 2));
        expect(controller.internal.hoveredNestTargetId.value, isNull);
        expect(fired, 0);

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets(
        'END-TO-END: releasing over a freshly converted host drops '
        'the item INTO the child grid and never fires abandoned', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);

        // Root uses a bigger host tile so the mounted child grid comfortably
        // contains the (stationary) release point.
        final rootCtrl = DashboardController(
          initialSlotCount: 4,
          initialLayout: const [
            LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
            LayoutItem(id: 'b', x: 1, y: 0, w: 2, h: 2),
          ],
        )..setEditMode(true);
        addTearDown(rootCtrl.dispose);

        // Example-like app state: dynamic conversions + abandon bookkeeping.
        final dynamicChildren = <String, DashboardController>{};
        final abandoned = <String>[];
        addTearDown(() {
          for (final c in dynamicChildren.values) {
            c.dispose();
          }
        });

        late StateSetter rebuild;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return DashboardNestedScope(
                    coordinator: coordinator,
                    subGridDynamicSameGrid: true,
                    nestHoverDelay: const Duration(milliseconds: 200),
                    // Mimics the example: convert the host, mount the grid.
                    onNestedGridRequested: (host, dragged, hostGrid) {
                      if (dynamicChildren.containsKey(host.id)) return;
                      final child = DashboardController(initialSlotCount: 2)..setEditMode(true);
                      dynamicChildren[host.id] = child;
                      hostGrid.updateItem(
                        host.id,
                        (i) => i.copyWith(hasNestedGrid: true),
                        recompact: false,
                      );
                      rebuild(() {});
                    },
                    onNestedGridRequestAbandoned: (host, grid) => abandoned.add(host.id),
                    child: SizedBox(
                      width: 400,
                      height: 400,
                      child: Dashboard<String>(
                        controller: rootCtrl,
                        itemBuilder: (context, item) {
                          final child = dynamicChildren[item.id];
                          if (item.hasNestedGrid && child != null) {
                            return NestedDashboard(
                              controller: child,
                              parentItemId: item.id,
                              autoSlotCount: false,
                              itemBuilder: (context, nested) => Text('N-${nested.id}'),
                            );
                          }
                          return ColoredBox(
                            color: Colors.blue,
                            child: Text('T-${item.id}'),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final aCenter = tester.getCenter(find.text('T-a'));
        final bCenter = tester.getCenter(find.text('T-b'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();
        await gesture.moveTo(bCenter);
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 400)); // freeze
        await tester.pump(const Duration(milliseconds: 250)); // fire+convert
        await tester.pump(); // let the NestedDashboard mount and register

        expect(
          dynamicChildren.containsKey('b'),
          isTrue,
          reason: 'the request must have converted the host',
        );
        final child = dynamicChildren['b']!;
        expect(
          coordinator.childGridsOf(rootCtrl)['b'],
          same(child),
          reason: 'the mounted NestedDashboard must have linked itself',
        );

        // The user gesture under test: plain release while still frozen over
        // the freshly converted host.
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          child.layout.value.map((i) => i.id),
          contains('a'),
          reason: 'the release must drop the item INTO the child grid',
        );
        expect(
          rootCtrl.layout.value.map((i) => i.id),
          isNot(contains('a')),
          reason: 'the item must have left the root grid',
        );
        expect(
          rootCtrl.layout.value.firstWhere((i) => i.id == 'b').hasNestedGrid,
          isTrue,
          reason: 'the host must stay converted',
        );
        expect(
          abandoned,
          isEmpty,
          reason: 'a drop into the requested child confirms the request — '
              'abandoned firing here is the bug that destroys the child',
        );
      });
    });

    testWidgets('scope syncs subGridDynamicSameGrid onto the coordinator', (tester) async {
      final coordinator = DashboardNestedCoordinator();
      addTearDown(coordinator.dispose);
      expect(coordinator.subGridDynamicSameGrid, isFalse);

      await tester.pumpWidget(build(coordinator: coordinator, sameGrid: true));
      expect(coordinator.subGridDynamicSameGrid, isTrue);

      await tester.pumpWidget(build(coordinator: coordinator, sameGrid: false));
      expect(coordinator.subGridDynamicSameGrid, isFalse);
    });

    testWidgets('same-grid pause move sequence covers anchor distance checks', (tester) async {
      await runOnDesktop(() async {
        final coordinator = DashboardNestedCoordinator();
        addTearDown(coordinator.dispose);

        await tester.pumpWidget(
          build(
            coordinator: coordinator,
            sameGrid: true,
          ),
        );
        await tester.pumpAndSettle();

        final aCenter = tester.getCenter(find.text('T-a'));

        final gesture = await tester.startGesture(aCenter);
        await tester.pump();

        // Initial move (sets anchor to pos1)
        final pos1 = aCenter + const Offset(10, 0);
        await gesture.moveTo(pos1);
        await tester.pump();

        // Micro-move (2px <= tolerance, condition is false)
        final pos2 = pos1 + const Offset(2, 0);
        await gesture.moveTo(pos2);
        await tester.pump();

        // Real move (15px > tolerance, condition is true with non-null anchor)
        final pos3 = pos1 + const Offset(15, 0);
        await gesture.moveTo(pos3);
        await tester.pump();

        await gesture.up();
        await tester.pumpAndSettle();
      });
    });
  });

  group('DashboardNestedCoordinator - Proportional & Custom Projection', () {
    test('projectItem respects preserveLogicalSize policy', () {
      final localCoordinator = DashboardNestedCoordinator(
        projectionPolicy: DimensionProjectionPolicy.preserveLogicalSize,
      );
      const item = LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2);
      final projected = localCoordinator.projectItem(
        item,
        sourceSlotCount: 8,
        targetSlotCount: 4,
      );
      expect(projected.w, equals(2));
      expect(projected.h, equals(2));
    });

    test('projectItem scales proportionally (preserveVisualProportion)', () {
      final localCoordinator = DashboardNestedCoordinator(
        projectionPolicy: DimensionProjectionPolicy.preserveVisualProportion,
      );
      const item = LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2);
      final projected = localCoordinator.projectItem(
        item,
        sourceSlotCount: 8,
        targetSlotCount: 4,
      );
      expect(projected.w, equals(1));
      expect(projected.h, equals(1));
    });

    test('projectItem clamps to target slots and constraints', () {
      final localCoordinator = DashboardNestedCoordinator(
        projectionPolicy: DimensionProjectionPolicy.preserveVisualProportion,
      );
      const item = LayoutItem(id: 'a', x: 0, y: 0, w: 4, h: 4, minW: 2);
      final projected = localCoordinator.projectItem(
        item,
        sourceSlotCount: 4,
        targetSlotCount: 2,
      );
      expect(projected.w, equals(2)); // Clamped to minW
      expect(projected.h, equals(2)); // Ratio 0.5 -> 2
    });

    test('projectItem enforces minW constraint when projected width is smaller than minW', () {
      final localCoordinator = DashboardNestedCoordinator(
        projectionPolicy: DimensionProjectionPolicy.preserveVisualProportion,
      );
      const item = LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2, minW: 2);
      final projected = localCoordinator.projectItem(
        item,
        sourceSlotCount: 8,
        targetSlotCount: 4,
      );
      expect(projected.w, equals(2)); // Calculated width is 1, clamped to minW (2)
    });

    test('projectItem supports custom projection callback', () {
      final localCoordinator = DashboardNestedCoordinator(
        projectionPolicy: DimensionProjectionPolicy.custom,
        customProjectionCallback: (item, {required sourceSlotCount, required targetSlotCount}) {
          return item.copyWith(w: 3, h: 3);
        },
      );
      const item = LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1);
      final projected = localCoordinator.projectItem(
        item,
        sourceSlotCount: 4,
        targetSlotCount: 8,
      );
      expect(projected.w, equals(3));
      expect(projected.h, equals(3));
    });

    test(
        'preserveLogicalSize sanitizes an item wider than the target grid '
        '(regression: inverted x.clamp range threw ArgumentError on hover)', () {
      final localCoordinator = DashboardNestedCoordinator(
        // Default policy: dimensions are kept as-is…
        projectionPolicy: DimensionProjectionPolicy.preserveLogicalSize,
      );
      const item = LayoutItem(id: 'a', x: 0, y: 0, w: 6, h: 2);
      final projected = localCoordinator.projectItem(
        item,
        sourceSlotCount: 8,
        targetSlotCount: 4,
      );
      // …except when they physically cannot fit the target grid.
      expect(projected.w, equals(4));
      expect(projected.h, equals(2));
    });

    test(
        'projection caps minW when it exceeds the target column count '
        '(regression: correctBounds assertion in the target grid)', () {
      final localCoordinator = DashboardNestedCoordinator(
        projectionPolicy: DimensionProjectionPolicy.preserveLogicalSize,
      );
      const item = LayoutItem(id: 'a', x: 0, y: 0, w: 5, h: 2, minW: 5);
      final projected = localCoordinator.projectItem(
        item,
        sourceSlotCount: 8,
        targetSlotCount: 4,
      );
      expect(projected.w, equals(4));
      expect(projected.minW, lessThanOrEqualTo(4));
    });

    test('custom callback output is sanitized against the target grid', () {
      final localCoordinator = DashboardNestedCoordinator(
        projectionPolicy: DimensionProjectionPolicy.custom,
        customProjectionCallback: (item, {required sourceSlotCount, required targetSlotCount}) {
          return item.copyWith(w: 999, h: 0);
        },
      );
      const item = LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1);
      final projected = localCoordinator.projectItem(
        item,
        sourceSlotCount: 4,
        targetSlotCount: 8,
      );
      expect(projected.w, equals(8)); // clamped to targetSlotCount
      expect(projected.h, equals(1)); // clamped to >= 1
    });

    test('proportional projection respects item minH constraints', () {
      final localCoordinator = DashboardNestedCoordinator(
        projectionPolicy: DimensionProjectionPolicy.preserveVisualProportion,
      );

      // Card of size 2x2 with a minH constraint of 2.
      // Scaling down from 8 columns to 4 columns yields a ratio of 0.5.
      // Mathematically, projected height would be 1, but minH clamp forces it to 2.
      const item = LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2, minH: 2);

      final projected = localCoordinator.projectItem(
        item,
        sourceSlotCount: 8,
        targetSlotCount: 4,
      );

      expect(projected.h, equals(2)); // Locked to minH
    });
  });

  test(
      'loadNestedTree normalizes hand-written JSON: an item carrying a '
      'subGrid payload becomes a host even when the flag is omitted', () {
    final coordinator = DashboardNestedCoordinator();
    addTearDown(coordinator.dispose);
    final root = DashboardController(initialSlotCount: 4);
    addTearDown(root.dispose);

    loadNestedTree(coordinator, root, [
      {
        'id': 'group',
        'x': 0,
        'y': 0,
        'w': 2,
        'h': 2,
        // no 'hasNestedGrid' key: hand-written JSON
        'subGrid': {
          'slotCount': 2,
          'items': [
            {'id': 'n1', 'x': 0, 'y': 0, 'w': 1, 'h': 1},
          ],
        },
      },
      {'id': 'leaf', 'x': 2, 'y': 0, 'w': 1, 'h': 1},
    ]);

    final group = root.layout.value.firstWhere((i) => i.id == 'group');
    expect(group.hasNestedGrid, isTrue, reason: 'normalized from subGrid payload');
    final leaf = root.layout.value.firstWhere((i) => i.id == 'leaf');
    expect(leaf.hasNestedGrid, isFalse);

    // The subGrid payload was stashed for the (unmounted) child grid.
    final stashed = coordinator.takeStashedChildGrid('group');
    expect(stashed, isNotNull);
    expect(stashed!.slotCount, 2);
    expect(stashed.items.single.id, 'n1');
  });
}
