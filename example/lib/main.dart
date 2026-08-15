import 'dart:async';
import 'dart:convert';
import 'dart:math';

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
                'Single grid: drag, resize, custom columns (up to 60+), slot tap, maxRows, extra metadata…',
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
  var initialSlots = 8;

  late final DashboardController controller;

  final standardScrollController = ScrollController();
  final sliverScrollController = ScrollController();
  final jsonController = TextEditingController();

  final showGenerateButton = ValueNotifier<bool>(false);
  final confirmHistory = ValueNotifier<bool>(false);
  final isEditing = ValueNotifier(false);
  final showMinimap = ValueNotifier(true);
  final enableImpactPreview = ValueNotifier<bool>(true);
  final useSliverDemo = ValueNotifier(false);
  final useDragHandlesOnly = ValueNotifier(false);
  final blockSectionCollision = ValueNotifier(true);
  final animateReflow = ValueNotifier(false);
  final autoShrink = ValueNotifier(false);
  final maxRows = ValueNotifier<int?>(null);
  final enableSlotTapToAdd = ValueNotifier<bool>(false);
  final enableAltDragClone = ValueNotifier<bool>(true);
  final enableLassoGuidance = ValueNotifier<bool>(true);
  final lassoMode = ValueNotifier<LassoSelectionMode>(
    LassoSelectionMode.emptySpace,
  );
  final dragMode = ValueNotifier<DragMode>(DragMode.cascade);

  // null = Use Responsive Breakpoints. Non-null = Override with custom fixed slot count.
  final customSlotCount = ValueNotifier<int?>(null);

  final compactionType = ValueNotifier<CompactType>(CompactType.vertical);
  final resizeBehavior = ValueNotifier<ResizeBehavior>(ResizeBehavior.push);
  final placementStrategy = ValueNotifier<AutoPlacementStrategy>(
    AutoPlacementStrategy.firstFit,
  );

  final random = Random();

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
      initialSlotCount: initialSlots,
      onLayoutChanged: (items, bkSlotCount) {
        _syncJsonField();
      },
      onUndo: (items, _) => _showHistoryToast('Undo — ${items.length} items'),
      onRedo: (items, _) => _showHistoryToast('Redo — ${items.length} items'),
      onWillUndo: (candidate) => _confirmHistoryOperation('Undo', candidate),
      onWillRedo: (candidate) => _confirmHistoryOperation('Redo', candidate),
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
          extra: {'category': 'CPU', 'tag': 'Hardware'},
        ),
        const LayoutItem(
          id: 'sys_mem',
          x: 2,
          y: 1,
          w: 2,
          h: 2,
          extra: {'category': 'RAM', 'tag': 'Hardware'},
        ),
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
          extra: {'category': 'Sales', 'tag': 'Analytics'},
        ),
        const LayoutItem(
          id: 'chart_geo',
          x: 4,
          y: 4,
          w: 2,
          h: 2,
          extra: {'category': 'Map', 'tag': 'Analytics'},
        ),
        const LayoutItem(
          id: 'table_logs',
          x: 6,
          y: 4,
          w: 2,
          h: 3,
          extra: {'category': 'Logs', 'tag': 'System'},
        ),
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
      cloneKeys: [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.controlRight,
      ],
      multiSelectKeys: [
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.shiftRight,
      ],
    );

    blockSectionCollision.addListener(_updatePolicy);
  }

  void _showHistoryToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
      );
  }

  /// The `onWillUndo` / `onWillRedo` veto hook.
  ///
  /// Returning `false` cancels the operation entirely: the layout, the history
  /// cursor and the `canUndo` / `canRedo` beacons are all left untouched.
  Future<bool> _confirmHistoryOperation(
    String action,
    List<LayoutItem> candidate,
  ) async {
    if (!confirmHistory.value) return true;
    if (!mounted) return false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action layout change?'),
        content: Text(
          'The layout will be restored to a state with '
          '${candidate.length} items.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return approved ?? false;
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
    final activeCols = controller.slotCount.value;
    // Adapt default new item size for fine grids (e.g. 48 or 60 cols)
    final scale = max(1, activeCols ~/ 8);
    final w = (random.nextInt(2) + 1) * scale;
    final h = (random.nextInt(2) + 1) * scale;

    final newItem = LayoutItem(
      id: 'widget_${DateTime.now().millisecondsSinceEpoch % 10000}',
      x: -1,
      y: -1,
      w: w,
      h: h,
      extra: const {'category': 'Dynamic', 'created': 'FAB'},
    );
    controller.addItem(newItem, strategy: placementStrategy.value);
  }

  void _addStressTestItems(int count) {
    final list = <LayoutItem>[];
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final activeCols = controller.slotCount.value;
    final scale = max(1, activeCols ~/ 8);

    for (var i = 0; i < count; i++) {
      list.add(
        LayoutItem(
          id: 's_${timestamp}_$i',
          x: -1,
          y: -1,
          w: (random.nextInt(2) + 1) * scale,
          h: (random.nextInt(2) + 1) * scale,
          extra: const {'category': 'StressTest'},
        ),
      );
    }
    controller.addItems(list, strategy: placementStrategy.value);
  }

  void _handleSlotTap(int x, int y) {
    final activeCols = controller.slotCount.value;
    final scale = max(1, activeCols ~/ 8);
    final w = 2 * scale;
    final h = 2 * scale;
    final targetX = min(x, max(0, activeCols - w));

    controller.addItem(
      LayoutItem(
        id: 'tap_${targetX}_$y',
        x: targetX,
        y: y,
        w: w,
        h: h,
        extra: {'category': 'Created', 'createdVia': 'Slot Tap ($x,$y)'},
      ),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added new ${w}x$h item at slot ($targetX, $y)'),
          duration: const Duration(seconds: 2),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  void _handleSlotLongPress(int x, int y) {
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Long-pressed empty slot at Column $x, Row $y'),
          duration: const Duration(seconds: 2),
          backgroundColor: Theme.of(context).colorScheme.tertiary,
        ),
      );
    }
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
    confirmHistory.dispose();
    isEditing.dispose();
    showMinimap.dispose();
    enableImpactPreview.dispose();
    useSliverDemo.dispose();
    useDragHandlesOnly.dispose();
    blockSectionCollision.dispose();
    animateReflow.dispose();
    autoShrink.dispose();
    maxRows.dispose();
    enableSlotTapToAdd.dispose();
    enableAltDragClone.dispose();
    customSlotCount.dispose();
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
      enableImpactPreview: enableImpactPreview,
      useSliverDemo: useSliverDemo,
      useDragHandlesOnly: useDragHandlesOnly,
      blockSectionCollision: blockSectionCollision,
      animateReflow: animateReflow,
      autoShrink: autoShrink,
      maxRows: maxRows,
      enableSlotTapToAdd: enableSlotTapToAdd,
      enableAltDragClone: enableAltDragClone,
      enableLassoGuidance: enableLassoGuidance,
      lassoMode: lassoMode,
      dragMode: dragMode,
      customSlotCount: customSlotCount,
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
          Builder(
            builder: (context) {
              return IconButton(
                icon: const Icon(Icons.undo),
                tooltip: 'Undo layout change',
                onPressed: controller.canUndo.watch(context)
                    ? () => unawaited(controller.undo())
                    : null,
              );
            },
          ),
          Builder(
            builder: (context) {
              return IconButton(
                icon: const Icon(Icons.redo),
                tooltip: 'Redo layout change',
                onPressed: controller.canRedo.watch(context)
                    ? () => unawaited(controller.redo())
                    : null,
              );
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: confirmHistory,
            builder: (context, confirm, _) {
              return IconButton(
                icon: Icon(confirm ? Icons.gpp_good : Icons.gpp_maybe_outlined),
                tooltip: confirm
                    ? 'Undo/redo confirmation ON (onWillUndo veto)'
                    : 'Undo/redo confirmation OFF',
                onPressed: () => confirmHistory.value = !confirm,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history_toggle_off),
            tooltip: 'Clear history',
            onPressed: () {
              controller.clearHistory();
              _showHistoryToast('History cleared');
            },
          ),
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
            child: ListenableBuilder(
              listenable: Listenable.merge([useSliverDemo, customSlotCount]),
              builder: (context, _) {
                return useSliverDemo.value
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

  /// Business hook for `Alt` / `Option` + drag duplication.
  ///
  /// The package never invents an id: it hands us the source tile and the
  /// grid it lives on, and we decide what a duplicate means. Returning null
  /// refuses the duplication — the gesture then degrades to a plain move.
  LayoutItem? _handleCloneRequested(
    LayoutItem source,
    DashboardController grid,
  ) {
    // Section barriers are structure, not content: never duplicate them.
    if (source.isSectionBarrier) return null;

    _cloneCounter++;
    return source.copyWith(
      id: '${source.id}_copy_$_cloneCounter',
      extra: {...?source.extra, 'clonedFrom': source.id},
    );
  }

  int _cloneCounter = 0;

  /// Grid style shared by both demos.
  GridStyle _buildGridStyle(ThemeData theme) {
    return GridStyle(
      fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.03),
      handleColor: theme.colorScheme.primary,
      lineColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
      lineWidth: 1,
    );
  }

  /// Pushes the rubberband ("lasso") configuration onto the controller.
  ///
  /// It lives there — next to `shortcuts` and `guidance` — rather than on
  /// the widget, because it is interaction policy rather than grid painting.
  void _syncLassoStyle(ThemeData theme) {
    controller
      ..lassoStyle = LassoStyle(
        mode: lassoMode.value,
        fillColor: theme.colorScheme.primary.withValues(alpha: 0.18),
        borderColor: theme.colorScheme.primary,
        borderWidth: 1.5,
      )
      // Guidance drives the lasso cursor (precise, over empty space) and the
      // label drawn beside the rectangle. Screen-reader announcements fire
      // either way.
      ..guidance = enableLassoGuidance.value
          ? DashboardGuidance.byDefault
          : null;
  }

  Widget _buildCard(BuildContext context, LayoutItem item) {
    final theme = Theme.of(context);
    final colorId = (item.extra?['clonedFrom'] as String?) ?? item.id;
    final colors = getColorsForItem(colorId, theme.colorScheme);

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
    return ListenableBuilder(
      listenable: Listenable.merge([
        customSlotCount,
        enableSlotTapToAdd,
        enableAltDragClone,
        enableImpactPreview,
        useDragHandlesOnly,
        showMinimap,
        animateReflow,
        enableLassoGuidance,
        lassoMode,
      ]),
      builder: (context, _) {
        final overrideSlots = customSlotCount.value;
        final slotTapEnabled = enableSlotTapToAdd.value;
        final cloneEnabled = enableAltDragClone.value;
        final impactPreviewEnabled = enableImpactPreview.value;
        final handlesOnly = useDragHandlesOnly.value;
        final minimap = showMinimap.value;
        final reflow = animateReflow.value;

        _syncLassoStyle(theme);

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
              onSlotTap: slotTapEnabled ? _handleSlotTap : null,
              onSlotLongPress: _handleSlotLongPress,
              // Hold Alt / Option and drag a tile: the copy follows the
              // cursor, the original stays put. Registering the callback
              // is what turns the feature on.
              onCloneRequested: cloneEnabled ? _handleCloneRequested : null,
              dragStartGesture: handlesOnly
                  ? DragStartGesture.none
                  : DragStartGesture.longPress,
              // Use responsive breakpoints when overrideSlots is null,
              // otherwise null disables responsive breakpoints to respect manual slotCount
              breakpoints: overrideSlots != null
                  ? null
                  : {0: 4, 600: 6, 900: 8},
              itemBuilder: _buildCard,
              onWillDelete: _confirmDeletion,
              gridStyle: _buildGridStyle(theme),
              itemStyle: DashboardItemStyle(
                focusColor: theme.colorScheme.primary,
                activeColor: theme.colorScheme.secondary,
                borderRadius: BorderRadius.circular(12),
                displacedDecoration: impactPreviewEnabled
                    ? BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.tertiary,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
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
    return ListenableBuilder(
      listenable: Listenable.merge([
        enableSlotTapToAdd,
        enableAltDragClone,
        enableImpactPreview,
        useDragHandlesOnly,
        enableImpactPreview,
        animateReflow,
        enableLassoGuidance,
        lassoMode,
      ]),
      builder: (context, _) {
        final slotTapEnabled = enableSlotTapToAdd.value;
        final cloneEnabled = enableAltDragClone.value;
        final handlesOnly = useDragHandlesOnly.value;
        final minimap = showMinimap.value;
        final reflow = animateReflow.value;
        final impactPreviewEnabled = enableImpactPreview.value;
        final overrideSlots = customSlotCount.value;

        _syncLassoStyle(theme);

        return Stack(
          children: [
            DashboardOverlay<String>(
              controller: controller,
              scrollController: sliverScrollController,
              dragStartGesture: handlesOnly
                  ? DragStartGesture.none
                  : DragStartGesture.longPress,
              onSlotTap: slotTapEnabled ? _handleSlotTap : null,
              onSlotLongPress: _handleSlotLongPress,
              // Same feature, wired on the raw overlay instead of the
              // high-level Dashboard widget.
              onCloneRequested: cloneEnabled ? _handleCloneRequested : null,
              gridStyle: _buildGridStyle(theme),
              itemStyle: DashboardItemStyle(
                focusColor: theme.colorScheme.primary,
                activeColor: theme.colorScheme.secondary,
                borderRadius: BorderRadius.circular(12),
                displacedDecoration: impactPreviewEnabled
                    ? BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.tertiary,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
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
                      breakpoints: overrideSlots != null
                          ? null
                          : {0: 4, 600: 6, 900: 8},
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
    return ListenableBuilder(
      listenable: Listenable.merge([useSliverDemo, enableImpactPreview]),
      builder: (context, _) {
        final sliverMode = useSliverDemo.value;
        final impactPreviewEnabled = enableImpactPreview.value;
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
                slotAspectRatio: 1.0,
                mainAxisSpacing: 8.0,
                crossAxisSpacing: 8.0,
                padding: const EdgeInsets.all(8.0),
                style: MinimapStyle(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.8),
                  itemColor: theme.colorScheme.primary,
                  staticItemColor: theme.colorScheme.outline,
                  displacedItemColor: impactPreviewEnabled
                      ? theme.colorScheme.tertiary
                      : null,
                  viewportColor: theme.colorScheme.primary.withValues(
                    alpha: 0.2,
                  ),
                ),
                onItemTap: (item) => controller.scrollToItem(item.id),
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

class _ConfigPanel extends StatelessWidget {
  const _ConfigPanel({
    required this.controller,
    required this.jsonController,
    required this.isEditing,
    required this.showMinimap,
    required this.enableImpactPreview,
    required this.useSliverDemo,
    required this.useDragHandlesOnly,
    required this.blockSectionCollision,
    required this.animateReflow,
    required this.autoShrink,
    required this.maxRows,
    required this.enableSlotTapToAdd,
    required this.enableAltDragClone,
    required this.enableLassoGuidance,
    required this.lassoMode,
    required this.dragMode,
    required this.customSlotCount,
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
  final ValueNotifier<bool> enableImpactPreview;
  final ValueNotifier<bool> useSliverDemo;
  final ValueNotifier<bool> useDragHandlesOnly;
  final ValueNotifier<bool> blockSectionCollision;
  final ValueNotifier<bool> animateReflow;
  final ValueNotifier<bool> autoShrink;
  final ValueNotifier<bool> enableSlotTapToAdd;
  final ValueNotifier<bool> enableAltDragClone;
  final ValueNotifier<bool> enableLassoGuidance;
  final ValueNotifier<LassoSelectionMode> lassoMode;
  final ValueNotifier<DragMode> dragMode;
  final ValueNotifier<int?> maxRows;
  final ValueNotifier<int?> customSlotCount;
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
          SizedBox(
            width: double.infinity,
            child: Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '💡 Keyboard Shortcuts:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• Shift + Click: Multi-select tiles\n'
                      '• Shift + Drag a tile: toggle Swap / Cascade\n'
                      '• Drag on empty space: Lasso selection\n'
                      '• Shift + Lasso: Add to the current selection\n'
                      '• Ctrl + Drag: Duplicate tile\n'
                      '• Space / Arrows: A11y keyboard moves',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const _SectionTitle('Visual Modes & Structures'),
          _SwitchTile(
            title: 'Edit Mode (Draggable/Resizable)',
            notifier: isEditing,
            onChanged: (val) => controller.setEditMode(val),
          ),
          _SwitchTile(
            title: 'Tap empty slot to add item (onSlotTap)',
            notifier: enableSlotTapToAdd,
          ),
          _SwitchTile(
            title: 'Ctrl + drag duplicates a tile (onCloneRequested)',
            notifier: enableAltDragClone,
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
          _SwitchTile(
            title: 'Highlight displaced tiles on drag (Impact Preview)',
            notifier: enableImpactPreview,
          ),
          _SwitchTile(
            title: 'Lasso cursor & tooltip (guidance)',
            notifier: enableLassoGuidance,
          ),
          const SizedBox(height: 10),
          Text(
            'Drag Mode (Shift toggles the opposite)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<DragMode>(
            valueListenable: dragMode,
            builder: (context, value, _) {
              return DropdownButton<DragMode>(
                isExpanded: true,
                dropdownColor: theme.colorScheme.surfaceContainerHigh,
                value: value,
                items: const [
                  DropdownMenuItem(
                    value: DragMode.cascade,
                    child: Text('CASCADE — PUSH NEIGHBOURS (DEFAULT)'),
                  ),
                  DropdownMenuItem(
                    value: DragMode.swap,
                    child: Text('SWAP — EXCHANGE POSITIONS'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  dragMode.value = v;
                  controller.setDragMode(v);
                },
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            'Lasso Selection Trigger (desktop / web)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<LassoSelectionMode>(
            valueListenable: lassoMode,
            builder: (context, value, _) {
              return DropdownButton<LassoSelectionMode>(
                isExpanded: true,
                dropdownColor: theme.colorScheme.surfaceContainerHigh,
                value: value,
                items: const [
                  DropdownMenuItem(
                    value: LassoSelectionMode.emptySpace,
                    child: Text('EMPTY SPACE DRAG (DEFAULT)'),
                  ),
                  DropdownMenuItem(
                    value: LassoSelectionMode.modifierRequired,
                    child: Text('SHIFT + EMPTY SPACE DRAG'),
                  ),
                  DropdownMenuItem(
                    value: LassoSelectionMode.disabled,
                    child: Text('DISABLED'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) lassoMode.value = v;
                },
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            'Grid Granularity / Columns (slotCount)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<int?>(
            valueListenable: customSlotCount,
            builder: (context, value, _) {
              return DropdownButton<int?>(
                isExpanded: true,
                dropdownColor: theme.colorScheme.surfaceContainerHigh,
                value: value,
                items: const [
                  DropdownMenuItem(
                    value: null,
                    child: Text('RESPONSIVE BREAKPOINTS (AUTO)'),
                  ),
                  DropdownMenuItem(value: 4, child: Text('4 COLUMNS (COARSE)')),
                  DropdownMenuItem(
                    value: 8,
                    child: Text('8 COLUMNS (STANDARD)'),
                  ),
                  DropdownMenuItem(
                    value: 12,
                    child: Text('12 COLUMNS (GRID SYSTEM)'),
                  ),
                  DropdownMenuItem(
                    value: 16,
                    child: Text('16 COLUMNS (DENSE)'),
                  ),
                  DropdownMenuItem(value: 24, child: Text('24 COLUMNS (FINE)')),
                  DropdownMenuItem(
                    value: 32,
                    child: Text('32 COLUMNS (HIGH GRANULARITY)'),
                  ),
                  DropdownMenuItem(
                    value: 48,
                    child: Text('48 COLUMNS (ULTRA-FINE)'),
                  ),
                  DropdownMenuItem(
                    value: 60,
                    child: Text('60 COLUMNS (MICRO-GRID)'),
                  ),
                ],
                onChanged: (v) {
                  customSlotCount.value = v;
                  if (v != null) {
                    controller.setSlotCount(v);
                  }
                },
              );
            },
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
            'Max Rows Limit (Main Axis Cap)',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          ValueListenableBuilder<int?>(
            valueListenable: maxRows,
            builder: (context, value, _) {
              return DropdownButton<int?>(
                isExpanded: true,
                dropdownColor: theme.colorScheme.surfaceContainerHigh,
                value: value,
                items: const [
                  DropdownMenuItem(
                    value: null,
                    child: Text('UNLIMITED (DEFAULT)'),
                  ),
                  DropdownMenuItem(value: 6, child: Text('6 ROWS MAX')),
                  DropdownMenuItem(value: 8, child: Text('8 ROWS MAX')),
                  DropdownMenuItem(value: 12, child: Text('12 ROWS MAX')),
                ],
                onChanged: (v) {
                  maxRows.value = v;
                  controller.setMaxRows(v);
                },
              );
            },
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
    final category = item.extra?['category'] as String?;

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
                if (category != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: textColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      category.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
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
