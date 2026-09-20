import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

import '../../test_helpers.dart';

/// Counts how many times its subtree is MOUNTED.
///
/// A re-parented element leaves exactly the same widgets on screen, so `find`
/// cannot see the defect these tests are about — only an `initState` counter
/// placed inside the tile's content can.
class _MountCounter extends StatefulWidget {
  const _MountCounter({required this.onMount, required this.child});

  final VoidCallback onMount;
  final Widget child;

  @override
  State<_MountCounter> createState() => _MountCounterState();
}

class _MountCounterState extends State<_MountCounter> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  group('A tile gesture never remounts the tile content', () {
    late DashboardController parent;
    late DashboardController child;
    var hostMounts = 0;

    setUp(() {
      // Reset in setUp, not only tearDown: a value left over from a previous
      // test turns the exact defect being hunted into a passing assertion.
      debugOverlayDisposedDuringInteraction = 0;
      hostMounts = 0;
      parent = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'group', x: 0, y: 0, w: 4, h: 2, hasNestedGrid: true),
        ],
      )..setEditMode(true);
      child = DashboardController(
        initialSlotCount: 4,
        initialLayout: const [
          LayoutItem(id: 'c1', x: 0, y: 0, w: 1, h: 1),
          LayoutItem(id: 'c2', x: 3, y: 0, w: 1, h: 1),
        ],
      )..setEditMode(true);
    });

    tearDown(() {
      debugOverlayDisposedDuringInteraction = 0;
      parent.dispose();
      child.dispose();
    });

    Widget buildNested({EdgeInsets? padding}) {
      return MaterialApp(
        home: Scaffold(
          body: DashboardNestedScope(
            child: Dashboard<String>(
              controller: parent,
              padding: padding,
              itemBuilder: (context, item) {
                if (item.id == 'group') {
                  return _MountCounter(
                    onMount: () => hostMounts++,
                    child: NestedDashboard(
                      controller: child,
                      parentItemId: 'group',
                      padding: padding,
                      itemBuilder: (context, item) =>
                          ColoredBox(color: Colors.orange, child: Text('C-${item.id}')),
                    ),
                  );
                }
                return ColoredBox(color: Colors.blue, child: Text('P-${item.id}'));
              },
            ),
          ),
        ),
      );
    }

    // The horizontal axis is the only falsifiable one here — vertical
    // compaction pulls a tile dragged downwards straight back to y == 0, so an
    // assertion on `y` passes whether or not the drag was ever processed.
    Future<void> dragC1Right(WidgetTester tester) async {
      final start = tester.getCenter(find.text('C-c1'));
      final target = tester.getCenter(find.text('C-c2'));
      final gesture = await tester.startGesture(start);
      await tester.pump();
      for (var i = 1; i <= 6; i++) {
        await gesture.moveTo(Offset.lerp(start, target, i / 6)!);
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('a nested drag never disposes the overlay driving it', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(buildNested());
        await tester.pumpAndSettle();

        await dragC1Right(tester);

        expect(debugOverlayDisposedDuringInteraction, 0);
        expect(child.layout.value.firstWhere((i) => i.id == 'c1').x, greaterThan(0));
      });
    });

    testWidgets('a nested drag survives the host tile losing the focus highlight', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(buildNested());
        await tester.pumpAndSettle();

        // Tab into the grid: the host tile takes the keyboard focus WITHOUT
        // being selected, which is the state in which its chrome carries a
        // focus decoration. Pressing a tile of the nested grid then hands the
        // focus over and drops that decoration, mid-gesture.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'DashboardItem(group)');
        expect(parent.selectedItemIds.value, isEmpty);

        final mountsBeforeDrag = hostMounts;
        await dragC1Right(tester);

        expect(
          debugOverlayDisposedDuringInteraction,
          0,
          reason: 'the nested overlay was rebuilt structurally mid-gesture; '
              'the rest of the drag ran on a defunct State',
        );
        expect(hostMounts, mountsBeforeDrag);
        expect(
          child.layout.value.firstWhere((i) => i.id == 'c1').x,
          greaterThan(0),
          reason: 'the nested tile did not actually move',
        );
      });
    });

    testWidgets('the same, with a non-zero padding', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(buildNested(padding: const EdgeInsets.all(20)));
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();

        final mountsBeforeDrag = hostMounts;
        await dragC1Right(tester);

        expect(debugOverlayDisposedDuringInteraction, 0);
        expect(hostMounts, mountsBeforeDrag);
        expect(child.layout.value.firstWhere((i) => i.id == 'c1').x, greaterThan(0));
      });
    });

    testWidgets('selecting and focusing a tile never remounts its content', (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(buildNested());
        await tester.pumpAndSettle();
        expect(hostMounts, 1);

        parent.toggleSelection('group');
        await tester.pumpAndSettle();
        expect(hostMounts, 1, reason: 'a selection decoration re-parented the content');

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(hostMounts, 1, reason: 'a focus decoration re-parented the content');

        parent.clearSelection();
        await tester.pumpAndSettle();
        expect(hostMounts, 1, reason: 'dropping the decoration re-parented the content');
      });
    });

    // Every gate above asserts the counter is 0, so a counter that can no
    // longer increment would make all of them pass for no reason. This is the
    // positive half: the only legitimate way an overlay is disposed with an
    // interaction in flight is the application removing the grid mid-gesture.
    testWidgets('the disposal counter fires when an overlay really is torn down mid-gesture',
        (tester) async {
      await runOnDesktop(() async {
        await tester.pumpWidget(buildNested());
        await tester.pumpAndSettle();

        final start = tester.getCenter(find.text('C-c1'));
        final gesture = await tester.startGesture(start);
        await tester.pump();
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();
        expect(child.isDragging.value, isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        // Exactly one: the root overlay bails out of `_onPointerDown` on the
        // nested grid's pointer claim, so it never had an active item.
        expect(debugOverlayDisposedDuringInteraction, 1);

        // The gesture is deliberately left dangling. Releasing it now would
        // replay the frozen hit path onto the disposed State — the very defect
        // this counter exists to detect.
        await gesture.removePointer();
      });
    });
  });
}
