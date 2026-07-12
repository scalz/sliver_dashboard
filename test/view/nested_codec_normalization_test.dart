import 'package:flutter_test/flutter_test.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

void main() {
  test(
      'loadNestedTree normalizes hand-written JSON: an item carrying a '
      'subGrid payload becomes a host even when the flag is omitted', () {
    final coordinator = DashboardNestedCoordinator();
    addTearDown(coordinator.dispose);
    final root = DashboardController(initialSlotCount: 4);
    addTearDown(root.dispose);

    loadNestedTree(coordinator, root, [
      {
        'id': 'group',
        'x': 0,
        'y': 0,
        'w': 2,
        'h': 2,
        // no 'hasNestedGrid' key: hand-written JSON
        'subGrid': {
          'slotCount': 2,
          'items': [
            {'id': 'n1', 'x': 0, 'y': 0, 'w': 1, 'h': 1},
          ],
        },
      },
      {'id': 'leaf', 'x': 2, 'y': 0, 'w': 1, 'h': 1},
    ]);

    final group = root.layout.value.firstWhere((i) => i.id == 'group');
    expect(group.hasNestedGrid, isTrue, reason: 'normalized from subGrid payload');
    final leaf = root.layout.value.firstWhere((i) => i.id == 'leaf');
    expect(leaf.hasNestedGrid, isFalse);

    // The subGrid payload was stashed for the (unmounted) child grid.
    final stashed = coordinator.takeStashedChildGrid('group');
    expect(stashed, isNotNull);
    expect(stashed!.slotCount, 2);
    expect(stashed.items.single.id, 'n1');
  });
}
