import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';

BeaconViewState _authorState({
  BeaconStatus status = BeaconStatus.open,
  List<TimelineHelpOffer> helpOffers = const [],
  List<BeaconParticipant> roomParticipants = const [],
  ReviewWindowInfo? reviewWindowInfo,
  bool beaconContextLoaded = true,
  bool isLoading = false,
}) =>
    BeaconViewState(
      beacon: Beacon(
        id: 'b1',
        title: 'T',
        author: const Profile(id: 'uAuthor', displayName: 'Author'),
        createdAt: DateTime.utc(2026, 6, 20),
        updatedAt: DateTime.utc(2026, 6, 20),
        status: status,
      ),
      myProfile: const Profile(id: 'uAuthor', displayName: 'Author'),
      helpOffers: helpOffers,
      roomParticipants: roomParticipants,
      reviewWindowInfo: reviewWindowInfo,
      beaconContextLoaded: beaconContextLoaded,
      status: isLoading ? StateStatus.isLoading : const StateIsSuccess(),
    );

TimelineHelpOffer _offer({
  String id = 'h1',
  CoordinationResponseType? response,
}) =>
    TimelineHelpOffer(
      user: Profile(id: id, displayName: 'Helper $id'),
      message: 'help',
      createdAt: DateTime.utc(2026, 6, 20),
      updatedAt: DateTime.utc(2026, 6, 20),
      coordinationResponse: response,
    );

void main() {
  group('deriveBeaconHudAuthorAction', () {
    test('returns null before context loaded', () {
      expect(
        deriveBeaconHudAuthorAction(
          _authorState(beaconContextLoaded: false),
        ),
        isNull,
      );
    });

    test('returns null for steward', () {
      final state = BeaconViewState(
        beacon: Beacon(
          id: 'b1',
          title: 'T',
          author: const Profile(id: 'uAuthor', displayName: 'Author'),
          createdAt: DateTime.utc(2026, 6, 20),
          updatedAt: DateTime.utc(2026, 6, 20),
        ),
        myProfile: const Profile(id: 'uSteward', displayName: 'Steward'),
        roomParticipants: [
          BeaconParticipant(
            id: 'p1',
            beaconId: 'b1',
            userId: 'uSteward',
            role: BeaconParticipantRoleBits.steward,
            status: BeaconParticipantStatusBits.committed,
            roomAccess: RoomAccessBits.admitted,
            createdAt: DateTime.utc(2026, 6, 20),
            updatedAt: DateTime.utc(2026, 6, 20),
          ),
        ],
        beaconContextLoaded: true,
      );
      expect(deriveBeaconHudAuthorAction(state), isNull);
    });

    test('unanswered offers outrank enough help suggestion', () {
      final state = _authorState(
        helpOffers: [
          _offer(),
          _offer(id: 'h2', response: CoordinationResponseType.useful),
        ],
      );
      expect(
        deriveBeaconHudAuthorAction(state),
        BeaconHudAuthorAction.reviewOffers,
      );
    });

    test('reviewOpen author owes review', () {
      final state = _authorState(
        status: BeaconStatus.reviewOpen,
        reviewWindowInfo: const ReviewWindowInfo(
          beaconId: 'b1',
          hasWindow: true,
          userReviewStatus: 0,
          totalCount: 2,
        ),
      );
      expect(
        deriveBeaconHudAuthorAction(state),
        BeaconHudAuthorAction.reviewContributions,
      );
    });

    test('reviewOpen close now requires server canCloseNow', () {
      final withoutSnapshot = _authorState(status: BeaconStatus.reviewOpen);
      expect(deriveBeaconHudAuthorAction(withoutSnapshot), isNull);

      final waiting = _authorState(
        status: BeaconStatus.reviewOpen,
        reviewWindowInfo: const ReviewWindowInfo(
          beaconId: 'b1',
          hasWindow: true,
          userReviewStatus: 2,
          totalCount: 2,
          reviewedCount: 1,
          canCloseNow: false,
        ),
      );
      expect(deriveBeaconHudAuthorAction(waiting), isNull);

      final canClose = _authorState(
        status: BeaconStatus.reviewOpen,
        reviewWindowInfo: const ReviewWindowInfo(
          beaconId: 'b1',
          hasWindow: true,
          userReviewStatus: 2,
          totalCount: 2,
          canCloseNow: true,
        ),
      );
      expect(
        deriveBeaconHudAuthorAction(canClose),
        BeaconHudAuthorAction.closeNow,
      );
    });

    test('forward only in open or needsMoreHelp when no higher action', () {
      expect(
        deriveBeaconHudAuthorAction(_authorState()),
        BeaconHudAuthorAction.forward,
      );
      expect(
        deriveBeaconHudAuthorAction(
          _authorState(status: BeaconStatus.enoughHelp),
        ),
        isNull,
      );
    });
  });

  group('deriveBeaconHudAuthorActSpec labels', () {
    test('maps review offers label', () {
      final l10n = lookupL10n(const Locale('en'));
      final spec = deriveBeaconHudAuthorActSpec(
        l10n: l10n,
        state: _authorState(helpOffers: [_offer()]),
      );
      expect(spec?.label, 'Review offers');
      expect(spec?.filled, isTrue);
    });
  });
}
