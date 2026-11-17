import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/view/guidance/guidance_bubble.dart';
import 'package:sliver_dashboard/src/view/guidance/guidance_interactor.dart';

import '../test_helpers.dart';

/// The package no longer wraps overlay content in a Material, so the ambient
/// styles those layers render with must come from somewhere else.
void main() {
  TextStyle? styleOf(WidgetTester tester, String text) => tester
      .widget<RichText>(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == text),
      )
      .text
      .style;

  testWidgets('cross-grid proxy inherits the source grid ambient text style', (tester) async {
    await runOnDesktop(() async {
      final gridA = DashboardController(
        initialSlotCount: 4,
        initialLayout: [const LayoutItem(id: 'a1', x: 0, y: 0, w: 2, h: 1)],
      )..setEditMode(true);
      final gridB = DashboardController(
        initialSlotCount: 4,
        initialLayout: [const LayoutItem(id: 'b1', x: 0, y: 0, w: 2, h: 1)],
      )..setEditMode(true);
      addTearDown(gridA.dispose);
      addTearDown(gridB.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardNestedScope(
              child: Column(
                children: [
                  SizedBox(
                    height: 250,
                    // Reason: a style only the source grid sees. The proxy is
                    // mounted in the root overlay, so it reaches the tile only
                    // through InheritedTheme.captureAll.
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(fontSize: 31),
                      child: Dashboard<String>(
                        controller: gridA,
                        itemBuilder: (context, item) => Text('A-${item.id}'),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 250,
                    child: Dashboard<String>(
                      controller: gridB,
                      itemBuilder: (context, item) => Text('B-${item.id}'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(styleOf(tester, 'A-a1')?.fontSize, 31);

      final gesture = await tester.startGesture(tester.getCenter(find.text('A-a1')));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('B-b1')) + const Offset(0, 60));
      await tester.pump();

      // The session removed a1 from grid A: the only 'A-a1' left is the proxy.
      expect(gridA.layout.value.any((i) => i.id == 'a1'), isFalse);
      expect(find.text('A-a1'), findsOneWidget);
      expect(styleOf(tester, 'A-a1')?.fontSize, 31);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  testWidgets('guidance bubble replaces the ambient text style instead of merging it',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        // Reason: stands in for WidgetsApp's debug error style, which is what
        // an OverlayEntry inherits when no Material sits above it.
        child: DefaultTextStyle(
          style: TextStyle(decoration: TextDecoration.underline, fontFamily: 'monospace'),
          child: Center(child: GuidanceBubble(message: 'hint')),
        ),
      ),
    );

    final style = styleOf(tester, 'hint');
    expect(style?.decoration, TextDecoration.none);
    expect(style?.fontFamily, isNull);
  });

  group('guidance bubble colors', () {
    const bubbleColor = Color(0xFF123456);
    const bubbleTextColor = Color(0xFFABCDEF);

    /// The painted (background, text) colors of the bubble showing [text].
    (Color?, Color?) bubbleColorsOf(WidgetTester tester, String text) {
      final bubble = find.ancestor(of: find.text(text), matching: find.byType(GuidanceBubble));
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: bubble, matching: find.byType(DecoratedBox)).first,
      );
      return ((box.decoration as BoxDecoration).color, styleOf(tester, text)?.color);
    }

    Future<void> pumpBubble(WidgetTester tester, Brightness platform, {bool override = false}) =>
        tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(platformBrightness: platform),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: GuidanceBubble(
                  message: 'hint',
                  color: override ? bubbleColor : null,
                  textColor: override ? bubbleTextColor : null,
                ),
              ),
            ),
          ),
        );

    testWidgets('defaults follow the platform brightness', (tester) async {
      await pumpBubble(tester, Brightness.light);
      expect(bubbleColorsOf(tester, 'hint'), (const Color(0xFF424242), const Color(0xFFFFFFFF)));

      await pumpBubble(tester, Brightness.dark);
      expect(bubbleColorsOf(tester, 'hint'), (const Color(0xFFE0E0E0), const Color(0xFF000000)));
    });

    testWidgets('overrides win over the platform brightness', (tester) async {
      await pumpBubble(tester, Brightness.dark, override: true);
      expect(bubbleColorsOf(tester, 'hint'), (bubbleColor, bubbleTextColor));
    });

    testWidgets(
      'DashboardGuidance colors reach the hover bubble',
      (tester) async {
        final controller = DashboardController(
          initialSlotCount: 4,
          initialLayout: [const LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)],
        )
          ..setEditMode(true)
          ..guidance = const DashboardGuidance(
            bubbleColor: bubbleColor,
            bubbleTextColor: bubbleTextColor,
          );
        addTearDown(controller.dispose);
        controller.internal.onDragStart('1');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DashboardControllerProvider(
                controller: controller,
                child: GuidanceInteractor(
                  item: controller.layout.value.first,
                  child: const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        );

        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);
        await gesture.moveTo(const Offset(50, 50));
        await tester.pumpAndSettle();

        final message = DashboardGuidance.byDefault.moving.message;
        expect(bubbleColorsOf(tester, message), (bubbleColor, bubbleTextColor));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets('DashboardGuidance colors reach the lasso label', (tester) async {
      await runOnDesktop(() async {
        final controller = DashboardController(
          initialSlotCount: 8,
          initialLayout: [const LayoutItem(id: '1', x: 0, y: 0, w: 1, h: 1)],
        )..setEditMode(true);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Dashboard<String>(
              controller: controller,
              guidance: const DashboardGuidance(
                bubbleColor: bubbleColor,
                bubbleTextColor: bubbleTextColor,
              ),
              itemBuilder: (context, item) => Text(item.id),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(
          const Offset(400, 300),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveTo(const Offset(300, 200));
        await tester.pump();

        final message = DashboardGuidance.byDefault.lassoSelect.message;
        expect(bubbleColorsOf(tester, message), (bubbleColor, bubbleTextColor));

        await gesture.up();
        await tester.pump();
      });
    });
  });
}
