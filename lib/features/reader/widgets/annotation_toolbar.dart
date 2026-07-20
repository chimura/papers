import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/reader_provider.dart';

class AnnotationToolbar extends ConsumerWidget {
  const AnnotationToolbar({super.key});

  /// Shared with the reader's selection toolbar so both offer the same
  /// palette.
  static const highlightColors = [
    Color(0xFFFFFF00), // Yellow
    Color(0xFF00FF00), // Green
    Color(0xFF00BFFF), // Blue
    Color(0xFFFF69B4), // Pink
    Color(0xFFFF8C00), // Orange
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readerState = ref.watch(readerStateProvider);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Highlight tool
            _ToolButton(
              icon: Icons.highlight,
              label: 'Highlight',
              isActive: readerState.activeTool == ReaderTool.highlight,
              activeColor: readerState.highlightColor,
              onPressed: () =>
                  ref.read(readerStateProvider.notifier).setTool(ReaderTool.highlight),
            ),

            // Note tool
            _ToolButton(
              icon: Icons.note_add,
              label: 'Note',
              isActive: readerState.activeTool == ReaderTool.note,
              onPressed: () =>
                  ref.read(readerStateProvider.notifier).setTool(ReaderTool.note),
            ),

            const VerticalDivider(width: 16),

            // Color picker (visible when highlight tool is active)
            if (readerState.activeTool == ReaderTool.highlight)
              ...(highlightColors.map((color) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: GestureDetector(
                      onTap: () => ref
                          .read(readerStateProvider.notifier)
                          .setHighlightColor(color),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: readerState.highlightColor == color
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ))),

            const Spacer(),

            // Toggle annotations visibility
            IconButton(
              icon: Icon(
                readerState.showAnnotations
                    ? Icons.visibility
                    : Icons.visibility_off,
              ),
              tooltip: 'Toggle annotations',
              onPressed: () =>
                  ref.read(readerStateProvider.notifier).toggleAnnotations(),
            ),

            // Page indicator
            Text(
              '${readerState.currentPage + 1} / ${readerState.totalPages}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color? activeColor;
  final VoidCallback onPressed;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isActive,
    this.activeColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: Material(
        color: isActive
            ? (activeColor ?? theme.colorScheme.primary).withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Icon(
              icon,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
