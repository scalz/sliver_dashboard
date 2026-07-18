import 'package:sliver_dashboard/src/controller/dashboard_controller_interface.dart';
import 'package:sliver_dashboard/src/models/layout_item.dart';
import 'package:sliver_dashboard/src/view/nested/dashboard_nested_scope.dart';

/// Recursive serialization of a nested dashboard tree.
///
/// each item is its plain [LayoutItem.toMap] representation, plus an optional
/// `subGrid` key when a nested grid is mounted inside it:
///
/// ```json
/// [
///   {"id": "a", "x": 0, "y": 0, "w": 2, "h": 2},
///   {"id": "group", "x": 2, "y": 0, "w": 4, "h": 4,
///    "subGrid": {"slotCount": 4, "items": [
///      {"id": "a1", "x": 0, "y": 0, "w": 1, "h": 1}
///    ]}}
/// ]
/// ```
///
/// The child `slotCount` is persisted so a tree restored
/// with `autoSlotCount: false` reproduces the exact same geometry and be in sync with the parent.
///
/// Item ids must be unique across the whole tree — the same invariant
/// cross-grid drag & drop relies on.

/// Exports the tree rooted at [root] as a JSON-encodable list, recursing into
/// every nested grid registered in [coordinator] (i.e. currently mounted or
/// linked via NestedDashboard).
///
/// Links declared by NestedDashboard survive virtualization unmounts, so
/// hosts scrolled out of view export their subtree normally. Only a grid
/// whose NestedDashboard has never mounted (and was never linked) exports
/// flat.
List<Map<String, dynamic>> exportNestedTree(
  DashboardNestedCoordinator coordinator,
  DashboardController root,
) {
  // Persistent links (not live registrations): a host item scrolled out of
  // view has its NestedDashboard unmounted by sliver virtualization, but its
  // child controller and link remain, so the subtree still exports fully.
  final children = coordinator.childGridsOf(root);
  return [
    for (final item in root.layout.value) _exportItem(coordinator, children, item),
  ];
}

Map<String, dynamic> _exportItem(
  DashboardNestedCoordinator coordinator,
  Map<String, DashboardController> siblingsChildren,
  LayoutItem item,
) {
  final map = item.toMap();
  final child = siblingsChildren[item.id];
  if (child != null) {
    // Self-healing: a linked host is exported with the declarative flag set,
    // even if the application forgot to set it on the item.
    map['hasNestedGrid'] = true;
    map['subGrid'] = <String, dynamic>{
      'slotCount': child.slotCount.value,
      'items': exportNestedTree(coordinator, child),
    };
  }
  return map;
}

/// Loads a tree produced by [exportNestedTree] into [root].
///
/// The root layout is imported immediately; every `subGrid` payload is
/// delivered to its host grid — applied at once when that grid is already
/// mounted, otherwise stashed in [coordinator] and consumed automatically by
/// the corresponding NestedDashboard on first mount.
void loadNestedTree(
  DashboardNestedCoordinator coordinator,
  DashboardController root,
  List<dynamic> tree,
) {
  final rootItems = _parseLevel(coordinator, tree);
  root.importLayout([for (final i in rootItems) i.toMap()]);
}

List<LayoutItem> _parseLevel(
  DashboardNestedCoordinator coordinator,
  List<dynamic> itemsJson,
) {
  final items = <LayoutItem>[];
  for (final e in itemsJson) {
    if (e is! Map) {
      throw const FormatException('Invalid nested layout: element is not a Map');
    }
    final map = Map<String, dynamic>.from(e);
    final sub = map.remove('subGrid');
    // Normalize: an item carrying a subGrid payload is a host by definition,
    // even in hand-written JSON that omits the flag.
    var item = LayoutItem.fromMap(map);
    if (sub is Map && !item.hasNestedGrid) {
      item = item.copyWith(hasNestedGrid: true);
    }
    items.add(item);
    if (sub is Map) {
      final subMap = Map<String, dynamic>.from(sub);
      final childItems = _parseLevel(
        coordinator,
        (subMap['items'] as List?) ?? const <dynamic>[],
      );
      coordinator.deliverChildGrid(
        item.id,
        NestedGridData(
          items: childItems,
          slotCount: subMap['slotCount'] is int ? subMap['slotCount'] as int : null,
        ),
      );
    }
  }
  return items;
}
