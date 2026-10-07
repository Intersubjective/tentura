import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/ui/bloc/state_base.dart';

BeaconParticipant _admittedHelper(String userId, {String? roleLabel}) =>
    BeaconParticipant(
      id: 'p-$userId',
      beaconId: 'b1',
      userId: userId,
      role: 0,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
      roleLabel: roleLabel,
    );

BeaconViewState _authorState(
  List<TimelineHelpOffer> offers, {
  List<BeaconParticipant> participants = const [],
}) => BeaconViewState(
  beacon: Beacon(
    createdAt: DateTime.utc(2025),
    updatedAt: DateTime.utc(2025),
    id: 'b1',
    title: 'T',
    author: const Profile(id: 'uAuthor', displayName: 'Author'),
    status: BeaconStatus.open,
  ),
  helpOffers: offers,
  roomParticipants: participants,
  myProfile: const Profile(id: 'uAuthor', displayName: 'Me'),
  status: const StateIsSuccess(),
);

TimelineHelpOffer _offer(String userId, {String? roleLabel}) =>
    TimelineHelpOffer(
      user: Profile(id: userId, displayName: userId),
      message: '',
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
      roleLabel: roleLabel,
    );

void main() {
  group('close confirmation counts of unsettled offers', () {
    test('offers with an assigned role are settled', () {
      final state = _authorState([
        _offer('u1', roleLabel: 'Driver'),
        _offer('u2', roleLabel: 'Cook'),
        _offer('u3', roleLabel: 'Host'),
      ]);

      final summary = buildClosureConfirmationSummary(state);

      expect(summary.relevantHelpOffersCount, 3);
      expect(summary.unsettledRelevantCount, 0);
    });

    test(
      'three admitted helpers carried over from a post, all with roles, '
      'leave nothing unsettled',
      () {
        final state = _authorState(
          [
            _offer('u1', roleLabel: 'Driver'),
            _offer('u2', roleLabel: 'Cook'),
            _offer('u3', roleLabel: 'Host'),
          ],
          participants: [
            _admittedHelper('u1', roleLabel: 'Driver'),
            _admittedHelper('u2', roleLabel: 'Cook'),
            _admittedHelper('u3', roleLabel: 'Host'),
          ],
        );

        final summary = buildClosureConfirmationSummary(state);

        expect(summary.relevantHelpOffersCount, 3);
        expect(summary.unsettledRelevantCount, 0);
        for (final o in state.helpOffers) {
          expect(helpOfferRowSettled(o, state), isTrue, reason: o.user.id);
        }
      },
    );

    test('an offer without a role stays unsettled', () {
      final state = _authorState([
        _offer('u1', roleLabel: 'Driver'),
        _offer('u2'),
        _offer('u3', roleLabel: ''),
      ]);

      final summary = buildClosureConfirmationSummary(state);

      expect(summary.unsettledRelevantCount, 2);
    });

    test('helpOfferRowSettled is true for an assigned role', () {
      final state = _authorState(const []);

      expect(helpOfferRowSettled(_offer('u1', roleLabel: 'Driver'), state), isTrue);
      expect(helpOfferRowSettled(_offer('u1'), state), isFalse);
    });
  });
}
