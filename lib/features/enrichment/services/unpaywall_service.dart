import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class UnpaywallService {
  static const _baseUrl = 'https://api.unpaywall.org/v2';
  static const _email = 'chimura.willian@gmail.com';

  final http.Client _client;

  UnpaywallService({http.Client? client}) : _client = client ?? http.Client();

  /// Looks up an open-access PDF URL for [doi] via the Unpaywall API.
  ///
  /// Returns null when the DOI is unknown, no OA location with a PDF exists,
  /// or the response cannot be parsed.
  Future<String?> findOaPdfUrl(String doi) async {
    final cleanDoi = doi.trim().replaceFirst(RegExp(r'^https?://doi\.org/'), '');
    final uri = Uri.parse('$_baseUrl/$cleanDoi').replace(queryParameters: {
      'email': _email,
    });

    final http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': 'Papers/1.0 (reference manager; mailto:$_email)',
      });
    } catch (_) {
      return null;
    }

    if (response.statusCode != 200) return null;

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;

      final bestLocation = json['best_oa_location'] as Map<String, dynamic>?;
      final bestPdfUrl = bestLocation?['url_for_pdf'] as String?;
      if (bestPdfUrl != null) return bestPdfUrl;

      final locations = json['oa_locations'] as List<dynamic>? ?? [];
      for (final location in locations) {
        final pdfUrl =
            (location as Map<String, dynamic>)['url_for_pdf'] as String?;
        if (pdfUrl != null) return pdfUrl;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  /// Downloads [url] to [savePath], verifying the body is actually a PDF by
  /// checking the `%PDF-` magic bytes (Content-Type headers can lie).
  ///
  /// Returns false on any failure; a partially written file is deleted.
  Future<bool> downloadPdf({
    required String url,
    required String savePath,
  }) async {
    final file = File(savePath);
    try {
      final response = await _client.get(Uri.parse(url), headers: {
        'User-Agent': 'Papers/1.0 (reference manager; mailto:$_email)',
      });

      if (response.statusCode != 200) return false;
      if (!_hasPdfMagicBytes(response.bodyBytes)) return false;

      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return true;
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Ignore cleanup failures.
      }
      return false;
    }
  }

  /// Finds an open-access PDF for [doi] and downloads it to [savePath].
  Future<bool> fetchOaPdf({
    required String doi,
    required String savePath,
  }) async {
    final url = await findOaPdfUrl(doi);
    if (url == null) return false;
    return downloadPdf(url: url, savePath: savePath);
  }

  bool _hasPdfMagicBytes(List<int> bytes) {
    const magic = [0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }
}
