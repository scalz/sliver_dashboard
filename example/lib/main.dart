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
      title: 'Sliver Dashboard Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Initial slot count for the controller.
  // The Dashboard widget will update this automatically based on breakpoints.
  var slotCount = 8;

  // Create and manage your DashboardController.
  late final DashboardController controller;

  final scrollController = ScrollController();

  final editMode = ValueNotifier(false);
  final compactionType = ValueNotifier<CompactType>(CompactType.vertical);
  final showMap = ValueNotifier(false);
  var scrollDirection = Axis.vertical;
  var resizeBehavior = ResizeBehavior.push;
  final cardColors = <String, Color>{};
  final random = Random();

  bool get isMobile {
    if (kIsWeb) {
      return defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Color getColorForItem(String id) {
    return cardColors.putIfAbsent(id, () {
      return Color.fromRGBO(
        random.nextInt(256),
        random.nextInt(256),
        random.nextInt(256),
        1,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    // Create and manage your DashboardController.
    controller = DashboardController(
      initialSlotCount: slotCount,
      onLayoutChanged: (items, bkSlotCount) {
        debugPrint(
          'Layout changed! Saving ${items.length} items to persistence for bkSlotCount=$bkSlotCount...',
        );
        // In a real app, you would save the layout to a DB or SharedPreferences.
        // You can get a JSON-ready list of maps using:
        // final json = controller.exportLayout();
        // myStorage.save(json);
      },
      onInteractionStart: (item) {
        // Do something, eg. haptic feedback..
        debugPrint('Interaction started on ${item.id}');
      },
      initialLayout: [
        // Row 1
        const LayoutItem(
          id: '9',
          x: 0,
          y: 0,
          w: 2,
          h: 2,
          isDraggable: true,
          isResizable: true,
          isStatic: false,
        ),
        const LayoutItem(id: '12', x: 2, y: 4, w: 2, h: 2),
        const LayoutItem(id: '7', x: 4, y: 0, w: 2, h: 2),
        const LayoutItem(id: '1', x: 6, y: 0, w: 2, h: 1),

        // Row 2
        const LayoutItem(id: '13', x: 6, y: 1, w: 2, h: 1),

        // Row 3
        const LayoutItem(id: '15', x: 0, y: 2, w: 2, h: 2),
        const LayoutItem(id: '0', x: 2, y: 2, w: 2, h: 1),
        const LayoutItem(id: '2', x: 4, y: 2, w: 2, h: 3),
        const LayoutItem(id: '14', x: 6, y: 2, w: 2, h: 2),

        // Row 4
        const LayoutItem(id: '6', x: 2, y: 3, w: 2, h: 1),

        // Row 5
        const LayoutItem(id: '24', x: 0, y: 4, w: 2, h: 2),
        const LayoutItem(id: '18', x: 2, y: 4, w: 2, h: 2),
        const LayoutItem(id: '21', x: 6, y: 4, w: 2, h: 2),

        // Row 6 (Static and others at the bottom)
        const LayoutItem(id: '19', x: 4, y: 5, w: 2, h: 2, isStatic: true),
        const LayoutItem(id: '20', x: 6, y: 6, w: 2, h: 2),
        const LayoutItem(id: '3', x: 4, y: 7, w: 2, h: 1),
      ],
    );

    controller.shortcuts = DashboardShortcuts(
      moveUp: {const SingleActivator(LogicalKeyboardKey.keyW)},
      moveLeft: {const SingleActivator(LogicalKeyboardKey.keyA)},
      moveDown: {const SingleActivator(LogicalKeyboardKey.keyS)},
      moveRight: {const SingleActivator(LogicalKeyboardKey.keyD)},
      grab: DashboardShortcuts.defaultShortcuts.grab,
      drop: DashboardShortcuts.defaultShortcuts.drop,
      cancel: DashboardShortcuts.defaultShortcuts.cancel,
    );
  }

  @override
  void dispose() {
    editMode.dispose();
    showMap.value = false;
    compactionType.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sliver Dashboard Example'),
        actions: [
          ValueListenableBuilder(
            valueListenable: showMap,
            builder: (context, value, _) {
              return IconButton(
                tooltip: 'Show Map',
                icon: Icon(
                  Icons.map,
                  color: value ? theme.colorScheme.primary : null,
                ),
                onPressed: () => showMap.value = !showMap.value,
              );
            },
          ),
          IconButton(
            tooltip: 'Optimize Layout',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => controller.optimizeLayout(),
          ),
          // Add a button to toggle edit mode.
          ValueListenableBuilder(
            valueListenable: editMode,
            builder: (context, value, _) {
              return IconButton(
                tooltip: 'Toggle Edit Mode',
                icon: Icon(value ? Icons.check : Icons.edit),
                onPressed: () {
                  editMode.value = !editMode.value;
                  controller.setEditMode(editMode.value);
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Wrap(
            direction: Axis.horizontal,
            alignment: WrapAlignment.center,
            runSpacing: 0,
            spacing: 8,
            children: [
              ValueListenableBuilder(
                valueListenable: compactionType,
                builder: (context, _, _) {
                  return SegmentedButton<CompactType>(
                    selected: {compactionType.value},
                    onSelectionChanged: (value) {
                      compactionType.value = value.first;
                      controller.setCompactionType(value.first);
                    },
                    segments: [
                      const ButtonSegment(
                        label: Text('None'),
                        value: CompactType.none,
                      ),
                      ButtonSegment(
                        label: Text('Compact ${CompactType.vertical.name}'),
                        value: CompactType.vertical,
                      ),
                      ButtonSegment(
                        label: Text('Compact ${CompactType.horizontal.name}'),
                        value: CompactType.horizontal,
                      ),
                    ],
                  );
                },
              ),
              SegmentedButton<Axis>(
                selected: {scrollDirection},
                onSelectionChanged: (value) => setState(() {
                  scrollDirection = value.firstOrNull == Axis.horizontal
                      ? Axis.horizontal
                      : Axis.vertical;
                }),
                segments: [
                  ButtonSegment(
                    label: Text('Scroll ${Axis.vertical.name}'),
                    value: Axis.vertical,
                  ),
                  ButtonSegment(
                    label: Text('Scroll ${Axis.horizontal.name}'),
                    value: Axis.horizontal,
                  ),
                ],
              ),
              SegmentedButton<ResizeBehavior>(
                selected: {resizeBehavior},
                onSelectionChanged: (value) => setState(() {
                  resizeBehavior = value.firstOrNull == ResizeBehavior.shrink
                      ? ResizeBehavior.shrink
                      : ResizeBehavior.push;
                }),
                segments: const [
                  ButtonSegment(
                    label: Text('Resize Push'),
                    value: ResizeBehavior.push,
                  ),
                  ButtonSegment(
                    label: Text('Resize Shrink'),
                    value: ResizeBehavior.shrink,
                  ),
                ],
              ),
            ],
          ),
          const Divider(),
          RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium,
              children: [
                if (!isMobile)
                  const TextSpan(
                    text: 'Keyboard navigation: ',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                if (!isMobile)
                  const TextSpan(
                    text: 'Tab, Space to start/stop moving, Arrows.\n',
                    style: TextStyle(fontWeight: FontWeight.normal),
                  ),
                const TextSpan(
                  text: 'Multi-select: ',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                TextSpan(
                  text: !isMobile
                      ? 'Select and move multiple items at once using Shift + Click (Single tap on mobile).'
                      : 'Single tap to select and move multiple items at once.',
                  style: const TextStyle(fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
          const Divider(),
          // Add some external draggables to demonstrate dropping new items.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Drag to add:'),
                Draggable<String>(
                  data: 'New Chart',
                  feedback: SizedBox(
                    width: 100,
                    height: 50,
                    child: Card(
                      elevation: 8,
                      child: Center(child: Icon(Icons.bar_chart)),
                    ),
                  ),
                  child: Chip(
                    label: Text('Chart'),
                    avatar: Icon(Icons.bar_chart),
                  ),
                ),
                Draggable<String>(
                  data: 'New Table',
                  feedback: SizedBox(
                    width: 100,
                    height: 50,
                    child: Card(
                      elevation: 8,
                      child: Center(child: Icon(Icons.table_rows)),
                    ),
                  ),
                  child: Chip(
                    label: Text('Table'),
                    avatar: Icon(Icons.table_rows),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            // Build the Dashboard widget.
            child: Stack(
              children: [
                Dashboard<String>(
                  controller: controller,
                  trashHoverDelay: const Duration(seconds: 1),
                  scrollDirection: scrollDirection,
                  scrollController: scrollController,
                  // ResizeBehavior.push or ResizeBehavior.shrink
                  resizeBehavior: resizeBehavior,
                  showScrollbar: true,
                  slotAspectRatio: 1.0,
                  // Responsive breakpoints:
                  breakpoints: {
                    0: 4, // Mobile: 4 cols
                    600: 8, // Tablet: 8 cols
                    1200: 12, // Desktop: 12 cols
                  },
                  // The size of the touch target
                  resizeHandleSide: 20, // default 20.0
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  mainAxisSpacing: 8.0, // default 8.0
                  crossAxisSpacing: 8.0, // default 8.0
                  // how many non visible pixels to preload on top and bottom
                  cacheExtent: 500,
                  guidance: DashboardGuidance
                      .byDefault, // default null for no guidance
                  // guidance: const DashboardGuidance(
                  //   move: InteractionGuidance(
                  //     SystemMouseCursors.grab,
                  //     'Click and drag to move item',
                  //   ),
                  // ),
                  gridStyle: GridStyle(
                    fillColor: Colors.black.withValues(alpha: 0.5),
                    handleColor: Colors.red.withValues(alpha: 0.5),
                    lineColor: Colors.black26.withValues(alpha: 0.5),
                    lineWidth: 1,
                  ),
                  // Custom Feedback Builder
                  itemFeedbackBuilder: (context, item, child) {
                    return Opacity(
                      opacity: 0.7,
                      child: Material(
                        elevation: 8,
                        shadowColor: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.transparent,
                        child: child,
                      ),
                    );
                  },
                  // Handle drops from external sources.
                  onDrop: (data, layoutItem) {
                    debugPrint('Dropped data: $data');
                    return DateTime.now().millisecondsSinceEpoch.toString();
                  },
                  // The itemBuilder builds the visual representation of each item.
                  itemBuilder: (context, item) {
                    return MyCard(
                      key: ValueKey(item.id),
                      item: item,
                      color: getColorForItem(item.id),
                      onDeleteItem: () => controller.removeItem(item.id),
                      isEditing: controller.isEditing.value,
                    );
                  },
                  // trashLayout: TrashLayout.bottomCenter,
                  trashLayout: TrashLayout(
                    visible: TrashLayout.bottomCenter.visible.copyWith(
                      bottom: 0,
                    ),
                    hidden: TrashLayout.bottomCenter.hidden,
                  ),
                  // Optional: Customize the trash area.
                  trashBuilder: (context, isHovered, isActive, activeItemId) {
                    return Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: 60,
                        width: 200,
                        margin: const EdgeInsets.all(20.0),
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.red
                              : (isHovered ? Colors.orange : Colors.redAccent),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: const [
                            BoxShadow(blurRadius: 10, color: Colors.black26),
                          ],
                          border: isHovered
                              ? Border.all(color: Colors.white, width: 2)
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isActive ? Icons.delete_forever : Icons.delete,
                              color: Colors.white,
                              size: isActive ? 30 : 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isActive ? 'Release to Delete' : 'Drop to Delete',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: isActive ? 18 : 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  // Validate the Trash deletion
                  onWillDelete: (items) async {
                    return await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text("Delete ?"),
                            content: Text(
                              "Do you want remove items ${items.map((e) => e.id).join(',')} ?",
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text("No"),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text("Yes"),
                              ),
                            ],
                          ),
                        ) ??
                        false;
                  },
                  // Optional: Called when an item is deleted
                  onItemsDeleted: (items) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Items ${items.map((e) => e.id).join(',')} deleted',
                        ),
                      ),
                    );
                  },
                ),
                Positioned(
                  left: 20,
                  bottom: 20,
                  child: ValueListenableBuilder(
                    valueListenable: showMap,
                    builder: (context, value, _) {
                      if (!value) return const SizedBox.shrink();

                      return Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        clipBehavior: Clip.antiAlias,
                        child: Container(
                          // Vertical : Fixed width (120), flexible height (max 200)
                          // Horizontal : Fixed height (120), flexible width (max 200 or more)
                          width: scrollDirection == Axis.vertical ? 120 : null,
                          height: scrollDirection == Axis.vertical ? null : 120,
                          constraints: BoxConstraints(
                            maxHeight: scrollDirection == Axis.vertical
                                ? 200
                                : 120,
                            maxWidth: scrollDirection == Axis.vertical
                                ? 120
                                : 200,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DashboardMinimap(
                            controller: controller,
                            scrollController: scrollController,
                            // Important : use fixed width only if vertical
                            // Else let the widget's LayoutBuilder calculate its constraints
                            width: scrollDirection == Axis.vertical
                                ? 120
                                : null,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      // Add a FloatingActionButton to add new items programmatically.
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewItem,
        tooltip: 'Add New Item',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _addNewItem() {
    final random = Random();
    final newItem = LayoutItem(
      // Use a unique ID for each item.
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      // The engine will find the best spot, so initial x/y can be 0.
      x: 0,
      y: 0,
      w: random.nextInt(2) + 1, // Random width (1 or 2)
      h: random.nextInt(2) + 1, // Random height (1 or 2)
    );
    controller.addItem(newItem);
  }
}

/// A custom widget to display inside a dashboard item.
class MyCard extends StatelessWidget {
  const MyCard({
    required this.item,
    required this.color,
    required this.onDeleteItem,
    required this.isEditing,
    super.key,
  });

  final LayoutItem item;
  final Color color;
  final VoidCallback onDeleteItem;
  final bool isEditing;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Item ${item.id}',
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Text('(${item.w}x${item.h})'),
                if (item.isStatic)
                  const Chip(label: Text('Static'), avatar: Icon(Icons.lock)),
              ],
            ),
          ),
          if (isEditing && !item.isStatic)
            Positioned(
              top: 4,
              right: 4,
              child: Tooltip(
                message: 'Delete Item',
                child: GestureDetector(
                  onTap: onDeleteItem,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.red),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
