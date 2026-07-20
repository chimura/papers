import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/models/paper_model.dart';
import '../../../core/router/app_router.dart';
import '../../citations/services/citation_clipboard.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/annotation_model.dart';
import '../providers/annotation_provider.dart';
import '../providers/reader_provider.dart';
import '../widgets/annotation_toolbar.dart';
import '../widgets/highlight_overlay.dart';
import '../widgets/note_panel.dart';

/// Color-inverts the rendered PDF for night reading.
const _invertMatrix = <double>[
  -1, 0, 0, 0, 255, //
  0, -1, 0, 0, 255, //
  0, 0, -1, 0, 255, //
  0, 0, 0, 1, 0, //
];

class ReaderScreen extends ConsumerStatefulWidget {
  final PaperModel paper;

  const ReaderScreen({super.key, required this.paper});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _pdfController = PdfViewerController();
  PdfTextSelection? _lastTextSelection;
  bool _showSidePanel = true;

  Timer? _positionSaveTimer;
  int? _pendingPage;

  @override
  void dispose() {
    _positionSaveTimer?.cancel();
    _flushReadingPosition();
    ref.read(readerStateProvider.notifier).reset();
    super.dispose();
  }

  void _scheduleReadingPositionSave(int pageNumber) {
    _pendingPage = pageNumber;
    _positionSaveTimer?.cancel();
    _positionSaveTimer =
        Timer(const Duration(seconds: 2), _flushReadingPosition);
  }

  void _flushReadingPosition() {
    final paperId = widget.paper.id;
    final page = _pendingPage;
    if (paperId == null || page == null) return;
    _pendingPage = null;

    final totalPages = ref.read(readerStateProvider).totalPages;
    ref.read(paperDaoProvider).updateReadingPosition(
          paperId,
          page: page,
          totalPages: totalPages > 0 ? totalPages : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final readerState = ref.watch(readerStateProvider);
    final annotationsAsync = widget.paper.id != null
        ? ref.watch(annotationsProvider(widget.paper.id!))
        : null;
    final annotations = annotationsAsync?.value ?? [];
    final isWide = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    final pdfDarkMode =
        ref.watch(settingsProvider).value?.pdfDarkMode ?? false;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () =>
            ref.read(readerStateProvider.notifier).setTool(ReaderTool.highlight),
        const SingleActivator(LogicalKeyboardKey.keyH, meta: true): () =>
            ref.read(readerStateProvider.notifier).setTool(ReaderTool.highlight),
        const SingleActivator(LogicalKeyboardKey.keyM, control: true): () =>
            ref.read(readerStateProvider.notifier).setTool(ReaderTool.note),
        const SingleActivator(LogicalKeyboardKey.keyM, meta: true): () =>
            ref.read(readerStateProvider.notifier).setTool(ReaderTool.note),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            ref.read(readerStateProvider.notifier).setTool(ReaderTool.none),
        const SingleActivator(LogicalKeyboardKey.keyC,
                control: true, shift: true):
            () => copyFormattedCitation(ref, context, widget.paper),
        const SingleActivator(LogicalKeyboardKey.keyB,
                control: true, shift: true):
            () => copyBibtexEntry(ref, context, widget.paper),
        const SingleActivator(LogicalKeyboardKey.keyK,
                control: true, shift: true):
            () => copyCiteCommand(ref, context, widget.paper),
        if (isWide)
          const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
              setState(() => _showSidePanel = !_showSidePanel),
        if (isWide)
          const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
              setState(() => _showSidePanel = !_showSidePanel),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              widget.paper.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: Icon(pdfDarkMode ? Icons.light_mode : Icons.dark_mode),
                tooltip: pdfDarkMode
                    ? 'Normal PDF colors'
                    : 'Dark PDF (inverted colors)',
                onPressed: () => ref
                    .read(settingsProvider.notifier)
                    .setPdfDarkMode(!pdfDarkMode),
              ),
              IconButton(
                icon: const Icon(Icons.format_quote),
                tooltip: 'Copy citation (Ctrl+Shift+C)',
                onPressed: () =>
                    copyFormattedCitation(ref, context, widget.paper),
              ),
              if (isWide)
                IconButton(
                  icon: Icon(
                      _showSidePanel ? Icons.view_sidebar : Icons.view_sidebar_outlined),
                  tooltip: 'Toggle side panel (Ctrl+B)',
                  onPressed: () =>
                      setState(() => _showSidePanel = !_showSidePanel),
                )
              else
                IconButton(
                  icon: const Icon(Icons.list),
                  tooltip: 'Annotations list',
                  onPressed: () =>
                      _showAnnotationsSheet(context, annotations),
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: isWide
                    ? _buildWideBody(readerState, annotations, pdfDarkMode)
                    : _buildPdfViewer(readerState, annotations, pdfDarkMode),
              ),
              const AnnotationToolbar(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Wide layout: PDF + side panel ──

  Widget _buildWideBody(
    ReaderState readerState,
    List<AnnotationModel> annotations,
    bool pdfDarkMode,
  ) {
    return Row(
      children: [
        Expanded(child: _buildPdfViewer(readerState, annotations, pdfDarkMode)),
        if (_showSidePanel) ...[
          const VerticalDivider(width: 1, thickness: 1),
          SizedBox(
            width: 320,
            child: _AnnotationSidePanel(
              annotations: annotations,
              onAnnotationTap: (a) => _onAnnotationTap(context, a),
              onDelete: (a) {
                if (a.id != null) {
                  ref
                      .read(annotationActionsProvider)
                      .deleteAnnotation(a.paperId, a.id!);
                }
              },
              onGoToPage: (page) =>
                  _pdfController.goToPage(pageNumber: page),
            ),
          ),
        ],
      ],
    );
  }

  // ── PDF viewer ──

  Widget _buildPdfViewer(
    ReaderState readerState,
    List<AnnotationModel> annotations,
    bool pdfDarkMode,
  ) {
    final pdfPath = widget.paper.localPdfPath;
    if (pdfPath == null || !File(pdfPath).existsSync()) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.picture_as_pdf, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('PDF file not found'),
            SizedBox(height: 8),
            Text('The file may have been moved or deleted.',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    Widget viewer = PdfViewer.file(
      pdfPath,
      controller: _pdfController,
      params: PdfViewerParams(
        onViewerReady: (document, controller) {
          ref
              .read(readerStateProvider.notifier)
              .setTotalPages(document.pages.length);
          final resumePage = widget.paper.lastReadPage;
          if (resumePage != null &&
              resumePage > 1 &&
              resumePage <= document.pages.length) {
            controller.goToPage(pageNumber: resumePage);
          }
        },
        onPageChanged: (pageNumber) {
          ref.read(readerStateProvider.notifier).setPage((pageNumber ?? 1) - 1);
          if (pageNumber != null) _scheduleReadingPositionSave(pageNumber);
        },
        textSelectionParams: PdfTextSelectionParams(
          onTextSelectionChange: (textSelection) {
            _lastTextSelection = textSelection;
          },
        ),
        pageOverlaysBuilder: (context, pageRect, page) {
          if (!readerState.showAnnotations) return [];

          final pageAnnotations =
              annotations.where((a) => a.page == page.pageNumber).toList();

          if (pageAnnotations.isEmpty) return [];

          return [
            HighlightOverlay(
              annotations: pageAnnotations,
              pageSize: Size(page.width, page.height),
              visible: readerState.showAnnotations,
              // The overlay renders inside the inverted viewer, so its
              // colors are pre-inverted to come out right.
              invertColors: pdfDarkMode,
              onAnnotationTap: (annotation) =>
                  _onAnnotationTap(context, annotation),
            ),
          ];
        },
      ),
    );

    if (pdfDarkMode) {
      viewer = ColorFiltered(
        colorFilter: const ColorFilter.matrix(_invertMatrix),
        child: viewer,
      );
    }

    return Stack(
      children: [
        viewer,

        if (readerState.activeTool == ReaderTool.highlight)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.icon(
                onPressed: _createHighlightFromSelection,
                icon: const Icon(Icons.highlight, size: 18),
                label: const Text('Highlight selection'),
              ),
            ),
          ),

        if (readerState.activeTool == ReaderTool.note)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (details) => _addNoteAtPosition(context, details),
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }

  // ── Actions ──

  Future<void> _createHighlightFromSelection() async {
    final textSelection = _lastTextSelection;
    if (textSelection == null || !textSelection.hasSelectedText) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select text first, then highlight')),
      );
      return;
    }

    final paperId = widget.paper.id;
    if (paperId == null) return;

    final readerState = ref.read(readerStateProvider);
    final selectedText = await textSelection.getSelectedText();
    final ranges = await textSelection.getSelectedTextRanges();

    for (final range in ranges) {
      final pageText = range.pageText;
      final pageNumber = pageText.pageNumber;

      double minX = double.infinity, minY = double.infinity;
      double maxX = 0, maxY = 0;

      for (var i = range.start;
          i <= range.end && i < pageText.charRects.length;
          i++) {
        final rect = pageText.charRects[i];
        if (rect.left < minX) minX = rect.left;
        if (rect.top < minY) minY = rect.top;
        if (rect.right > maxX) maxX = rect.right;
        if (rect.bottom > maxY) maxY = rect.bottom;
      }

      if (minX < double.infinity) {
        await ref.read(annotationActionsProvider).addHighlight(
              paperId: paperId,
              page: pageNumber,
              x: minX,
              y: minY,
              width: maxX - minX,
              height: maxY - minY,
              selectedText: selectedText,
              color: readerState.highlightColor,
            );
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Highlight added')),
      );
    }
  }

  void _addNoteAtPosition(BuildContext context, TapUpDetails details) {
    final paperId = widget.paper.id;
    if (paperId == null) return;

    final readerState = ref.read(readerStateProvider);
    final localPos = details.localPosition;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => NotePanel(
        onSave: (content) {
          ref.read(annotationActionsProvider).addNote(
                paperId: paperId,
                page: readerState.currentPage + 1,
                x: localPos.dx,
                y: localPos.dy,
                content: content,
              );
        },
      ),
    );
  }

  void _onAnnotationTap(BuildContext context, AnnotationModel annotation) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => NotePanel(
        annotation: annotation,
        onSave: (content) {
          ref.read(annotationActionsProvider).updateAnnotation(
                annotation.copyWith(content: content),
              );
        },
        onDelete: () {
          if (annotation.id != null) {
            ref
                .read(annotationActionsProvider)
                .deleteAnnotation(annotation.paperId, annotation.id!);
          }
        },
      ),
    );
  }

  void _showAnnotationsSheet(
      BuildContext context, List<AnnotationModel> annotations) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          if (annotations.isEmpty) {
            return const Center(child: Text('No annotations yet'));
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Annotations (${annotations.length})',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: annotations.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final annotation = annotations[index];
                    return _annotationListTile(context, annotation);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _annotationListTile(BuildContext context, AnnotationModel annotation) {
    return ListTile(
      leading: Icon(
        annotation.type == AnnotationType.highlight
            ? Icons.highlight
            : Icons.note,
        color: annotation.color,
      ),
      title: Text(
        annotation.selectedText ?? annotation.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('Page ${annotation.page}'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: () {
          if (annotation.id != null) {
            ref
                .read(annotationActionsProvider)
                .deleteAnnotation(annotation.paperId, annotation.id!);
            Navigator.pop(context);
          }
        },
      ),
      onTap: () {
        Navigator.pop(context);
        _pdfController.goToPage(pageNumber: annotation.page);
      },
    );
  }
}

/// Side panel showing annotations list for desktop layout.
class _AnnotationSidePanel extends StatelessWidget {
  final List<AnnotationModel> annotations;
  final void Function(AnnotationModel) onAnnotationTap;
  final void Function(AnnotationModel) onDelete;
  final void Function(int page) onGoToPage;

  const _AnnotationSidePanel({
    required this.annotations,
    required this.onAnnotationTap,
    required this.onDelete,
    required this.onGoToPage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Annotations (${annotations.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const Divider(height: 1),
        if (annotations.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                'No annotations yet',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: annotations.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final annotation = annotations[index];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    annotation.type == AnnotationType.highlight
                        ? Icons.highlight
                        : Icons.note,
                    color: annotation.color,
                    size: 20,
                  ),
                  title: Text(
                    annotation.selectedText ?? annotation.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  subtitle: Text('Page ${annotation.page}',
                      style: theme.textTheme.labelSmall),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => onDelete(annotation),
                  ),
                  onTap: () {
                    onGoToPage(annotation.page);
                    onAnnotationTap(annotation);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
