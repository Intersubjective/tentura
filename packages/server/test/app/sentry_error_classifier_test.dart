import 'package:test/test.dart';

import 'package:tentura_server/app/sentry/sentry_error_classifier.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

void main() {
  group('isInternalFaultException', () {
    test('UnspecifiedException is internal fault', () {
      expect(
        isInternalFaultException(const UnspecifiedException()),
        isTrue,
      );
    });

    test('UnauthorizedException is expected domain rejection', () {
      expect(
        isInternalFaultException(const UnauthorizedException()),
        isFalse,
      );
    });

    test('EvaluationException notEligible is expected', () {
      expect(
        isInternalFaultException(
          EvaluationException(
            code: EvaluationExceptionCode.notEligible,
          ),
        ),
        isFalse,
      );
    });

    test('EvaluationException unspecified is internal fault', () {
      expect(
        isInternalFaultException(
          EvaluationException(
            code: EvaluationExceptionCode.unspecified,
          ),
        ),
        isTrue,
      );
    });
  });
}
