import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/app/sentry/sentry_benign_filter.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';

void main() {
  test('expected business-rule errors are benign', () {
    for (final m in [
      'Plan text must be at most 60 characters',
      'Image is not attached to this request',
    ]) {
      expect(isBenignSentryThrowable(RemoteApiException(m)), isTrue, reason: m);
    }
    expect(
      isBenignSentryThrowable(Exception('Only open requests can be edited')),
      isTrue,
    );
    expect(isBenignSentryThrowable(const AuthSeedIsWrongException()), isTrue);
  });

  test('unexpected errors are still captured', () {
    expect(isBenignSentryThrowable(const RemoteApiException('boom')), isFalse);
    expect(isBenignSentryThrowable(StateError('x')), isFalse);
  });
}
