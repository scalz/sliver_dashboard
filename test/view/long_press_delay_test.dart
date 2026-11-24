import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

/// Counts mounts of the grid's content, to prove a delay change never
/// remounts the scroll view.
class _MountCounter extends StatefulWidget {
  const _MountCounter({required this.child});

  final Widget child;
  static int mounts = 0;

  @override
  State<_MountCounter> createState() => _MountCounterState();
}

class _MountCounterState extends State<_MountCounter> {
  @override
  void initState() {
    super.initState();
    _MountCounter.mounts++;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  // flutter_test runs as Android: the long-press path is the touch pick-up.
  late DashboardController controller;
  late ScrollController scroll;

  setUp(() {
    _MountCounter.mounts = 0;
    controller = DashboardController(
      initialSlotCount: 4,
      initialLayout: const [
        LayoutItem(id: 'a', x: 0, y: 0, w: 2, h: 1),
        LayoutItem(id: 'tall', x: 0, y: 20, w: 1, h: 1, isStatic: true),
      ],
    )..setEditMode(true);
    scroll = ScrollController();
  });

  tearDown(() {
    controller.dispose();
    scroll.dispose();
  });

  Widget app({Duration? delay, void Function(int, int)? onSlotLongPress}) => MaterialApp(
        home: Dashboard(
          controller: controller,
          scrollController: scroll,
          padding: const EdgeInsets.all(20),
          longPressDelay: delay,
          onSlotLongPress: onSlotLongPress,
          itemBuilder: (context, item) => _MountCounter(child: Text(item.id)),
        ),
      );

  Future<TestGesture> holdOn(WidgetTester tester, Offset at, Duration hold) async {
    final gesture = await tester.startGesture(at);
    await tester.pump(hold);
    return gesture;
  }

  testWidgets('default: 500 ms (kLongPressTimeout)', (tester) async {
    await tester.pumpWidget(app());
    final g =
        await holdOn(tester, tester.getCenter(find.text('a')), const Duration(milliseconds: 400));
    expect(controller.isDragging.value, isFalse);
    await tester.pump(const Duration(milliseconds: 150));
    expect(controller.isDragging.value, isTrue);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a custom delay picks the tile up sooner', (tester) async {
    await tester.pumpWidget(app(delay: const Duration(milliseconds: 200)));
    final g =
        await holdOn(tester, tester.getCenter(find.text('a')), const Duration(milliseconds: 150));
    expect(controller.isDragging.value, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.isDragging.value, isTrue);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the delay also drives onSlotLongPress', (tester) async {
    final hits = <(int, int)>[];
    await tester.pumpWidget(
      app(delay: const Duration(milliseconds: 200), onSlotLongPress: (x, y) => hits.add((x, y))),
    );
    // Right half of row 0 is empty (a is 2 wide on 4 columns).
    final a = tester.getRect(find.text('a').hitTestable().first);
    final emptyRight = Offset(tester.getSize(find.byType(Dashboard)).width - 40, a.center.dy);
    final g = await holdOn(tester, emptyRight, const Duration(milliseconds: 150));
    expect(hits, isEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    expect(hits, hasLength(1));
    expect(hits.single.$2, 0);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('changing the delay applies to the next press without remounting the grid',
      (tester) async {
    await tester.pumpWidget(app());
    final mountsBefore = _MountCounter.mounts;
    await tester.pumpWidget(app(delay: const Duration(milliseconds: 200)));
    expect(_MountCounter.mounts, mountsBefore, reason: 'tile content was remounted');

    final g =
        await holdOn(tester, tester.getCenter(find.text('a')), const Duration(milliseconds: 250));
    expect(controller.isDragging.value, isTrue);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a finger that moves before the delay scrolls instead', (tester) async {
    await tester.pumpWidget(app(delay: const Duration(milliseconds: 300)));
    final g = await tester.startGesture(tester.getCenter(find.text('a')));
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.isDragging.value, isFalse);
    expect(scroll.offset, greaterThan(0));
    await g.up();
    await tester.pumpAndSettle();
  });
}
