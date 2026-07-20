import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papers/features/enrichment/services/unpaywall_service.dart';

void main() {
  group('findOaPdfUrl', () {
    test('returns url_for_pdf from best_oa_location', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'api.unpaywall.org');
        expect(request.url.path, '/v2/10.1234/example');
        expect(
            request.url.queryParameters['email'], 'chimura.willian@gmail.com');
        return http.Response(
          jsonEncode({
            'best_oa_location': {
              'url_for_pdf': 'https://example.org/best.pdf',
            },
            'oa_locations': [
              {'url_for_pdf': 'https://example.org/other.pdf'},
            ],
          }),
          200,
        );
      });

      final service = UnpaywallService(client: client);
      final url = await service.findOaPdfUrl('https://doi.org/10.1234/example');
      expect(url, 'https://example.org/best.pdf');
    });

    test('falls back to scanning oa_locations when best has no pdf', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'best_oa_location': {
              'url_for_pdf': null,
              'url': 'https://example.org/landing-page',
            },
            'oa_locations': [
              {'url_for_pdf': null},
              {'url_for_pdf': 'https://example.org/fallback.pdf'},
            ],
          }),
          200,
        );
      });

      final service = UnpaywallService(client: client);
      final url = await service.findOaPdfUrl('10.1234/example');
      expect(url, 'https://example.org/fallback.pdf');
    });

    test('returns null on 404', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': true, 'message': 'not found'}),
          404,
        );
      });

      final service = UnpaywallService(client: client);
      final url = await service.findOaPdfUrl('10.1234/missing');
      expect(url, isNull);
    });
  });

  group('downloadPdf', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('unpaywall_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('writes file when body starts with %PDF-', () async {
      final pdfBytes = utf8.encode('%PDF-1.7 fake pdf content');
      final client = MockClient((request) async {
        return http.Response.bytes(pdfBytes, 200);
      });

      final service = UnpaywallService(client: client);
      final savePath = '${tempDir.path}${Platform.pathSeparator}paper.pdf';

      final ok = await service.downloadPdf(
        url: 'https://example.org/paper.pdf',
        savePath: savePath,
      );

      expect(ok, isTrue);
      final file = File(savePath);
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), pdfBytes);
    });

    test('returns false and writes no file when body is HTML', () async {
      final client = MockClient((request) async {
        return http.Response(
          '<html><body>Please sign in</body></html>',
          200,
          headers: {'content-type': 'application/pdf'}, // lying server
        );
      });

      final service = UnpaywallService(client: client);
      final savePath = '${tempDir.path}${Platform.pathSeparator}paper.pdf';

      final ok = await service.downloadPdf(
        url: 'https://example.org/paper.pdf',
        savePath: savePath,
      );

      expect(ok, isFalse);
      expect(await File(savePath).exists(), isFalse);
    });
  });

  group('fetchOaPdf', () {
    test('resolves DOI and downloads the pdf end-to-end', () async {
      final tempDir = await Directory.systemTemp.createTemp('unpaywall_test');
      addTearDown(() => tempDir.delete(recursive: true));

      final pdfBytes = utf8.encode('%PDF-1.4 end-to-end');
      final client = MockClient((request) async {
        if (request.url.host == 'api.unpaywall.org') {
          return http.Response(
            jsonEncode({
              'best_oa_location': {
                'url_for_pdf': 'https://repo.example.org/oa.pdf',
              },
            }),
            200,
          );
        }
        if (request.url.toString() == 'https://repo.example.org/oa.pdf') {
          return http.Response.bytes(pdfBytes, 200);
        }
        return http.Response('not found', 404);
      });

      final service = UnpaywallService(client: client);
      final savePath = '${tempDir.path}${Platform.pathSeparator}oa.pdf';

      final ok = await service.fetchOaPdf(
        doi: '10.5555/end2end',
        savePath: savePath,
      );

      expect(ok, isTrue);
      expect(await File(savePath).readAsBytes(), pdfBytes);
    });
  });
}
