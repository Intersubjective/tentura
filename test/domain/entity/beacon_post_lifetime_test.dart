import 'package:tentura_root/domain/entity/beacon_post_lifetime.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:test/test.dart';

const _kindRequest = 0;
const _kindPost = 1;

void main() {
  final now = DateTime.utc(2030, 6, 1, 12);
  final past = now.subtract(const Duration(seconds: 1));
  final future = now.add(const Duration(seconds: 1));

  bool isExpired({
    required int kind,
    required BeaconStatus status,
    required DateTime? expiresAt,
  }) => BeaconPostLifetime.isExpired(
    kind: kind,
    status: status,
    expiresAt: expiresAt,
    now: now,
  );

  group('Post lifetime constants', () {
    test('a Post lives at most 72 hours', () {
      expect(BeaconPostLifetime.max, const Duration(hours: 72));
    });

    test('the author is warned 3 hours before expiry', () {
      expect(BeaconPostLifetime.warnBefore, const Duration(hours: 3));
    });
  });

  group('BeaconPostLifetime.isExpired', () {
    test('a Request is never expired, whatever its expiry says', () {
      expect(
        isExpired(
          kind: _kindRequest,
          status: BeaconStatus.open,
          expiresAt: past,
        ),
        isFalse,
      );
      expect(
        isExpired(
          kind: _kindRequest,
          status: BeaconStatus.open,
          expiresAt: null,
        ),
        isFalse,
      );
    });

    test('a draft Post is not expired', () {
      expect(
        isExpired(kind: _kindPost, status: BeaconStatus.draft, expiresAt: past),
        isFalse,
      );
      expect(
        isExpired(
          kind: _kindPost,
          status: BeaconStatus.draft,
          expiresAt: null,
        ),
        isFalse,
      );
    });

    test('an open Post whose expiry is in the future is not expired', () {
      expect(
        isExpired(
          kind: _kindPost,
          status: BeaconStatus.open,
          expiresAt: future,
        ),
        isFalse,
      );
    });

    test('an open Post without an expiry is not expired', () {
      expect(
        isExpired(
          kind: _kindPost,
          status: BeaconStatus.open,
          expiresAt: null,
        ),
        isFalse,
      );
    });

    test('an open Post whose expiry is in the past is expired', () {
      expect(
        isExpired(kind: _kindPost, status: BeaconStatus.open, expiresAt: past),
        isTrue,
      );
    });

    test('an open Post whose expiry is exactly now is expired', () {
      expect(
        isExpired(kind: _kindPost, status: BeaconStatus.open, expiresAt: now),
        isTrue,
      );
    });

    test('a closed Post is closed, not expired', () {
      expect(
        isExpired(
          kind: _kindPost,
          status: BeaconStatus.closed,
          expiresAt: past,
        ),
        isFalse,
      );
    });
  });
}
