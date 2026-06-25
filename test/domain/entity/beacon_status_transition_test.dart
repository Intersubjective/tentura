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
    const allowedTransitions = <(BeaconStatus, BeaconStatus)>{
      // Create / publish
      (BeaconStatus.draft, BeaconStatus.open),
      // Open-family coordination intent
      (BeaconStatus.open, BeaconStatus.needsMoreHelp),
      (BeaconStatus.needsMoreHelp, BeaconStatus.open),
      (BeaconStatus.open, BeaconStatus.enoughHelp),
      (BeaconStatus.enoughHelp, BeaconStatus.open),
      (BeaconStatus.needsMoreHelp, BeaconStatus.enoughHelp),
      (BeaconStatus.enoughHelp, BeaconStatus.needsMoreHelp),
      // Cancel / close from open-family
      (BeaconStatus.open, BeaconStatus.cancelled),
      (BeaconStatus.needsMoreHelp, BeaconStatus.cancelled),
      (BeaconStatus.enoughHelp, BeaconStatus.cancelled),
      (BeaconStatus.open, BeaconStatus.closed),
      (BeaconStatus.needsMoreHelp, BeaconStatus.closed),
      (BeaconStatus.enoughHelp, BeaconStatus.closed),
      (BeaconStatus.open, BeaconStatus.reviewOpen),
      (BeaconStatus.needsMoreHelp, BeaconStatus.reviewOpen),
      (BeaconStatus.enoughHelp, BeaconStatus.reviewOpen),
      // Review window
      (BeaconStatus.reviewOpen, BeaconStatus.open),
      (BeaconStatus.reviewOpen, BeaconStatus.needsMoreHelp),
      (BeaconStatus.reviewOpen, BeaconStatus.enoughHelp),
      (BeaconStatus.reviewOpen, BeaconStatus.closed),
      // Delete
      (BeaconStatus.draft, BeaconStatus.deleted),
      (BeaconStatus.open, BeaconStatus.deleted),
      (BeaconStatus.needsMoreHelp, BeaconStatus.deleted),
      (BeaconStatus.enoughHelp, BeaconStatus.deleted),
      (BeaconStatus.cancelled, BeaconStatus.deleted),
      (BeaconStatus.closed, BeaconStatus.deleted),
      (BeaconStatus.reviewOpen, BeaconStatus.deleted),
    };

    const forbiddenTransitions = <(BeaconStatus, BeaconStatus)>{
      (BeaconStatus.closed, BeaconStatus.open),
      (BeaconStatus.draft, BeaconStatus.closed),
      (BeaconStatus.closed, BeaconStatus.enoughHelp),
      (BeaconStatus.deleted, BeaconStatus.open),
      (BeaconStatus.cancelled, BeaconStatus.open),
      (BeaconStatus.draft, BeaconStatus.needsMoreHelp),
      (BeaconStatus.reviewOpen, BeaconStatus.draft),
      (BeaconStatus.cancelled, BeaconStatus.closed),
      (BeaconStatus.closed, BeaconStatus.reviewOpen),
      (BeaconStatus.open, BeaconStatus.draft),
    };

    test('allowed transition matrix', () {
      expect(allowedTransitions, hasLength(27));

      for (final (from, to) in allowedTransitions) {
        final result = validateBeaconStatusTransition(from: from, to: to);
        expect(
          result.verdict,
          BeaconStatusTransitionVerdict.allowed,
          reason: '$from -> $to',
        );
        expect(result.message, isNull, reason: '$from -> $to');
      }
    });

    test('forbidden transition matrix', () {
      expect(forbiddenTransitions.length, greaterThanOrEqualTo(8));

      for (final (from, to) in forbiddenTransitions) {
        final result = validateBeaconStatusTransition(from: from, to: to);
        expect(
          result.verdict,
          BeaconStatusTransitionVerdict.disallowed,
          reason: '$from -> $to',
        );
        expect(
          result.message,
          'Transition $from -> $to is not allowed',
          reason: '$from -> $to',
        );
      }
    });

    test('noop when from equals to', () {
      for (final status in BeaconStatus.values) {
        final result = validateBeaconStatusTransition(from: status, to: status);
        expect(
          result.verdict,
          BeaconStatusTransitionVerdict.noop,
          reason: '$status -> $status',
        );
        expect(result.message, isNull, reason: '$status -> $status');
      }
    });
  });

  group('coordinationTargetStatus', () {
    test('maps more-help smallints (legacy 2, canonical 7)', () {
      for (final v in [2, 7]) {
        expect(
          coordinationTargetStatus(v),
          BeaconStatus.needsMoreHelp,
          reason: '$v',
        );
      }
    });

    test('maps enough-help smallints (legacy 3, canonical 8)', () {
      for (final v in [3, 8]) {
        expect(
          coordinationTargetStatus(v),
          BeaconStatus.enoughHelp,
          reason: '$v',
        );
      }
    });

    test('defaults to open for neutral and unknown smallints', () {
      for (final v in [0, 1, 4, 5, 6, 99]) {
        expect(
          coordinationTargetStatus(v),
          BeaconStatus.open,
          reason: '$v',
        );
      }
    });
  });

  group('reasonStringForTransition', () {
    const expectedReasonStrings = <BeaconStatusTransitionReason, String>{
      BeaconStatusTransitionReason.publish: 'published',
      BeaconStatusTransitionReason.needsMoreHelp: 'needsMoreHelp',
      BeaconStatusTransitionReason.enoughHelp: 'enoughHelp',
      BeaconStatusTransitionReason.neutralOpen: 'neutralOpen',
      BeaconStatusTransitionReason.reviewWindowOpened: 'reviewWindowOpened',
      BeaconStatusTransitionReason.directClose: 'directClose',
      BeaconStatusTransitionReason.authorCloseNow: 'authorCloseNow',
      BeaconStatusTransitionReason.reviewExpired: 'reviewExpired',
      BeaconStatusTransitionReason.reopenedFromReview: 'reopenedFromReview',
      BeaconStatusTransitionReason.cancelled: 'cancelled',
      BeaconStatusTransitionReason.deleted: 'deleted',
    };

    test('maps every reason to a non-empty stable string', () {
      expect(
        expectedReasonStrings.keys,
        containsAll(BeaconStatusTransitionReason.values),
      );

      for (final reason in BeaconStatusTransitionReason.values) {
        final expected = expectedReasonStrings[reason]!;
        final once = reasonStringForTransition(reason);
        final again = reasonStringForTransition(reason);

        expect(once, expected, reason: reason.name);
        expect(once, isNotEmpty, reason: reason.name);
        expect(again, once, reason: '${reason.name} stability');
      }
    });

    test('produces unique strings per reason', () {
      final strings = BeaconStatusTransitionReason.values
          .map(reasonStringForTransition)
          .toList();

      expect(strings, hasLength(strings.toSet().length));
    });
  });
}
