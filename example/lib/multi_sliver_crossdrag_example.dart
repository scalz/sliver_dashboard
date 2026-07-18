import 'package:flutter/material.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

/// Aesthetic color scheme matching the dark-theme design of other sub-examples.
class _Palette {
  static const grid1Header = Color(0xFF0D9488); // Teal 600
  static const grid2Header = Color(0xFF4F46E5); // Indigo 600

  static const cardGrid1 = Color(0xFF2DD4BF); // Teal 400
  static const cardGrid2 = Color(0xFF818CF8); // Indigo 400
  static const intermediateBox = Color(0xFF1E293B); // Slate 800

  static const onCard = Color(0xFF1F2937); // Slate 800
}

class MultiSliverExamplePage extends StatefulWidget {
  const MultiSliverExamplePage({super.key});

  @override
  State<MultiSliverExamplePage> createState() => _MultiSliverExamplePageState();
}

class _MultiSliverExamplePageState extends State<MultiSliverExamplePage> {
  final scrollController = ScrollController();
  final coordinator = DashboardNestedCoordinator();

  // Keys required to target each sliver specifically in the multi-sliver tree
  final sliverKey1 = GlobalKey();
  final sliverKey2 = GlobalKey();

  late final DashboardController controller1;
  late final DashboardController controller2;

  final isEditing = ValueNotifier<bool>(true);
  var activePolicy = DimensionProjectionPolicy.preserveVisualProportion;

  @override
  void initState() {
    super.initState();

    // Sibling 1: High Density (8 Columns)
    controller1 = DashboardController(
      initialSlotCount: 8,
      initialLayout: [
        const LayoutItem(
          id: 'grid1-cardA',
          x: 0,
          y: 0,
          w: 2,
          h: 2,
          minW: 1,
          minH: 1,
        ),
        const LayoutItem(id: 'grid1-cardB', x: 2, y: 0, w: 2, h: 2),
        const LayoutItem(id: 'grid1-cardC', x: 4, y: 0, w: 4, h: 2),
      ],
    )..setEditMode(isEditing.value);

    // Sibling 2: Low Density (4 Columns)
    controller2 = DashboardController(
      initialSlotCount: 4,
      initialLayout: [
        const LayoutItem(id: 'grid2-cardX', x: 0, y: 0, w: 2, h: 2),
        const LayoutItem(id: 'grid2-cardY', x: 2, y: 0, w: 2, h: 2),
      ],
    )..setEditMode(isEditing.value);

    isEditing.addListener(_onEditModeChanged);
  }

  void _onEditModeChanged() {
    controller1.setEditMode(isEditing.value);
    controller2.setEditMode(isEditing.value);
  }

  @override
  void dispose() {
    isEditing.removeListener(_onEditModeChanged);
    isEditing.dispose();
    controller1.dispose();
    controller2.dispose();
    scrollController.dispose();
    coordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 950;

    final configPanel = _ConfigPanel(
      isEditing: isEditing,
      activePolicy: activePolicy,
      onPolicyChanged: (policy) {
        setState(() {
          activePolicy = policy;
        });
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Multi-Sliver Drag & Drop'),
        actions: [
          if (!isDesktop)
            Builder(
              builder: (context) {
                return IconButton(
                  icon: const Icon(Icons.tune),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                );
              },
            ),
        ],
      ),
      endDrawer: isDesktop
          ? null
          : Drawer(
              backgroundColor:
                  Colors.grey.shade900, // Fixed: took full drawer height
              child: SafeArea(child: configPanel),
            ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DashboardNestedScope(
              coordinator: coordinator,
              projectionPolicy: activePolicy,
              customProjectionCallback:
                  (item, {required sourceSlotCount, required targetSlotCount}) {
                    // Custom rule: force dimensions to 1x1
                    return item.copyWith(w: 1, h: 1);
                  },
              child: DashboardOverlay<String>(
                controller: controller1,
                scrollController: scrollController,
                sliverKey: sliverKey1,
                // Must match the SliverPadding around sliverKey1: the overlay
                // padding is the cross-axis origin of all hit-test math.
                padding: const EdgeInsets.all(8.0),
                itemBuilder: _buildCard,
                gridStyle: GridStyle(
                  lineColor: Colors.white.withValues(alpha: 0.04),
                ),
                child: DashboardOverlay<String>(
                  controller: controller2,
                  scrollController: scrollController,
                  sliverKey: sliverKey2,
                  padding: const EdgeInsets.all(8.0),
                  itemBuilder: _buildCard,
                  gridStyle: GridStyle(
                    lineColor: Colors.white.withValues(alpha: 0.04),
                  ),
                  child: CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      // Section 1 Header
                      const SliverAppBar(
                        automaticallyImplyLeading: false,
                        pinned: false,
                        floating: true,
                        backgroundColor: _Palette.grid1Header,
                        title: Text('Sliver Grid #1 (8 Columns - Dense)'),
                      ),

                      // Sliver Dashboard 1
                      SliverPadding(
                        padding: const EdgeInsets.all(8.0),
                        sliver: SliverDashboard(
                          key: sliverKey1,
                          controller: controller1,
                          itemBuilder: _buildCard,
                        ),
                      ),

                      // Native Intermediate separator to prove physical transformations logic
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => Container(
                            color: _Palette.intermediateBox,
                            padding: const EdgeInsets.symmetric(
                              vertical: 24,
                              horizontal: 16,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.swap_vert,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    'Intermediate Native List Element $index\n(Drag elements across this separator)',
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          childCount: 2,
                        ),
                      ),

                      // Section 2 Header
                      const SliverAppBar(
                        automaticallyImplyLeading: false,
                        pinned: false,
                        floating: true,
                        backgroundColor: _Palette.grid2Header,
                        title: Text('Sliver Grid #2 (4 Columns - Large)'),
                      ),

                      // Sliver Dashboard 2
                      SliverPadding(
                        padding: const EdgeInsets.all(8.0),
                        sliver: SliverDashboard(
                          key: sliverKey2,
                          controller: controller2,
                          itemBuilder: _buildCard,
                        ),
                      ),

                      // Trailing Separator
                      SliverToBoxAdapter(
                        child: Container(
                          height: 100,
                          alignment: Alignment.center,
                          color: Colors.black38,
                          child: const Text(
                            'Footer content ...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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

  Widget _buildCard(BuildContext context, LayoutItem item) {
    // Dynamic Color Switching: card color adapts on the fly to match its host grid theme
    final isHost1 = controller1.layout.value.any((i) => i.id == item.id);
    final color = isHost1 ? _Palette.cardGrid1 : _Palette.cardGrid2;

    return Card(
      key: ValueKey(item.id),
      margin: EdgeInsets.zero,
      color: color,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              item.id,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: _Palette.onCard,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '(${item.w}x${item.h})',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigPanel extends StatelessWidget {
  const _ConfigPanel({
    required this.isEditing,
    required this.activePolicy,
    required this.onPolicyChanged,
  });

  final ValueNotifier<bool> isEditing;
  final DimensionProjectionPolicy activePolicy;
  final ValueChanged<DimensionProjectionPolicy> onPolicyChanged;

  String _getPolicyLabel(DimensionProjectionPolicy policy) {
    switch (policy) {
      case DimensionProjectionPolicy.preserveLogicalSize:
        return 'Preserve Logical Size';
      case DimensionProjectionPolicy.preserveVisualProportion:
        return 'Preserve Visual Proportion';
      case DimensionProjectionPolicy.custom:
        return 'Custom Callback (Force 1x1)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'CROSS-SLIVER PANEL',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.indigo.shade300,
            ),
          ),
          const Divider(),
          const SizedBox(height: 8),

          ValueListenableBuilder<bool>(
            valueListenable: isEditing,
            builder: (context, editing, _) {
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Edit Mode (DND active)',
                  style: TextStyle(fontSize: 13),
                ),
                value: editing,
                onChanged: (val) => isEditing.value = val,
              );
            },
          ),

          const SizedBox(height: 16),
          const Text(
            'Dimension Projection Policy',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButton<DimensionProjectionPolicy>(
            isExpanded: true,
            value: activePolicy,
            items: DimensionProjectionPolicy.values.map((v) {
              return DropdownMenuItem(
                value: v,
                child: Text(
                  _getPolicyLabel(v),
                  style: const TextStyle(fontSize: 12),
                ),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) onPolicyChanged(v);
            },
          ),

          const SizedBox(height: 16),
          _PolicyCard(activePolicy: activePolicy),
        ],
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.activePolicy});

  final DimensionProjectionPolicy activePolicy;

  @override
  Widget build(BuildContext context) {
    final String description;
    switch (activePolicy) {
      case DimensionProjectionPolicy.preserveLogicalSize:
        description =
            'Cards preserve their exact logical coordinates. A (2x2) card remains a (2x2) card regardless of the target density, leading to potential overlapping or oversized slots.';
      case DimensionProjectionPolicy.preserveVisualProportion:
        description =
            'Proportional scale adjustment is computed dynamically on the fly. Dragging a (2x2) item representing 25% of grid 1 (8 col) scales down to a (1x1) representing 25% of grid 2 (4 col) keeping perfectly aligned aspect ratio ratios.';
      case DimensionProjectionPolicy.custom:
        description =
            'An active custom callback projection is evaluated. In this demo, the custom policy is configured to always force the item to a (1x1) grid square upon drop.';
    }

    return Card(
      color: Colors.white.withValues(alpha: 0.02),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.indigo.shade300,
                ),
                SizedBox(width: 8),
                Text(
                  'Active Policy Logic',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white60,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
