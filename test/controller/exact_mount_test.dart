import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

/// A valid stored layout — sparse, with holes a compactor would close — must
/// come back exactly as stored when compaction is off. This is what a fixed
/// board relies on: a tile saved at row 3 stays at row 3.
void main() {
  // Holes everywhere: row 0 is empty, column 1 has a gap, a static floats.
  const stored = [
    LayoutItem(id: 'a', x: 0, y: 1, w: 2, h: 2),
    LayoutItem(id: 'b', x: 3, y: 4, w: 1, h: 1),
    LayoutItem(id: 'c', x: 2, y: 2, w: 1, h: 3),
    LayoutItem(id: 's', x: 3, y: 0, w: 1, h: 1, isStatic: true),
  ];

  List<(String, int, int, int, int)> geometry(List<LayoutItem> l) =>
      [for (final i in l) (i.id, i.x, i.y, i.w, i.h)]..sort((p, q) => p.$1.compareTo(q.$1));

  final expected = geometry(stored);

  DashboardController noCompaction({void Function()? onChange}) {
    final c = DashboardController(
      initialSlotCount: 4,
      onLayoutChanged: onChange == null ? null : (_, __) => onChange(),
    )..setCompactionType(CompactType.none);
    return c;
  }

  test('importLayout keeps every position and size', () {
    final c = noCompaction();
    addTearDown(c.dispose);
    c.importLayout([for (final i in stored) i.toMap()]);
    expect(geometry(c.layout.value), expected);
  });

  test('addItems with explicit coordinates keeps every position and size', () {
    final c = noCompaction();
    addTearDown(c.dispose);
    c.addItems(stored);
    expect(geometry(c.layout.value), expected);
  });

  test('importLayout on a maxRows grid keeps a layout that fits the cap', () {
    final c = noCompaction()..setMaxRows(5);
    addTearDown(c.dispose);
    c.importLayout([for (final i in stored) i.toMap()]);
    expect(geometry(c.layout.value), expected);
  });

  testWidgets('mounting a Dashboard moves nothing and reports nothing', (tester) async {
    var events = 0;
    final c = DashboardController(
      initialLayout: stored,
      initialSlotCount: 4,
      onLayoutChanged: (_, __) => events++,
    );
    addTearDown(c.dispose);
    // Set before mounting, then reset the counter: only the MOUNT is under test.
    c.setCompactionType(CompactType.none);
    events = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Dashboard(
            controller: c,
            padding: const EdgeInsets.all(20),
            itemBuilder: (context, item) => Text(item.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(geometry(c.layout.value), expected);
    expect(events, 0);
  });
}
