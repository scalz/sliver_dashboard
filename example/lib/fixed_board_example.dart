import 'package:material_ui/material_ui.dart';
import 'package:sliver_dashboard/sliver_dashboard.dart';

/// Only these tile sizes exist on the panel (an item's own size is always
/// accepted by contract, so older tiles still move).
class _PanelSizes extends DashboardPolicy {
  const _PanelSizes();

  static const sizes = {(1, 1), (2, 2), (4, 2)};

  @override
  bool isSizeAllowed(LayoutItem item, int w, int h) => sizes.contains((w, h));
}

/// A wall panel: 10 x 6 square slots that never scroll, three tile sizes,
/// tap an empty slot to add a tile there.
class FixedBoardExamplePage extends StatefulWidget {
  const FixedBoardExamplePage({super.key});

  @override
  State<FixedBoardExamplePage> createState() => _FixedBoardExamplePageState();
}

class _FixedBoardExamplePageState extends State<FixedBoardExamplePage> {
  static const _cols = 10;
  static const _rows = 6;

  late final DashboardController _controller =
      DashboardController(
          initialSlotCount: _cols,
          initialLayout: const [
            LayoutItem(id: 'clock', x: 0, y: 0, w: 4, h: 2),
            LayoutItem(id: 'temp', x: 4, y: 0, w: 2, h: 2),
            LayoutItem(id: 'light', x: 6, y: 0, w: 1, h: 1),
            LayoutItem(id: 'door', x: 7, y: 0, w: 1, h: 1),
            LayoutItem(id: 'camera', x: 0, y: 2, w: 4, h: 2),
            LayoutItem(id: 'scene', x: 4, y: 2, w: 2, h: 2),
          ],
        )
        ..setCompactionType(CompactType.none)
        ..setMaxRows(_rows)
        ..setStrictMaxRows(true)
        ..setFluidResize(true)
        ..setEditMode(true)
        ..policy = const _PanelSizes();

  var _nextId = 0;
  (int, int) _newSize = (2, 2);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addAt(int x, int y) {
    final (w, h) = _newSize;
    // The tapped slot is kept inside the tile, which is shifted back into the
    // board when it would overflow the right or bottom edge.
    final tile = LayoutItem(
      id: 'tile_$_nextId',
      x: x.clamp(0, _cols - w),
      y: y.clamp(0, _rows - h),
      w: w,
      h: h,
    );
    // canPlace: exactly here, nothing pushed. tryAddItem alone would also
    // accept a spot reached by pushing neighbours, as long as nothing crosses
    // the last row.
    final ok = _controller.canPlace(tile) && _controller.tryAddItem(tile);
    if (ok) {
      _nextId++;
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('No room for a ${w}x$h tile at ($x, $y)')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fixed board'),
        actions: [
          for (final size in _PanelSizes.sizes)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text('${size.$1}x${size.$2}'),
                selected: _newSize == size,
                onSelected: (_) => setState(() => _newSize = size),
              ),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Tap an empty slot to add the selected size. Resizes snap to 1x1, 2x2 or 4x2; '
              'nothing can be pushed below row $_rows.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: _cols / _rows,
                child: Dashboard(
                  controller: _controller,
                  padding: const EdgeInsets.all(12),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  physics: const NeverScrollableScrollPhysics(),
                  onSlotTap: _addAt,
                  itemBuilder: (context, item) => Card(
                    margin: EdgeInsets.zero,
                    color: theme.colorScheme.primaryContainer,
                    child: Center(
                      child: Text(
                        '${item.id}\n${item.w}x${item.h}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
