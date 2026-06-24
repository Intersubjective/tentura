import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/ui/bloc/state_base.dart';

Beacon _openBeacon({
  BeaconStatus status = BeaconStatus.open,
}) =>
    Beacon(
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
      id: 'b1',
      title: 'T',
      author: const Profile(id: 'uAuthor', displayName: 'Author'),
      status: status,
    );

BeaconViewState _baseAuthorState({
  Beacon? beacon,
  List<TimelineHelpOffer> helpOffers = const [],
  List<BeaconParticipant> roomParticipants = const [],
  BeaconRoomState? beaconRoomCue,
  List<BeaconActivityEvent> roomActivityEvents = const [],
  StateStatus status = const StateIsSuccess(),
  Profile myProfile = const Profile(id: 'uAuthor', displayName: 'Me'),
}) =>
    BeaconViewState(
      beacon: beacon ?? _openBeacon(),
      helpOffers: helpOffers,
      roomParticipants: roomParticipants,
      beaconRoomCue: beaconRoomCue,
      roomActivityEvents: roomActivityEvents,
      myProfile: myProfile,
      status: status,
    );

TimelineHelpOffer _helpOffer({
  required String userId,
  CoordinationResponseType? coordinationResponse,
  bool withdrawn = false,
}) =>
    TimelineHelpOffer(
      user: Profile(id: userId, displayName: userId),
      message: '',
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
      isWithdrawn: withdrawn,
      coordinationResponse: coordinationResponse,
    );

void main() {
  group('closeHardGate', () {
    test('false when not author', () {
      final s = _baseAuthorState(
        myProfile: const Profile(id: 'other', displayName: 'X'),
      );
      expect(closeHardGate(s), false);
    });

    test('false when lifecycle not open', () {
      final s = _baseAuthorState(
        beacon: _openBeacon().copyWith(status: BeaconStatus.closed),
      );
      expect(closeHardGate(s), false);
    });

    test('false when loading', () {
      final s = _baseAuthorState(status: StateStatus.isLoading);
      expect(closeHardGate(s), false);
    });

    test('false when author id empty', () {
      final s = _baseAuthorState(
        beacon: Beacon(
          createdAt: DateTime.utc(2025),
          updatedAt: DateTime.utc(2025),
          id: 'b1',
        ),
      );
      expect(closeHardGate(s), false);
    });

    test('true for loaded author open beacon', () {
      expect(closeHardGate(_baseAuthorState()), true);
    });
  });

  group('computeClosureReadiness', () {
    test('notCloseable when hard gate fails', () {
      expect(
        computeClosureReadiness(_baseAuthorState(status: StateStatus.isLoading)),
        BeaconClosureReadiness.notCloseable,
      );
    });

    test('blocked when open blocker title present', () {
      final s = _baseAuthorState(
        beaconRoomCue: BeaconRoomState(
          beaconId: 'b1',
          updatedAt: DateTime.utc(2025),
          openBlockerTitle: 'Airline slot',
        ),
      );
      expect(computeClosureReadiness(s), BeaconClosureReadiness.blocked);
    });

    test('blocked when coordination asks for more help', () {
      final s = _baseAuthorState(
        beacon: _openBeacon(
          status: BeaconStatus.needsMoreHelp,
        ),
      );
      expect(computeClosureReadiness(s), BeaconClosureReadiness.blocked);
    });

    test('enough help alone does not yield readyToClose', () {
      final s = _baseAuthorState(
        beacon: _openBeacon(
          status: BeaconStatus.enoughHelp,
        ),
        helpOffers: [
          _helpOffer(userId: 'h1'),
        ],
      );
      expect(computeClosureReadiness(s), isNot(BeaconClosureReadiness.readyToClose));
    });

    test('readyToClose when enoughHelp + useful + all relevant settled', () {
      final s = _baseAuthorState(
        beacon: _openBeacon(
          status: BeaconStatus.enoughHelp,
        ),
        helpOffers: [
          _helpOffer(
            userId: 'h1',
            coordinationResponse: CoordinationResponseType.useful,
          ),
        ],
        roomParticipants: [
          BeaconParticipant(
            id: 'p1',
            beaconId: 'b1',
            userId: 'h1',
            role: BeaconParticipantRoleBits.helper,
            status: BeaconParticipantStatusBits.done,
            roomAccess: RoomAccessBits.admitted,
            createdAt: DateTime.utc(2025),
            updatedAt: DateTime.utc(2025),
          ),
        ],
      );
      expect(computeClosureReadiness(s), BeaconClosureReadiness.readyToClose);
    });

    test('premature when neutral with offers and no strong path', () {
      final s = _baseAuthorState(
        beacon: _openBeacon(
          
        ),
        helpOffers: [
          _helpOffer(userId: 'h1'),
        ],
      );
      expect(
        computeClosureReadiness(s),
        BeaconClosureReadiness.premature,
      );
    });

    test('author participant needsInfo blocks → readiness blocked', () {
      final s = _baseAuthorState(
        roomParticipants: [
          BeaconParticipant(
            id: 'pa',
            beaconId: 'b1',
            userId: 'uAuthor',
            role: BeaconParticipantRoleBits.author,
            status: BeaconParticipantStatusBits.needsInfo,
            roomAccess: RoomAccessBits.admitted,
            createdAt: DateTime.utc(2025),
            updatedAt: DateTime.utc(2025),
          ),
        ],
      );
      expect(computeClosureReadiness(s), BeaconClosureReadiness.blocked);
    });

    test('helper needsInfo does not block in v1', () {
      final s = _baseAuthorState(
        helpOffers: [_helpOffer(userId: 'h1')],
        roomParticipants: [
          BeaconParticipant(
            id: 'p1',
            beaconId: 'b1',
            userId: 'h1',
            role: BeaconParticipantRoleBits.helper,
            status: BeaconParticipantStatusBits.needsInfo,
            roomAccess: RoomAccessBits.admitted,
            createdAt: DateTime.utc(2025),
            updatedAt: DateTime.utc(2025),
          ),
        ],
      );
      expect(computeClosureReadiness(s), isNot(BeaconClosureReadiness.blocked));
    });

    test('whole-beacon done signal via diffJson yields readyToClose', () {
      final s = _baseAuthorState(
        roomActivityEvents: [
          BeaconActivityEvent(
            id: 'e1',
            beaconId: 'b1',
            visibility: BeaconActivityEventVisibilityBits.room,
            type: BeaconActivityEventTypeBits.doneMarked,
            createdAt: DateTime.utc(2025),
            diffJson: '{"scope":"wholeBeacon"}',
          ),
        ],
      );
      expect(computeClosureReadiness(s), BeaconClosureReadiness.readyToClose);
    });

    test('message-kind doneMarked does not imply whole-beacon done', () {
      final s = _baseAuthorState(
        roomActivityEvents: [
          BeaconActivityEvent(
            id: 'e1',
            beaconId: 'b1',
            visibility: BeaconActivityEventVisibilityBits.room,
            type: BeaconActivityEventTypeBits.doneMarked,
            createdAt: DateTime.utc(2025),
            diffJson: '{"kind":"message"}',
          ),
        ],
      );
      expect(
        computeClosureReadiness(s),
        isNot(BeaconClosureReadiness.readyToClose),
      );
    });
  });

  group('closureActionPriorityFor', () {
    test('blocked maps to hidden when force disallowed', () {
      expect(
        closureActionPriorityFor(
          BeaconClosureReadiness.blocked,
          allowForceCloseWhenBlocked: false,
        ),
        ClosureActionPriority.hidden,
      );
    });

    test('blocked maps to overflow when force allowed', () {
      expect(
        closureActionPriorityFor(
          BeaconClosureReadiness.blocked,
          allowForceCloseWhenBlocked: true,
        ),
        ClosureActionPriority.overflow,
      );
    });

    test('matches kBeaconAllowForceCloseWhenBlocked default contract', () {
      expect(kBeaconAllowForceCloseWhenBlocked, false);
    });
  });
}
