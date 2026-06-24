import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';
import 'package:test/test.dart';

void main() {
  group('isAllowedBeaconStatusSmallint', () {
    test('allows canonical values', () {
      for (final v in [0, 1, 2, 3, 5, 6, 7, 8]) {
        expect(isAllowedBeaconStatusSmallint(v), isTrue, reason: '$v');
      }
    });

    test('rejects legacy 4 and unknown', () {
      expect(isAllowedBeaconStatusSmallint(4), isFalse);
      expect(isAllowedBeaconStatusSmallint(99), isFalse);
    });
  });

  group('validateBeaconStatusTransition', () {
    test('noop when same status', () {
      final r = validateBeaconStatusTransition(
        from: BeaconStatus.open,
        to: BeaconStatus.open,
      );
      expect(r.verdict, BeaconStatusTransitionVerdict.noop);
    });

    test('allows open -> needsMoreHelp', () {
      final r = validateBeaconStatusTransition(
        from: BeaconStatus.open,
        to: BeaconStatus.needsMoreHelp,
      );
      expect(r.verdict, BeaconStatusTransitionVerdict.allowed);
    });

    test('disallows closed -> enoughHelp', () {
      final r = validateBeaconStatusTransition(
        from: BeaconStatus.closed,
        to: BeaconStatus.enoughHelp,
      );
      expect(r.verdict, BeaconStatusTransitionVerdict.disallowed);
    });

    test('disallows enoughHelp -> reviewOpen without open path', () {
      // enoughHelp -> reviewOpen is allowed via table
      final r = validateBeaconStatusTransition(
        from: BeaconStatus.enoughHelp,
        to: BeaconStatus.reviewOpen,
      );
      expect(r.verdict, BeaconStatusTransitionVerdict.allowed);
    });
  });
}
