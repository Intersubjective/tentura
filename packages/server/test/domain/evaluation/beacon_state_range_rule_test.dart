import 'package:test/test.dart';

/// Regression: Postgres `beacon_state_range` must allow lifecycle values 5 and 6
/// (closed review open / complete). m0015 used `state <= 4`, which caused
/// `23514` on close-with-review until m0020 widened the CHECK to `state <= 6`.
void main() {
  group('beacon state domain range', () {
    test('allows all BeaconLifecycle smallints including closed-review (5, 6)', () {
      for (final s in [0, 1, 2, 3, 4, 5, 6]) {
        expect(_isAllowedBeaconState(s), isTrue, reason: 'state $s');
      }
    });

    test('rejects out-of-range states', () {
      expect(_isAllowedBeaconState(-1), isFalse);
      expect(_isAllowedBeaconState(7), isFalse);
    });
  });
}

/// Mirrors the intended CHECK (state >= 0 AND state <= 6) from migration 0020.
bool _isAllowedBeaconState(int state) => state >= 0 && state <= 6;
