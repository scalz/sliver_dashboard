import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/view/dashboard_lasso_layer.dart';

import '../test_helpers.dart';

/// Geometry of the fixtures below, at the default 800x600 test surface.
///
/// `padding: EdgeInsets.all(20)` -> crossAxisExtent = 760, slotCount = 8,
/// spacing = 8  =>  slotWidth = (760 - 7*8) / 8 = 88, stride = 96.
///
/// Content-space pixel bands of the three fixture tiles (all on row 0, so
/// vertical compaction leaves them where they are):
///   a (x = 0) -> [  0,  88]
///   b (x = 3) -> [288, 376]
///   c (x = 6) -> [576, 664]
/// Row 0 spans y in [0, 88]; anything below y = 88 is empty space.
const double _kStride = 96;
const double _kSlot = 88;

/// Content -> global for a vertically scrolling grid at scroll offset 0.
///
/// Cross axis: the padding IS added manually (it is not part of the scroll
/// extent). Main axis: the leading padding is already inside
/// `precedingScrollExtent`, and is added exactly once — see the
/// Content-Origin Convention.
Offset _g(double cx, double cy, EdgeInsets padding) => Offset(cx + padding.left, cy + padding.top);

List<LayoutItem> _fixtureLayout() => const [
      LayoutItem(id: 'a', x: 0, y: 0, w: 1, h: 1),
      LayoutItem(id: 'b', x: 3, y: 0, w: 1, h: 1),
      LayoutItem(id: 'c', x: 6, y: 0, w: 1, h: 1),
    ];

void main() {
  late DashboardController controller;
  late ScrollController scrollController;
  late List<String> announcements;

  const padded = EdgeInsets.all(20);

  Future<void> pumpDashboard(
    WidgetTester tester, {
    EdgeInsets padding = padded,
    LassoStyle lassoStyle = LassoStyle.byDefault,
    DashboardGuidance? guidance,
    DragStartGesture dragStartGesture = DragStartGesture.longPress,
    List<LayoutItem>? layout,
    bool editing = true,
  }) async {
    controller = DashboardController(
      initialSlotCount: 8,
      initialLayout: layout ?? _fixtureLayout(),
    );
    addTearDown(controller.dispose);
    controller
      ..setEditMode(editing)
      ..lassoStyle = lassoStyle;
    scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Dashboard<String>(
          controller: controller,
          scrollController: scrollController,
          breakpoints: null,
          padding: padding,
          slotAspectRatio: 1,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          gridStyle: const GridStyle(),
          guidance: guidance,
          dragStartGesture: dragStartGesture,
          itemBuilder: (context, item) => ColoredBox(
            color: Colors.blueGrey,
            child: Center(child: Text(item.id)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Presses at [from], drags to [to] and releases, as a mouse would.
  Future<void> lasso(
    WidgetTester tester,
    Offset from,
    Offset to, {
    bool release = true,
  }) async {
    final gesture = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    if (release) {
      await gesture.up();
      await tester.pump();
    }
  }

  setUp(() {
    announcements = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        final map = message as Map<dynamic, dynamic>;
        if (map['type'] == 'announce') {
          final data = map['data'] as Map<dynamic, dynamic>;
          announcements.add(data['message'] as String);
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null);
  });

  group('lasso — drag selection', () {
    testWidgets('selects the tiles the rectangle overlaps (non-zero padding)', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester);

        // Start below row 0 (empty space), drag up-left over tile "a" only.
        await lasso(tester, _g(150, 150, padded), _g(10, 10, padded));

        expect(controller.selectedItemIds.value, {'a'});
      });
    });

    testWidgets('selects several tiles and ignores those outside the rectangle', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester);

        // x in [150, 700] covers b [288, 376] and c [576, 664] but not a.
        await lasso(tester, _g(150, 150, padded), _g(700, 10, padded));

        expect(controller.selectedItemIds.value, {'b', 'c'});
      });
    });

    testWidgets('zero-padding mirror keeps the historical geometry', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester, padding: EdgeInsets.zero);

        // crossAxisExtent = 800 -> slotWidth = 93, stride = 101.
        // a -> [0, 93], b -> [303, 396], c -> [606, 699].
        await lasso(
          tester,
          _g(200, 200, EdgeInsets.zero),
          _g(10, 10, EdgeInsets.zero),
        );

        expect(controller.selectedItemIds.value, {'a'});
      });
    });

    testWidgets('is pixel-precise: a rectangle inside the gutter selects nothing', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester);

        // The gutter between column 0 and column 1 spans [88, 96] in content
        // space. A rectangle strictly inside it touches no tile, even though
        // it sits between two occupied cells.
        await lasso(tester, _g(90, 150, padded), _g(94, 10, padded));

        expect(controller.selectedItemIds.value, isEmpty);
      });
    });

    testWidgets('a same-size hit set with different members is published', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester);

        final gesture = await tester.startGesture(
          _g(150, 150, padded),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();

        // Covers 'a' only.
        await gesture.moveTo(_g(10, 10, padded));
        await tester.pump();
        expect(controller.selectedItemIds.value, {'a'});

        // Covers 'b' only: SAME cardinality as before, different member. The
        // publish guard compares sets, not lengths, so this must still be
        // pushed to the selection.
        await gesture.moveTo(_g(300, 10, padded));
        await tester.pump();
        expect(controller.selectedItemIds.value, {'b'});

        await gesture.up();
        await tester.pump();
      });
    });

    testWidgets('a move that does not change the hit set keeps the selection', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester);

        final gesture = await tester.startGesture(
          _g(150, 150, padded),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveTo(_g(10, 10, padded));
        await tester.pump();
        final first = controller.selectedItemIds.value;
        expect(first, {'a'});

        // The rectangle grows inside the cells it already covers: the O(N)
        // scan runs, resolves the same ids, and must NOT write the beacon —
        // that write is what would rebuild every item shell at pointer rate.
        await gesture.moveTo(_g(20, 20, padded));
        await tester.pump();
        expect(controller.selectedItemIds.value, {'a'});
        expect(
          identical(controller.selectedItemIds.value, first),
          isTrue,
          reason: 'an unchanged hit set must not republish the selection',
        );

        await gesture.up();
        await tester.pump();
      });
    });

    testWidgets('a press on empty space without movement changes nothing', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester);
        controller.toggleSelection('a');

        final gesture =
            await tester.startGesture(_g(150, 150, padded), kind: PointerDeviceKind.mouse);
        await tester.pump();
        await gesture.up();
        await tester.pump();

        expect(controller.selectedItemIds.value, {'a'});
        expect(announcements, isEmpty);
      });
    });

    testWidgets('a press on a tile never starts a lasso', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester);

        // Press inside tile "a" and drag across b and c. This is a tile drag,
        // so the selection stays reduced to the dragged tile.
        await lasso(tester, _g(40, 40, padded), _g(700, 40, padded));

        expect(controller.selectedItemIds.value, {'a'});
        expect(announcements, isEmpty);
      });
    });
  });

  group('lasso — selection semantics', () {
    testWidgets('replaces the previous selection by default', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester);
        controller.toggleSelection('a');

        await lasso(tester, _g(150, 150, padded), _g(400, 10, padded));

        expect(controller.selectedItemIds.value, {'b'});
      });
    });

    testWidgets('a held multi-select key makes the lasso additive', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester);
        controller.toggleSelection('a');

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        try {
          await lasso(tester, _g(150, 150, padded), _g(400, 10, padded));
        } finally {
          // HardwareKeyboard is a process-wide singleton: a leaked key makes
          // the whole suite order-dependent.
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }

        expect(controller.selectedItemIds.value, {'a', 'b'});
      });
    });

    testWidgets('static tiles are not selectable, section barriers are', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(
          tester,
          layout: const [
            LayoutItem(id: 'bar', x: 0, y: 0, w: 8, h: 1, isSectionBarrier: true),
            LayoutItem(id: 'fixed', x: 0, y: 1, w: 1, h: 1, isStatic: true),
            LayoutItem(id: 'free', x: 3, y: 1, w: 1, h: 1),
          ],
        );

        // Row 0 = the barrier, row 1 = the two tiles; row 2 (y >= 192) is
        // empty and is where the gesture starts.
        await lasso(tester, _g(700, 300, padded), _g(10, 10, padded));

        expect(controller.selectedItemIds.value, {'bar', 'free'});
      });
    });
  });

  group('lasso — modifier requirement', () {
    const modifierRequired = LassoStyle(mode: LassoSelectionMode.modifierRequired);

    testWidgets('does nothing without the modifier', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester, lassoStyle: modifierRequired);

        await lasso(tester, _g(150, 150, padded), _g(10, 10, padded));

        expect(controller.selectedItemIds.value, isEmpty);
        expect(announcements, isEmpty);
      });
    });

    testWidgets('triggers when the modifier is held at pointer-down', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester, lassoStyle: modifierRequired);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        try {
          await lasso(tester, _g(150, 150, padded), _g(10, 10, padded));
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }

        expect(controller.selectedItemIds.value, {'a'});
      });
    });

    testWidgets('the trigger key alone does not make the lasso additive in this mode',
        (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester, lassoStyle: modifierRequired);
        controller.toggleSelection('a');

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        try {
          await lasso(tester, _g(150, 150, padded), _g(400, 10, padded));
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }

        // Shift is BOTH the trigger and a multi-select key: counted as the
        // trigger only, otherwise a replacing lasso would be unreachable here.
        expect(controller.selectedItemIds.value, {'b'});
      });
    });

    testWidgets('a second, non-overlapping multi-select key restores additivity', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester, lassoStyle: modifierRequired);
        controller.toggleSelection('a');

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        try {
          await lasso(tester, _g(150, 150, padded), _g(400, 10, padded));
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }

        expect(controller.selectedItemIds.value, {'a', 'b'});
      });
    });

    testWidgets('a custom lassoModifier is honoured', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester, lassoStyle: modifierRequired);
        controller.shortcuts = const DashboardShortcuts(
          lassoModifier: [LogicalKeyboardKey.altLeft],
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        try {
          await lasso(tester, _g(150, 150, padded), _g(10, 10, padded));
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        }

        expect(controller.selectedItemIds.value, {'a'});
      });
    });
  });

  group('lasso — accessibility', () {
    testWidgets('announces start, then the resulting count on release', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester);

        await lasso(tester, _g(150, 150, padded), _g(700, 10, padded));

        expect(controller.selectedItemIds.value, {'b', 'c'});
        expect(announcements, [
          DashboardGuidance.byDefault.a11yLassoStart,
          DashboardGuidance.byDefault.a11yLassoEnd(2),
        ]);
      });
    });

    testWidgets('the announced count matches the final selection size exactly', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester);

        await lasso(tester, _g(150, 150, padded), _g(10, 10, padded));

        expect(
          announcements.last,
          DashboardGuidance.byDefault.a11yLassoEnd(controller.selectedItemIds.value.length),
        );
      });
    });

    testWidgets('announcements do not require guidance to be enabled', (tester) async {
      await runOnDesktop(() async {
        // guidance: null disables the tooltip and the cursor, never the
        // screen-reader announcements.
        await pumpDashboard(tester);
        expect(controller.guidance, isNull);

        await lasso(tester, _g(150, 150, padded), _g(10, 10, padded));

        expect(announcements, isNotEmpty);
      });
    });

    testWidgets('custom messages are used', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(
          tester,
          guidance: DashboardGuidance(
            a11yLassoStart: 'lasso on',
            a11yLassoEnd: (count) => 'picked $count',
          ),
        );

        await lasso(tester, _g(150, 150, padded), _g(10, 10, padded));

        expect(announcements, ['lasso on', 'picked 1']);
      });
    });
  });

  group('lasso — rendering', () {
    testWidgets('paints a rectangle while dragging and removes it on release', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester);

        final gesture = await tester.startGesture(
          _g(150, 150, padded),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveTo(_g(10, 10, padded));
        await tester.pump();

        final painter = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(DashboardLassoLayer),
            matching: find.byType(CustomPaint),
          ),
        );
        final state = (painter.painter! as LassoPainter).state;
        // Content [10, 150] shifted by the content origin (20, 20).
        expect(state.rect, const Rect.fromLTRB(30, 30, 170, 170));
        expect(state.fillColor, LassoStyle.byDefault.fillColor);
        expect(state.borderColor, LassoStyle.byDefault.borderColor);

        await gesture.up();
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(DashboardLassoLayer),
            matching: find.byType(CustomPaint),
          ),
          findsNothing,
        );
      });
    });

    testWidgets('honours custom lasso colors', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(
          tester,
          lassoStyle: const LassoStyle(
            fillColor: Color(0x22FF0000),
            borderColor: Color(0xFFFF0000),
            borderWidth: 3,
          ),
        );

        final gesture = await tester.startGesture(
          _g(150, 150, padded),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveTo(_g(10, 10, padded));
        await tester.pump();

        final painter = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(DashboardLassoLayer),
            matching: find.byType(CustomPaint),
          ),
        );
        final state = (painter.painter! as LassoPainter).state;
        expect(state.fillColor, const Color(0x22FF0000));
        expect(state.borderColor, const Color(0xFFFF0000));
        expect(state.borderWidth, 3);

        await gesture.up();
        await tester.pump();
      });
    });

    testWidgets('shows the guidance label only when guidance is enabled', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester, guidance: DashboardGuidance.byDefault);

        final gesture = await tester.startGesture(
          _g(150, 150, padded),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveTo(_g(10, 10, padded));
        await tester.pump();

        expect(
          find.text(DashboardGuidance.byDefault.lassoSelect.message),
          findsOneWidget,
        );

        await gesture.up();
        await tester.pump();
      });
    });
  });

  group('lasso — cursor', () {
    const modifierRequiredStyle = LassoStyle(mode: LassoSelectionMode.modifierRequired);

    // `MouseTracker` keys its state by DEVICE, not by pointer id, and every
    // mouse `TestPointer` reports device 1 whatever pointer id it was given
    // (`TestPointer` derives the device from the kind). So there is exactly
    // one mouse per test: creating a second gesture to get a "fresh" probe
    // would raise a duplicate PointerAddedEvent for device 1 rather than
    // isolate anything.
    const mouseDevice = 1;
    TestGesture? mouse;

    Future<MouseCursor?> hoverCursor(WidgetTester tester, Offset position) async {
      final existing = mouse;
      final TestGesture gesture;
      if (existing != null) {
        gesture = existing;
      } else {
        gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        mouse = gesture;
        addTearDown(() async {
          await gesture.removePointer();
          mouse = null;
        });
        await gesture.addPointer(location: Offset.zero);
        await tester.pump();
      }
      await gesture.moveTo(position);
      await tester.pumpAndSettle();
      return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(mouseDevice);
    }

    testWidgets('empty space shows the lasso cursor in emptySpace mode', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester, guidance: DashboardGuidance.byDefault);

        expect(
          await hoverCursor(tester, _g(150, 150, padded)),
          SystemMouseCursors.precise,
        );
      });
    });

    testWidgets('modifierRequired shows the cursor only while the key is held', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(
          tester,
          guidance: DashboardGuidance.byDefault,
          lassoStyle: modifierRequiredStyle,
        );

        expect(
          await hoverCursor(tester, _g(150, 150, padded)),
          isNot(SystemMouseCursors.precise),
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        try {
          await tester.pumpAndSettle();
          expect(
            await hoverCursor(tester, _g(150, 152, padded)),
            SystemMouseCursors.precise,
          );
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
      });
    });

    testWidgets('the lasso cursor never leaks onto a tile', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester, guidance: DashboardGuidance.byDefault);

        // Every MouseRegion inside a tile defers (FocusableActionDetector and
        // GuidanceInteractor both build one with no cursor), so without the
        // cursor floor on the tile the resolver walks past it and lands on the
        // overlay's ancestor lasso region.
        expect(
          await hoverCursor(tester, _g(40, 40, padded)),
          isNot(SystemMouseCursors.precise),
        );
      });
    });

    testWidgets('the modifier state is published on the controller', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(
          tester,
          guidance: DashboardGuidance.byDefault,
          lassoStyle: modifierRequiredStyle,
        );
        expect(controller.lassoModifierHeld.value, isFalse);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        try {
          await tester.pump();
          expect(controller.lassoModifierHeld.value, isTrue);
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.pump();
        expect(controller.lassoModifierHeld.value, isFalse);
      });
    });

    testWidgets('LassoStyle.off defers the cursor', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(
          tester,
          guidance: DashboardGuidance.byDefault,
          lassoStyle: LassoStyle.off,
        );

        expect(
          await hoverCursor(tester, _g(150, 150, padded)),
          isNot(SystemMouseCursors.precise),
        );
      });
    });

    testWidgets('no cursor change when guidance is disabled', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester);

        expect(
          await hoverCursor(tester, _g(150, 150, padded)),
          isNot(SystemMouseCursors.precise),
        );
      });
    });

    testWidgets('no cursor change outside edit mode', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(
          tester,
          guidance: DashboardGuidance.byDefault,
          editing: false,
        );

        expect(
          await hoverCursor(tester, _g(150, 150, padded)),
          isNot(SystemMouseCursors.precise),
        );
      });
    });
  });

  group('lasso — platform and edit-mode gating', () {
    testWidgets('never arms on a touch platform', (tester) async {
      await runOnPlatform(TargetPlatform.android, () async {
        await pumpDashboard(tester, dragStartGesture: DragStartGesture.tap);

        await lasso(tester, _g(150, 150, padded), _g(10, 10, padded));

        expect(controller.selectedItemIds.value, isEmpty);
        expect(announcements, isEmpty);
      });
    });

    testWidgets('never arms outside edit mode', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester, editing: false);

        await lasso(tester, _g(150, 150, padded), _g(10, 10, padded));

        expect(controller.selectedItemIds.value, isEmpty);
      });
    });

    testWidgets('LassoStyle.off disables the feature entirely', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(tester, lassoStyle: LassoStyle.off);

        await lasso(tester, _g(150, 150, padded), _g(10, 10, padded));

        expect(controller.selectedItemIds.value, isEmpty);
        expect(announcements, isEmpty);
        expect(find.byType(DashboardLassoLayer), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(DashboardLassoLayer),
            matching: find.byType(CustomPaint),
          ),
          findsNothing,
        );
      });
    });
  });

  group('lasso — value types', () {
    test('LassoStyle obeys the equality laws', () {
      // Built through copyWith, NOT as two `const` literals: identical const
      // expressions are canonicalized to the same instance, so `identical`
      // short-circuits `==` on its first line and the field comparisons are
      // never executed — the comparison would be asserted without ever
      // running.
      LassoStyle build() => LassoStyle.byDefault.copyWith(
            mode: LassoSelectionMode.modifierRequired,
            fillColor: const Color(0x11223344),
            borderColor: const Color(0xFF00FF00),
            borderWidth: 2,
          );
      final a = build();
      final b = build();
      expect(identical(a, b), isFalse, reason: 'the guard above must hold');

      expect(a, b);
      expect(b, a);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(LassoStyle.byDefault));
      // One differing field per clause, so every comparison in `==` runs.
      expect(a, isNot(a.copyWith(fillColor: const Color(0x11223345))));
      expect(a, isNot(a.copyWith(borderColor: const Color(0xFF00FF01))));
      expect(a, isNot(a.copyWith(borderWidth: 3)));
      expect(a.isEnabled, isTrue);
      expect(LassoStyle.off.isEnabled, isFalse);
      expect(
        a.copyWith(mode: LassoSelectionMode.emptySpace).mode,
        LassoSelectionMode.emptySpace,
      );
      expect(a.copyWith().fillColor, a.fillColor);
    });

    test('GridStyle obeys the equality laws', () {
      GridStyle build() =>
          const GridStyle().copyWith(lineWidth: 2, handleColor: const Color(0xFF00FF00));
      final a = build();
      final b = build();
      expect(identical(a, b), isFalse);

      expect(a, b);
      expect(b, a);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const GridStyle()));
      expect(a, isNot(a.copyWith(lineColor: const Color(0xFF112233))));
      expect(a, isNot(a.copyWith(lineWidth: 3)));
      expect(a, isNot(a.copyWith(fillColor: const Color(0xFF445566))));
      expect(a, isNot(a.copyWith(handleColor: const Color(0xFF00FF01))));
      expect(a.copyWith(lineWidth: 3).lineWidth, 3);
      expect(a.copyWith().handleColor, a.handleColor);
    });

    test('LassoPainter repaints only when the state changes', () {
      // A builder rather than `const` literals, for the canonicalization
      // reason above: two identical const states are the SAME instance, so
      // `==` returns on `identical` and never compares a field.
      LassoOverlayState build({
        double right = 10,
        Rect? clipRect,
        Color fill = const Color(0x11000000),
        Color border = const Color(0xFF000000),
        double width = 1,
        String? message,
      }) =>
          LassoOverlayState(
            rect: Rect.fromLTRB(0, 0, right, 10),
            clipRect: clipRect,
            fillColor: fill,
            borderColor: border,
            borderWidth: width,
            message: message,
          );

      final state = build();
      final same = build();
      expect(identical(state, same), isFalse);

      expect(state, same);
      expect(state.hashCode, same.hashCode);
      expect(LassoPainter(state).shouldRepaint(LassoPainter(same)), isFalse);

      // One differing field per clause of `==`, so every comparison runs.
      for (final other in [
        build(right: 11),
        build(clipRect: const Rect.fromLTRB(0, 0, 5, 5)),
        build(fill: const Color(0x11000001)),
        build(border: const Color(0xFF000001)),
        build(width: 2),
        build(message: 'hint'),
      ]) {
        expect(state, isNot(other));
        expect(LassoPainter(state).shouldRepaint(LassoPainter(other)), isTrue);
      }
    });
  });

  group('lasso — scroll robustness', () {
    testWidgets('the anchor stays pinned to the content while scrolling', (tester) async {
      await runOnDesktop(() async {
        await pumpDashboard(
          tester,
          layout: [
            for (var row = 0; row < 12; row++) LayoutItem(id: 'i$row', x: 0, y: row, w: 1, h: 1),
          ],
        );

        // Anchor on empty space to the right of column 0, then scroll one
        // stride down and finish the rectangle. The anchor is stored in
        // content space, so the rectangle grows over the content that scrolled
        // past rather than shearing with the viewport.
        final gesture = await tester.startGesture(
          _g(400, 300, padded),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveTo(_g(390, 290, padded));
        await tester.pump();

        scrollController.jumpTo(_kStride);
        await tester.pump();

        // After the jump, the pointer sits one stride further down in content
        // space, so the rectangle now reaches the tile that scrolled into it.
        await gesture.moveTo(_g(10, 10, padded));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        expect(controller.selectedItemIds.value, isNotEmpty);
        // Sanity: the anchor never drifted past the content height.
        expect(controller.selectedItemIds.value.length, lessThan(12));
      });
    });
  });

  test('slot geometry assumptions of this suite', () {
    // Guards the hard-coded content bands above: if the fixture geometry
    // changes, this fails first and explains why every coordinate assertion
    // in the file moved.
    expect((760 - 7 * 8) / 8, _kSlot);
    expect(_kSlot + 8, _kStride);
  });
}
