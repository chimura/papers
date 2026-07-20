import 'package:flutter_test/flutter_test.dart';
import 'package:papers/features/import/services/ris_parser_service.dart';

void main() {
  final parser = RisParserService();

  test('parses a multi-record Zotero-style export', () {
    const ris = '''
Provider: Zotero
Content: text/plain; charset="UTF-8"

TY  - JOUR
TI  - Attention Is All You Need
AU  - Vaswani, Ashish
AU  - Shazeer, Noam
AU  - Parmar, Niki
PY  - 2017
JO  - Advances in Neural Information Processing Systems
VL  - 30
SP  - 5998
EP  - 6008
DO  - https://doi.org/10.48550/arXiv.1706.03762
UR  - https://arxiv.org/abs/1706.03762
KW  - deep learning
KW  - transformers
AB  - The dominant sequence transduction models are based on complex
recurrent or convolutional neural networks.
ER  -
TY  - JOUR
TI  - BERT: Pre-training of Deep Bidirectional Transformers
AU  - Devlin, Jacob
A2  - Toutanova, Kristina
PY  - 2019
JO  - NAACL
IS  - 1
SP  - 4171
PB  - Association for Computational Linguistics
KW  - language models
ER  -
''';

    final papers = parser.parse(ris);
    expect(papers, hasLength(2));

    final first = papers[0];
    expect(first.title, 'Attention Is All You Need');
    expect(first.authors, hasLength(3));
    expect(first.authors[0].familyName, 'Vaswani');
    expect(first.authors[0].givenName, 'Ashish');
    expect(first.authors[1].familyName, 'Shazeer');
    expect(first.authors[2].familyName, 'Parmar');
    expect(first.year, '2017');
    expect(first.journal, 'Advances in Neural Information Processing Systems');
    expect(first.volume, '30');
    expect(first.pages, '5998-6008');
    expect(first.doi, '10.48550/arXiv.1706.03762');
    expect(first.url, 'https://arxiv.org/abs/1706.03762');
    expect(first.tags, ['deep learning', 'transformers']);
    expect(
      first.abstract_,
      'The dominant sequence transduction models are based on complex '
      'recurrent or convolutional neural networks.',
    );

    final second = papers[1];
    expect(second.title, 'BERT: Pre-training of Deep Bidirectional Transformers');
    expect(second.authors, hasLength(2));
    expect(second.authors[0].familyName, 'Devlin');
    expect(second.authors[1].familyName, 'Toutanova');
    expect(second.authors[1].givenName, 'Kristina');
    expect(second.year, '2019');
    expect(second.journal, 'NAACL');
    expect(second.issue, '1');
    expect(second.pages, '4171');
    expect(second.publisher, 'Association for Computational Linguistics');
    expect(second.tags, ['language models']);
  });

  test('parses a Mendeley-style record using T1/Y1/JF/N2', () {
    const ris = '''
TY  - JOUR
T1  - Deep Residual Learning for Image Recognition
A1  - He, Kaiming
A1  - Zhang, Xiangyu
Y1  - 2016/06/27
JF  - IEEE Conference on Computer Vision and Pattern Recognition
N2  - Deeper neural networks are more difficult to train.
ER  -
''';

    final papers = parser.parse(ris);
    expect(papers, hasLength(1));

    final paper = papers.single;
    expect(paper.title, 'Deep Residual Learning for Image Recognition');
    expect(paper.authors, hasLength(2));
    expect(paper.authors[0].familyName, 'He');
    expect(paper.authors[0].givenName, 'Kaiming');
    expect(paper.year, '2016');
    expect(
      paper.journal,
      'IEEE Conference on Computer Vision and Pattern Recognition',
    );
    expect(paper.abstract_, 'Deeper neural networks are more difficult to train.');
  });

  test('handles CRLF line endings', () {
    const ris = 'TY  - JOUR\r\n'
        'TI  - Windows Export\r\n'
        'AU  - Curie, Marie\r\n'
        'PY  - 1911///\r\n'
        'ER  - \r\n';

    final papers = parser.parse(ris);
    expect(papers, hasLength(1));
    expect(papers.single.title, 'Windows Export');
    expect(papers.single.authors.single.familyName, 'Curie');
    expect(papers.single.year, '1911');
  });

  test('parses "Given Family" author format', () {
    const ris = '''
TY  - JOUR
TI  - Some Paper
AU  - Marie Skłodowska Curie
ER  -
''';

    final papers = parser.parse(ris);
    expect(papers.single.authors.single.familyName, 'Curie');
    expect(papers.single.authors.single.givenName, 'Marie Skłodowska');
  });

  test('uses "Untitled" when the title is missing', () {
    const ris = '''
TY  - JOUR
AU  - Doe, John
ER  -
''';

    final papers = parser.parse(ris);
    expect(papers, hasLength(1));
    expect(papers.single.title, 'Untitled');
  });

  test('parses a record without ER at end of file', () {
    const ris = '''
TY  - JOUR
TI  - Truncated Export
PY  - 2020/01/15
''';

    final papers = parser.parse(ris);
    expect(papers, hasLength(1));
    expect(papers.single.title, 'Truncated Export');
    expect(papers.single.year, '2020');
  });

  test('ignores unknown tags', () {
    const ris = '''
TY  - JOUR
TI  - Known Tags Only
ID  - 12345
L1  - file:///papers/paper.pdf
ER  -
''';

    final papers = parser.parse(ris);
    expect(papers, hasLength(1));
    expect(papers.single.title, 'Known Tags Only');
  });

  test('returns empty list for empty input', () {
    expect(parser.parse(''), isEmpty);
  });

  test('returns empty list for garbage input', () {
    expect(parser.parse('not ris at all\njust some lines\n'), isEmpty);
  });

  test('sets dateAdded and dateModified', () {
    const ris = '''
TY  - JOUR
TI  - Dated Paper
ER  -
''';

    final before = DateTime.now();
    final paper = parser.parse(ris).single;
    final after = DateTime.now();

    expect(paper.dateAdded.isBefore(before), isFalse);
    expect(paper.dateAdded.isAfter(after), isFalse);
    expect(paper.dateModified, paper.dateAdded);
  });
}
