import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papers/features/import/services/identifier_resolver_service.dart';

/// A trimmed but structurally faithful arXiv export-API Atom response.
const _arxivAtom = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:arxiv="http://arxiv.org/schemas/atom">
  <link href="http://arxiv.org/api/query?id_list=1706.03762" rel="self" type="application/atom+xml"/>
  <title type="html">ArXiv Query: search_query=&amp;id_list=1706.03762</title>
  <id>http://arxiv.org/api/QhQNvbtGDbQC0oCPCFqDVEcXNlY</id>
  <updated>2026-07-19T00:00:00-04:00</updated>
  <opensearch:totalResults xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/">1</opensearch:totalResults>
  <entry>
    <id>http://arxiv.org/abs/1706.03762v5</id>
    <updated>2017-12-06T03:30:32Z</updated>
    <published>2017-06-12T18:57:34Z</published>
    <title>Attention Is All You Need</title>
    <summary>  The dominant sequence transduction models are based on complex recurrent or
convolutional neural networks that include an encoder and a decoder.
</summary>
    <author>
      <name>Ashish Vaswani</name>
    </author>
    <author>
      <name>Noam Shazeer</name>
    </author>
    <author>
      <name>Aidan N. Gomez</name>
    </author>
    <arxiv:doi xmlns:arxiv="http://arxiv.org/schemas/atom">10.5555/3295222.3295349</arxiv:doi>
    <arxiv:journal_ref xmlns:arxiv="http://arxiv.org/schemas/atom">NIPS 2017</arxiv:journal_ref>
    <link href="http://arxiv.org/abs/1706.03762v5" rel="alternate" type="text/html"/>
    <category term="cs.CL" scheme="http://arxiv.org/schemas/atom"/>
  </entry>
</feed>
''';

/// arXiv's in-band error shape for an unparseable id.
const _arxivError = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title type="html">ArXiv Query: search_query=&amp;id_list=9999.99999</title>
  <entry>
    <id>http://arxiv.org/api/errors#incorrect_id_format_for_9999.99999</id>
    <title>Error</title>
    <summary>incorrect id format for 9999.99999</summary>
    <author><name>arXiv api core</name></author>
  </entry>
</feed>
''';

String _pubmedSummary(String uid) => jsonEncode({
      'header': {'type': 'esummary', 'version': '0.3'},
      'result': {
        'uids': [uid],
        uid: {
          'uid': uid,
          'pubdate': '2019 Nov 1',
          'epubdate': '2019 May 2',
          'source': 'Bioinformatics',
          'authors': [
            {'name': 'Smith AB', 'authtype': 'Author'},
            {'name': 'van der Berg CD', 'authtype': 'Author'},
            {'name': 'WHO Study Group', 'authtype': 'Author'},
          ],
          'title': 'A fast method for aligning long reads.',
          'volume': '35',
          'issue': '21',
          'pages': '4453-4455',
          'fulljournalname': 'Bioinformatics (Oxford, England)',
          'articleids': [
            {'idtype': 'pubmed', 'value': uid},
            {'idtype': 'pii', 'value': 'btz305'},
            {'idtype': 'doi', 'value': '10.1093/bioinformatics/btz305'},
          ],
        },
      },
    });

const _pubmedMissing = '''
{"header":{"type":"esummary","version":"0.3"},
 "result":{"uids":["99999999"],
   "99999999":{"uid":"99999999","error":"cannot get document summary"}}}
''';

String _crossrefWork(String doi) => jsonEncode({
      'status': 'ok',
      'message': {
        'DOI': doi,
        'title': ['A CrossRef Registered Work'],
        'container-title': ['Journal of Examples'],
        'issued': {
          'date-parts': [
            [2021, 3, 4]
          ]
        },
        'author': [
          {'given': 'Jane', 'family': 'Doe'},
        ],
      },
    });

void main() {
  group('detectType', () {
    final service = IdentifierResolverService(
      client: MockClient((_) async => http.Response('', 404)),
    );

    test('recognises a bare DOI', () {
      expect(service.detectType('10.1093/bioinformatics/btz305'),
          IdentifierType.doi);
    });

    test('recognises a doi.org URL', () {
      expect(service.detectType('https://doi.org/10.1038/s41586-021-03819-2'),
          IdentifierType.doi);
      expect(
          service.detectType('doi:10.1038/nature12373'), IdentifierType.doi);
    });

    test('recognises arXiv ids with and without a prefix', () {
      expect(service.detectType('arXiv:1706.03762'), IdentifierType.arxiv);
      expect(service.detectType('arXiv: 1706.03762v5'), IdentifierType.arxiv);
      expect(service.detectType('1706.03762'), IdentifierType.arxiv);
      expect(service.detectType('2301.07041v2'), IdentifierType.arxiv);
      expect(service.detectType('https://arxiv.org/abs/1706.03762'),
          IdentifierType.arxiv);
    });

    test('recognises legacy arXiv ids', () {
      expect(service.detectType('hep-th/9901001'), IdentifierType.arxiv);
      expect(service.detectType('math.GT/0309136'), IdentifierType.arxiv);
    });

    test('recognises a PMID', () {
      expect(service.detectType('31452104'), IdentifierType.pmid);
      expect(service.detectType('7'), IdentifierType.pmid);
    });

    test('an arXiv id containing "10." is not mistaken for a DOI', () {
      expect(service.detectType('1510.01234'), IdentifierType.arxiv);
    });

    test('returns unknown for garbage and empty input', () {
      expect(service.detectType('not an identifier'), IdentifierType.unknown);
      expect(service.detectType(''), IdentifierType.unknown);
      expect(service.detectType('   '), IdentifierType.unknown);
      expect(service.detectType('123456789012'), IdentifierType.unknown);
    });
  });

  group('splitIdentifiers', () {
    final service = IdentifierResolverService(
      client: MockClient((_) async => http.Response('', 404)),
    );

    test('splits a messy multi-line blob', () {
      const blob = '''
        10.1093/bioinformatics/btz305, arXiv:1706.03762
        31452104;  hep-th/9901001

          https://doi.org/10.1038/nature12373
      ''';

      expect(service.splitIdentifiers(blob), [
        '10.1093/bioinformatics/btz305',
        'arXiv:1706.03762',
        '31452104',
        'hep-th/9901001',
        'https://doi.org/10.1038/nature12373',
      ]);
    });

    test('returns an empty list for whitespace only', () {
      expect(service.splitIdentifiers('  \n\t , ; '), isEmpty);
    });
  });

  group('resolve — arXiv', () {
    test('parses title, authors, year, doi and arxivId', () async {
      late Uri seen;
      final client = MockClient((request) async {
        seen = request.url;
        return http.Response(_arxivAtom, 200);
      });

      final paper =
          await IdentifierResolverService(client: client).resolve('arXiv:1706.03762');

      expect(seen.host, 'export.arxiv.org');
      expect(seen.queryParameters['id_list'], '1706.03762');

      expect(paper, isNotNull);
      // The feed's own <title> must not leak into the entry.
      expect(paper!.title, 'Attention Is All You Need');
      expect(paper.year, '2017');
      expect(paper.arxivId, '1706.03762v5');
      expect(paper.doi, '10.5555/3295222.3295349');
      expect(paper.journal, 'NIPS 2017');
      expect(paper.abstract_, startsWith('The dominant sequence transduction'));
      expect(paper.abstract_, isNot(contains('\n')));

      expect(paper.authors.map((a) => a.displayName), [
        'Ashish Vaswani',
        'Noam Shazeer',
        'Aidan N. Gomez',
      ]);
      expect(paper.authors.first.familyName, 'Vaswani');
      expect(paper.authors.first.givenName, 'Ashish');
      expect(paper.authors.last.familyName, 'Gomez');
      expect(paper.authors.last.givenName, 'Aidan N.');
    });

    test('strips an abs URL down to the bare id before querying', () async {
      late Uri seen;
      final client = MockClient((request) async {
        seen = request.url;
        return http.Response(_arxivAtom, 200);
      });

      await IdentifierResolverService(client: client)
          .resolve('https://arxiv.org/abs/1706.03762');

      expect(seen.queryParameters['id_list'], '1706.03762');
    });

    test('returns null for arXiv\'s in-band error entry', () async {
      final client = MockClient((_) async => http.Response(_arxivError, 200));
      final paper =
          await IdentifierResolverService(client: client).resolve('9999.99999');
      expect(paper, isNull);
    });
  });

  group('resolve — PubMed', () {
    test('parses title, journal, year, pages and the doi from articleids',
        () async {
      late Uri seen;
      final client = MockClient((request) async {
        seen = request.url;
        return http.Response(_pubmedSummary('31452104'), 200);
      });

      final paper =
          await IdentifierResolverService(client: client).resolve('31452104');

      expect(seen.host, 'eutils.ncbi.nlm.nih.gov');
      expect(seen.queryParameters['db'], 'pubmed');
      expect(seen.queryParameters['id'], '31452104');
      expect(seen.queryParameters['retmode'], 'json');

      expect(paper, isNotNull);
      expect(paper!.title, 'A fast method for aligning long reads');
      expect(paper.journal, 'Bioinformatics (Oxford, England)');
      expect(paper.year, '2019');
      expect(paper.volume, '35');
      expect(paper.issue, '21');
      expect(paper.pages, '4453-4455');
      expect(paper.pmid, '31452104');
      expect(paper.doi, '10.1093/bioinformatics/btz305');

      expect(paper.authors.length, 3);
      expect(paper.authors[0].familyName, 'Smith');
      expect(paper.authors[0].givenName, 'AB');
      // Multi-token family names keep every token but the initials.
      expect(paper.authors[1].familyName, 'van der Berg');
      expect(paper.authors[1].givenName, 'CD');
      // Collective authors have no initials to split off.
      expect(paper.authors[2].familyName, 'WHO Study Group');
      expect(paper.authors[2].givenName, isNull);
    });

    test('returns null when the record carries an in-band error', () async {
      final client = MockClient((_) async => http.Response(_pubmedMissing, 200));
      final paper =
          await IdentifierResolverService(client: client).resolve('99999999');
      expect(paper, isNull);
    });
  });

  group('resolve — DOI', () {
    test('delegates to CrossRef using the shared client', () async {
      late Uri seen;
      final client = MockClient((request) async {
        seen = request.url;
        return http.Response(_crossrefWork('10.1038/nature12373'), 200);
      });

      final paper = await IdentifierResolverService(client: client)
          .resolve('https://doi.org/10.1038/nature12373');

      expect(seen.host, 'api.crossref.org');
      expect(seen.path, '/works/10.1038/nature12373');
      expect(paper, isNotNull);
      expect(paper!.title, 'A CrossRef Registered Work');
      expect(paper.year, '2021');
      expect(paper.doi, '10.1038/nature12373');
    });
  });

  group('resolve — failure handling', () {
    test('returns null for garbage without making a request', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('', 200);
      });

      final service = IdentifierResolverService(client: client);
      expect(await service.resolve('this is not an identifier'), isNull);
      expect(await service.resolve(''), isNull);
      expect(calls, 0);
    });

    test('returns null on a non-200 response', () async {
      final client = MockClient((_) async => http.Response('nope', 500));
      final service = IdentifierResolverService(client: client);
      expect(await service.resolve('1706.03762'), isNull);
      expect(await service.resolve('31452104'), isNull);
    });

    test('returns null when the network throws', () async {
      final client = MockClient((_) async => throw const SocketFailure());
      final service = IdentifierResolverService(client: client);
      expect(await service.resolve('1706.03762'), isNull);
      expect(await service.resolve('31452104'), isNull);
      expect(await service.resolve('10.1038/nature12373'), isNull);
    });

    test('returns null on an unparseable body', () async {
      final client = MockClient((_) async => http.Response('<<<not xml', 200));
      final service = IdentifierResolverService(client: client);
      expect(await service.resolve('1706.03762'), isNull);
      expect(await service.resolve('31452104'), isNull);
    });
  });

  group('resolveMany', () {
    test('preserves input order and skips failures', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'export.arxiv.org') {
          return http.Response(_arxivAtom, 200);
        }
        if (request.url.host == 'eutils.ncbi.nlm.nih.gov') {
          return http.Response(_pubmedSummary('31452104'), 200);
        }
        // CrossRef leg fails — that entry must be skipped, not fatal.
        return http.Response('not found', 404);
      });

      final papers = await IdentifierResolverService(client: client)
          .resolveMany([
        'arXiv:1706.03762',
        '10.9999/does-not-exist', // fails
        'total garbage', // unknown type
        '31452104',
      ]);

      expect(papers.map((p) => p.title), [
        'Attention Is All You Need',
        'A fast method for aligning long reads',
      ]);
    });

    test('returns an empty list when everything fails', () async {
      final client = MockClient((_) async => http.Response('', 503));
      final papers = await IdentifierResolverService(client: client)
          .resolveMany(['1706.03762', '31452104']);
      expect(papers, isEmpty);
    });

    test('accepts an empty iterable', () async {
      final client = MockClient((_) async => http.Response('', 200));
      expect(
          await IdentifierResolverService(client: client).resolveMany([]),
          isEmpty);
    });
  });
}

class SocketFailure implements Exception {
  const SocketFailure();
}
