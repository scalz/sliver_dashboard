import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

/// Counts mounts of a tile's content (to catch re-parenting).
class _Content extends StatefulWidget {
  const _Content(this.id);

  final String id;
  static int mounts = 0;

  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  @override
  void initState() {
    super.initState();
    _Content.mounts++;
  }

  @override
  Widget build(BuildContext context) => Center(child: Text(widget.id));
}

void main() {
  late DashboardController controller;
  late List<List<String>> deleted;
  late int dragStarts;
  late int resizeStarts;

  setUp(() {
    _Content.mounts = 0;
    deleted = [];
    dragStarts = 0;
    resizeStarts = 0;
    controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 2),
        LayoutItem(id: 'b', x: 2, y: 0, w: 2, h: 2),
      ],
    )..setEditMode(true);
  });

  tearDown(() => controller.dispose());

  Widget app({
    DashboardEditOverlayBuilder? overlay,
    DashboardWillDeleteCallback? onWillDelete,
    DashboardCloneRequestCallback? onClone,
    WidgetBuilder? emptyBuilder,
    Widget Function(LayoutItem item)? content,
  }) =>
      MaterialApp(
        home: Dashboard(
          controller: controller,
          padding: const EdgeInsets.all(20),
          editOverlayBuilder: overlay,
          emptyBuilder: emptyBuilder,
          onWillDelete: onWillDelete,
          onItemsDeleted: (items) => deleted.add([for (final i in items) i.id]),
          onCloneRequested: onClone,
          onItemDragStart: (_) => dragStarts++,
          onItemResizeStart: (_) => resizeStarts++,
          itemBuilder: (context, item) => content?.call(item) ?? _Content(item.id),
        ),
      );

  // A close button in the top-right corner: inside the resize zone.
  Widget closeButton(BuildContext context, LayoutItem item, DashboardTileActions actions) => Align(
        alignment: Alignment.topRight,
        child: GestureDetector(
          key: ValueKey('close-${item.id}'),
          onTap: actions.delete,
          child: const SizedBox(width: 16, height: 16, child: ColoredBox(color: Colors.red)),
        ),
      );

  Future<void> desktop(Future<void> Function() body) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  }

  Future<void> click(WidgetTester tester, Finder f) async {
    final g = await tester.startGesture(tester.getCenter(f), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
  }

  group('editOverlayBuilder', () {
    testWidgets('shown in edit mode only', (tester) async {
      await tester.pumpWidget(app(overlay: closeButton));
      expect(find.byKey(const ValueKey('close-a')), findsOneWidget);
      controller.setEditMode(false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('close-a')), findsNothing);
    });

    testWidgets('delete goes through the pipeline and starts no grid gesture', (tester) async {
      await desktop(() async {
        await tester.pumpWidget(app(overlay: closeButton));
        await click(tester, find.byKey(const ValueKey('close-a')));
        expect(controller.layout.value.map((i) => i.id), ['b']);
        expect(deleted, [
          ['a'],
        ]);
        expect(controller.canUndo.value, isTrue);
        expect((dragStarts, resizeStarts), (0, 0), reason: 'corner press started a gesture');
        expect(
          controller.selectedItemIds.value,
          isEmpty,
          reason: 'the press changed the selection',
        );
      });
    });

    testWidgets('onWillDelete can veto', (tester) async {
      await desktop(() async {
        await tester.pumpWidget(app(overlay: closeButton, onWillDelete: (_) async => false));
        await click(tester, find.byKey(const ValueKey('close-a')));
        expect(controller.layout.value.map((i) => i.id), ['a', 'b']);
        expect(deleted, isEmpty);
      });
    });

    testWidgets('targets this tile only, never the rest of the selection', (tester) async {
      await desktop(() async {
        await tester.pumpWidget(app(overlay: closeButton));
        controller.selectedItemIds.value = {'a', 'b'};
        await tester.pump();
        await click(tester, find.byKey(const ValueKey('close-a')));
        expect(controller.layout.value.map((i) => i.id), ['b']);
      });
    });

    testWidgets('touch: a tap reaches the button and leaves the selection alone', (tester) async {
      // flutter_test runs as Android. The veto keeps the tile, so any change
      // to the selection could only come from the grid's tap handling
      // (removeItems itself clears the selection, like the Delete key).
      var asked = 0;
      await tester.pumpWidget(
        app(
          overlay: closeButton,
          onWillDelete: (_) async {
            asked++;
            return false;
          },
        ),
      );
      controller.selectedItemIds.value = {'b'};
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('close-a')));
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(controller.selectedItemIds.value, {'b'});
    });

    testWidgets('the rest of the tile still drags', (tester) async {
      await desktop(() async {
        await tester.pumpWidget(app(overlay: closeButton));
        final g = await tester.startGesture(
          tester.getCenter(find.text('a')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await g.moveBy(const Offset(0, 30));
        await tester.pump();
        expect(dragStarts, 1);
        await g.up();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('duplicate clones this tile only', (tester) async {
      await desktop(() async {
        var n = 0;
        await tester.pumpWidget(
          app(
            onClone: (item, _) => item.copyWith(id: 'copy${n++}'),
            overlay: (context, item, actions) => Align(
              alignment: Alignment.bottomLeft,
              child: GestureDetector(
                key: ValueKey('dup-${item.id}'),
                onTap: actions.duplicate,
                child:
                    const SizedBox(width: 16, height: 16, child: ColoredBox(color: Colors.green)),
              ),
            ),
          ),
        );
        controller.selectedItemIds.value = {'a', 'b'};
        await tester.pump();
        await click(tester, find.byKey(const ValueKey('dup-a')));
        expect(controller.layout.value.map((i) => i.id), containsAll(['a', 'b', 'copy0']));
        expect(controller.layout.value, hasLength(3));
      });
    });

    testWidgets('no re-parenting of the content while editing', (tester) async {
      await desktop(() async {
        await tester.pumpWidget(app(overlay: closeButton));
        final mounts = _Content.mounts;
        controller.selectedItemIds.value = {'a'};
        await tester.pump();
        controller.selectedItemIds.value = {'a', 'b'};
        await tester.pump();
        controller.clearSelection();
        await tester.pump();
        expect(_Content.mounts, mounts);
      });
    });

    testWidgets('an edit-mode toggle remounts no more with the layer than without', (tester) async {
      Future<int> toggleMounts(DashboardEditOverlayBuilder? overlay) async {
        controller.setEditMode(true);
        await tester.pumpWidget(app(overlay: overlay));
        await tester.pumpAndSettle();
        final before = _Content.mounts;
        controller.setEditMode(false);
        await tester.pumpAndSettle();
        controller.setEditMode(true);
        await tester.pumpAndSettle();
        return _Content.mounts - before;
      }

      final without = await toggleMounts(null);
      await tester.pumpWidget(const SizedBox());
      final withLayer = await toggleMounts(closeButton);
      expect(withLayer, without);
    });
  });

  group('DashboardGestureExclusion in application content', () {
    testWidgets('a button inside a tile gets its tap and starts no drag', (tester) async {
      await desktop(() async {
        var taps = 0;
        await tester.pumpWidget(
          app(
            content: (item) => Center(
              child: DashboardGestureExclusion(
                child: GestureDetector(
                  key: ValueKey('btn-${item.id}'),
                  onTap: () => taps++,
                  child:
                      const SizedBox(width: 30, height: 30, child: ColoredBox(color: Colors.green)),
                ),
              ),
            ),
          ),
        );
        final g = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('btn-a'))),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await g.moveBy(const Offset(0, 1));
        await g.up();
        await tester.pumpAndSettle();
        expect(taps, 1);
        expect(dragStarts, 0);
        expect(controller.selectedItemIds.value, isEmpty);
      });
    });
  });

  group('emptyBuilder', () {
    testWidgets('shown on an empty grid outside edit mode only', (tester) async {
      controller
        ..removeItems(['a', 'b'])
        ..setEditMode(false);
      await tester.pumpWidget(app(emptyBuilder: (_) => const Text('nothing yet')));
      expect(find.text('nothing yet'), findsOneWidget);

      controller.setEditMode(true);
      await tester.pump();
      expect(find.text('nothing yet'), findsNothing, reason: 'edit mode keeps a drop surface');

      controller
        ..setEditMode(false)
        ..addItem(const LayoutItem(id: 'n', x: 0, y: 0, w: 1, h: 1));
      await tester.pumpAndSettle();
      expect(find.text('nothing yet'), findsNothing);
    });

    testWidgets('showing and hiding it never remounts the scroll view', (tester) async {
      controller
        ..removeItems(['a', 'b'])
        ..setEditMode(false);
      await tester.pumpWidget(app(emptyBuilder: (_) => const Text('nothing yet')));
      final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      controller.setEditMode(true);
      await tester.pump();
      controller.setEditMode(false);
      await tester.pump();
      expect(
        identical(tester.state<ScrollableState>(find.byType(Scrollable).first).position, position),
        isTrue,
      );
    });
  });
}
