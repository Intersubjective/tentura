import 'package:test/test.dart';

import 'package:tentura_server/api/util/attachment_content_disposition.dart';

void main() {
  group('attachmentDownloadContentDisposition', () {
    test('percent-encodes Cyrillic in filename*', () {
      final headers = attachmentDownloadContentDisposition('Отчёт.pdf');
      final cd = headers['Content-Disposition']!;
      expect(cd, contains("filename*=UTF-8''"));
      expect(cd, contains('%D0%9E%D1%82%D1%87%D1%91%D1%82.pdf'));
      expect(cd, isNot(contains('Отчёт')));
    });

    test('uses sanitized ASCII filename= fallback', () {
      final headers = attachmentDownloadContentDisposition('Отчёт.pdf');
      final cd = headers['Content-Disposition']!;
      expect(cd, contains('filename="_.pdf"'));
    });

    test('encodes quotes and parentheses for RFC 5987 attr-char', () {
      final headers = attachmentDownloadContentDisposition("Отчёт (v1)'!.pdf");
      final cd = headers['Content-Disposition']!;
      final star = cd.split("filename*=UTF-8''").last;
      expect(star, contains('%28'));
      expect(star, contains('%29'));
      expect(star, contains('%27'));
      expect(star, contains('%21'));
      expect(star.codeUnits.every((u) => u < 128), isTrue);
      expect(star, isNot(contains('Отчёт')));
    });

    test('header value is ASCII-only', () {
      final headers = attachmentDownloadContentDisposition('фото.png');
      final cd = headers['Content-Disposition']!;
      expect(cd.codeUnits.every((u) => u < 128), isTrue);
    });
  });
}
