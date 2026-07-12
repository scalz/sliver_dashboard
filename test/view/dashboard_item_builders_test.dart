import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:sliver_dashboard/src/controller/utility.dart';
import 'package:sliver_dashboard/src/view/dashboard_item_widget.dart';

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
}
