// #527 (review): the showcase shows its own "Withdraw offer" under a waiting
// offer in every status that allows withdrawing, but More actions hid its
// Withdraw only while the Request was Open, so Enough help and Wrapping up
// showed Withdraw twice.

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_app_bar_overflow.dart';

import 'beacon_view_screen_harness.dart';

void main() {
  const me = Profile(id: 'dave', displayName: 'Dave');

  BeaconViewState waitingOffer(BeaconStatus status) {
    final author = beaconViewHarnessAuthorState();
    return author.copyWith(
      beacon: author.beacon.copyWith(status: status),
      myProfile: me,
      helpOffers: [
        TimelineHelpOffer(
          user: me,
          message: 'I have a van',
          createdAt: kBeaconViewHarnessNow,
          updatedAt: kBeaconViewHarnessNow,
        ),
      ],
      isHelpOffered: true,
    );
  }

  for (final status in [
    BeaconStatus.open,
    BeaconStatus.enoughHelp,
    BeaconStatus.reviewOpen,
  ]) {
    test('More actions hides Withdraw while the showcase shows it '
        '(${status.name})', () {
      final state = waitingOffer(status);

      expect(beaconShowcaseShowsWithdraw(state), isTrue);
      expect(hideOfferHelpWithdrawFromOverflow(state), isTrue);
    });
  }

  // Guard: once the Request is finished neither surface offers Withdraw, and
  // the overflow rule for a finished Request stays as it was.
  test('a closed Request shows no showcase Withdraw', () {
    final state = waitingOffer(BeaconStatus.closed);

    expect(beaconShowcaseShowsWithdraw(state), isFalse);
    expect(hideOfferHelpWithdrawFromOverflow(state), isFalse);
  });
}
