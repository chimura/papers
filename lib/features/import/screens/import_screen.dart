import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../library/providers/library_provider.dart';
import '../providers/bibtex_import_provider.dart';
import '../providers/doi_import_provider.dart';
import '../providers/identifier_import_provider.dart';
import '../providers/pdf_import_provider.dart';
import '../services/ris_parser_service.dart';
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

  late final _identifierController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _doiController.dispose();
    _bibtexController.dispose();
    _identifierController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Paper'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.link), text: 'DOI'),
            Tab(icon: Icon(Icons.tag), text: 'Identifiers'),
            Tab(icon: Icon(Icons.picture_as_pdf), text: 'PDF'),
            Tab(icon: Icon(Icons.code), text: 'BibTeX / RIS'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DoiTab(controller: _doiController),
          _IdentifiersTab(controller: _identifierController),
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

/// Bulk paste of mixed DOIs, arXiv IDs and PMIDs.
class _IdentifiersTab extends ConsumerWidget {
  final TextEditingController controller;
  const _IdentifiersTab({required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(identifierImportProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            maxLines: 5,
            minLines: 3,
            decoration: const InputDecoration(
              labelText: 'DOIs, arXiv IDs, PMIDs',
              hintText:
                  '10.1038/s41586-021-03819-2\narXiv:1706.03762\n32015507',
              helperText: 'One per line, or separated by spaces/commas',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: state.isLoading
                ? null
                : () => ref
                    .read(identifierImportProvider.notifier)
                    .lookup(controller.text),
            icon: state.isLoading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(state.isLoading ? 'Looking up...' : 'Look up all'),
          ),
          const SizedBox(height: 12),
          if (state.error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(state.error!),
              ),
            ),
          if (state.unresolved.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Could not resolve: ${state.unresolved.join(', ')}',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (state.papers.isNotEmpty) ...[
            Row(
              children: [
                Text('${state.papers.length} found'),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () => _importAll(context, ref, state.papers),
                  icon: const Icon(Icons.playlist_add, size: 18),
                  label: Text('Add all (${state.papers.length})'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: state.papers.length,
                itemBuilder: (context, index) {
                  final paper = state.papers[index];
                  return MetadataPreviewCard(
                    paper: paper,
                    onImport: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await ref
                          .read(libraryProvider.notifier)
                          .addPaper(paper);
                      messenger.showSnackBar(
                          SnackBar(content: Text('Added: ${paper.title}')));
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _importAll(
      BuildContext context, WidgetRef ref, List<dynamic> papers) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    for (final paper in papers) {
      await ref.read(libraryProvider.notifier).addPaper(paper);
    }
    ref.read(identifierImportProvider.notifier).reset();
    messenger.showSnackBar(
        SnackBar(content: Text('${papers.length} papers added to library')));
    navigator.pop();
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
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final text = controller.text.trim();
                    if (text.isNotEmpty) {
                      ref.read(bibtexImportProvider.notifier).parseBibtex(text);
                    }
                  },
                  child: const Text('Parse'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openFile(context, ref, controller),
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Open .bib / .ris file'),
                ),
              ),
            ],
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

  /// Loads a whole reference-manager export off disk. RIS is parsed here and
  /// pushed into the same preview list the BibTeX parser feeds.
  Future<void> _openFile(BuildContext context, WidgetRef ref,
      TextEditingController controller) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bib', 'ris', 'txt'],
      dialogTitle: 'Open a BibTeX or RIS export',
    );
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final content = await File(path).readAsString();

    if (p.extension(path).toLowerCase() == '.ris') {
      final papers = RisParserService().parse(content);
      ref.read(bibtexImportProvider.notifier).setPapers(papers);
      messenger.showSnackBar(SnackBar(
          content: Text('Parsed ${papers.length} entries from '
              '${p.basename(path)}')));
    } else {
      controller.text = content;
      ref.read(bibtexImportProvider.notifier).parseBibtex(content);
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
