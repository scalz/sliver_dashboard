import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/view/dashboard_item_widget.dart';
import 'package:sliver_dashboard/src/view/guidance/guidance_interactor.dart';

void main() {
  late DashboardController controller;
  const item = LayoutItem(id: 'i1', x: 0, y: 0, w: 2, h: 1);

  setUp(() {
    controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [item],
    );
  });

  tearDown(() => controller.dispose());

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: DashboardControllerProvider(
            controller: controller,
            child: FocusTraversalGroup(child: child),
          ),
        ),
      );

  group('DashboardItem — itemLayoutBuilder', () {
    testWidgets('builds with live dimensions and rebuilds when they change', (tester) async {
      var builds = 0;

      Widget itemAt(double width) => host(
            DashboardItem(
              item: item,
              isEditing: false,
              itemLayoutBuilder: (context, it, w, h, slots) {
                builds++;
                return Text('lay:${w.toStringAsFixed(0)}x${h.toStringAsFixed(0)}:$slots');
              },
              itemWidth: width,
              itemHeight: 50,
              slotCount: 4,
            ),
          );

      await tester.pumpWidget(itemAt(100));
      expect(find.text('lay:100x50:4'), findsOneWidget);
      expect(builds, 1);

      // Dimension change invalidates the cache (trackDimensions path).
      await tester.pumpWidget(itemAt(140));
      expect(find.text('lay:140x50:4'), findsOneWidget);
      expect(builds, 2);

      // Same dimensions: cached, no rebuild of the heavy content.
      await tester.pumpWidget(itemAt(140));
      expect(builds, 2);
    });
  });

  group('DashboardItem — itemBreakpointBuilder', () {
    testWidgets('rebuilds only when the resolved breakpoint transitions', (tester) async {
      var builds = 0;

      Widget itemAtWidth(double width) => host(
            DashboardItem(
              item: item,
              isEditing: false,
              itemBreakpointBuilder: (context, it, breakpoint, w, h, slots) {
                builds++;
                return Text('bp:$breakpoint');
              },
              breakpointResolver: (w, h, it, slots) => w > 150 ? 'wide' : 'narrow',
              itemWidth: width,
              itemHeight: 50,
              slotCount: 4,
            ),
          );

      await tester.pumpWidget(itemAtWidth(100));
      expect(find.text('bp:narrow'), findsOneWidget);
      expect(builds, 1);

      // 100 -> 120: same side of the breakpoint. The DashboardItem cache is
      // invalidated (dimensions changed) but the inner breakpoint cache holds:
      // the user builder must NOT run again.
      await tester.pumpWidget(itemAtWidth(120));
      expect(find.text('bp:narrow'), findsOneWidget);
      expect(builds, 1);

      // 120 -> 200: crosses the breakpoint -> exactly one more user build.
      await tester.pumpWidget(itemAtWidth(200));
      expect(find.text('bp:wide'), findsOneWidget);
      expect(builds, 2);
    });
  });

  group('DashboardItem — nest-hover highlight', () {
    testWidgets('shows the ring while the item is armed as a nest target', (tester) async {
      await tester.pumpWidget(
        host(
          DashboardItem(
            item: item,
            isEditing: false,
            itemBuilder: (context, it) => const Text('content'),
          ),
        ),
      );

      // The ring is the decoration of the item's own Container (the nearest
      // Container ancestor of the cached content). Scoping the check there
      // makes it immune to any other Container in the app scaffolding.
      BoxDecoration? itemDecoration() {
        final container = tester.widget<Container>(
          find.ancestor(of: find.text('content'), matching: find.byType(Container)).first,
        );
        return container.decoration as BoxDecoration?;
      }

      bool hasRing() {
        final deco = itemDecoration();
        return deco != null && deco.border != null && (deco.border! as Border).top.width == 4;
      }

      expect(hasRing(), isFalse);

      controller.internal.setNestTargetHover('i1');
      await tester.pumpAndSettle();
      expect(hasRing(), isTrue);

      controller.internal.setNestTargetHover(null);
      await tester.pumpAndSettle();
      expect(hasRing(), isFalse);
    });
  });

  group('DashboardBreakpointBuilder (direct)', () {
    testWidgets(
        'caches across same-breakpoint updates, rebuilds on transition '
        'and on content signature change', (tester) async {
      var builds = 0;

      Widget bp({required double width, required LayoutItem it}) => MaterialApp(
            home: DashboardBreakpointBuilder<String>(
              width: width,
              height: 50,
              item: it,
              resolver: (w, h) => w > 150 ? 'wide' : 'narrow',
              builder: (context, item, layout, w, h) {
                builds++;
                return Text('direct:$layout');
              },
            ),
          );

      await tester.pumpWidget(bp(width: 100, it: item));
      expect(find.text('direct:narrow'), findsOneWidget);
      expect(builds, 1);

      // Same breakpoint: cached.
      await tester.pumpWidget(bp(width: 120, it: item));
      expect(builds, 1);

      // Transition: rebuild.
      await tester.pumpWidget(bp(width: 200, it: item));
      expect(find.text('direct:wide'), findsOneWidget);
      expect(builds, 2);

      // Content signature change (w: 2 -> 3): rebuild even without transition.
      await tester.pumpWidget(bp(width: 200, it: item.copyWith(w: 3)));
      expect(builds, 3);
    });
  });

  group('GuidanceInteractor', () {
    late DashboardController controller;

    setUp(() {
      controller = DashboardController(
        initialSlotCount: 4,
        initialLayout: [
          const LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1),
        ],
      )
        ..setEditMode(true)

        // Initialize guidance
        ..guidance = DashboardGuidance.byDefault;
    });

    tearDown(() => controller.dispose());

    testWidgets(
      'Guidance shows correct cursors and messages on hover',
      (tester) async {
        final controller = DashboardController(
          initialLayout: [
            const LayoutItem(id: '1', x: 0, y: 0, w: 4, h: 4, isResizable: true),
          ],
          initialSlotCount: 10,
        );
        addTearDown(controller.dispose);

        const guidance = DashboardGuidance(
          resizeTopLeft: InteractionGuidance(SystemMouseCursors.help, 'TopLeft'),
          resizeTopRight: InteractionGuidance(SystemMouseCursors.help, 'TopRight'),
          resizeXY: InteractionGuidance(SystemMouseCursors.help, 'Corner'),
          resizeX: InteractionGuidance(SystemMouseCursors.help, 'Side X'),
          resizeY: InteractionGuidance(SystemMouseCursors.help, 'Side Y'),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 400,
                child: Dashboard(
                  controller: controller,
                  guidance: guidance,
                  resizeHandleSide: 20,
                  itemBuilder: (_, item) => Container(color: Colors.blue),
                ),
              ),
            ),
          ),
        );

        controller.toggleEditing();
        await tester.pump();

        final itemFinder = find.byKey(const ValueKey('1'));
        final center = tester.getCenter(itemFinder);
        final size = tester.getSize(itemFinder);
        final topLeft = tester.getTopLeft(itemFinder);
        final bottomRight = tester.getBottomRight(itemFinder);

        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);

        Future<void> checkHover(Offset target, String expectedMessage) async {
          await gesture.moveTo(target);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(
            find.text(expectedMessage),
            findsOneWidget,
            reason: 'Should show "$expectedMessage" at $target',
          );
        }

        // 1. Test Top-Left Corner
        await checkHover(topLeft + const Offset(5, 5), 'TopLeft');

        // 2. Test Top-Right Corner
        await checkHover(topLeft + Offset(size.width - 5, 5), 'TopRight');

        // 3. Test Bottom-Right Corner (ResizeXY)
        await checkHover(bottomRight - const Offset(5, 5), 'Corner');

        // 4. Test Right Side (ResizeX)
        await checkHover(center + Offset(size.width / 2 - 5, 0), 'Side X');

        // 5. Test Bottom Side (ResizeY)
        await checkHover(center + Offset(0, size.height / 2 - 5), 'Side Y');
      },
      // Enable MouseRegions.
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'shows moving message when hovering the active item',
      (tester) async {
        final item = controller.layout.value.first;

        // Use onDragStart to properly set isDragging and activeItemId
        controller.internal.onDragStart(item.id);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DashboardControllerProvider(
                controller: controller,
                child: GuidanceInteractor(
                  item: item,
                  child: Container(width: 100, height: 100, color: Colors.red),
                ),
              ),
            ),
          ),
        );

        // 2. Simulate hover
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);
        await tester.pump();

        // Move cursor on item
        await gesture.moveTo(const Offset(50, 50));
        await tester.pumpAndSettle();

        // 3. Check "Moving" message is displayed
        expect(find.text(DashboardGuidance.byDefault.moving.message), findsOneWidget);
      },
      // Use platform variant
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  });
}
