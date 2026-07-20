import 'dart:convert';

import 'package:http/http.dart' as http;

/// A CrossRef update notice pointing at one of our papers.
///
/// [noticeDoi] is the DOI of the *notice itself* (the retraction/correction
/// record), not of the paper it applies to — it is what the "read the notice"
/// link in the banner resolves.
class RetractionNotice {
  final String type;
  final String? noticeDoi;
  final String label;

  const RetractionNotice({
    required this.type,
    required this.noticeDoi,
    required this.label,
  });

  /// Retractions and expressions of concern warrant a red banner; a correction
  /// is informational.
  bool get isSerious =>
      type == 'retraction' || type == 'expression_of_concern';

  @override
  String toString() => 'RetractionNotice($type, $noticeDoi, $label)';
}

/// Checks the library against CrossRef's update graph for retractions,
/// expressions of concern and corrections, and reads preprint→published
/// relations out of already-stored CSL JSON.
///
/// Designed to be run from the auto-sync timer, so every network path fails
/// soft: a dead API means "no notices found", never an exception.
class RetractionService {
  static const _baseUrl = 'https://api.crossref.org/works';
  static const _email = 'chimura.willian@gmail.com';
  static const _userAgent =
      'Papers/1.0 (reference manager; mailto:$_email)';

  /// CrossRef rejects very long filter strings; 20 DOIs keeps the URL well
  /// inside limits while still covering a typical library in a few calls.
  static const _batchSize = 20;

  /// Update types worth surfacing to the user. CrossRef defines many more
  /// (`new_version`, `addendum`, …) that would only be noise in the library.
  static const _interestingTypes = {
    'retraction',
    'expression_of_concern',
    'correction',
  };

  static const _labels = {
    'retraction': 'Retracted',
    'expression_of_concern': 'Expression of concern',
    'correction': 'Correction issued',
  };

  final http.Client _client;

  RetractionService({http.Client? client}) : _client = client ?? http.Client();

  /// Looks up update notices for [dois], batching [_batchSize] per request.
  ///
  /// The query returns *notice* works; each one's `update-to` array names the
  /// papers it applies to, so results are keyed by the affected paper's DOI
  /// (lowercased). DOIs with no notices are simply absent from the map.
  ///
  /// Never throws — failed batches are skipped and the rest still report.
  Future<Map<String, RetractionNotice>> checkDois(List<String> dois) async {
    final results = <String, RetractionNotice>{};

    final cleaned = <String>[];
    final wanted = <String>{};
    for (final doi in dois) {
      final clean = _cleanDoi(doi);
      if (clean.isEmpty) continue;
      if (wanted.add(clean.toLowerCase())) cleaned.add(clean);
    }
    if (cleaned.isEmpty) return results;

    for (var start = 0; start < cleaned.length; start += _batchSize) {
      final end = (start + _batchSize).clamp(0, cleaned.length);
      final chunk = cleaned.sublist(start, end);

      final filter = chunk.map((doi) => 'updates:$doi').join(',');
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'filter': filter,
        'rows': '100',
        'mailto': _email,
      });

      final http.Response response;
      try {
        response = await _client.get(uri, headers: {
          'Accept': 'application/json',
          'User-Agent': _userAgent,
        });
      } catch (_) {
        continue;
      }

      if (response.statusCode != 200) continue;

      try {
        _collectNotices(response.body, wanted, results);
      } catch (_) {
        continue;
      }
    }

    return results;
  }

  /// Reads `relation['is-preprint-of'][0]['id']` out of a stored CrossRef CSL
  /// JSON object string — the hook for "a published version of this preprint
  /// is available".
  ///
  /// Returns null for absent, malformed, or unrelated JSON.
  String? publishedVersionDoiFrom(String? cslJson) {
    if (cslJson == null || cslJson.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(cslJson);
      if (decoded is! Map<String, dynamic>) return null;

      final relation = decoded['relation'];
      if (relation is! Map<String, dynamic>) return null;

      final preprintOf = relation['is-preprint-of'];
      if (preprintOf is! List || preprintOf.isEmpty) return null;

      final first = preprintOf.first;
      if (first is! Map<String, dynamic>) return null;

      final id = first['id'];
      if (id is! String || id.trim().isEmpty) return null;

      return id.trim();
    } catch (_) {
      return null;
    }
  }

  // --- internals ------------------------------------------------------------

  void _collectNotices(
    String body,
    Set<String> wanted,
    Map<String, RetractionNotice> results,
  ) {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) return;

    final message = json['message'];
    if (message is! Map<String, dynamic>) return;

    final items = message['items'] as List<dynamic>? ?? [];

    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;

      final noticeDoi = item['DOI'] as String?;
      final updateTo = item['update-to'] as List<dynamic>? ?? [];

      for (final entry in updateTo) {
        if (entry is! Map<String, dynamic>) continue;

        final targetDoi = (entry['DOI'] as String?)?.trim().toLowerCase();
        if (targetDoi == null || !wanted.contains(targetDoi)) continue;

        final type = (entry['type'] as String?)?.trim();
        if (type == null || !_interestingTypes.contains(type)) continue;

        final notice = RetractionNotice(
          type: type,
          noticeDoi: noticeDoi,
          label: _labels[type] ?? 'Update issued',
        );

        // A paper can carry both a correction and a retraction; the more
        // serious notice is the one the user needs to see.
        final existing = results[targetDoi];
        if (existing == null || (!existing.isSerious && notice.isSerious)) {
          results[targetDoi] = notice;
        }
      }
    }
  }

  String _cleanDoi(String doi) =>
      doi.trim().replaceFirst(RegExp(r'^https?://(dx\.)?doi\.org/'), '');
}
