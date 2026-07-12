import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

/// Nested grids demo (v2) — a self-contained showcase of every nested-grid
/// capability, styled to match the main Playground:
///
///  * a root dashboard whose `group` item hosts a nested dashboard;
///  * drag & drop of items between the two levels (and back);
///  * `sizeToContent` vs fixed-size internal scrolling;
///  * live `compactType` switching on every grid;
///  * `subGridDynamic`: hover a plain leaf with a dragged item to turn it
///    into a brand-new nested grid on the fly;
///  * save / load of the whole tree, with the JSON shown in the panel.
///
/// Run with: flutter run -t lib/nested_example.dart
void main() => runApp(const NestedExampleApp());

class NestedExampleApp extends StatelessWidget {
  const NestedExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'sliver_dashboard — nested grids',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const NestedExamplePage(),
    );
  }
}

/// A palette with enough contrast for labels on top of the tiles.
class _Palette {
  static const hostBackground = Color(0xFFFFF3D6); // pale amber grid backdrop
  static const hostHeader = Color(0xFFF59E0B); // amber 500
  static const nestedTile = Color(0xFFFB923C); // orange 400
  static const leafTile = Color(0xFF4ADE80); // green 400
  static const dynamicHostTile = Color(0xFF67E8F9); // cyan 300 (was a leaf)
  static const onTile = Color(0xFF1F2937); // slate 800 — readable on pastels
}

class NestedExamplePage extends StatefulWidget {
  const NestedExamplePage({super.key});

  @override
  State<NestedExamplePage> createState() => _NestedExamplePageState();
}

class _NestedExamplePageState extends State<NestedExamplePage> {
  final coordinator = DashboardNestedCoordinator();

  late final DashboardController root = DashboardController(
    initialSlotCount: 8,
    initialLayout: const [
      LayoutItem(id: 'group', x: 0, y: 0, w: 4, h: 4, hasNestedGrid: true),
      LayoutItem(id: 'leaf-1', x: 4, y: 0, w: 2, h: 2),
      LayoutItem(id: 'leaf-2', x: 6, y: 0, w: 2, h: 2),
      LayoutItem(id: 'leaf-3', x: 4, y: 2, w: 2, h: 2),
    ],
  )..setEditMode(true);

  late final DashboardController group = DashboardController(
    initialSlotCount: 4,
    initialLayout: const [
      LayoutItem(id: 'nested-1', x: 0, y: 0, w: 1, h: 1),
      LayoutItem(id: 'nested-2', x: 1, y: 0, w: 1, h: 1),
      LayoutItem(id: 'nested-3', x: 2, y: 0, w: 2, h: 1),
    ],
  )..setEditMode(true);

  /// Child controllers for grids created on the fly by [subGridDynamic],
  /// keyed by the host item id. Kept so their layout survives virtualization.
  final Map<String, DashboardController> _dynamicChildren = {};

  final jsonController = TextEditingController();
  final maxDepthController = TextEditingController();

  /// null = unlimited nesting.
  final maxNestingDepth = ValueNotifier<int?>(null);

  final isEditing = ValueNotifier<bool>(true);
  final sizeToContent = ValueNotifier<bool>(true);
  final subGridDynamic = ValueNotifier<bool>(false);

  /// Same-grid variant: pause the pointer mid-drag over a sibling leaf.
  final subGridDynamicSameGrid = ValueNotifier<bool>(false);
  final compactionType = ValueNotifier<CompactType>(CompactType.vertical);

  List<Map<String, dynamic>>? _savedTree;

  @override
  void dispose() {
    isEditing.dispose();
    sizeToContent.dispose();
    subGridDynamic.dispose();
    subGridDynamicSameGrid.dispose();
    compactionType.dispose();
    jsonController.dispose();
    maxDepthController.dispose();
    maxNestingDepth.dispose();
    coordinator.dispose();
    root.dispose();
    group.dispose();
    for (final c in _dynamicChildren.values) {
      c.dispose();
    }
    super.dispose();
  }

  Iterable<DashboardController> get _allControllers => [
    root,
    group,
    ..._dynamicChildren.values,
  ];

  void _applyEditMode() {
    for (final c in _allControllers) {
      c.setEditMode(isEditing.value);
    }
  }

  /// Parses the depth text field. Empty/invalid -> unlimited (null); clamps
  /// negatives to 0. Applied on submit so partial typing never fights the user.
  void _setMaxDepthFromText(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      maxNestingDepth.value = null;
      return;
    }
    final parsed = int.tryParse(text);
    if (parsed == null) {
      // Invalid entry: reset to unlimited and clear the field.
      maxNestingDepth.value = null;
      maxDepthController.clear();
      return;
    }
    maxNestingDepth.value = parsed < 0 ? 0 : parsed;
  }

  void _applyCompactType() {
    for (final c in _allControllers) {
      c.setCompactionType(compactionType.value);
    }
  }

  /// subGridDynamic: the user held a dragged item over [host] long enough to
  /// request turning it into a nested grid. We create a controller for it,
  /// flag the item, and move the dragged item into the new grid.
  void _onNestedGridRequested(
    LayoutItem host,
    LayoutItem dragged,
    DashboardController hostGrid,
  ) {
    if (host.hasNestedGrid || _dynamicChildren.containsKey(host.id)) return;

    final child = DashboardController(initialSlotCount: host.w)
      ..setEditMode(isEditing.value)
      ..setCompactionType(compactionType.value);
    _dynamicChildren[host.id] = child;

    // Flag the host so the builder swaps its content to a NestedDashboard.
    // A metadata-only change, so recompact:false keeps the other items put.
    hostGrid.updateItem(
      host.id,
      (i) => i.copyWith(hasNestedGrid: true),
      recompact: false,
    );
    setState(() {});
    // No programmatic move: the held drag hands itself over to the freshly
    // mounted child grid (next pointer move or the release itself), through
    // the regular cross-grid session. A programmatic move here would even be
    // harmful in the same-grid flow: the dragged item is still present in
    // hostGrid, so moving it mid-drag would duplicate its id across grids.
  }

  /// A request fired but the drag ended without dropping into the host's
  /// child grid: revert the speculative conversion (issue: without this,
  /// every armed-but-unused leaf stays converted as an empty nested grid).
  void _onNestedGridAbandoned(LayoutItem host, DashboardController hostGrid) {
    final child = _dynamicChildren.remove(host.id);
    if (child == null) return; // not one of our dynamic conversions

    coordinator.unlinkChildGrid(child);
    hostGrid.updateItem(
      host.id,
      (i) => i.copyWith(hasNestedGrid: false),
      recompact: false,
    );
    // The NestedDashboard for this host may still be mounted this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => child.dispose());
    setState(() {});
  }

  void _saveTree() {
    final tree = exportNestedTree(coordinator, root);
    _savedTree = tree;
    jsonController.text = const JsonEncoder.withIndent('  ').convert(tree);
    setState(() {}); // enable the restore button
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved ${tree.length} root items (JSON in the panel)'),
        backgroundColor: Colors.indigo,
      ),
    );
  }

  void _restoreTree() {
    final saved = _savedTree;
    if (saved == null) return;
    loadNestedTree(coordinator, root, saved);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tree restored from the last save'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // --- Tile builders -------------------------------------------------------

  Widget _tile(LayoutItem item, Color color) {
    return Card(
      color: color,
      margin: EdgeInsets.zero,
      child: Center(
        child: Text(
          item.id,
          style: const TextStyle(
            color: _Palette.onTile,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _nestedHost(
    BuildContext context,
    LayoutItem item,
    DashboardController child,
  ) {
    return ValueListenableBuilder<bool>(
      valueListenable: sizeToContent,
      builder: (context, stc, _) {
        return Card(
          margin: EdgeInsets.zero,
          color: _Palette.hostBackground,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: _Palette.hostHeader,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(
                  'Nested grid · ${item.id}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: NestedDashboard(
                  controller: child,
                  parentItemId: item.id,
                  sizeToContent: stc,
                  chromeExtent: 40, // the header above
                  itemBuilder: (context, leaf) =>
                      _tile(leaf, _Palette.nestedTile),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDashboard() {
    return DashboardNestedScope(
      coordinator: coordinator,
      subGridDynamic: subGridDynamic.value,
      subGridDynamicSameGrid: subGridDynamicSameGrid.value,
      maxNestingDepth: maxNestingDepth.value,
      onNestedGridRequested: _onNestedGridRequested,
      onNestedGridRequestAbandoned: _onNestedGridAbandoned,
      onItemMovedToGrid: (item, from, to) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 900),
            content: Text('Moved "${item.id}" between grids'),
          ),
        );
      },
      child: Dashboard<String>(
        controller: root,
        slotAspectRatio: 1.0,
        mainAxisSpacing: 8.0,
        crossAxisSpacing: 8.0,
        padding: const EdgeInsets.all(8.0),
        itemBuilder: (context, item) {
          // Branch on the declarative flag rather than the id: this is what
          // keeps hosts portable (a flagged item dropped into another grid
          // still renders as a grid if that grid's builder does the same).
          if (item.hasNestedGrid) {
            final child = item.id == 'group'
                ? group
                : _dynamicChildren[item.id];
            if (child != null) return _nestedHost(context, item, child);
          }
          final color = _dynamicChildren.containsKey(item.id)
              ? _Palette.dynamicHostTile
              : _Palette.leafTile;
          return _tile(item, color);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 950;

    final configPanel = _ConfigPanel(
      isEditing: isEditing,
      sizeToContent: sizeToContent,
      subGridDynamic: subGridDynamic,
      subGridDynamicSameGrid: subGridDynamicSameGrid,
      compactionType: compactionType,
      maxNestingDepth: maxNestingDepth,
      maxDepthController: maxDepthController,
      onMaxDepthSubmitted: _setMaxDepthFromText,
      jsonController: jsonController,
      canRestore: _savedTree != null,
      onEditModeChanged: _applyEditMode,
      onCompactTypeChanged: _applyCompactType,
      onSave: _saveTree,
      onRestore: _restoreTree,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nested grids — drag between levels'),
        elevation: 2,
        actions: [
          if (!isDesktop)
            Builder(
              builder: (context) {
                return IconButton(
                  icon: const Icon(Icons.tune),
                  tooltip: 'Open Config Panel',
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                );
              },
            ),
        ],
      ),
      endDrawer: isDesktop ? null : Drawer(child: SafeArea(child: configPanel)),
      body: Row(
        children: [
          Expanded(
            // subGridDynamic and maxNestingDepth are read in _buildDashboard():
            // rebuild when either changes.
            child: ListenableBuilder(
              listenable: Listenable.merge([
                subGridDynamic,
                subGridDynamicSameGrid,
                maxNestingDepth,
              ]),
              builder: (context, _) => _buildDashboard(),
            ),
          ),
          if (isDesktop)
            Container(
              width: 320,
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Colors.grey.shade800)),
              ),
              child: Material(color: Colors.grey.shade900, child: configPanel),
            ),
        ],
      ),
    );
  }
}

class _ConfigPanel extends StatelessWidget {
  const _ConfigPanel({
    required this.isEditing,
    required this.sizeToContent,
    required this.subGridDynamic,
    required this.subGridDynamicSameGrid,
    required this.compactionType,
    required this.maxNestingDepth,
    required this.maxDepthController,
    required this.onMaxDepthSubmitted,
    required this.jsonController,
    required this.canRestore,
    required this.onEditModeChanged,
    required this.onCompactTypeChanged,
    required this.onSave,
    required this.onRestore,
  });

  final ValueNotifier<bool> isEditing;
  final ValueNotifier<bool> sizeToContent;
  final ValueNotifier<bool> subGridDynamic;
  final ValueNotifier<bool> subGridDynamicSameGrid;
  final ValueNotifier<CompactType> compactionType;
  final ValueNotifier<int?> maxNestingDepth;
  final TextEditingController maxDepthController;
  final ValueChanged<String> onMaxDepthSubmitted;
  final TextEditingController jsonController;
  final bool canRestore;
  final VoidCallback onEditModeChanged;
  final VoidCallback onCompactTypeChanged;
  final VoidCallback onSave;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NESTED GRID PANEL',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.indigo.shade300,
            ),
          ),
          const Divider(),

          _SectionTitle('Interaction'),
          _SwitchTile(
            title: 'Edit Mode (Draggable/Resizable)',
            notifier: isEditing,
            onChanged: (_) => onEditModeChanged(),
          ),

          const SizedBox(height: 16),
          _SectionTitle('Nested Behavior'),
          _SwitchTile(
            title: 'sizeToContent (host grows vs internal scroll)',
            notifier: sizeToContent,
          ),
          _SwitchTile(
            title: 'subGridDynamic (hover a leaf to nest it)',
            notifier: subGridDynamic,
          ),
          _SwitchTile(
            title: 'subGridDynamicSameGrid (pause mid-drag over a sibling)',
            notifier: subGridDynamicSameGrid,
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<int?>(
            valueListenable: maxNestingDepth,
            builder: (context, depth, _) {
              return TextField(
                controller: maxDepthController,
                keyboardType: TextInputType.number,
                onSubmitted: onMaxDepthSubmitted,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  labelText: 'maxNestingDepth',
                  helperText: depth == null
                      ? 'empty = unlimited · 0 = off · 1 = one level'
                      : 'limit: $depth level(s) — press Enter to apply',
                ),
              );
            },
          ),

          const SizedBox(height: 10),
          const Text(
            'Compaction Type',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          ValueListenableBuilder<CompactType>(
            valueListenable: compactionType,
            builder: (context, value, _) {
              return DropdownButton<CompactType>(
                isExpanded: true,
                value: value,
                items: CompactType.values
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(v.name.toUpperCase()),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    compactionType.value = v;
                    onCompactTypeChanged();
                  }
                },
              );
            },
          ),

          const SizedBox(height: 16),
          _SectionTitle('Tree Save / Load'),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save),
                label: const Text('Save tree'),
              ),
              OutlinedButton.icon(
                onPressed: canRestore ? onRestore : null,
                icon: const Icon(Icons.restore),
                label: const Text('Restore'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: jsonController,
            maxLines: 8,
            readOnly: true,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Exported tree (JSON)',
            ),
          ),

          const SizedBox(height: 16),
          _SectionTitle('How to try it'),
          Text(
            'Drag "nested-*" out into the amber root grid, or a green leaf into '
            'the nested grid. Turn on subGridDynamic, then hold a dragged item '
            'over a green leaf to turn it into its own grid (it goes cyan).',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: Colors.white70,
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.notifier,
    this.onChanged,
  });

  final String title;
  final ValueNotifier<bool> notifier;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (context, value, _) {
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title, style: const TextStyle(fontSize: 12)),
          value: value,
          onChanged: (val) {
            notifier.value = val;
            onChanged?.call(val);
          },
        );
      },
    );
  }
}
