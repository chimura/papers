import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papers/features/enrichment/services/retraction_service.dart';

/// A trimmed but realistic CrossRef notice work: the item *is* the retraction
/// notice, and `update-to` names the paper it applies to.
Map<String, dynamic> notice({
  required String noticeDoi,
  required String targetDoi,
  String type = 'retraction',
}) {
  return {
    'DOI': noticeDoi,
    'type': 'journal-article',
    'title': ['Retraction notice to "A Study of Things"'],
    'update-to': [
      {
        'DOI': targetDoi,
        'type': type,
        'label': type == 'retraction' ? 'Retraction' : 'Correction',
        'updated': {
          'date-parts': [
            [2024, 3, 14],
          ],
        },
      },
    ],
  };
}

String noticeBody(List<Map<String, dynamic>> items) => jsonEncode({
      'status': 'ok',
      'message-type': 'work-list',
      'message': {
        'total-results': items.length,
        'items': items,
      },
    });

void main() {
  group('checkDois', () {
    test('parses a notice whose update-to names our DOI', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'api.crossref.org');
        expect(request.url.path, '/works');
        expect(
          request.url.queryParameters['filter'],
          'updates:10.1234/retracted',
        );
        expect(request.url.queryParameters['rows'], '100');
        expect(
          request.url.queryParameters['mailto'],
          'chimura.willian@gmail.com',
        );
        return http.Response(
          noticeBody([
            notice(
              noticeDoi: '10.1234/retraction-notice',
              targetDoi: '10.1234/retracted',
            ),
          ]),
          200,
        );
      });

      final result = await RetractionService(client: client)
          .checkDois(['10.1234/retracted']);

      expect(result.length, 1);
      final found = result['10.1234/retracted']!;
      expect(found.type, 'retraction');
      expect(found.noticeDoi, '10.1234/retraction-notice');
      expect(found.label, 'Retracted');
      expect(found.isSerious, isTrue);
    });

    test('omits DOIs with no notices from the map', () async {
      final client = MockClient((_) async {
        return http.Response(
          noticeBody([
            notice(
              noticeDoi: '10.1234/notice',
              targetDoi: '10.1234/retracted',
            ),
          ]),
          200,
        );
      });

      final result = await RetractionService(client: client).checkDois([
        '10.1234/retracted',
        '10.1234/perfectly-fine',
      ]);

      expect(result.keys, ['10.1234/retracted']);
      expect(result.containsKey('10.1234/perfectly-fine'), isFalse);
    });

    test('maps each interesting type to its user-facing label', () async {
      final client = MockClient((_) async {
        return http.Response(
          noticeBody([
            notice(
              noticeDoi: '10.1/n1',
              targetDoi: '10.1/a',
              type: 'retraction',
            ),
            notice(
              noticeDoi: '10.1/n2',
              targetDoi: '10.1/b',
              type: 'expression_of_concern',
            ),
            notice(
              noticeDoi: '10.1/n3',
              targetDoi: '10.1/c',
              type: 'correction',
            ),
          ]),
          200,
        );
      });

      final result = await RetractionService(client: client)
          .checkDois(['10.1/a', '10.1/b', '10.1/c']);

      expect(result['10.1/a']!.label, 'Retracted');
      expect(result['10.1/a']!.isSerious, isTrue);
      expect(result['10.1/b']!.label, 'Expression of concern');
      expect(result['10.1/b']!.isSerious, isTrue);
      expect(result['10.1/c']!.label, 'Correction issued');
      expect(result['10.1/c']!.isSerious, isFalse);
    });

    test('ignores update types we do not surface', () async {
      final client = MockClient((_) async {
        return http.Response(
          noticeBody([
            notice(
              noticeDoi: '10.1/n',
              targetDoi: '10.1/a',
              type: 'new_version',
            ),
          ]),
          200,
        );
      });

      final result =
          await RetractionService(client: client).checkDois(['10.1/a']);

      expect(result, isEmpty);
    });

    test('ignores update-to entries for DOIs we did not ask about', () async {
      final client = MockClient((_) async {
        return http.Response(
          noticeBody([
            {
              'DOI': '10.1/notice',
              'update-to': [
                {'DOI': '10.1/someone-elses-paper', 'type': 'retraction'},
                {'DOI': '10.1/ours', 'type': 'retraction'},
              ],
            },
          ]),
          200,
        );
      });

      final result =
          await RetractionService(client: client).checkDois(['10.1/ours']);

      expect(result.keys, ['10.1/ours']);
    });

    test('batches 45 DOIs into three requests of 20/20/5', () async {
      final dois = [for (var i = 0; i < 45; i++) '10.1000/paper$i'];
      final filters = <String>[];

      final client = MockClient((request) async {
        filters.add(request.url.queryParameters['filter']!);
        return http.Response(noticeBody([]), 200);
      });

      await RetractionService(client: client).checkDois(dois);

      expect(filters.length, 3);
      expect(filters[0].split(',').length, 20);
      expect(filters[1].split(',').length, 20);
      expect(filters[2].split(',').length, 5);
      expect(filters[0].startsWith('updates:10.1000/paper0,'), isTrue);
      expect(filters[2], 'updates:10.1000/paper40,updates:10.1000/paper41,'
          'updates:10.1000/paper42,updates:10.1000/paper43,'
          'updates:10.1000/paper44');
    });

    test('matches DOIs case-insensitively and normalizes doi.org URLs',
        () async {
      late String filter;
      final client = MockClient((request) async {
        filter = request.url.queryParameters['filter']!;
        return http.Response(
          noticeBody([
            notice(
              noticeDoi: '10.1/notice',
              targetDoi: '10.1234/MixedCase',
            ),
          ]),
          200,
        );
      });

      final result = await RetractionService(client: client)
          .checkDois(['https://doi.org/10.1234/mixedcase']);

      expect(filter, 'updates:10.1234/mixedcase');
      expect(result.containsKey('10.1234/mixedcase'), isTrue);
    });

    test('prefers the serious notice when a paper has both', () async {
      final client = MockClient((_) async {
        return http.Response(
          noticeBody([
            notice(
              noticeDoi: '10.1/correction',
              targetDoi: '10.1/a',
              type: 'correction',
            ),
            notice(
              noticeDoi: '10.1/retraction',
              targetDoi: '10.1/a',
              type: 'retraction',
            ),
          ]),
          200,
        );
      });

      final result =
          await RetractionService(client: client).checkDois(['10.1/a']);

      expect(result['10.1/a']!.type, 'retraction');
      expect(result['10.1/a']!.noticeDoi, '10.1/retraction');
    });

    test('returns an empty map on a non-200 response', () async {
      final client = MockClient((_) async => http.Response('nope', 503));
      final result =
          await RetractionService(client: client).checkDois(['10.1/a']);
      expect(result, isEmpty);
    });

    test('returns an empty map on malformed JSON', () async {
      final client = MockClient((_) async => http.Response('<html>', 200));
      final result =
          await RetractionService(client: client).checkDois(['10.1/a']);
      expect(result, isEmpty);
    });

    test('survives a transport error and keeps checking later batches',
        () async {
      final dois = [for (var i = 0; i < 25; i++) '10.1000/paper$i'];
      var call = 0;

      final client = MockClient((request) async {
        call++;
        if (call == 1) throw http.ClientException('connection reset');
        return http.Response(
          noticeBody([
            notice(noticeDoi: '10.1/n', targetDoi: '10.1000/paper24'),
          ]),
          200,
        );
      });

      final result = await RetractionService(client: client).checkDois(dois);

      expect(call, 2);
      expect(result.keys, ['10.1000/paper24']);
    });

    test('makes no request for an empty or blank input', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(noticeBody([]), 200);
      });

      final service = RetractionService(client: client);
      expect(await service.checkDois([]), isEmpty);
      expect(await service.checkDois(['  ', '']), isEmpty);
      expect(calls, 0);
    });
  });

  group('publishedVersionDoiFrom', () {
    final service = RetractionService();

    test('returns the DOI from relation.is-preprint-of', () {
      final cslJson = jsonEncode({
        'DOI': '10.48550/arXiv.1706.03762',
        'title': ['Attention Is All You Need'],
        'relation': {
          'is-preprint-of': [
            {'id-type': 'doi', 'id': '10.1145/3292500.3330701', 'asserted-by': 'subject'},
          ],
        },
      });

      expect(
        service.publishedVersionDoiFrom(cslJson),
        '10.1145/3292500.3330701',
      );
    });

    test('returns null when the relation is absent', () {
      final cslJson = jsonEncode({
        'DOI': '10.1/x',
        'relation': {
          'has-review': [
            {'id': '10.1/review'},
          ],
        },
      });

      expect(service.publishedVersionDoiFrom(cslJson), isNull);
    });

    test('returns null when there is no relation key at all', () {
      expect(
        service.publishedVersionDoiFrom(jsonEncode({'DOI': '10.1/x'})),
        isNull,
      );
    });

    test('returns null for malformed JSON', () {
      expect(service.publishedVersionDoiFrom('{not valid json'), isNull);
      expect(service.publishedVersionDoiFrom('[]'), isNull);
      expect(service.publishedVersionDoiFrom('"just a string"'), isNull);
    });

    test('returns null for null, empty and whitespace input', () {
      expect(service.publishedVersionDoiFrom(null), isNull);
      expect(service.publishedVersionDoiFrom(''), isNull);
      expect(service.publishedVersionDoiFrom('   '), isNull);
    });

    test('returns null for an empty or malformed is-preprint-of array', () {
      expect(
        service.publishedVersionDoiFrom(
          jsonEncode({
            'relation': {'is-preprint-of': []},
          }),
        ),
        isNull,
      );
      expect(
        service.publishedVersionDoiFrom(
          jsonEncode({
            'relation': {
              'is-preprint-of': [
                {'id-type': 'doi'},
              ],
            },
          }),
        ),
        isNull,
        reason: 'entry without an id',
      );
      expect(
        service.publishedVersionDoiFrom(
          jsonEncode({
            'relation': {
              'is-preprint-of': ['10.1/bare-string'],
            },
          }),
        ),
        isNull,
      );
    });
  });

  group('RetractionNotice', () {
    test('isSerious covers retraction and expression of concern only', () {
      const retraction = RetractionNotice(
        type: 'retraction',
        noticeDoi: '10.1/n',
        label: 'Retracted',
      );
      const concern = RetractionNotice(
        type: 'expression_of_concern',
        noticeDoi: '10.1/n',
        label: 'Expression of concern',
      );
      const correction = RetractionNotice(
        type: 'correction',
        noticeDoi: '10.1/n',
        label: 'Correction issued',
      );

      expect(retraction.isSerious, isTrue);
      expect(concern.isSerious, isTrue);
      expect(correction.isSerious, isFalse);
    });
  });
}
