import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/models/author_model.dart';
import '../../../core/models/paper_model.dart';

class CrossRefService {
  static const _baseUrl = 'https://api.crossref.org/works';

  final http.Client _client;

  CrossRefService({http.Client? client}) : _client = client ?? http.Client();

  Future<PaperModel?> fetchByDoi(String doi) async {
    final cleanDoi = doi.trim().replaceFirst(RegExp(r'^https?://doi\.org/'), '');
    final uri = Uri.parse('$_baseUrl/$cleanDoi');

    final response = await _client.get(uri, headers: {
      'Accept': 'application/json',
      'User-Agent': 'Papers/1.0 (reference manager; mailto:chimura.willian@gmail.com)',
    });

    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final message = json['message'] as Map<String, dynamic>;
    return _parseCrossRefWork(message);
  }

  Future<List<PaperModel>> search(String query, {int rows = 20}) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'query': query,
      'rows': rows.toString(),
      'sort': 'relevance',
    });

    final response = await _client.get(uri, headers: {
      'Accept': 'application/json',
      'User-Agent': 'Papers/1.0 (reference manager; mailto:chimura.willian@gmail.com)',
    });

    if (response.statusCode != 200) return [];

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final message = json['message'] as Map<String, dynamic>;
    final items = message['items'] as List<dynamic>? ?? [];

    return items
        .map((item) => _parseCrossRefWork(item as Map<String, dynamic>))
        .toList();
  }

  PaperModel _parseCrossRefWork(Map<String, dynamic> work) {
    final now = DateTime.now();

    // Extract title
    final titles = work['title'] as List<dynamic>?;
    final title = titles?.firstOrNull as String? ?? 'Untitled';

    // Extract abstract
    final abstract_ = work['abstract'] as String?;

    // Extract DOI
    final doi = work['DOI'] as String?;

    // Extract year from date-parts
    String? year;
    final issued = work['issued'] as Map<String, dynamic>?;
    final dateParts = issued?['date-parts'] as List<dynamic>?;
    if (dateParts != null && dateParts.isNotEmpty) {
      final parts = dateParts.first as List<dynamic>;
      if (parts.isNotEmpty) year = parts.first.toString();
    }

    // Extract journal
    final containerTitle = work['container-title'] as List<dynamic>?;
    final journal = containerTitle?.firstOrNull as String?;

    // Extract volume, issue, pages
    final volume = work['volume'] as String?;
    final issue = work['issue'] as String?;
    final pages = work['page'] as String?;

    // Extract publisher
    final publisher = work['publisher'] as String?;

    // Extract URL
    final url = work['URL'] as String?;

    // Extract authors
    final authorList = work['author'] as List<dynamic>? ?? [];
    final authors = authorList.map((a) {
      final authorMap = a as Map<String, dynamic>;
      return AuthorModel(
        givenName: authorMap['given'] as String?,
        familyName: authorMap['family'] as String? ?? 'Unknown',
        orcid: authorMap['ORCID'] as String?,
      );
    }).toList();

    return PaperModel(
      title: title,
      abstract_: _cleanAbstract(abstract_),
      doi: doi,
      year: year,
      journal: journal,
      volume: volume,
      issue: issue,
      pages: pages,
      publisher: publisher,
      url: url,
      authors: authors,
      dateAdded: now,
      dateModified: now,
      cslJson: jsonEncode(work),
    );
  }

  String? _cleanAbstract(String? abstract_) {
    if (abstract_ == null) return null;
    // CrossRef abstracts often contain JATS XML tags
    return abstract_
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
