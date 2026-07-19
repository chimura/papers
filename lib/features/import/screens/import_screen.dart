import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/providers/library_provider.dart';
import '../providers/bibtex_import_provider.dart';
import '../providers/doi_import_provider.dart';
import '../providers/pdf_import_provider.dart';
import '../widgets/metadata_preview_card.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _doiController = TextEditingController();
  final _bibtexController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _doiController.dispose();
    _bibtexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Paper'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.link), text: 'DOI'),
            Tab(icon: Icon(Icons.picture_as_pdf), text: 'PDF'),
            Tab(icon: Icon(Icons.code), text: 'BibTeX'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DoiTab(controller: _doiController),
          const _PdfTab(),
          _BibtexTab(controller: _bibtexController),
        ],
      ),
    );
  }
}

class _DoiTab extends ConsumerWidget {
  final TextEditingController controller;
  const _DoiTab({required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importState = ref.watch(doiImportProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'DOI',
              hintText: 'e.g. 10.1038/s41586-021-03819-2',
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: (_) => _lookup(ref),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: importState.status == ImportStatus.loading
                ? null
                : () => _lookup(ref),
            child: importState.status == ImportStatus.loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Look up'),
          ),
          const SizedBox(height: 16),
          if (importState.status == ImportStatus.error)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  importState.error ?? 'Unknown error',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          if (importState.paper != null)
            Expanded(
              child: MetadataPreviewCard(
                paper: importState.paper!,
                onImport: () => _importPaper(context, ref, importState.paper!),
              ),
            ),
        ],
      ),
    );
  }

  void _lookup(WidgetRef ref) {
    final doi = controller.text.trim();
    if (doi.isNotEmpty) {
      ref.read(doiImportProvider.notifier).lookupDoi(doi);
    }
  }

  Future<void> _importPaper(
      BuildContext context, WidgetRef ref, paper) async {
    await ref.read(libraryProvider.notifier).addPaper(paper);
    ref.read(doiImportProvider.notifier).reset();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paper added to library')),
      );
      Navigator.of(context).pop();
    }
  }
}

class _PdfTab extends ConsumerWidget {
  const _PdfTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importState = ref.watch(pdfImportProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed:
                importState.isLoading ? null : () => _pickPdf(ref),
            icon: importState.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            label: const Text('Choose PDF file'),
          ),
          const SizedBox(height: 16),
          if (importState.error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(importState.error!),
              ),
            ),
          if (importState.paper != null)
            Expanded(
              child: MetadataPreviewCard(
                paper: importState.paper!,
                onImport: () =>
                    _importPaper(context, ref, importState.paper!),
              ),
            ),
        ],
      ),
    );
  }

  void _pickPdf(WidgetRef ref) {
    ref.read(pdfImportProvider.notifier).pickAndImportPdf();
  }

  Future<void> _importPaper(
      BuildContext context, WidgetRef ref, paper) async {
    await ref.read(libraryProvider.notifier).addPaper(paper);
    ref.read(pdfImportProvider.notifier).reset();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paper added to library')),
      );
      Navigator.of(context).pop();
    }
  }
}

class _BibtexTab extends ConsumerWidget {
  final TextEditingController controller;
  const _BibtexTab({required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importState = ref.watch(bibtexImportProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                labelText: 'Paste BibTeX',
                hintText: '@article{key,\n  title={...},\n  author={...},\n  ...\n}',
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                ref.read(bibtexImportProvider.notifier).parseBibtex(text);
              }
            },
            child: const Text('Parse'),
          ),
          const SizedBox(height: 12),
          if (importState.error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(importState.error!),
              ),
            ),
          if (importState.papers.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  '${importState.papers.length} '
                  '${importState.papers.length == 1 ? 'entry' : 'entries'} found',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Spacer(),
                if (importState.papers.length > 1)
                  FilledButton.tonalIcon(
                    onPressed: () => _importAll(context, ref),
                    icon: const Icon(Icons.playlist_add, size: 18),
                    label: Text('Add all (${importState.papers.length})'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 3,
              child: ListView.builder(
                itemCount: importState.papers.length,
                itemBuilder: (context, index) {
                  final paper = importState.papers[index];
                  return MetadataPreviewCard(
                    paper: paper,
                    onImport: () => _importPaper(context, ref, paper),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _importPaper(
      BuildContext context, WidgetRef ref, paper) async {
    await ref.read(libraryProvider.notifier).addPaper(paper);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added: ${paper.title}')),
      );
    }
  }

  Future<void> _importAll(BuildContext context, WidgetRef ref) async {
    final papers = ref.read(bibtexImportProvider).papers;
    for (final paper in papers) {
      await ref.read(libraryProvider.notifier).addPaper(paper);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${papers.length} papers added to library')),
      );
      Navigator.of(context).pop();
    }
  }
}
