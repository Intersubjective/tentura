import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #474: which completion checks are unmet comes with the close summary, a
// backup offer is never "not settled", and the counts read as real plurals.

BeaconViewState _authorState(
  List<TimelineHelpOffer> offers, {
  BeaconStatus status = BeaconStatus.open,
}) => BeaconViewState(
  beacon: Beacon(
    createdAt: DateTime.utc(2025),
    updatedAt: DateTime.utc(2025),
    id: 'b1',
    title: 'T',
    author: const Profile(id: 'uAuthor', displayName: 'Author'),
    status: status,
  ),
  helpOffers: offers,
  myProfile: const Profile(id: 'uAuthor', displayName: 'Me'),
);

TimelineHelpOffer _offer(
  String userId, {
  CoordinationResponseType? response,
  int offerKind = TimelineHelpOffer.offerKindRegular,
}) => TimelineHelpOffer(
  user: Profile(id: userId, displayName: userId),
  message: '',
  createdAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2025),
  coordinationResponse: response,
  offerKind: offerKind,
);

void main() {
  group('close summary missing criteria', () {
    test('lists only the unmet check while waiting for review', () {
      final state = _authorState([
        _offer('u1', response: CoordinationResponseType.useful),
      ]);

      final summary = buildClosureConfirmationSummary(state);

      expect(summary.readiness, BeaconClosureReadiness.waitingForReview);
      expect(summary.missingCriteria, {BeaconClosureCriterion.enoughHelp});
      expect(summary.allChecksPass, isFalse);
    });

    test('is empty when every check passes', () {
      final state = _authorState(
        [_offer('u1', response: CoordinationResponseType.useful)],
        status: BeaconStatus.enoughHelp,
      );

      final summary = buildClosureConfirmationSummary(state);

      expect(summary.readiness, BeaconClosureReadiness.readyToClose);
      expect(summary.missingCriteria, isEmpty);
      expect(summary.allChecksPass, isTrue);
    });

    test('lists both evidence checks for a premature close', () {
      final state = _authorState(const []);

      final summary = buildClosureConfirmationSummary(state);

      expect(summary.readiness, BeaconClosureReadiness.premature);
      expect(summary.missingCriteria, {
        BeaconClosureCriterion.enoughHelp,
        BeaconClosureCriterion.usefulOrDoneResult,
      });
    });

    test('an ordinary unsettled offer is still a missing check', () {
      final state = _authorState(
        [
          _offer('u1', response: CoordinationResponseType.useful),
          _offer('u2'),
        ],
        status: BeaconStatus.enoughHelp,
      );

      final summary = buildClosureConfirmationSummary(state);

      expect(summary.unsettledRelevantCount, 1);
      expect(summary.readiness, BeaconClosureReadiness.waitingForReview);
      expect(summary.missingCriteria, {BeaconClosureCriterion.offersSettled});
    });
  });

  group('backup offers', () {
    test('a backup offer kept on standby is not counted as unsettled', () {
      final state = _authorState(
        [
          _offer('u1', response: CoordinationResponseType.useful),
          _offer('uFay', offerKind: TimelineHelpOffer.offerKindBackup),
        ],
        status: BeaconStatus.enoughHelp,
      );

      final summary = buildClosureConfirmationSummary(state);

      expect(summary.unsettledRelevantCount, 0);
      expect(allRelevantHelpOffersSettled(state), isTrue);
      expect(summary.readiness, BeaconClosureReadiness.readyToClose);
      expect(summary.missingCriteria, isEmpty);
    });
  });

  group('unsettled and unanswered counts are plurals', () {
    test('RU uses the right form for 1, 3 and 5', () {
      final ru = lookupL10n(const Locale('ru'));

      expect(
        ru.beaconCloseSheetEvidenceUnsettledCount(1),
        '1 предложение помощи не доведено до ясного статуса',
      );
      expect(
        ru.beaconCloseSheetEvidenceUnsettledCount(3),
        '3 предложения помощи не доведены до ясного статуса',
      );
      expect(
        ru.beaconCloseSheetEvidenceUnsettledCount(5),
        '5 предложений помощи не доведены до ясного статуса',
      );
      expect(
        ru.beaconCloseSheetEvidenceUnansweredCount(1),
        '1 предложение помощи ждёт вашей координации',
      );
      expect(
        ru.beaconCloseSheetEvidenceUnansweredCount(5),
        '5 предложений помощи ждут вашей координации',
      );
    });

    test('EN has no (s) hack', () {
      final en = lookupL10n(const Locale('en'));

      expect(
        en.beaconCloseSheetEvidenceUnsettledCount(1),
        '1 help offer not settled',
      );
      expect(
        en.beaconCloseSheetEvidenceUnsettledCount(3),
        '3 help offers not settled',
      );
      expect(
        en.beaconCloseSheetEvidenceUnansweredCount(1),
        '1 help offer awaits coordination review',
      );
    });
  });
}
