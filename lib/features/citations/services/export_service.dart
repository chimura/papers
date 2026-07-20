import 'dart:ui';

import '../../../core/models/paper_model.dart';
import '../../reader/models/annotation_model.dart';

class ExportService {
  /// Export a single paper as BibTeX
  String toBibtex(PaperModel paper) {
    final key = paper.bibtexKey ?? _generateBibtexKey(paper);
    final buf = StringBuffer('@article{$key,\n');

    buf.writeln('  title = {${paper.title}},');

    if (paper.authors.isNotEmpty) {
      final authors =
          paper.authors.map((a) => '${a.familyName}, ${a.givenName ?? ''}').join(' and ');
      buf.writeln('  author = {$authors},');
    }

    if (paper.journal != null) buf.writeln('  journal = {${paper.journal}},');
    if (paper.year != null) buf.writeln('  year = {${paper.year}},');
    if (paper.volume != null) buf.writeln('  volume = {${paper.volume}},');
    if (paper.issue != null) buf.writeln('  number = {${paper.issue}},');
    if (paper.pages != null) buf.writeln('  pages = {${paper.pages}},');
    if (paper.doi != null) buf.writeln('  doi = {${paper.doi}},');
    if (paper.abstract_ != null) buf.writeln('  abstract = {${paper.abstract_}},');

    buf.write('}');
    return buf.toString();
  }

  /// Export a single paper as RIS
  String toRis(PaperModel paper) {
    final buf = StringBuffer();
    buf.writeln('TY  - JOUR');
    buf.writeln('TI  - ${paper.title}');

    for (final author in paper.authors) {
      buf.writeln('AU  - ${author.familyName}, ${author.givenName ?? ''}');
    }

    if (paper.journal != null) buf.writeln('JO  - ${paper.journal}');
    if (paper.year != null) buf.writeln('PY  - ${paper.year}');
    if (paper.volume != null) buf.writeln('VL  - ${paper.volume}');
    if (paper.issue != null) buf.writeln('IS  - ${paper.issue}');
    if (paper.pages != null) {
      final pageParts = paper.pages!.split('-');
      buf.writeln('SP  - ${pageParts.first.trim()}');
      if (pageParts.length > 1) buf.writeln('EP  - ${pageParts.last.trim()}');
    }
    if (paper.doi != null) buf.writeln('DO  - ${paper.doi}');
    if (paper.abstract_ != null) buf.writeln('AB  - ${paper.abstract_}');

    buf.writeln('ER  - ');
    return buf.toString();
  }

  /// Export multiple papers as BibTeX
  String toBibtexMultiple(List<PaperModel> papers) {
    return papers.map(toBibtex).join('\n\n');
  }

  /// Export multiple papers as RIS
  String toRisMultiple(List<PaperModel> papers) {
    return papers.map(toRis).join('\n');
  }

  /// Renders a paper's highlights and notes as a self-contained Markdown
  /// document (Obsidian-friendly: YAML frontmatter + blockquoted highlights).
  String toMarkdownSummary(
    PaperModel paper,
    List<AnnotationModel> annotations, {
    String? formattedCitation,
  }) {
    final buf = StringBuffer();

    buf.writeln('---');
    buf.writeln('title: "${paper.title.replaceAll('"', r'\"')}"');
    if (paper.authors.isNotEmpty) {
      buf.writeln(
          'authors: ${paper.authors.map((a) => a.displayName).join(', ')}');
    }
    if (paper.year != null) buf.writeln('year: ${paper.year}');
    if (paper.journal != null) buf.writeln('journal: "${paper.journal}"');
    if (paper.doi != null) buf.writeln('doi: ${paper.doi}');
    if (paper.tags.isNotEmpty) {
      buf.writeln('tags: [${paper.tags.join(', ')}]');
    }
    buf.writeln('citekey: ${paper.bibtexKey ?? _generateBibtexKey(paper)}');
    buf.writeln('---');
    buf.writeln();
    buf.writeln('# ${paper.title}');
    buf.writeln();
    if (formattedCitation != null) {
      buf.writeln('**Citation:** $formattedCitation');
      buf.writeln();
    }

    final sorted = [...annotations]..sort((a, b) {
        final byPage = a.page.compareTo(b.page);
        return byPage != 0 ? byPage : a.y.compareTo(b.y);
      });

    final highlights =
        sorted.where((a) => a.type == AnnotationType.highlight).toList();
    final notes = sorted.where((a) => a.type == AnnotationType.note).toList();

    if (highlights.isNotEmpty) {
      buf.writeln('## Highlights');
      buf.writeln();
      for (final h in highlights) {
        final quote = (h.selectedText ?? '').trim();
        if (quote.isEmpty) continue;
        buf.writeln(
            '> ${quote.replaceAll('\n', ' ')} ${_colorMarker(h.color)}');
        buf.writeln('> — p. ${h.page}');
        final comment = h.content.trim();
        if (comment.isNotEmpty) {
          buf.writeln();
          buf.writeln(comment);
        }
        buf.writeln();
      }
    }

    if (notes.isNotEmpty) {
      buf.writeln('## Notes');
      buf.writeln();
      for (final n in notes) {
        final content = n.content.trim();
        if (content.isEmpty) continue;
        buf.writeln('- (p. ${n.page}) $content');
      }
      buf.writeln();
    }

    if (highlights.isEmpty && notes.isEmpty) {
      buf.writeln('_No annotations yet._');
    }

    return buf.toString();
  }

  String _colorMarker(Color color) {
    // Matches the reader's highlight palette.
    switch (color.toARGB32() & 0x00FFFFFF) {
      case 0xFFFF00:
        return '🟡';
      case 0x00FF00:
        return '🟢';
      case 0x00BFFF:
        return '🔵';
      case 0xFF69B4:
        return '🩷';
      case 0xFF8C00:
        return '🟠';
      default:
        return '';
    }
  }

  String _generateBibtexKey(PaperModel paper) {
    final firstAuthor =
        paper.authors.isNotEmpty ? paper.authors.first.familyName : 'unknown';
    final year = paper.year ?? 'nd';
    final titleWord = paper.title.split(' ').first.toLowerCase();
    return '${firstAuthor.toLowerCase()}$year$titleWord';
  }
}
