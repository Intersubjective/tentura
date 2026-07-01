import 'package:test/test.dart';

import 'package:tentura_server/domain/util/debug_send_rate_limiter.dart';

void main() {
  test('first acquire allowed, second within window denied', () {
    final limiter = DebugSendRateLimiter(
      cooldown: const Duration(seconds: 10),
    );

    expect(limiter.tryAcquire('u1', DebugSendChannel.fcm), isTrue);
    expect(limiter.tryAcquire('u1', DebugSendChannel.fcm), isFalse);
  });

  test('fcm and email channels are independent', () {
    final limiter = DebugSendRateLimiter(
      cooldown: const Duration(seconds: 10),
    );

    expect(limiter.tryAcquire('u1', DebugSendChannel.fcm), isTrue);
    expect(limiter.tryAcquire('u1', DebugSendChannel.email), isTrue);
    expect(limiter.tryAcquire('u1', DebugSendChannel.fcm), isFalse);
    expect(limiter.tryAcquire('u1', DebugSendChannel.email), isFalse);
  });

  test('allowed again after cooldown', () async {
    final limiter = DebugSendRateLimiter(
      cooldown: const Duration(milliseconds: 50),
    );

    expect(limiter.tryAcquire('u1', DebugSendChannel.email), isTrue);
    expect(limiter.tryAcquire('u1', DebugSendChannel.email), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(limiter.tryAcquire('u1', DebugSendChannel.email), isTrue);
  });
}
