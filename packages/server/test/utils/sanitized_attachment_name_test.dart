import 'package:test/test.dart';

import 'package:tentura_server/utils/sanitized_attachment_name.dart';

void main() {
  group('sanitizedAttachmentBaseName', () {
    test('returns file for empty input', () {
      expect(sanitizedAttachmentBaseName(''), 'file');
      expect(sanitizedAttachmentBaseName('   '), 'file');
    });

    test('strips directory segments from unix and windows paths', () {
      expect(
        sanitizedAttachmentBaseName(r'C:\Users\me\docs\report final.pdf'),
        'report_final.pdf',
      );
      expect(
        sanitizedAttachmentBaseName('/tmp/uploads/photo (1).png'),
        'photo_1_.png',
      );
    });

    test('replaces unsafe characters with underscores', () {
      expect(
        sanitizedAttachmentBaseName('my file@name!.txt'),
        'my_file_name_.txt',
      );
    });

    test('truncates to 200 characters before sanitizing', () {
      final raw = '${'a' * 250}.txt';
      final sanitized = sanitizedAttachmentBaseName(raw);
      final expected = 'a' * 200;
      expect(sanitized.length, 200);
      expect(sanitized, expected);
    });
  });
}
