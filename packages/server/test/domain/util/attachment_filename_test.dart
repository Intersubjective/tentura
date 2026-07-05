import 'package:test/test.dart';

import 'package:tentura_server/domain/util/attachment_filename.dart';

void main() {
  group('attachmentDisplayName', () {
    test('preserves Cyrillic and extension', () {
      expect(attachmentDisplayName('Отчёт.pdf'), 'Отчёт.pdf');
    });

    test('returns file for empty input', () {
      expect(attachmentDisplayName(''), 'file');
      expect(attachmentDisplayName('   '), 'file');
    });

    test('returns file for dot-only names', () {
      expect(attachmentDisplayName('.'), 'file');
      expect(attachmentDisplayName('..'), 'file');
    });

    test('strips directory segments from unix and windows paths', () {
      expect(
        attachmentDisplayName(r'C:\Users\me\docs\Отчёт.pdf'),
        'Отчёт.pdf',
      );
      expect(
        attachmentDisplayName('/tmp/uploads/фото (1).png'),
        'фото (1).png',
      );
    });

    test('removes control chars and quotes', () {
      expect(attachmentDisplayName('ab\u0007cd"ef.txt'), 'abcdef.txt');
    });

    test('truncates to 200 characters', () {
      final raw = '${'а' * 250}.txt';
      final result = attachmentDisplayName(raw);
      expect(result.length, 200);
      expect(result, 'а' * 200);
    });
  });
}
