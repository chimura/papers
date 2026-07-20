import 'package:flutter/material.dart';

import '../../../core/models/paper_model.dart';

class MetadataPreviewCard extends StatelessWidget {
  final PaperModel paper;
  final VoidCallback onImport;

  const MetadataPreviewCard({
    super.key,
    required this.paper,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              paper.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (paper.authors.isNotEmpty)
              Text(
                paper.authorsFormatted,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 4),
            _buildMetadataRow(theme, paper),
            if (paper.importedFilePath != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.attachment,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text('PDF linked',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.primary)),
                ],
              ),
            ],
            if (paper.abstract_ != null) ...[
              const SizedBox(height: 8),
              Text(
                paper.abstract_!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add to Library'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataRow(ThemeData theme, PaperModel paper) {
    final parts = <String>[];
    if (paper.year != null) parts.add(paper.year!);
    if (paper.journal != null) parts.add(paper.journal!);
    if (paper.doi != null) parts.add('DOI: ${paper.doi}');

    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' · '),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
