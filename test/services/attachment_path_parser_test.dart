import 'package:flutter_test/flutter_test.dart';
import 'package:papers/features/import/services/attachment_path_parser.dart';

void main() {
  group('BibTeX file field', () {
    test('Zotero Unix: description:path:mimetype', () {
      expect(
        AttachmentPathParser.fromBibtexFileField(
            'Full Text PDF:/home/me/Zotero/storage/AB/Smith 2020.pdf:application/pdf'),
        ['/home/me/Zotero/storage/AB/Smith 2020.pdf'],
      );
    });

    test('Zotero Windows: escaped colon and doubled backslashes', () {
      expect(
        AttachmentPathParser.fromBibtexFileField(
            r'Full Text PDF:C\:\\Users\\me\\Zotero\\f.pdf:application/pdf'),
        [r'C:\Users\me\Zotero\f.pdf'],
      );
    });

    test('Mendeley Unix: empty description', () {
      expect(
        AttachmentPathParser.fromBibtexFileField(
            '/Users/me/Documents/paper.pdf:pdf'),
        ['/Users/me/Documents/paper.pdf'],
      );
      expect(
        AttachmentPathParser.fromBibtexFileField(
            ':/Users/me/Documents/paper.pdf:pdf'),
        ['/Users/me/Documents/paper.pdf'],
      );
    });

    test('Mendeley Windows: \$\\backslash\$ backslash escape', () {
      expect(
        AttachmentPathParser.fromBibtexFileField(
            r':C$\backslash$:$\backslash$Users$\backslash$me$\backslash$f.pdf:pdf'),
        [r'C:\Users\me\f.pdf'],
      );
    });

    test('JabRef relative path', () {
      expect(
        AttachmentPathParser.fromBibtexFileField('files/10/paper.pdf:PDF'),
        ['files/10/paper.pdf'],
      );
      expect(
        AttachmentPathParser.fromBibtexFileField(':files/10/paper.pdf:PDF'),
        ['files/10/paper.pdf'],
      );
    });

    test('description that is itself a filename (Mendeley naming)', () {
      expect(
        AttachmentPathParser.fromBibtexFileField(
            'Smith - 2020 - Title.pdf:/home/me/Smith - 2020 - Title.pdf:pdf'),
        ['/home/me/Smith - 2020 - Title.pdf'],
      );
    });

    test('file:// URI with percent-encoding', () {
      expect(
        AttachmentPathParser.fromBibtexFileField(
            'file:///home/me/a%20paper.pdf'),
        ['/home/me/a paper.pdf'],
      );
      expect(
        AttachmentPathParser.fromBibtexFileField('file://C:/Users/me/f.pdf'),
        ['C:/Users/me/f.pdf'],
      );
    });

    test('multiple attachments: only the PDF is kept', () {
      expect(
        AttachmentPathParser.fromBibtexFileField(
            'Snapshot:/home/me/page.html:text/html;'
            'Full Text PDF:/home/me/paper.pdf:application/pdf'),
        ['/home/me/paper.pdf'],
      );
    });

    test('non-PDF attachment yields nothing', () {
      expect(
        AttachmentPathParser.fromBibtexFileField(
            'EPUB:/home/me/book.epub:application/epub+zip'),
        isEmpty,
      );
      expect(AttachmentPathParser.fromBibtexFileField(''), isEmpty);
    });
  });

  group('RIS link', () {
    test('bare path', () {
      expect(
        AttachmentPathParser.fromRisLink('/Users/me/paper.pdf'),
        '/Users/me/paper.pdf',
      );
    });

    test('file:// URI', () {
      expect(
        AttachmentPathParser.fromRisLink('file://C:/Users/me/paper.pdf'),
        'C:/Users/me/paper.pdf',
      );
    });

    test('non-PDF link is null', () {
      expect(AttachmentPathParser.fromRisLink('https://example.com/'), isNull);
    });
  });
}
