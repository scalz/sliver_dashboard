import 'dart:ui';
import 'package:flutter/material.dart';

class DashboardShortcutsHud extends StatelessWidget {
  const DashboardShortcutsHud({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 680,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.88,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.keyboard_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Keyboard Shortcuts & Gestures',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: onClose ?? () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildSection(theme, 'Navigation & Selection', [
                    ('Tab', 'Focus next item'),
                    ('Ctrl / ⌘ + A', 'Select all items'),
                    ('Drag empty space', 'Lasso / Rubberband selection'),
                    ('Escape', 'Cancel drag / Clear selection'),
                  ]),
                  const SizedBox(height: 16),
                  _buildSection(theme, 'Grid Manipulation', [
                    ('Space / Enter', 'Grab / Drop active item'),
                    ('Arrows', 'Move grabbed item'),
                    ('Ctrl / ⌘ + D', 'Duplicate selection'),
                    ('Del / Backspace', 'Delete selected item(s)'),
                    ('Shift + Drag', 'Toggle Swap / Cascade mode'),
                    ('Alt + Drag', 'Duplicate tile on drag'),
                  ]),
                  const SizedBox(height: 16),
                  _buildSection(theme, 'History', [
                    ('Ctrl / ⌘ + Z', 'Undo last change'),
                    ('Ctrl / ⌘ + Y', 'Redo change'),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    ThemeData theme,
    String title,
    List<(String, String)> shortcuts,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: shortcuts
              .map((s) => _buildShortcutRow(theme, s.$1, s.$2))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildShortcutRow(ThemeData theme, String keyText, String desc) {
    return SizedBox(
      width: 300,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              keyText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              desc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
