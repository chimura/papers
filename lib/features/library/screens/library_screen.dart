import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/auth/auth_provider.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/drive/drive_provider.dart';
import '../../../core/drive/drive_sync_service.dart';
import '../../../core/models/paper_model.dart';
import '../../../core/router/app_router.dart';
import '../../citations/services/citation_clipboard.dart';
import '../../import/providers/pdf_import_provider.dart';
import '../../import/screens/import_screen.dart';
import '../../import/services/bibtex_parser_service.dart';
import '../../import/services/ris_parser_service.dart';
import '../../reader/screens/reader_screen.dart';
import '../models/library_filter.dart';
import '../providers/collection_providers.dart';
import '../providers/library_filter_provider.dart';
import '../providers/library_provider.dart';
import '../providers/library_search_provider.dart';
import '../providers/selection_provider.dart';
import '../widgets/bulk_action_bar.dart';
import '../widgets/filter_drawer.dart';
import '../widgets/paper_grid_tile.dart';
import '../widgets/paper_list_tile.dart';
import 'paper_detail_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _isSearching = false;
  bool _dragging = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (_isSearching) {
        _searchFocusNode.requestFocus();
      } else {
        _searchController.clear();
        ref.read(searchQueryProvider.notifier).clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final libraryState = ref.watch(libraryProvider);
    final filter = ref.watch(libraryFilterProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final searchResults = ref.watch(searchResultsProvider);
    final isWide = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    final selectedPaper = ref.watch(selectedPaperProvider);
    final selection = ref.watch(selectionProvider);

    // Notify when a sync finishes.
    ref.listen(syncStateProvider, (previous, next) {
      if (previous?.status != SyncStatus.syncing) return;
      final messenger = ScaffoldMessenger.of(context);
      if (next.status == SyncStatus.success) {
        messenger.showSnackBar(SnackBar(
          content: Text(
              'Sync complete — ${next.uploadedCount} uploaded, ${next.downloadedCount} downloaded'),
        ));
        ref.read(libraryProvider.notifier).refresh();
      } else if (next.status == SyncStatus.error) {
        messenger.showSnackBar(SnackBar(
          content: Text('Sync failed: ${next.message ?? 'unknown error'}'),
          backgroundColor: theme.colorScheme.error,
        ));
      }
    });

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _toggleSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _toggleSearch,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            _openImport(context),
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            _openImport(context),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (ref.read(selectionProvider).isNotEmpty) {
            ref.read(selectionProvider.notifier).clear();
          } else if (_isSearching) {
            _toggleSearch();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
          final visible = _visiblePaperIds();
          if (visible.isNotEmpty) {
            ref.read(selectionProvider.notifier).selectAll(visible);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyC,
            control: true, shift: true): () {
          final paper = ref.read(selectedPaperProvider);
          if (paper != null) copyFormattedCitation(ref, context, paper);
        },
        const SingleActivator(LogicalKeyboardKey.keyB,
            control: true, shift: true): () {
          final paper = ref.read(selectedPaperProvider);
          if (paper != null) copyBibtexEntry(ref, context, paper);
        },
        const SingleActivator(LogicalKeyboardKey.keyK,
            control: true, shift: true): () {
          final paper = ref.read(selectedPaperProvider);
          if (paper != null) copyCiteCommand(ref, context, paper);
        },
      },
      child: Focus(
        autofocus: true,
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (details) {
            setState(() => _dragging = false);
            _handleDrop(details);
          },
          child: Stack(
            children: [
              Scaffold(
                appBar: selection.isNotEmpty
                    ? const BulkActionBar()
                    : AppBar(
                        title: _isSearching
                            ? TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                autofocus: true,
                                decoration: const InputDecoration(
                                  hintText: 'Search papers...',
                                  border: InputBorder.none,
                                  filled: false,
                                ),
                                onChanged: (value) => ref
                                    .read(searchQueryProvider.notifier)
                                    .update(value),
                              )
                            : const Text('Library'),
                        actions: [
                          _SyncButton(),
                          IconButton(
                            icon: Icon(_isSearching ? Icons.close : Icons.search),
                            tooltip:
                                _isSearching ? 'Close search' : 'Search (Ctrl+F)',
                            onPressed: _toggleSearch,
                          ),
                          _buildSortMenu(filter),
                          Builder(
                            builder: (context) => IconButton(
                              icon: Badge(
                                isLabelVisible: filter.isActive,
                                child: const Icon(Icons.filter_list),
                              ),
                              tooltip: 'Filters',
                              onPressed: () => Scaffold.of(context).openEndDrawer(),
                            ),
                          ),
                        ],
                      ),
                endDrawer: const FilterDrawer(),
                body: _isSearching && searchQuery.isNotEmpty
                    ? _buildSearchResults(theme, searchResults, isWide)
                    : isWide
                        ? _buildWideLayout(
                            theme, libraryState, filter, selectedPaper)
                        : _buildNarrowLayout(theme, libraryState, filter),
                floatingActionButton: selection.isNotEmpty
                    ? null
                    : FloatingActionButton(
                        onPressed: () => _openImport(context),
                        tooltip: 'Import paper (Ctrl+N)',
                        child: const Icon(Icons.add),
                      ),
              ),
              if (_dragging)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.file_download_outlined,
                                    size: 48,
                                    color: theme.colorScheme.primary),
                                const SizedBox(height: 8),
                                const Text(
                                    'Drop PDF, BibTeX, or RIS files to import'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    final messenger = ScaffoldMessenger.of(context);
    var pdfCount = 0, refCount = 0, skipped = 0;

    for (final file in details.files) {
      final path = file.path;
      final ext = p.extension(path).toLowerCase();
      try {
        switch (ext) {
          case '.pdf':
            final paper =
                await ref.read(fileImportServiceProvider).importPdf(path);
            await ref.read(libraryProvider.notifier).addPaper(paper);
            pdfCount++;
          case '.bib':
            final papers =
                BibtexParserService().parse(await File(path).readAsString());
            for (final paper in papers) {
              await ref.read(libraryProvider.notifier).addPaper(paper);
              refCount++;
            }
          case '.ris':
            final papers =
                RisParserService().parse(await File(path).readAsString());
            for (final paper in papers) {
              await ref.read(libraryProvider.notifier).addPaper(paper);
              refCount++;
            }
          default:
            skipped++;
        }
      } catch (_) {
        skipped++;
      }
    }

    final parts = <String>[
      if (pdfCount > 0) '$pdfCount PDF${pdfCount == 1 ? '' : 's'}',
      if (refCount > 0) '$refCount reference${refCount == 1 ? '' : 's'}',
    ];
    messenger.showSnackBar(SnackBar(
      content: Text(parts.isEmpty
          ? 'Nothing to import — drop PDF, .bib, or .ris files'
          : 'Imported ${parts.join(' and ')}'
              '${skipped > 0 ? ' ($skipped skipped)' : ''}'),
    ));
  }

  Widget _buildSortMenu(LibraryFilter filter) {
    return PopupMenuButton<Object>(
      icon: const Icon(Icons.sort),
      tooltip: 'Sort by',
      onSelected: (value) {
        final notifier = ref.read(libraryFilterProvider.notifier);
        if (value is SortOption) {
          notifier.setSortBy(value);
        } else if (value == 'direction') {
          notifier.toggleSortDirection();
        }
      },
      itemBuilder: (context) => [
        for (final option in SortOption.values)
          CheckedPopupMenuItem(
            value: option,
            checked: filter.sortBy == option,
            child: Text(option.label),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'direction',
          child: ListTile(
            leading: Icon(filter.sortDescending
                ? Icons.arrow_downward
                : Icons.arrow_upward),
            title: Text(filter.sortDescending ? 'Descending' : 'Ascending'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  void _openImport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ImportScreen()),
    );
  }

  // ── Wide layout: master-detail ──

  Widget _buildWideLayout(
    ThemeData theme,
    AsyncValue<List<PaperModel>> libraryState,
    LibraryFilter filter,
    PaperModel? selectedPaper,
  ) {
    return Row(
      children: [
        // Master: paper list
        SizedBox(
          width: 380,
          child: _buildNarrowLayout(theme, libraryState, filter,
              selectedPaperId: selectedPaper?.id),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        // Detail: paper detail
        Expanded(
          child: selectedPaper != null
              ? PaperDetailScreen(paper: selectedPaper)
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.article_outlined,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text(
                        'Select a paper to view details',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ── Narrow layout: simple list ──

  Widget _buildNarrowLayout(
    ThemeData theme,
    AsyncValue<List<PaperModel>> libraryState,
    LibraryFilter filter, {
    int? selectedPaperId,
  }) {
    return libraryState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('Error loading library',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(error.toString(), style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.read(libraryProvider.notifier).refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (allPapers) {
        final papers = _applyFilters(allPapers, filter);

        if (papers.isEmpty) {
          return _buildEmptyState(theme, filter);
        }

        final list = RefreshIndicator(
          onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
          child: ListView.separated(
            itemCount: papers.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final paper = papers[index];
              final isSelected = selectedPaperId != null &&
                  paper.id == selectedPaperId;
              final selection = ref.watch(selectionProvider);
              final inSelectionMode = selection.isNotEmpty;

              return Container(
                color: isSelected
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                    : null,
                child: PaperListTile(
                  paper: paper,
                  selected: inSelectionMode
                      ? selection.contains(paper.id)
                      : null,
                  onSelectedChanged: paper.id == null
                      ? null
                      : (_) => ref
                          .read(selectionProvider.notifier)
                          .toggle(paper.id!),
                  onTap: () {
                    if (inSelectionMode) {
                      if (paper.id != null) _selectWithModifiers(paper.id!);
                    } else {
                      _onPaperTap(context, paper);
                    }
                  },
                  onLongPress: paper.id == null
                      ? null
                      : () => ref
                          .read(selectionProvider.notifier)
                          .toggle(paper.id!),
                  onStatusTap: () =>
                      ref.read(libraryProvider.notifier).cycleReadStatus(paper),
                  onFavoriteToggle: () {
                    if (paper.id != null) {
                      ref
                          .read(libraryProvider.notifier)
                          .toggleFavorite(paper.id!, !paper.isFavorite);
                    }
                  },
                ),
              );
            },
          ),
        );

        final continueReading = filter.isActive
            ? const <PaperModel>[]
            : ((allPapers
                    .where(
                        (p) => p.lastReadAt != null && p.localPdfPath != null)
                    .toList()
                  ..sort((a, b) => b.lastReadAt!.compareTo(a.lastReadAt!)))
                .take(8)
                .toList());

        if (continueReading.isEmpty) return list;

        return Column(
          children: [
            _ContinueReadingShelf(
              papers: continueReading,
              onTap: _openReader,
            ),
            const Divider(height: 1),
            Expanded(child: list),
          ],
        );
      },
    );
  }

  void _openReader(PaperModel paper) {
    if (paper.id != null) {
      ref.read(paperDaoProvider).markReadingIfUnread(paper.id!);
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ReaderScreen(paper: paper)))
        .then((_) => ref.read(libraryProvider.notifier).refresh());
  }

  /// Shift extends the selection from the last clicked row; a plain click
  /// toggles just this one.
  void _selectWithModifiers(int paperId) {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final shiftHeld = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
    final notifier = ref.read(selectionProvider.notifier);
    if (shiftHeld) {
      notifier.selectRangeTo(paperId, _visiblePaperIds());
    } else {
      notifier.toggle(paperId);
    }
  }

  /// Ids currently shown in the list, in display order — the basis for
  /// Ctrl+A and shift-click range selection.
  List<int> _visiblePaperIds() {
    final papers = ref.read(libraryProvider).value ?? const <PaperModel>[];
    return _applyFilters(papers, ref.read(libraryFilterProvider))
        .map((p) => p.id)
        .whereType<int>()
        .toList();
  }

  // ── Search results ──

  Widget _buildSearchResults(
    ThemeData theme,
    AsyncValue<List<dynamic>> searchResults,
    bool isWide,
  ) {
    return searchResults.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Search error: $e')),
      data: (papers) {
        if (papers.isEmpty) {
          return Center(
            child: Text('No results found', style: theme.textTheme.bodyLarge),
          );
        }

        if (isWide) {
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisExtent: 200,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: papers.length,
            itemBuilder: (context, index) {
              final paper = papers[index];
              return PaperGridTile(
                paper: paper,
                onTap: () => _onPaperTap(context, paper),
              );
            },
          );
        }

        return ListView.separated(
          itemCount: papers.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final paper = papers[index];
            return PaperListTile(
              paper: paper,
              onTap: () => _onPaperTap(context, paper),
            );
          },
        );
      },
    );
  }

  // ── Helpers ──

  void _onPaperTap(BuildContext context, PaperModel paper) {
    // A tapped search result should open the paper, not select it invisibly
    // behind the results view — leave search mode first.
    if (_isSearching) _toggleSearch();

    final isWide = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    if (isWide) {
      ref.read(selectedPaperProvider.notifier).select(paper);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PaperDetailScreen(paper: paper)),
      );
    }
  }

  Widget _buildEmptyState(ThemeData theme, LibraryFilter filter) {
    if (filter.isActive) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.filter_list_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text('No papers match filters',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  ref.read(libraryFilterProvider.notifier).clearAll(),
              child: const Text('Clear filters'),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 64,
            color:
                theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No papers yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Import papers by DOI, PDF, or BibTeX',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _openImport(context),
            icon: const Icon(Icons.add),
            label: const Text('Import a paper'),
          ),
        ],
      ),
    );
  }

  List<PaperModel> _applyFilters(List<PaperModel> papers, LibraryFilter filter) {
    var result = papers.toList();

    if (filter.collectionId != null) {
      final memberIds = ref
              .watch(collectionPaperIdsProvider(filter.collectionId!))
              .value ??
          const <int>{};
      result = result.where((p) => memberIds.contains(p.id)).toList();
    }

    if (filter.favoritesOnly) {
      result = result.where((p) => p.isFavorite).toList();
    }

    if (filter.readStatus != null) {
      result =
          result.where((p) => p.readStatus == filter.readStatus).toList();
    }

    if (filter.missingPdfOnly) {
      result = result.where((p) => p.localPdfPath == null).toList();
    }

    if (filter.needsReviewOnly) {
      result = result.where((p) => p.needsReview).toList();
    }

    if (filter.tags.isNotEmpty) {
      result = result
          .where((p) => p.tags.any((t) => filter.tags.contains(t)))
          .toList();
    }

    if (filter.yearFrom != null) {
      result = result
          .where((p) =>
              p.year != null && p.year!.compareTo(filter.yearFrom!) >= 0)
          .toList();
    }

    if (filter.yearTo != null) {
      result = result
          .where((p) =>
              p.year != null && p.year!.compareTo(filter.yearTo!) <= 0)
          .toList();
    }

    result.sort((a, b) {
      int cmp;
      switch (filter.sortBy) {
        case SortOption.title:
          cmp = a.title.compareTo(b.title);
        case SortOption.year:
          cmp = (a.year ?? '').compareTo(b.year ?? '');
        case SortOption.author:
          cmp = a.authorsFormatted.compareTo(b.authorsFormatted);
        case SortOption.dateAdded:
          cmp = a.dateAdded.compareTo(b.dateAdded);
      }
      return filter.sortDescending ? -cmp : cmp;
    });

    return result;
  }
}

/// Horizontal "Continue reading" strip of recently opened papers.
class _ContinueReadingShelf extends StatelessWidget {
  final List<PaperModel> papers;
  final void Function(PaperModel) onTap;

  const _ContinueReadingShelf({required this.papers, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 108,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Continue reading',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: papers.length,
              itemBuilder: (context, index) {
                final paper = papers[index];
                final progress = (paper.totalPages ?? 0) > 0
                    ? (paper.lastReadPage ?? 1) / paper.totalPages!
                    : null;

                return SizedBox(
                  width: 220,
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onTap(paper),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                paper.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (progress != null) ...[
                              LinearProgressIndicator(
                                value: progress.clamp(0.0, 1.0),
                                minHeight: 3,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'p. ${paper.lastReadPage} / ${paper.totalPages}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Sync button for the app bar: spins while syncing, disabled with an
/// explanatory tooltip when the user has no Google session.
class _SyncButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncStateProvider);
    final user = ref.watch(authStateProvider).value;
    final canSync = user != null && !user.isAnonymous;
    final isSyncing = syncState.status == SyncStatus.syncing;

    if (isSyncing) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return IconButton(
      icon: const Icon(Icons.cloud_sync_outlined),
      tooltip: canSync
          ? 'Sync with Google Drive'
          : 'Sign in with Google (Settings) to sync',
      onPressed:
          canSync ? () => ref.read(syncStateProvider.notifier).sync() : null,
    );
  }
}
