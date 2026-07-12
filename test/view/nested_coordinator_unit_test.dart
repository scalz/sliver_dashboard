import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/layout_metrics.dart';

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
}

/// Lazy render-box resolver for [_FakeTarget.boxProvider].
RenderBox? Function() boxOf(GlobalKey key) =>
    () => key.currentContext?.findRenderObject() as RenderBox?;

void main() {
  group('DashboardNestedCoordinator (unit)', () {
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
      // pointer - grab + size/2 = (100-10+40, 100-5+20)
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

      // Registration picks the link up and childrenOf sees the mounted child.
      final childTarget = _FakeTarget(childCtrl);
      final reg = coordinator.register(childTarget, depth: 1);
      expect(reg.parentController, same(origin));
      expect(reg.parentItemId, 'x1');
      expect(coordinator.childrenOf(origin).map((r) => r.target), [childTarget]);

      // Unlink clears both the link map and the live registration's parent.
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

      // No link for 'ghost': deliver must stash instead of applying.
      coordinator.deliverChildGrid('ghost', data);
      final taken = coordinator.takeStashedChildGrid('ghost');
      expect(taken, isNotNull);
      expect(taken!.slotCount, 3);
      expect(taken.items.single.id, 'n1');
      // Taking removes it.
      expect(coordinator.takeStashedChildGrid('ghost'), isNull);

      // Direct stash path.
      coordinator.stashChildGrid('ghost2', data);
      expect(coordinator.takeStashedChildGrid('ghost2'), isNotNull);
    });

    test('moveItemToGrid honors explicit coordinates and rejects no-ops', () {
      // identical(from, to) -> null
      expect(
        coordinator.moveItemToGrid(from: origin, to: origin, itemId: 'x1'),
        isNull,
      );
      // unknown item -> null, neither grid modified
      expect(
        coordinator.moveItemToGrid(from: origin, to: other, itemId: 'nope'),
        isNull,
      );
      expect(origin.layout.value.length, 2);
      expect(other.layout.value, isEmpty);

      // explicit x/y are honored
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
      // With vertical compaction the item lands at the requested column.
      expect(placed!.x, 1);
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
      // Temporary silent removal from the source grid.
      expect(origin.layout.value.any((i) => i.id == 'x1'), isFalse);

      // Move inside the dest box: enter + placeholder drive.
      coordinator.updateSession(const Offset(50, 50));
      expect(destTarget.overCalls, greaterThan(0));
      expect(destTarget.lastOverItem!.id, 'x1');

      // Move outside every grid: leave fires once.
      coordinator.updateSession(const Offset(500, 500));
      expect(destTarget.leaveCalls, 1);

      // Drop back inside: foreignDrop resolves, movedAway commits + callback.
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
      // Pre-drag layout restored, same ids and geometry.
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
      // Cancel again: harmless no-op.
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
        // No expect() here: this fires inside a Timer during tester.pump(),
        // and calling a guarded test API from there is a guard conflict.
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

        // Hover the leaf: freeze (leave) + highlight, no placeholder drive.
        ..updateSession(const Offset(50, 50));
      expect(destTarget.highlight, 'leaf');
      expect(destTarget.leaveCalls, 1); // freeze reverts pushes
      expect(destTarget.overCalls, 0); // frozen: no foreignDragOver

      // Wait out the delay: the request fires with host + dragged + grid.
      await tester.pump(const Duration(milliseconds: 150));
      expect(requestedHost?.id, 'leaf');
      expect(requestedDragged?.id, 'x1');
      expect(identical(requestedGrid, other), isTrue);

      // Move off the leaf (still inside the grid): disarm + resume placeholder.
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
      await tester.pump(const Duration(milliseconds: 150)); // request fires

      // Drop into the dest grid itself (NOT a child of 'leaf'): abandoned.
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
      await tester.pump(const Duration(milliseconds: 150)); // request fires

      // App-side conversion: 'leaf' now hosts childCtrl, whose grid overlays
      // the same box one level deeper — the natural handoff resolves it.
      final childTarget = _FakeTarget(childCtrl)..boxProvider = boxOf(boxKey);
      coordinator
        ..linkChildGrid(parent: other, parentItemId: 'leaf', child: childCtrl)
        ..register(childTarget, depth: 1)
        ..updateSession(const Offset(50, 50)); // hands over to child
      childTarget.dropResult = const LayoutItem(id: 'x1', x: 0, y: 0, w: 1, h: 1);
      final placed = coordinator.dropSession(const Offset(50, 50));

      expect(placed, isNotNull);
      expect(
        abandoned,
        isEmpty,
        reason: 'landing in the requested child grid confirms the request',
      );
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
      await tester.pump(const Duration(milliseconds: 150)); // request fires

      coordinator.cancelSession();
      expect(abandoned, ['leaf']);

      coordinator
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

      // The request callback is assigned as a plain statement, NEVER as a
      // `..cb = (…) => …` cascade section followed by more `..` sections:
      // that shape is a grammar trap — after a merge/reformat the trailing
      // sections can end up parsed as a cascade on the lambda BODY. With
      // fail() the trap is silent: it returns `Never`, which statically
      // accepts any member, so the swallowed register() calls compile fine
      // and simply never run (targetAt then returns null).
      var fired = 0;
      coordinator.onNestedGridRequested = (h, d, c) => fired++;
      coordinator
        ..subGridDynamic = true
        ..register(sourceTarget, depth: 0)
        ..register(destTarget, depth: 0)
        // 'leaf' already hosts a grid via the link map.
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
      await tester.pump(); // settle the proxy overlay insert

      // Split diagnostic: registration mechanics first, geometry second. If
      // the first probe fails, register() never ran (see the grammar-trap
      // note above); if only the second fails, it is targetAt/geometry.
      expect(
        coordinator.registrationOf(other),
        isNotNull,
        reason: 'destTarget must be registered before the probe',
      );
      expect(
        coordinator.targetAt(const Offset(50, 50))?.target,
        same(destTarget),
        reason: 'targetAt must resolve the dest grid before the dynamic check '
            '(box attached: '
            '${boxKey.currentContext?.findRenderObject()?.attached})',
      );

      coordinator.updateSession(const Offset(50, 50));

      // Not hostable: no highlight, and the placeholder path runs instead.
      expect(destTarget.highlight, isNull);
      expect(destTarget.overCalls, greaterThan(0));
      expect(fired, 0, reason: 'must not arm on a host item');

      // Outlive the default nestHoverDelay (600ms): nothing may fire late.
      await tester.pump(const Duration(milliseconds: 700));
      expect(fired, 0, reason: 'must not arm on a host item (late timer)');

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
        // Dest grid is already at depth 1: hosting 'g' would create depth 2.
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

      // The depth-limited grid is not offered: no enter, no placeholder.
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
      // Outside the box: null either way.
      expect(coordinator.targetAt(const Offset(500, 500), acceptingOnly: false), isNull);

      coordinator.unregister(t);
    });
  });
}
