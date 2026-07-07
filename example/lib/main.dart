import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sliver Dashboard Playground',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const DashboardPage(),
    );
  }
}

/// A strict enterprise policy to isolate layout regions and block specific collisions.
class CustomDashboardPolicy extends DashboardPolicy {
  const CustomDashboardPolicy({required this.blockSectionCollision});

  final bool blockSectionCollision;

  @override
  bool canCollide(LayoutItem itemA, LayoutItem itemB) {
    // If enabled, prevent any dynamic item from pushing/colliding with
    // section barriers. The section headers act as immoveable visual dividers.
    if (blockSectionCollision && itemB.isSectionBarrier) {
      return false;
    }
    return true;
  }

  @override
  bool canMoveTo(
    LayoutItem item,
    int targetX,
    int targetY,
    List<LayoutItem> currentLayout,
  ) {
    // Optional: block moving items above y=0 if it's the reserved top section
    return true;
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Initial slot count for the controller.
  var slotCount = 8;

  // Create and manage your DashboardController.
  late final DashboardController controller;

  final standardScrollController = ScrollController();
  final sliverScrollController = ScrollController();
  final jsonController = TextEditingController();

  final showGenerateButton = ValueNotifier<bool>(false);
  final isEditing = ValueNotifier(false);
  final showMinimap = ValueNotifier(true);
  final useSliverDemo = ValueNotifier(false);
  final useDragHandlesOnly = ValueNotifier(false);
  final blockSectionCollision = ValueNotifier(true);
  final autoShrink = ValueNotifier(false);
  final compactionType = ValueNotifier<CompactType>(CompactType.vertical);
  final resizeBehavior = ValueNotifier<ResizeBehavior>(ResizeBehavior.push);
  final placementStrategy = ValueNotifier<AutoPlacementStrategy>(
    AutoPlacementStrategy.firstFit,
  );

  final cardColors = <String, Color>{};
  final random = Random();

  Color getColorForItem(String id) {
    return cardColors.putIfAbsent(id, () {
      return Color.fromRGBO(
        random.nextInt(120) + 50,
        random.nextInt(120) + 50,
        random.nextInt(120) + 120,
        1,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    controller = DashboardController(
      initialSlotCount: slotCount,
      onLayoutChanged: (items, bkSlotCount) {
        _syncJsonField();
      },
      initialLayout: [
        // Section 1 Barrier
        const LayoutItem(
          id: 'sec_sys',
          x: 0,
          y: 0,
          w: 8,
          h: 1,
          isSectionBarrier: true,
          sectionTitle: '📌 System Diagnostics (Section 1)',
        ),
        const LayoutItem(
          id: 'sys_cpu',
          x: 0,
          y: 1,
          w: 2,
          h: 2,
          minW: 1,
          minH: 1,
        ),
        const LayoutItem(id: 'sys_mem', x: 2, y: 1, w: 2, h: 2),

        // Section 2 Barrier
        const LayoutItem(
          id: 'sec_usr',
          x: 0,
          y: 3,
          w: 8,
          h: 1,
          isSectionBarrier: true,
          sectionTitle: '📊 Custom Widgets & Analytics (Section 2)',
        ),
        const LayoutItem(
          id: 'chart_sales',
          x: 0,
          y: 4,
          w: 4,
          h: 2,
          isResizable: true,
        ),
        const LayoutItem(id: 'chart_geo', x: 4, y: 4, w: 2, h: 2),
        const LayoutItem(id: 'table_logs', x: 6, y: 4, w: 2, h: 3),
      ],
    );

    // Sync initial configuration
    controller.setEditMode(isEditing.value);
    controller.setAllowAutoShrink(allow: autoShrink.value);
    _updatePolicy();
    _syncJsonField();

    controller.shortcuts = DashboardShortcuts(
      moveUp: {const SingleActivator(LogicalKeyboardKey.keyW)},
      moveLeft: {const SingleActivator(LogicalKeyboardKey.keyA)},
      moveDown: {const SingleActivator(LogicalKeyboardKey.keyS)},
      moveRight: {const SingleActivator(LogicalKeyboardKey.keyD)},
      grab: DashboardShortcuts.defaultShortcuts.grab,
      drop: DashboardShortcuts.defaultShortcuts.drop,
      cancel: DashboardShortcuts.defaultShortcuts.cancel,
    );

    blockSectionCollision.addListener(_updatePolicy);
  }

  void _updatePolicy() {
    controller.policy = CustomDashboardPolicy(
      blockSectionCollision: blockSectionCollision.value,
    );
  }

  void _syncJsonField() {
    final list = controller.exportLayout();
    if (list.length > 30) {
      jsonController.text =
          '// Auto-serialization paused for layouts with > 25 items.\n'
          '// Total items: ${list.length}\n'
          '//\n'
          '// Rendering 15,000+ lines of raw text in a TextField slows down perf.\n'
          '// Click "GENERATE JSON" below to export the schema manually at any time.';
      showGenerateButton.value = true;
      return;
    }
    jsonController.text = const JsonEncoder.withIndent('  ').convert(list);
    showGenerateButton.value = false;
  }

  /// Forces the generation of the JSON schema regardless of the layout size.
  void _forceGenerateJson() {
    final list = controller.exportLayout();
    jsonController.text = const JsonEncoder.withIndent('  ').convert(list);
    showMinimap.value = false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'JSON Schema generated successfully for ${list.length} items!',
        ),
        backgroundColor: Colors.indigo,
      ),
    );
  }

  void _importJson() {
    try {
      final decoded = jsonDecode(jsonController.text);
      if (decoded is List) {
        controller.importLayout(decoded);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Layout imported successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid JSON: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _addNewItem() {
    final w = random.nextInt(2) + 1;
    final h = random.nextInt(2) + 1;
    final newItem = LayoutItem(
      id: 'widget_${DateTime.now().millisecondsSinceEpoch % 10000}',
      x: -1,
      y: -1,
      w: w,
      h: h,
    );
    controller.addItem(newItem, strategy: placementStrategy.value);
  }

  void _addStressTestItems(int count) {
    final list = <LayoutItem>[];
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < count; i++) {
      list.add(
        LayoutItem(
          id: 'stress_${timestamp}_$i',
          x: -1,
          y: -1,
          w: random.nextInt(2) + 1,
          h: random.nextInt(2) + 1,
        ),
      );
    }
    controller.addItems(list, strategy: placementStrategy.value);
  }

  /// Unified deletion dialog helper supporting both singular and plural grammar.
  Future<bool> _confirmDeletion(List<LayoutItem> items) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete ?'),
        content: Text(
          items.length == 1
              ? 'Do you want to remove item ${items.first.id}?'
              : 'Do you want to remove items ${items.map((e) => e.id).join(', ')}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    return confirm ?? false;
  }

  /// Triggered when clicking the manual 'x' close button on a single card.
  Future<void> _confirmAndDelete(LayoutItem item) async {
    final confirm = await _confirmDeletion([item]);
    if (confirm) {
      controller.removeItem(item.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Item ${item.id} deleted')));
      }
    }
  }

  @override
  void dispose() {
    blockSectionCollision.removeListener(_updatePolicy);
    showGenerateButton.dispose();
    isEditing.dispose();
    showMinimap.dispose();
    useSliverDemo.dispose();
    useDragHandlesOnly.dispose();
    blockSectionCollision.dispose();
    autoShrink.dispose();
    compactionType.dispose();
    resizeBehavior.dispose();
    placementStrategy.dispose();
    jsonController.dispose();
    controller.dispose();
    standardScrollController.dispose();
    sliverScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 950;

    final configPanel = _ConfigPanel(
      controller: controller,
      jsonController: jsonController,
      isEditing: isEditing,
      showMinimap: showMinimap,
      useSliverDemo: useSliverDemo,
      useDragHandlesOnly: useDragHandlesOnly,
      blockSectionCollision: blockSectionCollision,
      autoShrink: autoShrink,
      compactionType: compactionType,
      resizeBehavior: resizeBehavior,
      placementStrategy: placementStrategy,
      showGenerateButton: showGenerateButton,
      onForceGenerate: _forceGenerateJson,
      onImportJson: _importJson,
      onStressTest: _addStressTestItems,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sliver Dashboard Playground'),
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
            child: ValueListenableBuilder(
              valueListenable: useSliverDemo,
              builder: (context, sliverMode, _) {
                if (sliverMode) {
                  return _buildSliverDemoView();
                } else {
                  return _buildStandardDemoView();
                }
              },
            ),
          ),
          if (isDesktop)
            Container(
              width: 320,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.grey.shade800, width: 1),
                ),
              ),
              child: Material(color: Colors.grey.shade900, child: configPanel),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewItem,
        tooltip: 'Add Auto-Placed Item (-1,-1)',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildStandardDemoView() {
    return ValueListenableBuilder2(
      useDragHandlesOnly,
      showMinimap,
      builder: (context, handlesOnly, minimap, _) {
        return Stack(
          children: [
            Dashboard<String>(
              controller: controller,
              scrollController: standardScrollController,
              scrollDirection: controller.scrollDirection.value,
              slotAspectRatio: 1.0,
              mainAxisSpacing: 8.0,
              crossAxisSpacing: 8.0,
              padding: const EdgeInsets.all(8.0),
              dragStartGesture: handlesOnly
                  ? DragStartGesture.none
                  : DragStartGesture.longPress,
              breakpoints: {0: 4, 600: 6, 900: 8},
              itemBuilder: _buildCard,
              onWillDelete: _confirmDeletion,
              gridStyle: GridStyle(
                fillColor: Colors.white.withValues(alpha: 0.04),
                handleColor: Colors.indigo.shade400,
                lineColor: Colors.white.withValues(alpha: 0.08),
                lineWidth: 1,
              ),
              itemStyle: DashboardItemStyle(
                focusColor:
                    Colors.indigoAccent, // Border color when focused/selected
                activeColor:
                    Colors.deepOrange, // Border color when actively dragged
                borderRadius: BorderRadius.circular(
                  12,
                ), // Match your card's border radius
                // Or provide a fully custom BoxDecoration:
                // focusDecoration: BoxDecoration(
                //   border: Border.all(color: Colors.green, width: 4),
                //   borderRadius: BorderRadius.circular(12),
                // ),
              ),
              trashLayout: const TrashLayout(
                visible: TrashPosition(bottom: 20, left: 100, right: 100),
                hidden: TrashPosition(bottom: -100, left: 100, right: 100),
              ),
              trashBuilder: _buildTrashBin,
            ),
            if (minimap) _buildMinimapOverlay(),
          ],
        );
      },
    );
  }

  Widget _buildSliverDemoView() {
    return ValueListenableBuilder2(
      useDragHandlesOnly,
      showMinimap,
      builder: (context, handlesOnly, minimap, _) {
        return Stack(
          children: [
            DashboardOverlay<String>(
              controller: controller,
              scrollController: sliverScrollController,
              dragStartGesture: handlesOnly
                  ? DragStartGesture.none
                  : DragStartGesture.longPress,
              gridStyle: GridStyle(
                fillColor: Colors.white.withValues(alpha: 0.04),
                handleColor: Colors.indigo.shade400,
                lineColor: Colors.white.withValues(alpha: 0.08),
                lineWidth: 1,
              ),
              padding: const EdgeInsets.all(8.0),
              fillViewport: true,
              itemBuilder: (ctx, item) => _buildCard(ctx, item),
              onWillDelete: _confirmDeletion,
              trashLayout: const TrashLayout(
                visible: TrashPosition(bottom: 20, left: 100, right: 100),
                hidden: TrashPosition(bottom: -100, left: 100, right: 100),
              ),
              trashBuilder: _buildTrashBin,
              child: CustomScrollView(
                controller: sliverScrollController,
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    expandedHeight: 120,
                    backgroundColor: Colors.indigo.shade900,
                    flexibleSpace: const FlexibleSpaceBar(
                      title: Text('Sliver direct composition'),
                      centerTitle: false,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.all(8.0),
                    sliver: SliverDashboard(itemBuilder: _buildCard),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => ListTile(
                        leading: CircleAvatar(child: Text('$index')),
                        title: Text('Subsequent List Item $index'),
                        subtitle: const Text(
                          'Rendered natively alongside the grid sliver',
                        ),
                      ),
                      childCount: 15,
                    ),
                  ),
                ],
              ),
            ),
            if (minimap) _buildMinimapOverlay(),
          ],
        );
      },
    );
  }

  Widget _buildCard(BuildContext context, LayoutItem item) {
    final editing = isEditing.value;
    final handlesOnly = useDragHandlesOnly.value;

    return Card(
      key: ValueKey(item.id),
      elevation: 3,
      color: getColorForItem(item.id),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.id.startsWith('stress')
                      ? 'Item ${item.id.substring(7)}'
                      : item.id,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '(${item.w}x${item.h})',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          if (editing && handlesOnly)
            Positioned(
              left: 4,
              top: 4,
              child: DashboardDragStartListener(
                itemId: item.id,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.drag_handle,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (editing)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => _confirmAndDelete(item),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTrashBin(
    BuildContext context,
    bool hovered,
    bool active,
    String? activeItemId,
  ) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 60,
        margin: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          color: active
              ? Colors.red
              : (hovered ? Colors.orange : Colors.red.shade900),
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black54)],
          border: hovered ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? Icons.delete_forever : Icons.delete,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Text(
              active ? 'Release to Delete!' : 'Drop here to Delete',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMinimapOverlay() {
    return ValueListenableBuilder<bool>(
      valueListenable: useSliverDemo,
      builder: (context, sliverMode, _) {
        final activeScrollController = sliverMode
            ? sliverScrollController
            : standardScrollController;

        return Positioned(
          left: 16,
          bottom: 16,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Container(
              width: 120,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade800),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DashboardMinimap(
                controller: controller,
                scrollController: activeScrollController,
                width: 120,
                style: const MinimapStyle(
                  backgroundColor: Colors.black54,
                  itemColor: Colors.indigo,
                  staticItemColor: Colors.grey,
                  viewportColor: Color(0x332196F3),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ValueListenableBuilder2<A, B> extends StatelessWidget {
  const ValueListenableBuilder2(
    this.first,
    this.second, {
    required this.builder,
    super.key,
  });

  final ValueListenable<A> first;
  final ValueListenable<B> second;
  final Widget Function(BuildContext context, A a, B b, Widget? child) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<A>(
      valueListenable: first,
      builder: (context, a, _) {
        return ValueListenableBuilder<B>(
          valueListenable: second,
          builder: (context, b, _) {
            return builder(context, a, b, null);
          },
        );
      },
    );
  }
}

class _ConfigPanel extends StatelessWidget {
  const _ConfigPanel({
    required this.controller,
    required this.jsonController,
    required this.isEditing,
    required this.showMinimap,
    required this.useSliverDemo,
    required this.useDragHandlesOnly,
    required this.blockSectionCollision,
    required this.autoShrink,
    required this.compactionType,
    required this.resizeBehavior,
    required this.placementStrategy,
    required this.showGenerateButton,
    required this.onForceGenerate,
    required this.onImportJson,
    required this.onStressTest,
  });

  final DashboardController controller;
  final TextEditingController jsonController;
  final ValueNotifier<bool> isEditing;
  final ValueNotifier<bool> showMinimap;
  final ValueNotifier<bool> useSliverDemo;
  final ValueNotifier<bool> useDragHandlesOnly;
  final ValueNotifier<bool> blockSectionCollision;
  final ValueNotifier<bool> autoShrink;
  final ValueNotifier<CompactType> compactionType;
  final ValueNotifier<ResizeBehavior> resizeBehavior;
  final ValueNotifier<AutoPlacementStrategy> placementStrategy;
  final ValueNotifier<bool> showGenerateButton;
  final VoidCallback onForceGenerate;
  final VoidCallback onImportJson;
  final void Function(int) onStressTest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CONFIGURATION PANEL',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.indigo.shade300,
            ),
          ),
          const Divider(),

          // Section 1: Visual Mode
          _SectionTitle('Visual Modes & Structures'),
          _SwitchTile(
            title: 'Edit Mode (Draggable/Resizable)',
            notifier: isEditing,
            onChanged: (val) => controller.setEditMode(val),
          ),
          _SwitchTile(
            title: 'Use Custom Drag Handles only',
            notifier: useDragHandlesOnly,
          ),
          _SwitchTile(
            title: 'Native Sliver Direct Composition',
            notifier: useSliverDemo,
          ),
          _SwitchTile(
            title: 'Render Interactive Mini-Map',
            notifier: showMinimap,
          ),

          const SizedBox(height: 16),
          // Section 2: Layout Rules
          _SectionTitle('Collision & Layout Rules'),
          _SwitchTile(
            title: 'Block Section Header Collisions',
            notifier: blockSectionCollision,
          ),
          _SwitchTile(
            title: 'Auto-Shrink neighbors on Drag',
            notifier: autoShrink,
            onChanged: (val) => controller.setAllowAutoShrink(allow: val),
          ),

          const SizedBox(height: 10),
          const Text(
            'Compaction Type',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          ValueListenableBuilder(
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
                    controller.setCompactionType(v);
                  }
                },
              );
            },
          ),

          const SizedBox(height: 10),
          const Text(
            'Resize Behavior',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          DropdownButton<ResizeBehavior>(
            isExpanded: true,
            value: resizeBehavior.value,
            items: ResizeBehavior.values
                .map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(v.name.toUpperCase()),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) {
                resizeBehavior.value = v;
                controller.setResizeBehavior(v);
              }
            },
          ),

          const SizedBox(height: 10),
          const Text(
            'Auto-placement Strategy',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          ValueListenableBuilder(
            valueListenable: placementStrategy,
            builder: (context, value, _) {
              return DropdownButton<AutoPlacementStrategy>(
                isExpanded: true,
                value: value,
                items: AutoPlacementStrategy.values
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(v.name.toUpperCase()),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    placementStrategy.value = v;
                  }
                },
              );
            },
          ),

          const SizedBox(height: 16),
          _SectionTitle('Stress Tests & Bulk actions'),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: () => onStressTest(20),
                child: const Text('+20 Items'),
              ),
              ElevatedButton(
                onPressed: () => onStressTest(100),
                child: const Text('+100 Items'),
              ),
              OutlinedButton(
                onPressed: () => controller.layout.value = [],
                child: const Text('Clear Grid'),
              ),
            ],
          ),

          const SizedBox(height: 16),
          _SectionTitle('JSON Schema Import/Export'),
          ValueListenableBuilder<bool>(
            valueListenable: showGenerateButton,
            builder: (context, show, _) {
              if (!show) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onForceGenerate,
                    icon: const Icon(Icons.bolt),
                    label: const Text('Generate JSON Schema'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: jsonController,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'JSON Layout',
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onImportJson,
              icon: const Icon(Icons.download),
              label: const Text('Import Layout from JSON'),
            ),
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
