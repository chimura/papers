import 'package:flutter/material.dart';

import '../../../core/models/paper_model.dart';

class PaperListTile extends StatelessWidget {
  final PaperModel paper;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onStatusTap;

  /// Non-null puts the tile in selection mode and shows a checkbox.
  final bool? selected;
  final ValueChanged<bool?>? onSelectedChanged;

  const PaperListTile({
    super.key,
    required this.paper,
    this.onTap,
    this.onLongPress,
    this.onFavoriteToggle,
    this.onStatusTap,
    this.selected,
    this.onSelectedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRetracted = paper.updateStatus == 'retraction' ||
        paper.updateStatus == 'expression_of_concern';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Row(
        children: [
          if (isRetracted) ...[
            Icon(Icons.report, size: 16, color: theme.colorScheme.error),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              paper.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                decoration: isRetracted ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            paper.authorsFormatted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          _buildMetaRow(theme),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (paper.needsReview)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'Imported automatically — check its details',
                child: Icon(Icons.fiber_new,
                    size: 18, color: theme.colorScheme.tertiary),
              ),
            ),
          IconButton(
            icon: Icon(
              paper.isFavorite ? Icons.star : Icons.star_border,
              color: paper.isFavorite ? Colors.amber : null,
            ),
            onPressed: onFavoriteToggle,
          ),
        ],
      ),
      leading: selected != null
          ? Checkbox(value: selected, onChanged: onSelectedChanged)
          : _StatusLeading(
              paper: paper,
              onTap: onStatusTap,
            ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  Widget _buildMetaRow(ThemeData theme) {
    final parts = <String>[];
    if (paper.year != null) parts.add(paper.year!);
    if (paper.journal != null) parts.add(paper.journal!);

    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }
}

/// File-type icon that doubles as the read-status control.
class _StatusLeading extends StatelessWidget {
  final PaperModel paper;
  final VoidCallback? onTap;

  const _StatusLeading({required this.paper, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPdf = paper.localPdfPath != null;

    final (IconData icon, Color color, String label) =
        switch (paper.readStatus) {
      ReadStatus.unread => (
          hasPdf ? Icons.picture_as_pdf : Icons.article_outlined,
          hasPdf ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
          'Unread — click to mark as reading',
        ),
      ReadStatus.reading => (
          Icons.auto_stories,
          theme.colorScheme.tertiary,
          'Reading — click to mark as read',
        ),
      ReadStatus.read => (
          Icons.check_circle,
          theme.colorScheme.primary.withValues(alpha: 0.7),
          'Read — click to mark unread',
        ),
    };

    return Tooltip(
      message: label,
      child: IconButton(
        icon: Icon(icon, color: color),
        onPressed: onTap,
      ),
    );
  }
}
