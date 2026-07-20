import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papers/core/models/author_model.dart';
import 'package:papers/core/models/paper_model.dart';
import 'package:papers/features/enrichment/services/enrichment_service.dart';

PaperModel makePaper({
  String title = 'Attention Is All You Need',
  String? abstract_,
  String? doi,
  String? year,
  String? journal,
  String? volume,
  String? publisher,
  String? arxivId,
  String? pmid,
  List<AuthorModel> authors = const [],
}) {
  final now = DateTime(2026, 7, 20);
  return PaperModel(
    title: title,
    abstract_: abstract_,
    doi: doi,
    year: year,
    journal: journal,
    volume: volume,
    publisher: publisher,
    arxivId: arxivId,
    pmid: pmid,
    authors: authors,
    dateAdded: now,
    dateModified: now,
  );
}

/// A realistic (trimmed) CrossRef `works` item.
Map<String, dynamic> crossRefItem({
  required String title,
  String doi = '10.1145/3292500.3330701',
  String journal = 'Journal of Machine Learning Research',
  int year = 2017,
}) {
  return {
    'DOI': doi,
    'title': [title],
    'container-title': [journal],
    'issued': {
      'date-parts': [
        [year, 6, 12],
      ],
    },
    'volume': '30',
    'issue': '4',
    'page': '5998-6008',
    'publisher': 'Association for Computing Machinery',
    'URL': 'https://doi.org/$doi',
    'abstract':
        '<jats:p>The dominant sequence transduction models are based on '
            'complex recurrent networks.</jats:p>',
    'author': [
      {'given': 'Ashish', 'family': 'Vaswani'},
      {'given': 'Noam', 'family': 'Shazeer'},
    ],
  };
}

String crossRefSearchBody(List<Map<String, dynamic>> items) => jsonEncode({
      'status': 'ok',
      'message-type': 'work-list',
      'message': {
        'total-results': items.length,
        'items': items,
      },
    });

void main() {
  group('isIncomplete', () {
    final service = EnrichmentService(
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    test('is false when abstract, doi, journal and year are all present', () {
      final paper = makePaper(
        abstract_: 'We propose a new architecture.',
        doi: '10.1145/3292500.3330701',
        year: '2017',
        journal: 'JMLR',
      );
      expect(service.isIncomplete(paper), isFalse);
    });

    test('is true when any of the four fields is missing', () {
      expect(
        service.isIncomplete(
          makePaper(doi: '10.1/x', year: '2017', journal: 'JMLR'),
        ),
        isTrue,
        reason: 'missing abstract',
      );
      expect(
        service.isIncomplete(
          makePaper(abstract_: 'a', year: '2017', journal: 'JMLR'),
        ),
        isTrue,
        reason: 'missing doi',
      );
      expect(
        service.isIncomplete(
          makePaper(abstract_: 'a', doi: '10.1/x', year: '2017'),
        ),
        isTrue,
        reason: 'missing journal',
      );
      expect(
        service.isIncomplete(
          makePaper(abstract_: 'a', doi: '10.1/x', journal: 'JMLR'),
        ),
        isTrue,
        reason: 'missing year',
      );
    });

    test('treats whitespace-only values as missing', () {
      final paper = makePaper(
        abstract_: '   ',
        doi: '10.1/x',
        year: '2017',
        journal: 'JMLR',
      );
      expect(service.isIncomplete(paper), isTrue);
    });
  });

  group('findByTitle', () {
    test('builds the CrossRef query with rows, author and mailto', () async {
      late Uri captured;
      final client = MockClient((request) async {
        captured = request.url;
        expect(
          request.headers['User-Agent'],
          contains('mailto:chimura.willian@gmail.com'),
        );
        return http.Response(
          crossRefSearchBody(
            [crossRefItem(title: 'Attention Is All You Need')],
          ),
          200,
        );
      });

      final service = EnrichmentService(client: client);
      await service.findByTitle(
        'Attention Is All You Need',
        firstAuthorFamily: 'Vaswani',
      );

      expect(captured.host, 'api.crossref.org');
      expect(captured.path, '/works');
      expect(
        captured.queryParameters['query.bibliographic'],
        'Attention Is All You Need',
      );
      expect(captured.queryParameters['rows'], '3');
      expect(captured.queryParameters['query.author'], 'Vaswani');
      expect(captured.queryParameters['mailto'], 'chimura.willian@gmail.com');
    });

    test('omits query.author when no family name is given', () async {
      late Uri captured;
      final client = MockClient((request) async {
        captured = request.url;
        return http.Response(crossRefSearchBody([]), 200);
      });

      await EnrichmentService(client: client)
          .findByTitle('Attention Is All You Need');

      expect(captured.queryParameters.containsKey('query.author'), isFalse);
    });

    test('accepts a near-exact match differing only in punctuation and case',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          crossRefSearchBody([
            crossRefItem(title: 'ATTENTION is all you need!'),
          ]),
          200,
        );
      });

      final paper = await EnrichmentService(client: client)
          .findByTitle('Attention Is All You Need');

      expect(paper, isNotNull);
      expect(paper!.doi, '10.1145/3292500.3330701');
      expect(paper.year, '2017');
      expect(paper.journal, 'Journal of Machine Learning Research');
      expect(paper.authors.map((a) => a.familyName), ['Vaswani', 'Shazeer']);
      expect(
        paper.abstract_,
        'The dominant sequence transduction models are based on complex '
        'recurrent networks.',
        reason: 'JATS tags should be stripped',
      );
    });

    test('rejects a low-similarity result rather than returning the wrong paper',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          crossRefSearchBody([
            crossRefItem(
              title: 'Deep Residual Learning for Image Recognition',
              doi: '10.1109/CVPR.2016.90',
            ),
          ]),
          200,
        );
      });

      final paper = await EnrichmentService(client: client)
          .findByTitle('Attention Is All You Need');

      expect(paper, isNull);
    });

    test('picks the best candidate above the threshold', () async {
      final client = MockClient((_) async {
        return http.Response(
          crossRefSearchBody([
            crossRefItem(
              title: 'Attention Is All You Need for Machines',
              doi: '10.1/loose',
            ),
            crossRefItem(title: 'Attention is all you need', doi: '10.1/exact'),
            crossRefItem(
              title: 'A Survey of Attention Mechanisms',
              doi: '10.1/unrelated',
            ),
          ]),
          200,
        );
      });

      final paper = await EnrichmentService(client: client)
          .findByTitle('Attention Is All You Need');

      expect(paper?.doi, '10.1/exact');
    });

    test('returns null on a non-200 response without throwing', () async {
      final client = MockClient((_) async => http.Response('boom', 500));
      final paper =
          await EnrichmentService(client: client).findByTitle('Anything');
      expect(paper, isNull);
    });

    test('returns null on malformed JSON without throwing', () async {
      final client = MockClient((_) async => http.Response('not json', 200));
      final paper =
          await EnrichmentService(client: client).findByTitle('Anything');
      expect(paper, isNull);
    });

    test('returns null for an empty query without calling the API', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(crossRefSearchBody([]), 200);
      });

      expect(await EnrichmentService(client: client).findByTitle('   '), isNull);
      expect(calls, 0);
    });
  });

  group('fetchBatchByDoi', () {
    test('chunks 150 ids into two requests and aligns results positionally',
        () async {
      final dois = [for (var i = 0; i < 150; i++) '10.1000/paper$i'];
      final requestBodies = <List<dynamic>>[];

      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.host, 'api.semanticscholar.org');
        expect(request.url.path, '/graph/v1/paper/batch');
        expect(
          request.url.queryParameters['fields'],
          'title,abstract,year,venue,externalIds,openAccessPdf',
        );

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final ids = body['ids'] as List<dynamic>;
        requestBodies.add(ids);

        // Respond positionally, with a null hole to mimic an unknown paper.
        final response = <dynamic>[];
        for (var i = 0; i < ids.length; i++) {
          final id = ids[i] as String;
          if (i == 1) {
            response.add(null);
          } else {
            response.add({
              'paperId': 'ss-$i',
              'title': 'Paper for $id',
              'year': 2020,
              'venue': 'Nature',
              'externalIds': {'DOI': id.substring('DOI:'.length)},
            });
          }
        }
        return http.Response(jsonEncode(response), 200);
      });

      final result = await EnrichmentService(client: client).fetchBatchByDoi(
        dois,
      );

      expect(requestBodies.length, 2, reason: '150 ids at 100 per chunk');
      expect(requestBodies[0].length, 100);
      expect(requestBodies[1].length, 50);
      expect(requestBodies[0].first, 'DOI:10.1000/paper0');
      expect(requestBodies[1].first, 'DOI:10.1000/paper100');

      // Two null holes (one per chunk) are dropped, the rest are keyed by the
      // input DOI.
      expect(result.length, 148);
      expect(result.containsKey('10.1000/paper1'), isFalse);
      expect(result.containsKey('10.1000/paper101'), isFalse);
      expect(result['10.1000/paper0']!['title'], 'Paper for DOI:10.1000/paper0');
      expect(
        result['10.1000/paper149']!['title'],
        'Paper for DOI:10.1000/paper149',
      );
    });

    test('keys results by the input DOI lowercased, not the response DOI',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode([
            {
              'title': 'Mixed Case DOI',
              'externalIds': {'DOI': '10.1000/DIFFERENT'},
            },
          ]),
          200,
        );
      });

      final result = await EnrichmentService(client: client)
          .fetchBatchByDoi(['10.1000/MixedCase']);

      expect(result.keys, ['10.1000/mixedcase']);
    });

    test('strips doi.org prefixes before sending', () async {
      late List<dynamic> ids;
      final client = MockClient((request) async {
        ids = (jsonDecode(request.body) as Map<String, dynamic>)['ids']
            as List<dynamic>;
        return http.Response(jsonEncode([null]), 200);
      });

      await EnrichmentService(client: client)
          .fetchBatchByDoi(['https://doi.org/10.1000/prefixed']);

      expect(ids, ['DOI:10.1000/prefixed']);
    });

    test('returns what it has so far when a later chunk fails', () async {
      final dois = [for (var i = 0; i < 150; i++) '10.1000/paper$i'];
      var call = 0;

      final client = MockClient((request) async {
        call++;
        if (call == 1) {
          final ids = (jsonDecode(request.body) as Map<String, dynamic>)['ids']
              as List<dynamic>;
          return http.Response(
            jsonEncode([
              for (final id in ids) {'title': 'ok $id'},
            ]),
            200,
          );
        }
        return http.Response('rate limited', 429);
      });

      final result =
          await EnrichmentService(client: client).fetchBatchByDoi(dois);

      expect(call, 2);
      expect(result.length, 100);
      expect(result.containsKey('10.1000/paper0'), isTrue);
      expect(result.containsKey('10.1000/paper100'), isFalse);
    });

    test('returns an empty map for an empty input without calling the API',
        () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('[]', 200);
      });

      expect(await EnrichmentService(client: client).fetchBatchByDoi([]), isEmpty);
      expect(calls, 0);
    });
  });

  group('mergeEnrichment', () {
    test('fills null fields from CrossRef', () {
      final original = makePaper(title: 'Attention Is All You Need');
      final crossref = makePaper(
        title: 'Attention Is All You Need',
        abstract_: 'The dominant sequence transduction models...',
        doi: '10.1145/3292500.3330701',
        year: '2017',
        journal: 'JMLR',
        volume: '30',
        publisher: 'ACM',
        authors: const [AuthorModel(givenName: 'Ashish', familyName: 'Vaswani')],
      );

      final merged = EnrichmentService().mergeEnrichment(
        original,
        crossref: crossref,
      );

      expect(merged.abstract_, 'The dominant sequence transduction models...');
      expect(merged.doi, '10.1145/3292500.3330701');
      expect(merged.year, '2017');
      expect(merged.journal, 'JMLR');
      expect(merged.volume, '30');
      expect(merged.publisher, 'ACM');
      expect(merged.authors.single.familyName, 'Vaswani');
    });

    test('never overwrites existing user data', () {
      final original = makePaper(
        abstract_: 'My own summary.',
        doi: '10.9999/mine',
        year: '1999',
        journal: 'My Journal',
        authors: const [AuthorModel(familyName: 'Chimura')],
      );
      final crossref = makePaper(
        abstract_: 'CrossRef abstract',
        doi: '10.1145/other',
        year: '2017',
        journal: 'JMLR',
        authors: const [AuthorModel(familyName: 'Vaswani')],
      );

      final merged = EnrichmentService().mergeEnrichment(
        original,
        crossref: crossref,
        semanticScholar: const {
          'abstract': 'Semantic Scholar abstract',
          'year': 2018,
          'venue': 'NeurIPS',
          'externalIds': {'DOI': '10.1145/ss'},
        },
      );

      expect(merged.abstract_, 'My own summary.');
      expect(merged.doi, '10.9999/mine');
      expect(merged.year, '1999');
      expect(merged.journal, 'My Journal');
      expect(merged.authors.single.familyName, 'Chimura');
    });

    test('maps Semantic Scholar fields, including int year and externalIds', () {
      final original = makePaper();

      final merged = EnrichmentService().mergeEnrichment(
        original,
        semanticScholar: const {
          'abstract': 'SS abstract',
          'year': 2017,
          'venue': 'NeurIPS',
          'externalIds': {
            'DOI': '10.1145/ss',
            'ArXiv': '1706.03762',
            'PubMed': 12345678,
          },
        },
      );

      expect(merged.abstract_, 'SS abstract');
      expect(merged.year, '2017');
      expect(merged.journal, 'NeurIPS');
      expect(merged.doi, '10.1145/ss');
      expect(merged.arxivId, '1706.03762');
      expect(merged.pmid, '12345678');
    });

    test('prefers CrossRef over Semantic Scholar when both supply a field', () {
      final merged = EnrichmentService().mergeEnrichment(
        makePaper(),
        crossref: makePaper(journal: 'CrossRef Journal', year: '2017'),
        semanticScholar: const {'venue': 'SS Venue', 'year': 2018},
      );

      expect(merged.journal, 'CrossRef Journal');
      expect(merged.year, '2017');
    });

    test('falls back to Semantic Scholar when CrossRef leaves a field blank',
        () {
      final merged = EnrichmentService().mergeEnrichment(
        makePaper(),
        crossref: makePaper(journal: '   '),
        semanticScholar: const {'venue': 'NeurIPS'},
      );

      expect(merged.journal, 'NeurIPS');
    });

    test('treats whitespace-only existing values as fillable', () {
      final merged = EnrichmentService().mergeEnrichment(
        makePaper(journal: '   '),
        crossref: makePaper(journal: 'JMLR'),
      );

      expect(merged.journal, 'JMLR');
    });

    test('leaves the original untouched and never changes the title', () {
      final original = makePaper(title: 'My Local Title');
      final merged = EnrichmentService().mergeEnrichment(
        original,
        crossref: makePaper(title: 'Canonical CrossRef Title', doi: '10.1/x'),
      );

      expect(original.doi, isNull, reason: 'original must not be mutated');
      expect(merged.title, 'My Local Title');
      expect(merged.doi, '10.1/x');
    });

    test('keeps a partial author list rather than replacing it', () {
      final original = makePaper(
        authors: const [AuthorModel(familyName: 'Vaswani')],
      );
      final merged = EnrichmentService().mergeEnrichment(
        original,
        crossref: makePaper(
          authors: const [
            AuthorModel(familyName: 'Vaswani'),
            AuthorModel(familyName: 'Shazeer'),
          ],
        ),
      );

      expect(merged.authors.length, 1);
    });
  });

  group('diff', () {
    test('reports only changed fields, with old and new values', () {
      final before = makePaper(year: '2017');
      final after = before.copyWith(
        abstract_: 'New abstract',
        doi: '10.1/new',
        journal: 'JMLR',
      );

      final changes = EnrichmentService().diff(before, after);
      final byField = {for (final c in changes) c.field: c};

      expect(byField.keys, containsAll(['abstract', 'doi', 'journal']));
      expect(byField.containsKey('year'), isFalse);
      expect(byField.containsKey('title'), isFalse);
      expect(byField['abstract']!.oldValue, isNull);
      expect(byField['abstract']!.newValue, 'New abstract');
      expect(byField['doi']!.oldValue, isNull);
      expect(byField['doi']!.newValue, '10.1/new');
    });

    test('returns no changes for identical papers', () {
      final paper = makePaper(doi: '10.1/x', year: '2017');
      expect(EnrichmentService().diff(paper, paper), isEmpty);
    });

    test('reports an author list appearing', () {
      final before = makePaper();
      final after = before.copyWith(
        authors: const [
          AuthorModel(givenName: 'Ashish', familyName: 'Vaswani'),
          AuthorModel(familyName: 'Shazeer'),
        ],
      );

      final changes = EnrichmentService().diff(before, after);
      final authorChange = changes.firstWhere((c) => c.field == 'authors');

      expect(authorChange.oldValue, isNull);
      expect(authorChange.newValue, 'Ashish Vaswani, Shazeer');
    });

    test('describes an end-to-end enrichment', () {
      final service = EnrichmentService();
      final before = makePaper(title: 'Attention Is All You Need');
      final after = service.mergeEnrichment(
        before,
        semanticScholar: const {
          'abstract': 'SS abstract',
          'year': 2017,
          'venue': 'NeurIPS',
          'externalIds': {'DOI': '10.1/ss', 'ArXiv': '1706.03762'},
        },
      );

      final fields = service.diff(before, after).map((c) => c.field).toSet();
      expect(fields, {'abstract', 'doi', 'year', 'journal', 'arxivId'});
    });
  });

  group('FieldChange', () {
    test('compares by value', () {
      const a = FieldChange(field: 'doi', oldValue: null, newValue: '10.1/x');
      const b = FieldChange(field: 'doi', oldValue: null, newValue: '10.1/x');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
