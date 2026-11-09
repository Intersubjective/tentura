import 'package:test/test.dart';

import 'package:tentura_server/domain/closure/closure_exception.dart'
    as legacy_path;
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

/// Pins that the FCM and closure exception types, now kept with the other
/// domain exception types under lib/domain/exception/, are reachable through
/// package:tentura_server/domain/exception.dart with the same class names,
/// codes and wire strings as before the move.
void main() {
  String wire(String message, int code) =>
      '{"message":"$message","extensions":{"code":"$code","path":""}}';

  group('FCM exceptions via domain/exception.dart', () {
    test('FcmTokenNotFoundException', () {
      const e = FcmTokenNotFoundException(token: 't1');
      expect(e.runtimeType.toString(), 'FcmTokenNotFoundException');
      expect(e.code.codeNumber, 1002);
      expect(e.token, 't1');
      expect(e.toString(), wire('Token not found: [t1]', 1002));
    });

    test('FcmUnauthorizedException', () {
      const e = FcmUnauthorizedException();
      expect(e.runtimeType.toString(), 'FcmUnauthorizedException');
      expect(e.code.codeNumber, 1000);
      expect(e.toString(), wire('Fcm unauthorized', 1000));
    });

    test('FcmMessageRejectedException', () {
      const e = FcmMessageRejectedException(token: 't2', errorCode: 'E');
      expect(e.runtimeType.toString(), 'FcmMessageRejectedException');
      expect(e.code.codeNumber, 1000);
      expect(e.token, 't2');
      expect(e.errorCode, 'E');
      expect(e.toString(), wire('FCM rejected token [t2]: E', 1000));
    });
  });

  group('ClosureException via domain/exception.dart', () {
    final cases = <(ClosureException, ClosureExceptionCode, String, int)>[
      (
        const ClosureException.notAuthor(),
        ClosureExceptionCode.notAuthor,
        'notAuthor',
        1800,
      ),
      (
        const ClosureException.notVoter(),
        ClosureExceptionCode.notVoter,
        'notVoter',
        1801,
      ),
      (
        const ClosureException.notMember(),
        ClosureExceptionCode.notMember,
        'notMember',
        1802,
      ),
      (
        const ClosureException.staleEpoch(),
        ClosureExceptionCode.staleEpoch,
        'staleEpoch',
        1803,
      ),
      (
        const ClosureException.wrongStatus(),
        ClosureExceptionCode.wrongStatus,
        'wrongStatus',
        1804,
      ),
      (
        const ClosureException.reopenLimit(),
        ClosureExceptionCode.reopenLimit,
        'reopenLimit',
        1805,
      ),
      (
        const ClosureException.extendLimit(),
        ClosureExceptionCode.extendLimit,
        'extendLimit',
        1806,
      ),
      (
        const ClosureException.notReady(),
        ClosureExceptionCode.notReady,
        'notReady',
        1807,
      ),
      (
        const ClosureException.invalidSplit(),
        ClosureExceptionCode.invalidSplit,
        'invalidSplit',
        1808,
      ),
      (
        const ClosureException.splitTooLarge(),
        ClosureExceptionCode.splitTooLarge,
        'splitTooLarge',
        1809,
      ),
    ];

    for (final (e, closureCode, message, code) in cases) {
      test(message, () {
        expect(e, isA<ExceptionBase>());
        expect(e.runtimeType.toString(), 'ClosureException');
        expect(e.closureCode, closureCode);
        expect(e.code.codeNumber, code);
        expect(e.toString(), wire(message, code));
      });
    }

    test('old import path re-exports the same type', () {
      const legacy = legacy_path.ClosureException.notVoter();
      expect(legacy, isA<ClosureException>());
      expect(legacy.closureCode, legacy_path.ClosureExceptionCode.notVoter);
      expect(identical(legacy, const ClosureException.notVoter()), isTrue);
    });
  });
}
