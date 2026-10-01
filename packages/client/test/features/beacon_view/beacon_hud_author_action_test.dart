import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';

BeaconViewState _authorState({
  BeaconStatus status = BeaconStatus.open,
  List<TimelineHelpOffer> helpOffers = const [],
  List<BeaconParticipant> roomParticipants = const [],
  ClosureState? closureState,
  bool beaconContextLoaded = true,
  bool isLoading = false,
}) => BeaconViewState(
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
  closureState: closureState,
  beaconContextLoaded: beaconContextLoaded,
  status: isLoading ? StateStatus.isLoading : const StateIsSuccess(),
);

TimelineHelpOffer _offer({
  String id = 'h1',
  CoordinationResponseType? response,
  int roomAccess = 0,
}) => TimelineHelpOffer(
  user: Profile(id: id, displayName: 'Helper $id'),
  message: 'help',
  createdAt: DateTime.utc(2026, 6, 20),
  updatedAt: DateTime.utc(2026, 6, 20),
  coordinationResponse: response,
  roomAccess: roomAccess,
  stakeState:
      response == CoordinationResponseType.useful ||
          response == CoordinationResponseType.needCoordination
      ? CommitmentStakeState.acknowledged
      : CommitmentStakeState.none,
);

ClosureState _closure({required bool canCloseNow}) => ClosureState(
  epoch: 1,
  status: BeaconStatus.reviewOpen.smallintValue,
  role: ClosureRole.author,
  members: const [],
  closesAt: DateTime.utc(2026, 6, 27),
  canCloseNow: canCloseNow,
);

void main() {
  group('wrapping-up HUD', () {
    test('no closure snapshot offers no action', () {
      expect(
        deriveBeaconHudAuthorAction(
          _authorState(status: BeaconStatus.reviewOpen),
        ),
        isNull,
      );
    });

    for (final canCloseNow in [false, true]) {
      for (final isAuthor in [true, false]) {
        test('canCloseNow=$canCloseNow author=$isAuthor', () {
          final state = _authorState(
            status: BeaconStatus.reviewOpen,
            closureState: _closure(canCloseNow: canCloseNow),
          ).copyWith(myProfile: Profile(id: isAuthor ? 'uAuthor' : 'helper'));
          expect(
            deriveBeaconHudAuthorAction(state),
            isAuthor && canCloseNow ? BeaconHudAuthorAction.closeNow : null,
          );
        });
      }
    }

    test('a closed request offers no action even with a stale snapshot', () {
      final state = _authorState(
        status: BeaconStatus.closed,
        closureState: _closure(canCloseNow: true),
      );
      expect(deriveBeaconHudAuthorAction(state), isNull);
    });
  });

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

    test(
      'auto-admitted offer without coordination is not unanswered',
      () {
        final state = _authorState(
          helpOffers: [
            _offer(
              id: 'auto',
              roomAccess: RoomAccessBits.admitted,
            ),
            _offer(id: 'ok', response: CoordinationResponseType.useful),
          ],
        );
        expect(
          deriveBeaconHudAuthorAction(state),
          BeaconHudAuthorAction.markEnoughHelp,
        );
      },
    );

    test(
      'auto-admitted with enoughHelp offers wrap up not reviewOffers',
      () {
        final state = _authorState(
          status: BeaconStatus.enoughHelp,
          helpOffers: [
            _offer(
              id: 'auto',
              roomAccess: RoomAccessBits.admitted,
            ),
            _offer(id: 'ok', response: CoordinationResponseType.useful),
          ],
        );
        expect(
          deriveBeaconHudAuthorAction(state),
          BeaconHudAuthorAction.wrapUpForReview,
        );
      },
    );

    test(
      'admitted participant without offer roomAccess is not unanswered',
      () {
        final state = _authorState(
          helpOffers: [
            _offer(id: 'auto'),
            _offer(id: 'ok', response: CoordinationResponseType.useful),
          ],
          roomParticipants: [
            BeaconParticipant(
              id: 'p-auto',
              beaconId: 'b1',
              userId: 'auto',
              role: BeaconParticipantRoleBits.helper,
              status: BeaconParticipantStatusBits.committed,
              roomAccess: RoomAccessBits.admitted,
              createdAt: DateTime.utc(2026, 6, 20),
              updatedAt: DateTime.utc(2026, 6, 20),
            ),
          ],
        );
        expect(
          deriveBeaconHudAuthorAction(state),
          BeaconHudAuthorAction.markEnoughHelp,
        );
      },
    );

    test('truly pending offer still yields reviewOffers', () {
      final state = _authorState(
        helpOffers: [
          _offer(id: 'pending'),
          _offer(id: 'ok', response: CoordinationResponseType.useful),
        ],
      );
      expect(
        deriveBeaconHudAuthorAction(state),
        BeaconHudAuthorAction.reviewOffers,
      );
    });

    test('no forward ACT; open idle author has null HUD action', () {
      expect(deriveBeaconHudAuthorAction(_authorState()), isNull);
      expect(
        deriveBeaconHudAuthorAction(
          _authorState(status: BeaconStatus.enoughHelp),
        ),
        isNull,
      );
    });

    test('blocked coordination suppresses lifecycle ACT', () {
      expect(
        deriveBeaconHudAuthorAction(
          _authorState(status: BeaconStatus.needsMoreHelp),
        ),
        isNull,
      );
    });

    test('enoughHelp waitingForReview offers wrap up', () {
      final state = _authorState(
        status: BeaconStatus.enoughHelp,
        helpOffers: [
          _offer(response: CoordinationResponseType.useful),
        ],
      );
      expect(
        deriveBeaconHudAuthorAction(state),
        BeaconHudAuthorAction.wrapUpForReview,
      );
    });

    test('open blocker without personal responsibility offers resolve', () {
      final state = _authorState().copyWith(
        beaconRoomCue: BeaconRoomState(
          beaconId: 'b1',
          updatedAt: DateTime.utc(2026, 6, 20),
          openBlockerTitle: 'Waiting on vendor',
        ),
      );
      expect(
        deriveBeaconHudAuthorAction(state),
        BeaconHudAuthorAction.resolveBlocker,
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
      expect(
        spec?.effectLine,
        'Opens People; accept adds helper to the discussion',
      );
      expect(
        spec?.semanticsLabel,
        'Review offers. Opens People; accept adds helper to the discussion',
      );
      expect(
        spec?.effectPresentation,
        BeaconHudAuthorActEffectPresentation.tooltip,
      );
    });
  });

  group('effectPresentationForBeaconHudAuthorAction', () {
    test('maps each action to disclosure mode', () {
      expect(
        effectPresentationForBeaconHudAuthorAction(
          BeaconHudAuthorAction.reviewOffers,
        ),
        BeaconHudAuthorActEffectPresentation.tooltip,
      );
      expect(
        effectPresentationForBeaconHudAuthorAction(
          BeaconHudAuthorAction.markEnoughHelp,
        ),
        BeaconHudAuthorActEffectPresentation.hiddenKeepSemantics,
      );
      expect(
        effectPresentationForBeaconHudAuthorAction(
          BeaconHudAuthorAction.closeNow,
        ),
        BeaconHudAuthorActEffectPresentation.hiddenKeepSemantics,
      );
      expect(
        effectPresentationForBeaconHudAuthorAction(
          BeaconHudAuthorAction.resolveBlocker,
        ),
        BeaconHudAuthorActEffectPresentation.mutedSubtitle,
      );
      expect(
        effectPresentationForBeaconHudAuthorAction(
          BeaconHudAuthorAction.wrapUpForReview,
        ),
        BeaconHudAuthorActEffectPresentation.mutedSubtitle,
      );
    });
  });
}
