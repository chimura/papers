import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';

import '../../../core/models/paper_model.dart';
import 'crossref_service.dart';
import 'identifier_resolver_service.dart';

/// Extracts bibliographic metadata for a PDF.
///
/// [fromPdf] runs a three-stage cascade, cheapest and most reliable first:
///   1. embedded text of pages 1–2 → DOI / arXiv id → authoritative lookup;
///   2. raw-bytes XMP packet → `prism:doi` / `dc:title`;
///   3. a title guess from page 1 → CrossRef bibliographic search, accepted
///      only when the returned title is a near match.
///
/// Every stage is best-effort: a corrupt or image-only PDF simply yields
/// `null` so the caller can fall back to the filename.
class MetadataExtractor {
  /// Minimum Dice similarity between the guessed title and a CrossRef hit
  /// before we trust the match.
  static const double titleMatchThreshold = 0.8;

  final CrossRefService _crossRef;
  final IdentifierResolverService _resolver;

  MetadataExtractor({
    CrossRefService? crossRef,
    IdentifierResolverService? resolver,
    http.Client? client,
  })  : _crossRef = crossRef ?? CrossRefService(client: client),
        _resolver = resolver ?? IdentifierResolverService(client: client);

  /// Try to extract metadata from a DOI string.
  Future<PaperModel?> fromDoi(String doi) async {
    return _crossRef.fetchByDoi(doi);
  }

  /// Try to extract a DOI from a filename and look it up.
  Future<PaperModel?> fromFilename(String filename) async {
    final doi = _extractDoiFromFilename(filename);
    if (doi != null) {
      return _crossRef.fetchByDoi(doi);
    }
    return null;
  }

  /// Reads [path] and tries to identify the paper it contains.
  ///
  /// Returns `null` — never throws — when the file is missing, corrupt,
  /// image-only, or simply carries nothing we can resolve.
  Future<PaperModel?> fromPdf(String path) async {
    // --- Stage 1: embedded text of the first two pages ----------------------
    final text = await extractPdfText(path, maxPages: 2);
    if (text != null && text.trim().isNotEmpty) {
      final resolved = await _resolveFromText(text);
      if (resolved != null) return resolved;
    }

    // --- Stage 2: XMP metadata packet in the raw bytes ----------------------
    final xmp = await _readXmpPacket(path);
    String? xmpTitle;
    if (xmp != null) {
      final xmpDoi = extractXmpDoi(xmp);
      if (xmpDoi != null) {
        final paper = await _resolver.resolve(xmpDoi);
        if (paper != null) return paper;
      }
      xmpTitle = extractXmpTitle(xmp);
    }

    // --- Stage 3: title guess → CrossRef bibliographic search ---------------
    final guess = xmpTitle ?? (text == null ? null : guessTitle(text));
    if (guess != null) {
      final paper = await _searchByTitle(guess);
      if (paper != null) return paper;
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Stage 1 — PDF text
  // ---------------------------------------------------------------------------

  /// Extracts the embedded text of the first [maxPages] pages, headlessly.
  ///
  /// Returns `null` if the document cannot be opened or carries no text
  /// layer.
  @visibleForTesting
  static Future<String?> extractPdfText(String path, {int maxPages = 2}) async {
    PdfDocument? doc;
    try {
      await pdfrxFlutterInitialize();
      doc = await PdfDocument.openFile(path);
      final buffer = StringBuffer();
      final count = doc.pages.length < maxPages ? doc.pages.length : maxPages;
      for (var i = 0; i < count; i++) {
        final raw = await doc.pages[i].loadText();
        if (raw != null) {
          buffer.writeln(raw.fullText);
        }
      }
      final text = buffer.toString();
      return text.trim().isEmpty ? null : text;
    } catch (_) {
      // Corrupt, encrypted, missing, or pdfium unavailable — all non-fatal.
      return null;
    } finally {
      try {
        await doc?.dispose();
      } catch (_) {
        // Ignore: nothing useful to do if teardown fails.
      }
    }
  }

  Future<PaperModel?> _resolveFromText(String text) async {
    final doi = extractDoi(text);
    if (doi != null) {
      final paper = await _resolver.resolve(doi);
      if (paper != null) return paper;
    }

    final arxivId = extractArxivId(text);
    if (arxivId != null) {
      final paper = await _resolver.resolve('arXiv:$arxivId');
      if (paper != null) return paper;
    }

    return null;
  }

  static final _doiInText = RegExp(r'''10\.\d{4,}/[^\s"'<>,;]+''');
  static final _arxivInText = RegExp(
    r'arXiv:\s*(\d{4}\.\d{4,5})(v\d+)?',
    caseSensitive: false,
  );

  /// Finds the first DOI in [text], with trailing sentence punctuation
  /// removed (PDFs habitually print "doi:10.1234/x." at the end of a line).
  @visibleForTesting
  static String? extractDoi(String text) {
    final match = _doiInText.firstMatch(text);
    if (match == null) return null;
    final doi = match.group(0)!.replaceFirst(RegExp(r'[.,;:)\]}>]+$'), '');
    return doi.isEmpty ? null : doi;
  }

  /// Finds the first `arXiv:NNNN.NNNNN` id in [text] (version suffix dropped).
  @visibleForTesting
  static String? extractArxivId(String text) {
    return _arxivInText.firstMatch(text)?.group(1);
  }

  // ---------------------------------------------------------------------------
  // Stage 2 — XMP packet
  // ---------------------------------------------------------------------------

  /// Pulls the `<x:xmpmeta>…</x:xmpmeta>` block out of the raw file bytes.
  ///
  /// Decoded as latin1 so arbitrary binary stream data can never raise a
  /// UTF-8 decoding error; the XMP subset we read is ASCII anyway.
  Future<String?> _readXmpPacket(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return extractXmpPacket(latin1.decode(bytes, allowInvalid: true));
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static String? extractXmpPacket(String raw) {
    final start = raw.indexOf('<x:xmpmeta');
    if (start < 0) return null;
    const endTag = '</x:xmpmeta>';
    final end = raw.indexOf(endTag, start);
    if (end < 0) return null;
    return raw.substring(start, end + endTag.length);
  }

  static final _xmpTitle = RegExp(
    r'<dc:title>[\s\S]*?<rdf:li[^>]*>([\s\S]*?)</rdf:li>',
    caseSensitive: false,
  );
  static final _prismDoiAttr = RegExp(
    r'''prism:doi\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  );
  static final _prismDoiTag = RegExp(
    r'<prism:doi>([\s\S]*?)</prism:doi>',
    caseSensitive: false,
  );

  /// Reads `dc:title` (the first `rdf:li` alternative) from an XMP packet.
  @visibleForTesting
  static String? extractXmpTitle(String xmp) {
    final match = _xmpTitle.firstMatch(xmp);
    if (match == null) return null;
    return _clean(match.group(1)!);
  }

  /// Reads `prism:doi`, written either as an attribute or an element.
  @visibleForTesting
  static String? extractXmpDoi(String xmp) {
    final attr = _prismDoiAttr.firstMatch(xmp)?.group(1);
    final tag = _prismDoiTag.firstMatch(xmp)?.group(1);
    return _clean(attr ?? tag ?? '');
  }

  // ---------------------------------------------------------------------------
  // Stage 3 — title guess + CrossRef search
  // ---------------------------------------------------------------------------

  static final _boilerplate = RegExp(
    r'(downloaded from|all rights reserved|creative commons|https?://|'
    r'\bdoi\s*:|\barxiv\s*:|\bissn\b|\bisbn\b|©|copyright|'
    r'this article|licensed under|see discussions|preprint)',
    caseSensitive: false,
  );

  /// Picks the most plausible title line from page-1 text: the first
  /// reasonably long line that is not journal/copyright boilerplate and is
  /// not set in all caps (running heads and journal banners usually are).
  @visibleForTesting
  static String? guessTitle(String text) {
    for (final rawLine in const LineSplitter().convert(text)) {
      final line = _clean(rawLine);
      if (line == null || line.length <= 20) continue;
      if (_boilerplate.hasMatch(line)) continue;
      if (_isAllCaps(line)) continue;
      // Needs to read like a sentence, not a data row.
      final letters = line.replaceAll(RegExp(r'[^A-Za-z]'), '').length;
      if (letters < line.length * 0.6) continue;
      return line;
    }
    return null;
  }

  static bool _isAllCaps(String s) {
    final letters = s.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.length < 4) return false;
    final upper = letters.replaceAll(RegExp(r'[^A-Z]'), '').length;
    return upper / letters.length > 0.8;
  }

  Future<PaperModel?> _searchByTitle(String title) async {
    List<PaperModel> hits;
    try {
      hits = await _crossRef.search(title, rows: 5);
    } catch (_) {
      return null;
    }

    PaperModel? best;
    var bestScore = 0.0;
    for (final hit in hits) {
      final score = diceSimilarity(title, hit.title);
      if (score > bestScore) {
        bestScore = score;
        best = hit;
      }
    }
    return bestScore >= titleMatchThreshold ? best : null;
  }

  // ---------------------------------------------------------------------------
  // Similarity
  // ---------------------------------------------------------------------------

  /// Sørensen–Dice coefficient over character bigrams of the normalized
  /// strings, in 0.0–1.0. Kept local so we don't take a package dependency
  /// for twenty lines of arithmetic.
  @visibleForTesting
  static double diceSimilarity(String a, String b) {
    final x = _normalizeForCompare(a);
    final y = _normalizeForCompare(b);
    if (x.isEmpty || y.isEmpty) return 0.0;
    if (x == y) return 1.0;
    if (x.length < 2 || y.length < 2) return 0.0;

    final counts = <String, int>{};
    for (var i = 0; i < x.length - 1; i++) {
      final bigram = x.substring(i, i + 2);
      counts[bigram] = (counts[bigram] ?? 0) + 1;
    }

    var shared = 0;
    for (var i = 0; i < y.length - 1; i++) {
      final bigram = y.substring(i, i + 2);
      final remaining = counts[bigram] ?? 0;
      if (remaining > 0) {
        counts[bigram] = remaining - 1;
        shared++;
      }
    }

    return (2 * shared) / ((x.length - 1) + (y.length - 1));
  }

  static String _normalizeForCompare(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  static String? _clean(String s) {
    final t = s
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t.isEmpty ? null : t;
  }

  String? _extractDoiFromFilename(String filename) {
    // Common DOI pattern: 10.xxxx/xxxxx
    final doiPattern = RegExp(r'10\.\d{4,}/[^\s]+');
    final match = doiPattern.firstMatch(filename);
    return match?.group(0);
  }
}
