import '../../../core/models/paper_model.dart';
import '../models/citation_style.dart';
import 'export_service.dart';

/// Turns a multi-selection of papers into one deduplicated, correctly ordered
/// bibliography: alphabetical for author-date styles, numbered in selection
/// order for numeric ones.
class BibliographyBuilder {
  final ExportService _exportService;

  BibliographyBuilder({ExportService? exportService})
      : _exportService = exportService ?? ExportService();

  /// Numeric styles number their references instead of sorting them; IEEE is
  /// the only one of the built-in five.
  static bool isNumericStyle(CitationStyle style) => style.shortName == 'IEEE';

  String build(List<PaperModel> papers, CitationStyle style) {
    final unique = dedupe(papers);
    if (unique.isEmpty) return '';

    if (isNumericStyle(style)) {
      // Numeric styles keep the order they were cited/selected in.
      return [
        for (var i = 0; i < unique.length; i++)
          '[${i + 1}] ${style.format(unique[i])}',
      ].join('\n\n');
    }

    final sorted = sortAlphabetically(unique);
    return sorted.map(style.format).join('\n\n');
  }

  /// BibTeX has no style; it only needs the same dedupe pass.
  String buildBibtex(List<PaperModel> papers) {
    return _exportService.toBibtexMultiple(dedupe(papers));
  }

  /// Drops repeats, preferring the first occurrence. Identity is the database
  /// id when known, then the DOI, then the normalized title — so the same
  /// paper imported twice from different sources still collapses.
  List<PaperModel> dedupe(List<PaperModel> papers) {
    final seen = <String>{};
    final unique = <PaperModel>[];
    for (final paper in papers) {
      if (seen.add(_identity(paper))) unique.add(paper);
    }
    return unique;
  }

  String _identity(PaperModel paper) {
    if (paper.id != null) return 'id:${paper.id}';
    final doi = paper.doi?.trim().toLowerCase();
    if (doi != null && doi.isNotEmpty) return 'doi:$doi';
    return 'title:${paper.normalizedTitle}';
  }

  /// Author-date ordering: first author's family name, then year.
  List<PaperModel> sortAlphabetically(List<PaperModel> papers) {
    final sorted = [...papers];
    sorted.sort((a, b) {
      final byAuthor =
          _sortKey(a).toLowerCase().compareTo(_sortKey(b).toLowerCase());
      if (byAuthor != 0) return byAuthor;
      return (a.year ?? '').compareTo(b.year ?? '');
    });
    return sorted;
  }

  /// Authorless works file under their title, as most style guides require.
  String _sortKey(PaperModel paper) =>
      paper.authors.isNotEmpty ? paper.authors.first.familyName : paper.title;
}
