import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

void main() {
  late DashboardController controller;
  late List<(String, ResizeHandle, double)> calls;
  late int resizeStarts;

  setUp(() {
    calls = [];
    resizeStarts = 0;
    controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2)],
    )..setEditMode(true);
  });

  tearDown(() => controller.dispose());

  Widget grip(BuildContext context, LayoutItem item, ResizeHandle handle, double size) {
    calls.add((item.id, handle, size));
    return ColoredBox(key: ValueKey('grip-${item.id}-${handle.name}'), color: Colors.green);
  }

  Widget app({ResizeZoneResolver? resolver}) => MaterialApp(
        home: Dashboard(
          controller: controller,
          padding: const EdgeInsets.all(20),
          resizeHandleBuilder: grip,
          resizeZoneResolver: resolver,
          onItemResizeStart: (_) => resizeStarts++,
          itemBuilder: (context, item) => Center(child: Text(item.id)),
        ),
      );

  testWidgets('called for every active handle, with the item, inside its zone', (tester) async {
    await tester.pumpWidget(app());
    expect(
      {for (final c in calls) c.$2},
      ResizeHandle.values.toSet(),
    );
    expect(calls.every((c) => c.$1 == 'a'), isTrue);
    // Never larger than the default drawn handle (20) nor the zone.
    expect(calls.every((c) => c.$3 > 0 && c.$3 <= 20), isTrue);
    final box = tester.getSize(find.byKey(const ValueKey('grip-a-bottomRight')));
    expect(box.width, calls.firstWhere((c) => c.$2 == ResizeHandle.bottomRight).$3);
  });

  testWidgets('follows resizeZoneResolver: only the handles that exist are drawn', (tester) async {
    await tester.pumpWidget(
      app(resolver: (item, size) => const ResizeZones(handles: {ResizeHandle.bottomRight})),
    );
    expect(find.byKey(const ValueKey('grip-a-bottomRight')), findsOneWidget);
    expect(find.byKey(const ValueKey('grip-a-topLeft')), findsNothing);
  });

  testWidgets('a press on the custom grip still resizes', (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(app());
      final at = tester.getCenter(find.byKey(const ValueKey('grip-a-bottomRight')));
      final g = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await g.moveBy(const Offset(120, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(resizeStarts, 1);
      expect(controller.layout.value.single.w, greaterThan(2));
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  testWidgets('not drawn outside edit mode', (tester) async {
    controller.setEditMode(false);
    await tester.pumpWidget(app());
    expect(calls, isEmpty);
  });
}
