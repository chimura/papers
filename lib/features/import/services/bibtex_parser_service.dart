import '../../../core/models/author_model.dart';
import '../../../core/models/paper_model.dart';
import 'attachment_path_parser.dart';

class BibtexParserService {
  List<PaperModel> parse(String bibtex) {
    final entries = _splitEntries(bibtex);
    return entries.map(_parseEntry).whereType<PaperModel>().toList();
  }

  List<String> _splitEntries(String bibtex) {
    final entries = <String>[];
    final pattern = RegExp(r'@\w+\s*\{', multiLine: true);
    final matches = pattern.allMatches(bibtex).toList();

    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end = i + 1 < matches.length ? matches[i + 1].start : bibtex.length;
      entries.add(bibtex.substring(start, end).trim());
    }

    return entries;
  }

  PaperModel? _parseEntry(String entry) {
    // Extract entry type and key
    final headerMatch = RegExp(r'@(\w+)\s*\{\s*([^,]*),').firstMatch(entry);
    if (headerMatch == null) return null;

    final bibtexKey = headerMatch.group(2)?.trim();
    final fields = _parseFields(entry.substring(headerMatch.end));

    // The raw `file` value carries linked PDF paths (Zotero/Mendeley/JabRef).
    final fileField = fields['file'];
    final pdfPaths = fileField != null
        ? AttachmentPathParser.fromBibtexFileField(fileField)
        : const <String>[];

    final now = DateTime.now();

    return PaperModel(
      importedFilePath: pdfPaths.isNotEmpty ? pdfPaths.first : null,
      title: _cleanValue(fields['title'] ?? 'Untitled'),
      abstract_: fields['abstract'] != null ? _cleanValue(fields['abstract']!) : null,
      doi: fields['doi'] != null ? _cleanValue(fields['doi']!) : null,
      year: fields['year'] != null ? _cleanValue(fields['year']!) : null,
      journal: fields['journal'] != null ? _cleanValue(fields['journal']!) : null,
      volume: fields['volume'] != null ? _cleanValue(fields['volume']!) : null,
      issue: fields['number'] != null ? _cleanValue(fields['number']!) : null,
      pages: fields['pages'] != null ? _cleanValue(fields['pages']!) : null,
      publisher: fields['publisher'] != null ? _cleanValue(fields['publisher']!) : null,
      url: fields['url'] != null ? _cleanValue(fields['url']!) : null,
      authors: _parseAuthors(fields['author']),
      bibtexKey: bibtexKey,
      dateAdded: now,
      dateModified: now,
    );
  }

  Map<String, String> _parseFields(String body) {
    final fields = <String, String>{};
    // Match field = {value} or field = "value" or field = number
    final pattern = RegExp(
      r'(\w+)\s*=\s*(?:\{((?:[^{}]|\{[^{}]*\})*)\}|"([^"]*)"|(\d+))',
      multiLine: true,
    );

    for (final match in pattern.allMatches(body)) {
      final key = match.group(1)!.toLowerCase();
      final value = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
      fields[key] = value;
    }

    return fields;
  }

  List<AuthorModel> _parseAuthors(String? authorField) {
    if (authorField == null || authorField.isEmpty) return [];

    return authorField.split(' and ').map((name) {
      final trimmed = _cleanValue(name.trim());
      if (trimmed.contains(',')) {
        // "Last, First" format
        final parts = trimmed.split(',').map((s) => s.trim()).toList();
        return AuthorModel(
          familyName: parts[0],
          givenName: parts.length > 1 ? parts[1] : null,
        );
      } else {
        // "First Last" format
        final parts = trimmed.split(RegExp(r'\s+')).toList();
        if (parts.length == 1) {
          return AuthorModel(familyName: parts[0]);
        }
        return AuthorModel(
          givenName: parts.sublist(0, parts.length - 1).join(' '),
          familyName: parts.last,
        );
      }
    }).toList();
  }

  String _cleanValue(String value) {
    return value
        .replaceAll(RegExp(r'[{}]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
