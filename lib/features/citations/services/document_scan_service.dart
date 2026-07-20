import 'package:path/path.dart' as p;

import '../../../core/models/paper_model.dart';
import '../models/citation_style.dart';
import 'bibliography_builder.dart';

class ScanResult {
  /// The document with every resolvable placeholder replaced and a
  /// references section appended.
  final String output;

  /// Citation keys that matched nothing in the library, in first-seen order.
  /// Their placeholders are left untouched so no work is silently lost.
  final List<String> unresolved;

  /// How many placeholder occurrences were replaced (repeats counted).
  final int replacedCount;

  const ScanResult({
    required this.output,
    required this.unresolved,
    required this.replacedCount,
  });
}

/// Scans a plain-text/Markdown document for `[@key]` / `{@key}` placeholder
/// citations, replaces them with formatted in-text citations, and appends the
/// matching bibliography — the "write anywhere, format later" workflow.
class DocumentScanService {
  final BibliographyBuilder _bibliographyBuilder;

  DocumentScanService({BibliographyBuilder? bibliographyBuilder})
      : _bibliographyBuilder = bibliographyBuilder ?? BibliographyBuilder();

  /// Both bracket flavours, so the same document works whether the author
  /// writes Pandoc-style `[@key]` or Zotero-style `{@key}`.
  static final RegExp _placeholder =
      RegExp(r'\[@([A-Za-z0-9_:-]+)\]|\{@([A-Za-z0-9_:-]+)\}');

  ScanResult scan({
    required String content,
    required List<PaperModel> library,
    required CitationStyle style,
  }) {
    final byKey = <String, PaperModel>{};
    for (final paper in library) {
      final key = paper.bibtexKey?.trim().toLowerCase();
      if (key == null || key.isEmpty) continue;
      byKey.putIfAbsent(key, () => paper);
    }

    final numeric = BibliographyBuilder.isNumericStyle(style);
    final cited = <PaperModel>[]; // in order of first appearance
    final numbers = <String, int>{};
    final unresolved = <String>[];
    final unresolvedSeen = <String>{};
    var replacedCount = 0;

    final output = content.replaceAllMapped(_placeholder, (match) {
      final rawKey = match.group(1) ?? match.group(2)!;
      final key = rawKey.toLowerCase();
      final paper = byKey[key];
      if (paper == null) {
        if (unresolvedSeen.add(key)) unresolved.add(rawKey);
        return match.group(0)!; // leave the placeholder for the author to fix
      }

      final number = numbers.putIfAbsent(key, () {
        cited.add(paper);
        return cited.length;
      });
      replacedCount++;
      return numeric ? '[$number]' : inTextCitation(paper);
    });

    final buffer = StringBuffer(output);
    if (cited.isNotEmpty) {
      // The builder sorts author-date styles itself; numeric styles keep the
      // citation order we pass in.
      buffer
        ..write('\n\nReferences\n\n')
        ..write(_bibliographyBuilder.build(cited, style));
    }

    return ScanResult(
      output: buffer.toString(),
      unresolved: unresolved,
      replacedCount: replacedCount,
    );
  }

  /// The parenthetical form of a citation. The style classes only expose a
  /// full reference, so author-date in-text citations are rendered here.
  String inTextCitation(PaperModel paper) {
    final year = paper.year?.trim();
    final yearPart = (year == null || year.isEmpty) ? 'n.d.' : year;
    final authors = paper.authors;

    final String authorPart;
    if (authors.isEmpty) {
      authorPart = 'Anon.';
    } else if (authors.length == 1) {
      authorPart = authors.first.familyName;
    } else if (authors.length == 2) {
      authorPart = '${authors[0].familyName} & ${authors[1].familyName}';
    } else {
      authorPart = '${authors.first.familyName} et al.';
    }

    return '($authorPart, $yearPart)';
  }

  /// Where the formatted copy goes: `thesis.md` → `thesis-formatted.md`.
  /// Never overwrites the author's original.
  String extensionAwareOutputPath(String inputPath) {
    final extension = p.extension(inputPath);
    final stem = inputPath.substring(0, inputPath.length - extension.length);
    return '$stem-formatted$extension';
  }
}
