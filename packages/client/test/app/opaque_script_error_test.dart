import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/sentry/opaque_script_error.dart';

void main() {
  group('isOpaqueScriptErrorLiteral', () {
    test('matches opaque literals with case and whitespace', () {
      expect(isOpaqueScriptErrorLiteral('Script error.'), isTrue);
      expect(isOpaqueScriptErrorLiteral('  SCRIPT ERROR  '), isTrue);
      expect(isOpaqueScriptErrorLiteral('script error.'), isTrue);
      expect(isOpaqueScriptErrorLiteral('Script error'), isTrue);
    });

    test('rejects prefixed or real Flutter messages', () {
      expect(isOpaqueScriptErrorLiteral('Exception: Script error.'), isFalse);
      expect(
        isOpaqueScriptErrorLiteral('Null check operator used on a null value'),
        isFalse,
      );
      expect(isOpaqueScriptErrorLiteral(null), isFalse);
      expect(isOpaqueScriptErrorLiteral(''), isFalse);
    });
  });

  group('isOpaqueBrowserScriptErrorEvent', () {
    test('drops when every candidate is an opaque literal', () {
      expect(
        isOpaqueBrowserScriptErrorEvent(
          exceptionValues: ['Script error.'],
        ),
        isTrue,
      );
      expect(
        isOpaqueBrowserScriptErrorEvent(
          message: '  script error. ',
          exceptionValues: ['SCRIPT ERROR'],
        ),
        isTrue,
      );
    });

    test('keeps mixed opaque and real exception payloads', () {
      expect(
        isOpaqueBrowserScriptErrorEvent(
          exceptionValues: [
            'Script error.',
            'Null check operator used on a null value',
          ],
        ),
        isFalse,
      );
    });

    test('keeps prefixed script error messages', () {
      expect(
        isOpaqueBrowserScriptErrorEvent(
          message: 'Exception: Script error.',
        ),
        isFalse,
      );
    });

    test('keeps empty candidate sets', () {
      expect(isOpaqueBrowserScriptErrorEvent(), isFalse);
      expect(
        isOpaqueBrowserScriptErrorEvent(
          message: '',
          exceptionValues: ['', null],
        ),
        isFalse,
      );
    });

    test('reads object message fields defensively', () {
      expect(
        isOpaqueBrowserScriptErrorEvent(
          messageFormatted: 'Script error.',
        ),
        isTrue,
      );
      expect(
        isOpaqueBrowserScriptErrorEvent(
          messageObjectMessage: 'script error',
        ),
        isTrue,
      );
      expect(
        isOpaqueBrowserScriptErrorEvent(
          messageFormatted: 'Script error.',
          messageObjectMessage: 'Null check operator used on a null value',
        ),
        isFalse,
      );
    });
  });
}
