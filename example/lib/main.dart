import 'dart:math';
import 'package:sliver_dashboard/sliver_dashboard.dart';
import 'package:flutter/material.dart';

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
  late final controller = DashboardController(
    initialSlotCount: slotCount,
    onLayoutChanged: (items) {
      debugPrint(
        'Layout changed! Saving ${items.length} items to persistence...',
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

  final editMode = ValueNotifier(false);
  final compactionType = ValueNotifier<CompactType>(CompactType.vertical);
  var scrollDirection = Axis.vertical;
  var resizeBehavior = ResizeBehavior.push;
  final cardColors = <String, Color>{};
  final random = Random();

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
  void dispose() {
    editMode.dispose();
    compactionType.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sliver Dashboard Example'),
        actions: [
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
          Wrap(
            direction: Axis.horizontal,
            alignment: WrapAlignment.center,
            runSpacing: 8,
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
                      ButtonSegment(
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
                segments: [
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
          // Add some external draggables to demonstrate dropping new items.
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(8),
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
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              // Optional: Breakpoint wrapper widget for responsive
              child: Dashboard<String>(
                controller: controller,
                trashHoverDelay: const Duration(seconds: 1),
                scrollDirection: scrollDirection,
                // ResizeBehavior.push or ResizeBehavior.shrink
                resizeBehavior: resizeBehavior,
                showScrollbar: false,
                slotAspectRatio: 1.0,
                // Responsive breakpoints:
                breakpoints: {
                  0: 4, // Mobile: 4 cols
                  600: 8, // Tablet/Desktop: 8 cols
                },
                // The size of the touch target
                resizeHandleSide: 20, // default 20.0
                padding: EdgeInsets.zero,
                mainAxisSpacing: 8.0, // default 8.0
                crossAxisSpacing: 8.0, // default 8.0
                // how many non visible pixels to preload on top and bottom
                cacheExtent: 500,
                guidance:
                    DashboardGuidance.byDefault, // default null for no guidance
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
                  visible: TrashLayout.bottomCenter.visible.copyWith(bottom: 0),
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
                onWillDelete: (item) async {
                  return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text("Delete ?"),
                          content: Text("Do you want remove item ${item.id} ?"),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text("No"),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text("Yes"),
                            ),
                          ],
                        ),
                      ) ??
                      false;
                },
                // Optional: Called when an item is deleted
                onItemDeleted: (item) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Item ${item.id} deleted')),
                  );
                },
              ),
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
