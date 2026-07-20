import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/models/author_model.dart';
import '../../../core/models/paper_model.dart';

/// A single field-level difference produced by [EnrichmentService.diff], so the
/// UI can present an accept/reject list instead of a blind overwrite.
class FieldChange {
  final String field;
  final String? oldValue;
  final String? newValue;

  const FieldChange({
    required this.field,
    required this.oldValue,
    required this.newValue,
  });

  @override
  String toString() => 'FieldChange($field: $oldValue -> $newValue)';

  @override
  bool operator ==(Object other) =>
      other is FieldChange &&
      other.field == field &&
      other.oldValue == oldValue &&
      other.newValue == newValue;

  @override
  int get hashCode => Object.hash(field, oldValue, newValue);
}

/// Metadata Doctor: fills missing abstract / DOI / journal / year for papers
/// that were imported from a filename, a bare PDF, or a sparse `.bib` entry.
///
/// Two complementary sources:
///  * CrossRef `query.bibliographic` title search, gated by a Dice bigram
///    similarity check so a fuzzy search hit can never silently replace a
///    paper with a different one.
///  * The Semantic Scholar batch endpoint, which resolves up to 100 DOIs per
///    request and cross-links DOI / arXiv / PubMed identifiers.
///
/// Nothing here mutates the library: [mergeEnrichment] returns a copy and
/// [diff] describes what changed, leaving the accept/reject decision to the UI.
class EnrichmentService {
  static const _crossRefUrl = 'https://api.crossref.org/works';
  static const _semanticScholarBatchUrl =
      'https://api.semanticscholar.org/graph/v1/paper/batch';
  static const _email = 'chimura.willian@gmail.com';
  static const _userAgent =
      'Papers/1.0 (reference manager; mailto:$_email)';

  /// Semantic Scholar accepts up to 500 ids, but responses get unwieldy; 100
  /// keeps each request small enough to retry cheaply.
  static const _batchSize = 100;

  /// Minimum Dice bigram similarity for a CrossRef title hit to be accepted.
  static const _titleMatchThreshold = 0.9;

  final http.Client _client;

  EnrichmentService({http.Client? client}) : _client = client ?? http.Client();

  /// True when the paper is missing any of the four fields the Metadata Doctor
  /// knows how to fill.
  bool isIncomplete(PaperModel p) =>
      _isBlank(p.abstract_) ||
      _isBlank(p.doi) ||
      _isBlank(p.journal) ||
      _isBlank(p.year);

  /// Searches CrossRef for [title] and returns the best candidate whose
  /// normalized title is at least [_titleMatchThreshold] similar to the query.
  ///
  /// Passing [firstAuthorFamily] narrows the search but is not used for
  /// acceptance — the title similarity gate is the only thing that can admit a
  /// candidate. Returns null when nothing clears the bar. Never throws.
  Future<PaperModel?> findByTitle(
    String title, {
    String? firstAuthorFamily,
  }) async {
    final query = title.trim();
    if (query.isEmpty) return null;

    final uri = Uri.parse(_crossRefUrl).replace(queryParameters: {
      'query.bibliographic': query,
      'rows': '3',
      if (firstAuthorFamily != null && firstAuthorFamily.trim().isNotEmpty)
        'query.author': firstAuthorFamily.trim(),
      'mailto': _email,
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
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final message = json['message'] as Map<String, dynamic>?;
      final items = message?['items'] as List<dynamic>? ?? [];

      final target = _normalize(query);
      PaperModel? best;
      var bestScore = 0.0;

      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final candidate = _parseCrossRefWork(item);
        final score = _diceSimilarity(target, _normalize(candidate.title));
        if (score >= _titleMatchThreshold && score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }

      return best;
    } catch (_) {
      return null;
    }
  }

  /// Resolves [dois] through the Semantic Scholar batch endpoint.
  ///
  /// The API answers with a JSON array positionally aligned to the request's
  /// `ids`, using null for unknown papers — so results are keyed back to the
  /// *input* DOI (lowercased) rather than whatever DOI the response carries.
  ///
  /// Requests are chunked at [_batchSize]. Never throws: on a transport error
  /// or a non-200 response the chunks resolved so far are returned as-is.
  Future<Map<String, Map<String, dynamic>>> fetchBatchByDoi(
    List<String> dois,
  ) async {
    final results = <String, Map<String, dynamic>>{};

    final cleaned = <String>[];
    for (final doi in dois) {
      final clean = _cleanDoi(doi);
      if (clean.isNotEmpty) cleaned.add(clean);
    }
    if (cleaned.isEmpty) return results;

    final uri = Uri.parse(_semanticScholarBatchUrl).replace(queryParameters: {
      'fields': 'title,abstract,year,venue,externalIds,openAccessPdf',
    });

    for (var start = 0; start < cleaned.length; start += _batchSize) {
      final end = (start + _batchSize).clamp(0, cleaned.length);
      final chunk = cleaned.sublist(start, end);

      final http.Response response;
      try {
        response = await _client.post(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'User-Agent': _userAgent,
          },
          body: jsonEncode({
            'ids': [for (final doi in chunk) 'DOI:$doi'],
          }),
        );
      } catch (_) {
        return results;
      }

      if (response.statusCode != 200) return results;

      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! List) return results;

        for (var i = 0; i < chunk.length && i < decoded.length; i++) {
          final entry = decoded[i];
          if (entry is Map<String, dynamic>) {
            results[chunk[i].toLowerCase()] = entry;
          }
        }
      } catch (_) {
        return results;
      }
    }

    return results;
  }

  /// Returns a copy of [original] with blank fields filled from [crossref]
  /// and/or a [semanticScholar] batch entry.
  ///
  /// Existing user data is never overwritten — only null or whitespace-only
  /// fields are touched. CrossRef wins ties because its records are the ones
  /// the citation formatter and BibTeX export are modelled on.
  PaperModel mergeEnrichment(
    PaperModel original, {
    PaperModel? crossref,
    Map<String, dynamic>? semanticScholar,
  }) {
    final ss = semanticScholar;
    final externalIds = ss?['externalIds'] as Map<String, dynamic>?;

    String? ssYear;
    final rawYear = ss?['year'];
    if (rawYear is int) {
      ssYear = rawYear.toString();
    } else if (rawYear is String && rawYear.trim().isNotEmpty) {
      ssYear = rawYear.trim();
    }

    var merged = original.copyWith(
      abstract_: _fill(
        original.abstract_,
        [crossref?.abstract_, ss?['abstract'] as String?],
      ),
      doi: _fill(
        original.doi,
        [crossref?.doi, externalIds?['DOI'] as String?],
      ),
      year: _fill(original.year, [crossref?.year, ssYear]),
      journal: _fill(
        original.journal,
        [crossref?.journal, ss?['venue'] as String?],
      ),
      volume: _fill(original.volume, [crossref?.volume]),
      issue: _fill(original.issue, [crossref?.issue]),
      pages: _fill(original.pages, [crossref?.pages]),
      publisher: _fill(original.publisher, [crossref?.publisher]),
      url: _fill(original.url, [crossref?.url]),
      arxivId: _fill(
        original.arxivId,
        [crossref?.arxivId, _asString(externalIds?['ArXiv'])],
      ),
      pmid: _fill(
        original.pmid,
        [crossref?.pmid, _asString(externalIds?['PubMed'])],
      ),
      cslJson: _fill(original.cslJson, [crossref?.cslJson]),
    );

    // Only adopt authors wholesale when we have none; a partial author list is
    // still user data and merging two orderings would corrupt citations.
    if (merged.authors.isEmpty &&
        crossref != null &&
        crossref.authors.isNotEmpty) {
      merged = merged.copyWith(authors: crossref.authors);
    }

    return merged;
  }

  /// Field-by-field description of what enrichment changed, for the
  /// accept/reject dialog.
  List<FieldChange> diff(PaperModel before, PaperModel after) {
    final changes = <FieldChange>[];

    void compare(String field, String? oldValue, String? newValue) {
      if (oldValue == newValue) return;
      changes.add(
        FieldChange(field: field, oldValue: oldValue, newValue: newValue),
      );
    }

    compare('title', before.title, after.title);
    compare('abstract', before.abstract_, after.abstract_);
    compare('doi', before.doi, after.doi);
    compare('year', before.year, after.year);
    compare('journal', before.journal, after.journal);
    compare('volume', before.volume, after.volume);
    compare('issue', before.issue, after.issue);
    compare('pages', before.pages, after.pages);
    compare('publisher', before.publisher, after.publisher);
    compare('url', before.url, after.url);
    compare('arxivId', before.arxivId, after.arxivId);
    compare('pmid', before.pmid, after.pmid);
    compare(
      'authors',
      before.authors.isEmpty ? null : _authorsLabel(before.authors),
      after.authors.isEmpty ? null : _authorsLabel(after.authors),
    );

    return changes;
  }

  // --- internals ------------------------------------------------------------

  String _authorsLabel(List<AuthorModel> authors) =>
      authors.map((a) => a.displayName).join(', ');

  /// Returns the first non-blank candidate when [current] is blank, else null
  /// so `copyWith` leaves the existing value alone.
  String? _fill(String? current, List<String?> candidates) {
    if (!_isBlank(current)) return null;
    for (final candidate in candidates) {
      if (!_isBlank(candidate)) return candidate!.trim();
    }
    return null;
  }

  String? _asString(Object? value) => value?.toString();

  bool _isBlank(String? value) => value == null || value.trim().isEmpty;

  String _cleanDoi(String doi) =>
      doi.trim().replaceFirst(RegExp(r'^https?://(dx\.)?doi\.org/'), '');

  /// Lowercase, drop non-alphanumerics, collapse whitespace. Mirrors
  /// [PaperModel.normalizedTitle] so scores are comparable across the app.
  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Sørensen–Dice coefficient over character bigrams, multiset-aware so a
  /// repeated bigram cannot be matched twice.
  double _diceSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    if (a == b) return 1.0;
    if (a.length < 2 || b.length < 2) return 0.0;

    final counts = <String, int>{};
    for (var i = 0; i < a.length - 1; i++) {
      final bigram = a.substring(i, i + 2);
      counts[bigram] = (counts[bigram] ?? 0) + 1;
    }

    var intersection = 0;
    for (var i = 0; i < b.length - 1; i++) {
      final bigram = b.substring(i, i + 2);
      final remaining = counts[bigram] ?? 0;
      if (remaining > 0) {
        counts[bigram] = remaining - 1;
        intersection++;
      }
    }

    return (2 * intersection) / ((a.length - 1) + (b.length - 1));
  }

  PaperModel _parseCrossRefWork(Map<String, dynamic> work) {
    final now = DateTime.now();

    final titles = work['title'] as List<dynamic>?;
    final title =
        (titles != null && titles.isNotEmpty) ? titles.first as String : 'Untitled';

    String? year;
    final issued = work['issued'] as Map<String, dynamic>?;
    final dateParts = issued?['date-parts'] as List<dynamic>?;
    if (dateParts != null && dateParts.isNotEmpty) {
      final parts = dateParts.first as List<dynamic>;
      if (parts.isNotEmpty) year = parts.first.toString();
    }

    final containerTitle = work['container-title'] as List<dynamic>?;
    final journal = (containerTitle != null && containerTitle.isNotEmpty)
        ? containerTitle.first as String?
        : null;

    final authorList = work['author'] as List<dynamic>? ?? [];
    final authors = authorList
        .whereType<Map<String, dynamic>>()
        .map((a) => AuthorModel(
              givenName: a['given'] as String?,
              familyName: a['family'] as String? ?? 'Unknown',
              orcid: a['ORCID'] as String?,
            ))
        .toList();

    return PaperModel(
      title: title,
      abstract_: _cleanAbstract(work['abstract'] as String?),
      doi: work['DOI'] as String?,
      year: year,
      journal: journal,
      volume: work['volume'] as String?,
      issue: work['issue'] as String?,
      pages: work['page'] as String?,
      publisher: work['publisher'] as String?,
      url: work['URL'] as String?,
      authors: authors,
      dateAdded: now,
      dateModified: now,
      cslJson: jsonEncode(work),
    );
  }

  String? _cleanAbstract(String? abstract_) {
    if (abstract_ == null) return null;
    // CrossRef abstracts arrive wrapped in JATS XML tags.
    final cleaned = abstract_
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}
