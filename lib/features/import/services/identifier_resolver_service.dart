import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/models/author_model.dart';
import '../../../core/models/paper_model.dart';
import 'crossref_service.dart';

/// The kinds of identifier [IdentifierResolverService] knows how to resolve.
enum IdentifierType { doi, arxiv, pmid, unknown }

/// Resolves a raw identifier string (DOI, arXiv id or PMID) into a
/// [PaperModel] by querying the matching public metadata API.
///
/// Every method is failure-tolerant: network errors, non-200 responses and
/// unparseable payloads all yield `null` (or a skipped entry) rather than an
/// exception, because these are driven directly by user paste input.
class IdentifierResolverService {
  static const _arxivApi = 'http://export.arxiv.org/api/query';
  static const _pubmedApi =
      'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi';
  static const _userAgent =
      'Papers/1.0 (reference manager; mailto:chimura.willian@gmail.com)';

  /// Politeness gap between consecutive requests in [resolveMany].
  static const _politenessDelay = Duration(milliseconds: 350);

  final http.Client _client;
  final CrossRefService _crossRef;

  IdentifierResolverService({http.Client? client})
      : _client = client ?? http.Client(),
        _crossRef = CrossRefService(client: client);

  // ---------------------------------------------------------------------------
  // Detection
  // ---------------------------------------------------------------------------

  static final _arxivPrefix = RegExp(
    r'^(arxiv:|https?://(www\.)?arxiv\.org/(abs|pdf)/)',
    caseSensitive: false,
  );
  static final _doiPattern = RegExp(r'10\.\d{4,}/\S+');
  static final _arxivModern = RegExp(r'^\d{4}\.\d{4,5}(v\d+)?$');
  static final _arxivLegacy = RegExp(r'^[a-z-]+(\.[A-Z]{2})?/\d{7}(v\d+)?$');
  static final _pmidPattern = RegExp(r'^\d{1,8}$');

  /// Classifies [raw] as a DOI, arXiv id, PMID, or unknown.
  IdentifierType detectType(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return IdentifierType.unknown;

    // An explicit arXiv prefix or URL always wins.
    if (_arxivPrefix.hasMatch(s)) return IdentifierType.arxiv;

    // DOIs: "10.NNNN/suffix", optionally wrapped in a doi.org URL or a
    // "doi:" prefix.
    if (_doiPattern.hasMatch(s)) return IdentifierType.doi;

    if (_arxivModern.hasMatch(s)) return IdentifierType.arxiv;
    if (_arxivLegacy.hasMatch(s)) return IdentifierType.arxiv;

    if (_pmidPattern.hasMatch(s)) return IdentifierType.pmid;

    return IdentifierType.unknown;
  }

  // ---------------------------------------------------------------------------
  // Resolution
  // ---------------------------------------------------------------------------

  /// Resolves a single identifier, dispatching on [detectType].
  ///
  /// Returns `null` when the type is unknown or the lookup fails.
  Future<PaperModel?> resolve(String raw) async {
    final s = raw.trim();
    switch (detectType(s)) {
      case IdentifierType.doi:
        return _resolveDoi(s);
      case IdentifierType.arxiv:
        return resolveArxiv(normalizeArxivId(s));
      case IdentifierType.pmid:
        return resolvePmid(s);
      case IdentifierType.unknown:
        return null;
    }
  }

  /// Resolves each entry of [raws] sequentially, pausing between network
  /// calls so we stay well inside every API's rate limit. Failures are
  /// skipped silently; successes keep their input order.
  Future<List<PaperModel>> resolveMany(Iterable<String> raws) async {
    final results = <PaperModel>[];
    var first = true;
    for (final raw in raws) {
      if (raw.trim().isEmpty) continue;
      if (!first) await Future<void>.delayed(_politenessDelay);
      first = false;
      try {
        final paper = await resolve(raw);
        if (paper != null) results.add(paper);
      } catch (_) {
        // Skip and keep going: one bad id must not abort a bulk paste.
      }
    }
    return results;
  }

  /// Splits a pasted blob into candidate identifiers.
  ///
  /// Accepts any mix of newlines, commas, semicolons and whitespace so users
  /// can paste a list straight out of a spreadsheet, email or reference list.
  List<String> splitIdentifiers(String blob) {
    return blob
        .split(RegExp(r'[\s,;]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ---------------------------------------------------------------------------
  // DOI
  // ---------------------------------------------------------------------------

  Future<PaperModel?> _resolveDoi(String raw) async {
    final match = _doiPattern.firstMatch(raw);
    if (match == null) return null;
    final doi = _trimTrailingPunctuation(match.group(0)!);
    try {
      return await _crossRef.fetchByDoi(doi);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // arXiv
  // ---------------------------------------------------------------------------

  /// Strips `arXiv:` prefixes, abs/pdf URLs and a trailing `.pdf` from [raw].
  String normalizeArxivId(String raw) {
    var s = raw.trim();
    s = s.replaceFirst(_arxivPrefix, '');
    if (s.toLowerCase().endsWith('.pdf')) {
      s = s.substring(0, s.length - 4);
    }
    return s.trim();
  }

  /// Fetches an arXiv entry through the export API (Atom XML).
  Future<PaperModel?> resolveArxiv(String id) async {
    if (id.isEmpty) return null;
    final uri = Uri.parse(_arxivApi).replace(queryParameters: {
      'id_list': id,
      'max_results': '1',
    });

    final http.Response response;
    try {
      response = await _client.get(uri, headers: {'User-Agent': _userAgent});
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;

    try {
      return _parseArxivAtom(response.body, id);
    } catch (_) {
      return null;
    }
  }

  static final _entryBlock =
      RegExp(r'<entry\b[^>]*>([\s\S]*?)</entry>', caseSensitive: false);

  PaperModel? _parseArxivAtom(String xml, String requestedId) {
    // The feed itself carries a <title>, so scope every field lookup to the
    // first <entry> block.
    final entry = _entryBlock.firstMatch(xml)?.group(1);
    if (entry == null) return null;

    // arXiv reports bad ids as an entry pointing at its error endpoint.
    final entryId = _firstTag(entry, 'id');
    if (entryId != null && entryId.contains('/api/errors')) return null;

    final title = _firstTag(entry, 'title');
    if (title == null || title.isEmpty) return null;

    final summary = _firstTag(entry, 'summary');
    final published = _firstTag(entry, 'published');
    final year = (published != null && published.length >= 4)
        ? published.substring(0, 4)
        : null;

    final authors = <AuthorModel>[];
    final authorMatches =
        RegExp(r'<author\b[^>]*>([\s\S]*?)</author>', caseSensitive: false)
            .allMatches(entry);
    for (final m in authorMatches) {
      final name = _firstTag(m.group(1)!, 'name');
      if (name != null && name.isNotEmpty) {
        authors.add(parseDisplayName(name));
      }
    }

    final doi = _firstTag(entry, 'arxiv:doi');
    final journalRef = _firstTag(entry, 'arxiv:journal_ref');

    // Prefer the canonical id the API echoed back, minus its version suffix.
    var arxivId = requestedId;
    if (entryId != null) {
      final fromEntry =
          RegExp(r'arxiv\.org/abs/(.+)$').firstMatch(entryId)?.group(1);
      if (fromEntry != null && fromEntry.isNotEmpty) arxivId = fromEntry;
    }

    final now = DateTime.now();
    return PaperModel(
      title: title,
      abstract_: summary,
      doi: doi,
      year: year,
      journal: journalRef,
      url: 'https://arxiv.org/abs/$arxivId',
      arxivId: arxivId,
      authors: authors,
      dateAdded: now,
      dateModified: now,
    );
  }

  // ---------------------------------------------------------------------------
  // PMID
  // ---------------------------------------------------------------------------

  /// Fetches a PubMed record through the E-utilities esummary endpoint.
  Future<PaperModel?> resolvePmid(String pmid) async {
    final id = pmid.trim();
    if (id.isEmpty) return null;
    final uri = Uri.parse(_pubmedApi).replace(queryParameters: {
      'db': 'pubmed',
      'id': id,
      'retmode': 'json',
    });

    final http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': _userAgent,
      });
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;

    try {
      return _parsePubmedSummary(response.body, id);
    } catch (_) {
      return null;
    }
  }

  PaperModel? _parsePubmedSummary(String body, String id) {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) return null;
    final result = json['result'];
    if (result is! Map<String, dynamic>) return null;
    final record = result[id];
    if (record is! Map<String, dynamic>) return null;
    // E-utilities reports misses in-band rather than with a 404.
    if (record['error'] != null) return null;

    final title = (record['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;

    final pubdate = record['pubdate'] as String?;
    final year = (pubdate != null && pubdate.length >= 4)
        ? pubdate.substring(0, 4)
        : null;

    final journal = _nonEmpty(record['fulljournalname'] as String?) ??
        _nonEmpty(record['source'] as String?);

    String? doi;
    final articleIds = record['articleids'];
    if (articleIds is List) {
      for (final entry in articleIds) {
        if (entry is Map && entry['idtype'] == 'doi') {
          doi = _nonEmpty(entry['value']?.toString());
          if (doi != null) break;
        }
      }
    }

    final authors = <AuthorModel>[];
    final authorList = record['authors'];
    if (authorList is List) {
      for (final entry in authorList) {
        if (entry is! Map) continue;
        final name = _nonEmpty(entry['name']?.toString());
        if (name != null) authors.add(parsePubmedAuthor(name));
      }
    }

    final now = DateTime.now();
    return PaperModel(
      title: _stripTrailingPeriod(title),
      doi: doi,
      year: year,
      journal: journal,
      volume: _nonEmpty(record['volume'] as String?),
      issue: _nonEmpty(record['issue'] as String?),
      pages: _nonEmpty(record['pages'] as String?),
      url: 'https://pubmed.ncbi.nlm.nih.gov/$id/',
      pmid: id,
      authors: authors,
      dateAdded: now,
      dateModified: now,
    );
  }

  // ---------------------------------------------------------------------------
  // Name parsing
  // ---------------------------------------------------------------------------

  /// Splits a "Given Middle Family" display name; the last token is the
  /// family name.
  static AuthorModel parseDisplayName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return AuthorModel(familyName: parts.first);
    return AuthorModel(
      givenName: parts.sublist(0, parts.length - 1).join(' '),
      familyName: parts.last,
    );
  }

  /// Splits PubMed's "Family AB" form, where the trailing token is a run of
  /// given-name initials. Collective names ("WHO Study Group") keep their
  /// whole string as the family name.
  static AuthorModel parsePubmedAuthor(String name) {
    final trimmed = name.trim();
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) return AuthorModel(familyName: trimmed);
    final last = parts.last;
    final looksLikeInitials =
        last.length <= 4 && RegExp(r'^[A-Z]+$').hasMatch(last);
    if (!looksLikeInitials) return AuthorModel(familyName: trimmed);
    return AuthorModel(
      givenName: last,
      familyName: parts.sublist(0, parts.length - 1).join(' '),
    );
  }

  // ---------------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------------

  /// Reads the text content of the first `<tag>` in [xml].
  ///
  /// arXiv's Atom output is machine-generated and we only pull a handful of
  /// leaf fields, so a regex is sufficient here.
  static String? _firstTag(String xml, String tag) {
    final escaped = RegExp.escape(tag);
    final match = RegExp('<$escaped\\b[^>]*>([\\s\\S]*?)</$escaped>',
            caseSensitive: false)
        .firstMatch(xml);
    if (match == null) return null;
    return _nonEmpty(_collapse(_unescapeXml(match.group(1)!)));
  }

  static String _unescapeXml(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');

  static String _collapse(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String? _nonEmpty(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  static String _stripTrailingPeriod(String s) =>
      s.endsWith('.') ? s.substring(0, s.length - 1) : s;

  static String _trimTrailingPunctuation(String s) =>
      s.replaceFirst(RegExp(r'[.,;:)\]}>\s]+$'), '');
}
