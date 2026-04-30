import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';

TimelineCommitment _commitmentMe({
  required Profile me,
  CoordinationResponseType? coordinationResponse,
}) =>
    TimelineCommitment(
      user: me,
      message: '',
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      coordinationResponse: coordinationResponse,
    );

void main() {
  const author = Profile(id: 'auth', title: 'Author');
  const me = Profile(id: 'me', title: 'Me');
  final beacon =
      Beacon.empty.copyWith(id: 'Bxxxx', updatedAt: DateTime(2025), author: author);

  test('committed non-author gains room admission unless notSuitable', () {
    final noSignal = BeaconViewState(
      beacon: beacon,
      commitments: [_commitmentMe(me: me)],
      isCommitted: true,
      myProfile: me,
    );
    expect(noSignal.hasRoomAdmission, isFalse);
    expect(noSignal.canNavigateBeaconRoom, isFalse);

    final useful = BeaconViewState(
      beacon: beacon,
      commitments: [
        _commitmentMe(me: me, coordinationResponse: CoordinationResponseType.useful),
      ],
      isCommitted: true,
      myProfile: me,
    );
    expect(useful.hasRoomAdmission, isTrue);
    expect(useful.canNavigateBeaconRoom, isTrue);

    final rejected = BeaconViewState(
      beacon: beacon,
      commitments: [
        _commitmentMe(
          me: me,
          coordinationResponse: CoordinationResponseType.notSuitable,
        ),
      ],
      isCommitted: true,
      myProfile: me,
    );
    expect(rejected.hasRoomAdmission, isFalse);
    expect(rejected.coordinationDeniesRoomAdmission, isTrue);
  });

  test('non-author without commitment cannot open room', () {
    final notCommitted = BeaconViewState(
      beacon: beacon,
      myProfile: me,
    );
    expect(notCommitted.canNavigateBeaconRoom, isFalse);
    expect(notCommitted.isRoomAdmissionBlocked, isFalse);
  });

  test('beacon owner always has canNavigateBeaconRoom', () {
    final ownerCommits = BeaconViewState(
      beacon:
          Beacon.empty.copyWith(id: 'Bbbbb', updatedAt: DateTime(2025), author: me),
      commitments: [
        TimelineCommitment(
          user: me,
          message: '',
          createdAt: DateTime(2025),
          updatedAt: DateTime(2025),
        ),
      ],
      isCommitted: true,
      myProfile: me,
    );
    expect(ownerCommits.isBeaconMine, isTrue);
    expect(ownerCommits.canNavigateBeaconRoom, isTrue);
  });
}
