import 'package:test/test.dart';
import 'package:tentura/features/auth/data/service/stale_session_redirect_policy.dart';

void main() {
  group('shouldBounceRejectedSessionToLanding', () {
    test('bounces stale session on normal app paths', () {
      expect(
        shouldBounceRejectedSessionToLanding(pathname: '/', hash: ''),
        isTrue,
      );
      expect(
        shouldBounceRejectedSessionToLanding(
          pathname: '/',
          hash: '#/home/work',
        ),
        isTrue,
      );
      expect(
        shouldBounceRejectedSessionToLanding(
          pathname: '/settings',
          hash: '#/settings',
        ),
        isTrue,
      );
    });

    test('does not bounce on seed-recovery entry paths', () {
      expect(
        shouldBounceRejectedSessionToLanding(
          pathname: '/recover',
          hash: '#/recover-seed',
        ),
        isFalse,
      );
      expect(
        shouldBounceRejectedSessionToLanding(pathname: '/recover', hash: ''),
        isFalse,
      );
      expect(
        shouldBounceRejectedSessionToLanding(
          pathname: '/',
          hash: '#/recover-seed',
        ),
        isFalse,
      );
    });
  });
}
