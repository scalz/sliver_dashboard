import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

import 'multi_sliver_crossdrag_example.dart' show MultiSliverExamplePage;
import 'nested_example.dart' show NestedExamplePage;

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
      home: const ExampleHome(),
    );
  }
}

/// Launcher for the three dashboard demo examples.
class ExampleHome extends StatelessWidget {
  const ExampleHome({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Sliver Dashboard — Examples')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.surfaceContainer,
            child: ListTile(
              leading: Icon(Icons.dashboard, color: theme.colorScheme.primary),
              title: const Text('Playground'),
              subtitle: const Text(
                'Single grid: drag, resize, trash, sections, minimap, policies…',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DashboardPage()),
              ),
            ),
          ),
          Card(
            color: theme.colorScheme.surfaceContainer,
            child: ListTile(
              leading: Icon(
                Icons.grid_view,
                color: theme.colorScheme.secondary,
              ),
              title: const Text('Nested grids'),
              subtitle: const Text(
                'Grids inside items, cross-grid drag & drop, sizeToContent, '
                'save/load of the whole tree.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NestedExamplePage(),
                ),
              ),
            ),
          ),
          Card(
            color: theme.colorScheme.surfaceContainer,
            child: ListTile(
              leading: Icon(Icons.layers, color: theme.colorScheme.tertiary),
              title: const Text('Multi-Sliver Drag & Drop'),
              subtitle: const Text(
                'Asymmetric sliver grids, physical coordinate matrix translation, '
                'custom proportional scaling projection policies.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MultiSliverExamplePage(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A strict policy to isolate layout regions and block specific collisions.
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

/// Main playground viewport combining custom configurations and responsive grid views.
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
  final animateReflow = ValueNotifier(false);
  final autoShrink = ValueNotifier(false);
  final compactionType = ValueNotifier<CompactType>(CompactType.vertical);
  final resizeBehavior = ValueNotifier<ResizeBehavior>(ResizeBehavior.push);
  final placementStrategy = ValueNotifier<AutoPlacementStrategy>(
    AutoPlacementStrategy.firstFit,
  );

  final random = Random();

  // Cache holding both background and pre-calculated text colors as a tuple.
  final _cardColors = <String, ({Color cardColor, Color textColor})>{};

  ({Color cardColor, Color textColor}) _generateColor(
    String id,
    ColorScheme colorScheme,
  ) {
    final int hash = id.hashCode;
    final double hue = (hash.abs() % 360).toDouble();
    final bool isDark = colorScheme.brightness == Brightness.dark;

    final bgColor = HSLColor.fromAHSL(
      1.0,
      hue,
      isDark ? 0.35 : 0.65,
      isDark ? 0.25 : 0.85,
    ).toColor();

    final textColor = bgColor.computeLuminance() > 0.5
        ? Colors.black87
        : Colors.white;

    return (cardColor: bgColor, textColor: textColor);
  }

  ({Color cardColor, Color textColor}) getColorsForItem(
    String id,
    ColorScheme colorScheme,
  ) {
    return _cardColors[id] ??= _generateColor(id, colorScheme);
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

  void _forceGenerateJson() {
    final list = controller.exportLayout();
    jsonController.text = const JsonEncoder.withIndent('  ').convert(list);
    showMinimap.value = false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'JSON Schema generated successfully for ${list.length} items!',
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  void _importJson() {
    try {
      final decoded = jsonDecode(jsonController.text);
      if (decoded is List) {
        controller.importLayout(decoded);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Layout imported successfully!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid JSON: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
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
          id: 's_${timestamp}_$i',
          x: -1,
          y: -1,
          w: random.nextInt(2) + 1,
          h: random.nextInt(2) + 1,
        ),
      );
    }
    controller.addItems(list, strategy: placementStrategy.value);
  }

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
    animateReflow.dispose();
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
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 950;

    final configPanel = _ConfigPanel(
      controller: controller,
      jsonController: jsonController,
      isEditing: isEditing,
      showMinimap: showMinimap,
      useSliverDemo: useSliverDemo,
      useDragHandlesOnly: useDragHandlesOnly,
      blockSectionCollision: blockSectionCollision,
      animateReflow: animateReflow,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: useSliverDemo,
              builder: (context, sliverMode, _) {
                return sliverMode
                    ? _buildSliverDemoView()
                    : _buildStandardDemoView();
              },
            ),
          ),
          if (isDesktop)
            Container(
              width: 320,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
              ),
              child: Material(
                color: theme.colorScheme.surfaceContainerLow,
                child: configPanel,
              ),
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

  Widget _buildCard(BuildContext context, LayoutItem item) {
    final theme = Theme.of(context);
    final colors = getColorsForItem(item.id, theme.colorScheme);

    return _DashboardCard(
      key: ValueKey(item.id),
      item: item,
      isEditing: isEditing.value,
      useDragHandlesOnly: useDragHandlesOnly.value,
      cardColor: colors.cardColor,
      textColor: colors.textColor,
      theme: theme,
      onDelete: () => _confirmAndDelete(item),
    );
  }

  Widget _buildStandardDemoView() {
    final theme = Theme.of(context);
    return ValueListenableBuilder3(
      useDragHandlesOnly,
      showMinimap,
      animateReflow,
      builder: (context, handlesOnly, minimap, reflow, _) {
        return Stack(
          children: [
            Dashboard<String>(
              controller: controller,
              scrollController: standardScrollController,
              scrollDirection: controller.scrollDirection.value,
              animateReflow: reflow,
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
                fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.03),
                handleColor: theme.colorScheme.primary,
                lineColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                lineWidth: 1,
              ),
              itemStyle: DashboardItemStyle(
                focusColor: theme.colorScheme.primary,
                activeColor: theme.colorScheme.secondary,
                borderRadius: BorderRadius.circular(12),
                // Match your card's border radius
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
    final theme = Theme.of(context);
    return ValueListenableBuilder3(
      useDragHandlesOnly,
      showMinimap,
      animateReflow,
      builder: (context, handlesOnly, minimap, reflow, _) {
        return Stack(
          children: [
            DashboardOverlay<String>(
              controller: controller,
              scrollController: sliverScrollController,
              dragStartGesture: handlesOnly
                  ? DragStartGesture.none
                  : DragStartGesture.longPress,
              gridStyle: GridStyle(
                fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.03),
                handleColor: theme.colorScheme.primary,
                lineColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                lineWidth: 1,
              ),
              padding: const EdgeInsets.all(8.0),
              fillViewport: true,
              itemBuilder: _buildCard,
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
                    automaticallyImplyLeading: false,
                    pinned: true,
                    expandedHeight: 120,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    flexibleSpace: FlexibleSpaceBar(
                      title: Text(
                        'Sliver direct composition',
                        style: TextStyle(color: theme.colorScheme.onSurface),
                      ),
                      centerTitle: false,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.all(8.0),
                    sliver: SliverDashboard(
                      animateReflow: reflow,
                      itemBuilder: _buildCard,
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(
                            '$index',
                            style: TextStyle(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
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

  Widget _buildTrashBin(
    BuildContext context,
    bool hovered,
    bool active,
    String? activeItemId,
  ) {
    final theme = Theme.of(context);
    final activeBg = active
        ? theme.colorScheme.error
        : (hovered
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.onErrorContainer);
    final activeFg = active
        ? theme.colorScheme.onError
        : (hovered
              ? theme.colorScheme.onErrorContainer
              : theme.colorScheme.error);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 60,
        margin: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          color: activeBg,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black54)],
          border: hovered
              ? Border.all(color: theme.colorScheme.onError, width: 2)
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? Icons.delete_forever : Icons.delete, color: activeFg),
            const SizedBox(width: 10),
            Text(
              active ? 'Release to Delete!' : 'Drop here to Delete',
              style: TextStyle(color: activeFg, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMinimapOverlay() {
    final theme = Theme.of(context);
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
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DashboardMinimap(
                controller: controller,
                scrollController: activeScrollController,
                width: 120,
                // Must mirror the dashboard's layout config: the minimap has
                // no other way to know the real spacing/aspect/padding, and
                // defaults (0 spacing) skew the item proportions.
                slotAspectRatio: 1.0,
                mainAxisSpacing: 8.0,
                crossAxisSpacing: 8.0,
                padding: const EdgeInsets.all(8.0),
                style: MinimapStyle(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.8),
                  itemColor: theme.colorScheme.primary,
                  staticItemColor: theme.colorScheme.outline,
                  viewportColor: theme.colorScheme.primary.withValues(
                    alpha: 0.2,
                  ),
                ),
                markers: const [
                  MinimapMarker(
                    itemId: 'sec_sys',
                    color: Colors.red,
                    size: 10,
                    shape: MinimapMarkerShape.circle,
                    alignment: Alignment.centerRight,
                  ),
                  MinimapMarker(
                    itemId: 'sec_usr',
                    color: Colors.amber,
                    size: 12,
                    shape: MinimapMarkerShape.triangle,
                    alignment: Alignment.centerLeft,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Utility builder combining three ValueListenables inside standard build context trees.
class ValueListenableBuilder3<A, B, C> extends StatelessWidget {
  const ValueListenableBuilder3(
    this.first,
    this.second,
    this.third, {
    required this.builder,
    super.key,
  });

  final ValueListenable<A> first;
  final ValueListenable<B> second;
  final ValueListenable<C> third;
  final Widget Function(BuildContext context, A a, B b, C c, Widget? child)
  builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<A>(
      valueListenable: first,
      builder: (context, a, _) {
        return ValueListenableBuilder<B>(
          valueListenable: second,
          builder: (context, b, _) {
            return ValueListenableBuilder<C>(
              valueListenable: third,
              builder: (context, c, _) {
                return builder(context, a, b, c, null);
              },
            );
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
    required this.animateReflow,
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
  final ValueNotifier<bool> animateReflow;
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
              color: theme.colorScheme.primary,
            ),
          ),
          const Divider(),
          const _SectionTitle('Visual Modes & Structures'),
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
          const _SectionTitle('Collision & Layout Rules'),
          _SwitchTile(
            title: 'Block Section Header Collisions',
            notifier: blockSectionCollision,
          ),
          _SwitchTile(
            title: 'Auto-Shrink neighbors on Drag',
            notifier: autoShrink,
            onChanged: (val) => controller.setAllowAutoShrink(allow: val),
          ),
          _SwitchTile(
            title: 'Enable Reflow Animations',
            notifier: animateReflow,
          ),
          const SizedBox(height: 10),
          Text(
            'Compaction Type',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          ValueListenableBuilder(
            valueListenable: compactionType,
            builder: (context, value, _) {
              return DropdownButton<CompactType>(
                isExpanded: true,
                dropdownColor: theme.colorScheme.surfaceContainerHigh,
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
          Text(
            'Resize Behavior',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          ValueListenableBuilder<ResizeBehavior>(
            valueListenable: resizeBehavior,
            builder: (context, value, _) {
              return DropdownButton<ResizeBehavior>(
                isExpanded: true,
                dropdownColor: theme.colorScheme.surfaceContainerHigh,
                value: value,
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
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            'Auto-placement Strategy',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          ValueListenableBuilder(
            valueListenable: placementStrategy,
            builder: (context, value, _) {
              return DropdownButton<AutoPlacementStrategy>(
                isExpanded: true,
                dropdownColor: theme.colorScheme.surfaceContainerHigh,
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
          const _SectionTitle('Stress Tests & Bulk actions'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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
          const _SectionTitle('JSON Schema Import/Export'),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: theme.colorScheme.onSurfaceVariant,
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

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.item,
    required this.isEditing,
    required this.useDragHandlesOnly,
    required this.cardColor,
    required this.textColor,
    required this.theme,
    required this.onDelete,
    super.key,
  });

  final LayoutItem item;
  final bool isEditing;
  final bool useDragHandlesOnly;
  final Color cardColor;
  final Color textColor;
  final ThemeData theme;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      color: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      clipBehavior: Clip.none,
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.id.startsWith('s_')
                      ? 'Item ${item.id.substring(2)}'
                      : item.id,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '(${item.w}x${item.h})',
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          if (isEditing && useDragHandlesOnly)
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
          if (isEditing)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
