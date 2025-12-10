import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/dashboard_controller_impl.dart';
import 'package:sliver_dashboard/src/view/guidance/guidance_interactor.dart';

void main() {
  testWidgets(
    'Guidance shows correct cursors and messages on hover',
    (tester) async {
      final controller = DashboardController(
        initialLayout: [
          const LayoutItem(id: '1', x: 0, y: 0, w: 4, h: 4, isResizable: true),
        ],
        initialSlotCount: 10,
      );

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

    testWidgets(
      'shows moving message when hovering the active item',
      (tester) async {
        final item = controller.layout.value.first;

        // 1. Simulate active item (moving)
        (controller as DashboardControllerImpl).activeItem.value = item;

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
