import 'package:test/test.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

/// People tags errors live in their own code space and never echo the tag
/// name or glyph, because exception text reaches error reporting.
void main() {
  group('people tags exception codes', () {
    test('occupy code space 1900 in declaration order', () {
      expect(PeopleTagsExceptionCodes.codeSpace, 1900);
      expect(
        PeopleTagsExceptionCode.values.map((c) => c.name).toList(),
        [
          'tagNameTaken',
          'tagLimitReached',
          'memberLimitReached',
          'tagNotFound',
          'snapshotNotFound',
          'invalidTag',
          'opIdReused',
        ],
      );
      for (final code in PeopleTagsExceptionCode.values) {
        expect(
          PeopleTagsExceptionCodes(code).codeNumber,
          1900 + code.index,
        );
      }
    });

    test('every exception wire code is the code-space number', () {
      for (final code in PeopleTagsExceptionCode.values) {
        final exception = PeopleTagsException(peopleTagsCode: code);
        final extensions = exception.toMap['extensions']! as Map;
        expect(extensions['code'], '${1900 + code.index}');
        expect(exception.description, isNotEmpty);
      }
    });
  });
}
