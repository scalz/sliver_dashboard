import 'package:flutter/material.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

/// # Nested — size-driven folders
///
/// Composes two features into one interaction:
///
///  * `itemBreakpointBuilder` + `breakpointResolver`: a host tile resolves to
///    `_HostSize.mini` (1 slot in either axis) or `_HostSize.normal`, and its
///    subtree is rebuilt ONLY when that value transitions — not on every
///    pixel of a resize.
///  * `onItemDroppedOnHost`: while a host renders collapsed, its child grid
///    is detached, so the package treats the tile as a CLOSED HOST — a drop
///    target. Items dropped on it go straight into the folder's controller
///    without opening it.
///
/// Try it: grab a host's resize handle and shrink it to a single slot — it
/// collapses into a folder icon showing its item count. Drag a note onto the
/// collapsed folder: it disappears into it. Enlarge the folder again and the
/// full nested grid comes back, contents intact (the child controller is
/// owned by this State and never disposed on collapse).
enum _HostSize { mini, normal }

class NestedExamplePage extends StatefulWidget {
  const NestedExamplePage({super.key});

  @override
  State<NestedExamplePage> createState() => _NestedExamplePageState();
}

class _NestedExamplePageState extends State<NestedExamplePage> {
  final coordinator = DashboardNestedCoordinator();

  late final DashboardController root;

  /// Folder controllers, owned by this State: collapsing a folder only
  /// unmounts its widget, never disposes its controller, so the contents
  /// survive any number of collapse/expand cycles.
  final Map<String, DashboardController> folders = {};

  /// Panel-driven configuration.
  final isEditing = ValueNotifier<bool>(true);
  final sizeToContent = ValueNotifier<bool>(false);
  final compactionType = ValueNotifier<CompactType>(CompactType.vertical);
  final subGridDynamic = ValueNotifier<bool>(false);
  final subGridDynamicSameGrid = ValueNotifier<bool>(false);
  final restrictDrops = ValueNotifier<bool>(false);

  /// Slot span at or below which a folder collapses. Exposed in the panel to
  /// show that the breakpoint rule is entirely yours.
  final miniThreshold = ValueNotifier<int>(1);

  @override
  void initState() {
    super.initState();

    root = DashboardController(
      initialSlotCount: 6,
      initialLayout: const [
        // hasNestedGrid marks the intent; minW/minH: 1 is what makes the
        // collapse reachable through the resize handles.
        LayoutItem(
          id: 'projects',
          x: 0,
          y: 0,
          w: 3,
          h: 3,
          hasNestedGrid: true,
          minW: 1,
          minH: 1,
        ),
        LayoutItem(
          id: 'archive',
          x: 3,
          y: 0,
          w: 1,
          h: 1,
          hasNestedGrid: true,
          minW: 1,
          minH: 1,
        ),
        LayoutItem(id: 'note-1', x: 4, y: 0, w: 1, h: 1),
        LayoutItem(id: 'note-2', x: 5, y: 0, w: 1, h: 1),
        LayoutItem(id: 'note-3', x: 4, y: 1, w: 2, h: 1),
      ],
    )..setEditMode(true);

    folders['projects'] = DashboardController(
      initialSlotCount: 2,
      initialLayout: const [
        LayoutItem(id: 'task-a', x: 0, y: 0, w: 1, h: 1),
        LayoutItem(id: 'task-b', x: 1, y: 0, w: 1, h: 1),
      ],
    )..setEditMode(true);

    folders['archive'] = DashboardController(
      initialSlotCount: 2,
      initialLayout: const [LayoutItem(id: 'old-1', x: 0, y: 0, w: 1, h: 1)],
    )..setEditMode(true);
  }

  @override
  void dispose() {
    for (final folder in folders.values) {
      folder.dispose();
    }
    root.dispose();
    isEditing.dispose();
    sizeToContent.dispose();
    compactionType.dispose();
    subGridDynamic.dispose();
    subGridDynamicSameGrid.dispose();
    restrictDrops.dispose();
    miniThreshold.dispose();
    super.dispose();
  }

  void _applyEditMode() {
    root.setEditMode(isEditing.value);
    for (final folder in folders.values) {
      folder.setEditMode(isEditing.value);
    }
  }

  void _applyCompactType() {
    root.setCompactionType(compactionType.value);
    for (final folder in folders.values) {
      folder.setCompactionType(compactionType.value);
    }
  }

  /// Programmatic collapse/expand — the same state change the resize handles
  /// produce, useful when a host's minW/minH forbid shrinking by hand.
  void _collapse(String id) =>
      root.updateItem(id, (i) => i.copyWith(w: 1, h: 1), recompact: false);

  void _expand(String id) => root.updateItem(id, (i) => i.copyWith(w: 3, h: 3));

  /// The breakpoint. Keyed on the item's SLOT span rather than raw pixels:
  /// the collapse must happen on a grid-cell boundary, not at an arbitrary
  /// pixel width (the resolver also receives live `width`/`height` if a
  /// pixel-driven rule fits your design better).
  _HostSize _resolveHostSize(
    double width,
    double height,
    LayoutItem item,
    int slotCount,
  ) {
    final t = miniThreshold.value;
    return (item.w <= t || item.h <= t) ? _HostSize.mini : _HostSize.normal;
  }

  /// Per-grid drop rules.
  ///
  /// One scope-wide predicate serves the whole tree; branching on
  /// [targetGrid] is what expresses per-grid policy — there is no per-grid
  /// override, because the rule is consulted while resolving WHICH grid is
  /// under the pointer, before any grid owns the interaction.
  ///
  /// ### A rule needs TWO enforcement points, not one
  /// `canAcceptItem` covers drags that enter a **mounted** sub-grid. It
  /// cannot cover a drop onto a **closed folder tile**, because that runs
  /// through `onItemDroppedOnHost` before the child grid exists — there is no
  /// target controller to hand the predicate. In this demo the folders are
  /// exactly that: host tiles in the root grid. Enforcing the rule only in
  /// `canAcceptItem` would let every drop onto a folder through, which is the
  /// most visible interaction here.
  ///
  /// So the rule lives in [_isDropAllowed] and is applied from both
  /// [_canAcceptItem] and [_onItemDroppedOnHost]. That split is the point of
  /// this example, not an accident of it.
  ///
  /// Two rules here, one per direction:
  ///
  /// * "projects" only takes tasks. Dropping a note over it does not get
  ///   stuck: the refusal makes that sub-grid transparent, so the drag falls
  ///   through to the root grid and the note lands there instead.
  /// * "archive" is read-only. Nothing enters it, and because [sourceGrid] is
  ///   part of the contract, nothing leaves it either — a rule the
  ///   `(item, targetGrid)` pair alone could not express.
  ///
  /// Called on every pointer event over a candidate grid, so it stays to a
  /// couple of identity checks and a prefix test. Anything that walks a
  /// layout belongs behind a memo of your own, not here.
  /// The business rule itself, independent of how a drop reaches a grid.
  ///
  /// Kept separate from [_canAcceptItem] because it has to be enforced at
  /// **two** places — see the note on entry points above.
  bool _isDropAllowed(
    LayoutItem item,
    DashboardController targetGrid,
    DashboardController sourceGrid,
  ) {
    if (!restrictDrops.value) return true;

    final archive = folders['archive'];
    if (identical(sourceGrid, archive)) return false;
    if (identical(targetGrid, archive)) return false;

    if (identical(targetGrid, folders['projects'])) {
      return item.id.startsWith('task');
    }
    return true;
  }

  /// Enforcement point 1: dragging INTO a mounted sub-grid.
  bool _canAcceptItem(
    LayoutItem item,
    DashboardController targetGrid,
    DashboardController sourceGrid,
  ) => _isDropAllowed(item, targetGrid, sourceGrid);

  /// subGridDynamic: a dragged item was held over a plain note long enough
  /// to request turning it into a folder. We create its controller and flag
  /// it — and, unlike the classic example, we also make sure the new host
  /// clears the mini threshold: a 1x1 folder would render COLLAPSED, no
  /// child grid would mount, and the held drag would have nowhere to land.
  void _onNestedGridRequested(
    LayoutItem host,
    LayoutItem dragged,
    DashboardController hostGrid,
  ) {
    if (host.hasNestedGrid || folders.containsKey(host.id)) return;

    final open = miniThreshold.value + 1;
    folders[host.id] = DashboardController(initialSlotCount: open)
      ..setEditMode(isEditing.value)
      ..setCompactionType(compactionType.value);

    hostGrid.updateItem(
      host.id,
      (i) => i.copyWith(
        hasNestedGrid: true,
        w: i.w < open ? open : i.w,
        h: i.h < open ? open : i.h,
      ),
      // Metadata + a one-slot growth: recompact:false keeps the neighbours
      // still under the frozen drag preview, and the abandonment handler
      // below restores the armed-time geometry if the drop never lands.
      recompact: false,
    );
    setState(() {});
    // No programmatic move: the held drag hands itself over to the freshly
    // mounted child grid on the next pointer move or on release.
  }

  /// The request fired but the drag ended without landing in the new grid:
  /// revert the speculative conversion.
  void _onNestedGridAbandoned(LayoutItem host, DashboardController hostGrid) {
    final child = folders.remove(host.id);
    if (child == null) return;

    coordinator.unlinkChildGrid(child);
    hostGrid.updateItem(
      host.id,
      // `host` is the item AS IT WAS WHEN THE REQUEST ARMED: restoring its
      // geometry undoes the growth above (shrinking never collides, so
      // recompact:false is safe under every compaction mode).
      (i) => i.copyWith(hasNestedGrid: false, w: host.w, h: host.h),
      recompact: false,
    );
    // The NestedDashboard for this host may still be mounted this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => child.dispose());
    setState(() {});
  }

  /// Items released over a collapsed folder. The package has already
  /// restored the pre-drag layout, so nothing landed on the root grid: we
  /// move the items into the folder's own controller.
  void _onItemDroppedOnHost(
    List<LayoutItem> dragged,
    LayoutItem host,
    DashboardController hostGrid,
    DashboardController sourceGrid,
  ) {
    final folder = folders[host.id];
    if (folder == null) return;

    final ids = dragged.map((i) => i.id).toSet()..remove(host.id);
    if (ids.isEmpty) return;

    var moved = dragged.where((i) => ids.contains(i.id)).toList();

    // Enforcement point 2. The child grid is not mounted here, so
    // `canAcceptItem` never ran — this callback is where the same rule has to
    // be applied for a drop onto a closed folder.
    final refused = moved.where((i) => !_isDropAllowed(i, folder, sourceGrid));
    if (refused.isNotEmpty) {
      moved = moved
          .where((i) => _isDropAllowed(i, folder, sourceGrid))
          .toList();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1600),
          content: Text('"${host.id}" refused ${refused.length} item(s)'),
        ),
      );
      if (moved.isEmpty) return;
    }
    // The items are back where the drag started — which may be ANOTHER grid
    // (a nested folder, for instance), hence sourceGrid rather than hostGrid.
    sourceGrid.removeItems(moved.map((i) => i.id).toList());
    // -1/-1 lets the engine auto-place them inside the folder.
    folder.addItems(moved.map((i) => i.copyWith(x: -1, y: -1)).toList());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1200),
        content: Text('Filed ${moved.length} item(s) into "${host.id}"'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 950;

    final configPanel = _ConfigPanel(
      root: root,
      folders: folders,
      isEditing: isEditing,
      sizeToContent: sizeToContent,
      compactionType: compactionType,
      subGridDynamic: subGridDynamic,
      subGridDynamicSameGrid: subGridDynamicSameGrid,
      restrictDrops: restrictDrops,
      miniThreshold: miniThreshold,
      onEditModeChanged: _applyEditMode,
      onCompactTypeChanged: _applyCompactType,
      onCollapse: _collapse,
      onExpand: _expand,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nested — size-driven folders'),
        elevation: 2,
        actions: [
          if (!isDesktop)
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Open Config Panel',
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
        ],
      ),
      endDrawer: isDesktop
          ? null
          : Drawer(
              backgroundColor: theme.colorScheme.surfaceContainerLow,
              child: SafeArea(child: configPanel),
            ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Shrink a folder to the mini threshold: it collapses and '
                    'becomes a drop target. Drag a note onto it to file the '
                    'note away. Enlarge it to reopen the grid.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: Listenable.merge([
                      sizeToContent,
                      miniThreshold,
                      subGridDynamic,
                      subGridDynamicSameGrid,
                      restrictDrops,
                    ]),
                    builder: (context, _) => DashboardNestedScope(
                      coordinator: coordinator,
                      subGridDynamic: subGridDynamic.value,
                      subGridDynamicSameGrid: subGridDynamicSameGrid.value,
                      onNestedGridRequested: _onNestedGridRequested,
                      onNestedGridRequestAbandoned: _onNestedGridAbandoned,
                      onItemDroppedOnHost: _onItemDroppedOnHost,
                      canAcceptItem: _canAcceptItem,
                      child: Dashboard<String>(
                        // Remount on threshold change: the resolver's verdict
                        // depends on state OUTSIDE the item's dimensions, and
                        // the item cache compares RESOLVED VALUES computed
                        // with the current resolver — it cannot see that the
                        // rule itself moved. Keying the Dashboard is the
                        // simple, correct answer for a runtime-tunable rule.
                        key: ValueKey('dash-${miniThreshold.value}'),
                        controller: root,
                        slotAspectRatio: 1.0,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        padding: const EdgeInsets.all(8),
                        breakpointResolver: _resolveHostSize,
                        itemBreakpointBuilder:
                            (
                              context,
                              item,
                              breakpoint,
                              width,
                              height,
                              slotCount,
                            ) {
                              final folder = folders[item.id];
                              if (folder == null) {
                                return _NoteTile(
                                  key: ValueKey(item.id),
                                  item: item,
                                );
                              }
                              // The point of the breakpoint builder: this branch
                              // runs once per TRANSITION, so the nested grid is
                              // not torn down and rebuilt on every pixel of a
                              // resize.
                              return breakpoint == _HostSize.mini
                                  ? _CollapsedFolder(
                                      key: ValueKey('${item.id}-mini'),
                                      item: item,
                                      folder: folder,
                                      coordinator: coordinator,
                                    )
                                  : _OpenFolder(
                                      key: ValueKey('${item.id}-open'),
                                      item: item,
                                      folder: folder,
                                      sizeToContent: sizeToContent,
                                    );
                            },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isDesktop)
            Container(
              width: 320,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Material(
                color: theme.colorScheme.surfaceContainerLow,
                child: configPanel,
              ),
            ),
        ],
      ),
    );
  }
}

class _ConfigPanel extends StatelessWidget {
  const _ConfigPanel({
    required this.root,
    required this.folders,
    required this.isEditing,
    required this.sizeToContent,
    required this.compactionType,
    required this.subGridDynamic,
    required this.subGridDynamicSameGrid,
    required this.restrictDrops,
    required this.miniThreshold,
    required this.onEditModeChanged,
    required this.onCompactTypeChanged,
    required this.onCollapse,
    required this.onExpand,
  });

  final DashboardController root;
  final Map<String, DashboardController> folders;
  final ValueNotifier<bool> isEditing;
  final ValueNotifier<bool> sizeToContent;
  final ValueNotifier<CompactType> compactionType;
  final ValueNotifier<bool> subGridDynamic;
  final ValueNotifier<bool> subGridDynamicSameGrid;
  final ValueNotifier<bool> restrictDrops;
  final ValueNotifier<int> miniThreshold;
  final VoidCallback onEditModeChanged;
  final VoidCallback onCompactTypeChanged;
  final void Function(String id) onCollapse;
  final void Function(String id) onExpand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // state_beacon is re-exported by the package barrel: watching a
    // controller needs no extra dependency in the app.
    final layout = root.layout.watch(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SIZE-DRIVEN FOLDERS',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const Divider(),
          const _SectionTitle('Interaction'),
          _SwitchTile(
            title: 'Edit Mode (Draggable/Resizable)',
            notifier: isEditing,
            onChanged: (_) => onEditModeChanged(),
          ),
          const SizedBox(height: 8),
          const _SectionTitle('Breakpoint rule'),
          Text(
            'A folder collapses when its width OR height reaches this many '
            'slots.',
            style: theme.textTheme.bodySmall,
          ),
          ValueListenableBuilder<int>(
            valueListenable: miniThreshold,
            builder: (context, value, _) => DropdownButton<int>(
              isExpanded: true,
              value: value,
              items: const [
                DropdownMenuItem(value: 1, child: Text('mini at 1 slot')),
                DropdownMenuItem(value: 2, child: Text('mini at 2 slots')),
              ],
              onChanged: (v) => miniThreshold.value = v ?? 1,
            ),
          ),
          const SizedBox(height: 8),
          const _SectionTitle('Open folders'),
          _SwitchTile(
            title: 'sizeToContent (host grows vs internal scroll)',
            notifier: sizeToContent,
          ),
          const SizedBox(height: 8),
          const _SectionTitle('Nested Behavior'),
          _SwitchTile(
            title: 'subGridDynamic (hover a note to turn it into a folder)',
            notifier: subGridDynamic,
          ),
          _SwitchTile(
            title: 'subGridDynamicSameGrid (pause mid-drag over a sibling)',
            notifier: subGridDynamicSameGrid,
          ),
          _SwitchTile(
            title:
                'canAcceptItem: "projects" takes tasks only, '
                '"archive" is read-only',
            notifier: restrictDrops,
          ),
          const SizedBox(height: 8),
          const _SectionTitle('Compaction'),
          ValueListenableBuilder<CompactType>(
            valueListenable: compactionType,
            builder: (context, value, _) => DropdownButton<CompactType>(
              isExpanded: true,
              value: value,
              items: CompactType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                  .toList(),
              onChanged: (t) {
                if (t == null) return;
                compactionType.value = t;
                onCompactTypeChanged();
              },
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('Folders'),
          for (final id in folders.keys)
            Builder(
              builder: (context) {
                // No package:collection dependency in this example: the
                // package's own firstWhereOrNull is internal.
                final matches = layout.where((i) => i.id == id);
                final item = matches.isEmpty ? null : matches.first;
                final count = folders[id]!.layout.watch(context).length;
                final collapsed =
                    item == null ||
                    item.w <= miniThreshold.value ||
                    item.h <= miniThreshold.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        collapsed ? Icons.folder : Icons.folder_open,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$id · $count item(s)'
                          '${item == null ? '' : ' · ${item.w}x${item.h}'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Collapse',
                        icon: const Icon(Icons.close_fullscreen, size: 16),
                        onPressed: collapsed ? null : () => onCollapse(id),
                      ),
                      IconButton(
                        tooltip: 'Expand',
                        icon: const Icon(Icons.open_in_full, size: 16),
                        onPressed: collapsed ? () => onExpand(id) : null,
                      ),
                    ],
                  ),
                );
              },
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

/// A folder rendered at its mini breakpoint: no child grid is mounted, so
/// the package sees a closed host and turns the tile into a drop target.
class _CollapsedFolder extends StatefulWidget {
  const _CollapsedFolder({
    required this.item,
    required this.folder,
    required this.coordinator,
    super.key,
  });

  final LayoutItem item;
  final DashboardController folder;
  final DashboardNestedCoordinator coordinator;

  @override
  State<_CollapsedFolder> createState() => _CollapsedFolderState();
}

class _CollapsedFolderState extends State<_CollapsedFolder> {
  @override
  void initState() {
    super.initState();
    // Detach the child grid so `hasChildGrid` becomes false and the tile
    // qualifies as a drop target.
    //
    // Why this is an APP decision: NestedDashboard deliberately does NOT
    // unlink when it unmounts, because sliver virtualization unmounts it
    // whenever the host scrolls out of view — the link must survive that.
    // Collapsing, on the other hand, is a real state change, so we say so.
    // Expanding re-links automatically when NestedDashboard mounts again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.coordinator.unlinkChildGrid(widget.folder);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Live count: state_beacon is re-exported by the package barrel, so no
    // extra dependency is needed to watch a controller's layout.
    final count = widget.folder.layout.watch(context).length;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      color: theme.colorScheme.secondaryContainer,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder, color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(height: 4),
            Text(
              widget.item.id,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                color: theme.colorScheme.onSecondaryContainer,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A folder rendered at its normal breakpoint: the real nested grid, with
/// full cross-grid drag in and out.
class _OpenFolder extends StatelessWidget {
  const _OpenFolder({
    required this.item,
    required this.folder,
    required this.sizeToContent,
    super.key,
  });

  final LayoutItem item;
  final DashboardController folder;
  final ValueNotifier<bool> sizeToContent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 32,
            color: theme.colorScheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(
                  Icons.folder_open,
                  size: 16,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.id,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: sizeToContent,
              builder: (context, stc, _) => NestedDashboard(
                controller: folder,
                parentItemId: item.id,
                sizeToContent: stc,
                chromeExtent: 32,
                itemBuilder: (context, leaf) =>
                    _NoteTile(key: ValueKey(leaf.id), item: leaf, dense: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.item, this.dense = false, super.key});

  final LayoutItem item;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      color: theme.colorScheme.tertiaryContainer,
      child: Center(
        child: Text(
          item.id,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: theme.colorScheme.onTertiaryContainer,
            fontWeight: FontWeight.w600,
            fontSize: dense ? 11 : 13,
          ),
        ),
      ),
    );
  }
}
