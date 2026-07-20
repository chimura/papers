import '../../../core/models/author_model.dart';
import '../../../core/models/paper_model.dart';
import 'attachment_path_parser.dart';

class RisParserService {
  /// Matches a RIS tag line: two-character tag, two spaces, hyphen, space.
  /// The trailing space is optional so bare `ER  -` lines are recognized too.
  static final _tagPattern = RegExp(r'^([A-Z][A-Z0-9])  - ?(.*)$');

  List<PaperModel> parse(String content) {
    final records = _splitRecords(content);
    return records.map(_parseRecord).whereType<PaperModel>().toList();
  }

  /// Splits the input into records of ordered (tag, value) pairs.
  ///
  /// A record starts at a `TY` line and ends at `ER` (or at end of input).
  /// Content before the first `TY` is skipped. Lines that don't match the
  /// tag pattern are continuations of the previous value — Zotero wraps
  /// long abstracts this way.
  List<List<MapEntry<String, String>>> _splitRecords(String content) {
    final records = <List<MapEntry<String, String>>>[];
    List<MapEntry<String, String>>? current;

    for (final line in content.split(RegExp(r'\r?\n'))) {
      final match = _tagPattern.firstMatch(line);
      if (match != null) {
        final tag = match.group(1)!;
        final value = match.group(2)!.trim();
        switch (tag) {
          case 'TY':
            current = <MapEntry<String, String>>[];
            records.add(current);
          case 'ER':
            current = null;
          default:
            current?.add(MapEntry(tag, value));
        }
      } else if (current != null &&
          current.isNotEmpty &&
          line.trim().isNotEmpty) {
        final last = current.removeLast();
        current.add(MapEntry(last.key, '${last.value} ${line.trim()}'.trim()));
      }
    }

    return records;
  }

  PaperModel? _parseRecord(List<MapEntry<String, String>> fields) {
    String? title;
    String? year;
    String? journal;
    String? volume;
    String? issue;
    String? startPage;
    String? endPage;
    String? doi;
    String? url;
    String? publisher;
    String? abstract_;
    String? fileLink;
    final authors = <AuthorModel>[];
    final tags = <String>[];

    for (final field in fields) {
      final value = field.value;
      if (value.isEmpty) continue;

      switch (field.key) {
        case 'TI' || 'T1':
          title ??= value;
        case 'AU' || 'A1' || 'A2':
          authors.add(_parseAuthor(value));
        case 'PY' || 'Y1':
          year ??= _parseYear(value);
        case 'JO' || 'JF' || 'T2':
          journal ??= value;
        case 'VL':
          volume ??= value;
        case 'IS':
          issue ??= value;
        case 'SP':
          startPage ??= value;
        case 'EP':
          endPage ??= value;
        case 'DO':
          doi ??= _cleanDoi(value);
        case 'UR':
          url ??= value;
        case 'PB':
          publisher ??= value;
        case 'AB' || 'N2':
          abstract_ ??= value;
        case 'L1' || 'LK':
          // Link to the local PDF (first PDF-looking link wins).
          fileLink ??= AttachmentPathParser.fromRisLink(value);
        case 'KW':
          tags.add(value);
        default:
          // Unknown tag: ignore.
          break;
      }
    }

    final now = DateTime.now();

    return PaperModel(
      importedFilePath: fileLink,
      title: title ?? 'Untitled',
      abstract_: abstract_,
      doi: doi,
      year: year,
      journal: journal,
      volume: volume,
      issue: issue,
      pages: _combinePages(startPage, endPage),
      publisher: publisher,
      url: url,
      authors: authors,
      tags: tags,
      dateAdded: now,
      dateModified: now,
    );
  }

  AuthorModel _parseAuthor(String name) {
    final trimmed = name.trim();
    if (trimmed.contains(',')) {
      // "Family, Given" format
      final parts = trimmed.split(',').map((s) => s.trim()).toList();
      return AuthorModel(
        familyName: parts[0],
        givenName: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null,
      );
    } else {
      // "Given Family" format
      final parts = trimmed.split(RegExp(r'\s+')).toList();
      if (parts.length == 1) {
        return AuthorModel(familyName: parts[0]);
      }
      return AuthorModel(
        givenName: parts.sublist(0, parts.length - 1).join(' '),
        familyName: parts.last,
      );
    }
  }

  /// Extracts the leading 4-digit year from values like "2020",
  /// "2020/01/15" or "2020///".
  String? _parseYear(String value) {
    return RegExp(r'^\d{4}').firstMatch(value)?.group(0);
  }

  String _cleanDoi(String value) {
    return value.replaceFirst(
      RegExp(r'^https?://(?:dx\.)?doi\.org/', caseSensitive: false),
      '',
    );
  }

  String? _combinePages(String? startPage, String? endPage) {
    if (startPage == null) return null;
    if (endPage == null) return startPage;
    return '$startPage-$endPage';
  }
}
