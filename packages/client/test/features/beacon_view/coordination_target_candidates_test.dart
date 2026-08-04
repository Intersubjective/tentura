import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/coordination_target_candidates.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

BeaconParticipant _participant({
  required String userId,
  String userTitle = '',
  String handle = '',
}) {
  final t = DateTime.utc(2025, 1, 2);
  return BeaconParticipant(
    id: 'P-$userId',
    beaconId: 'B1',
    userId: userId,
    role: BeaconParticipantRoleBits.helper,
    status: BeaconParticipantStatusBits.committed,
    roomAccess: RoomAccessBits.admitted,
    userTitle: userTitle,
    handle: handle,
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  final l10n = L10nEn();
  const myUserId = 'Ume0000000001';
  const authorId = 'Uauthor000001';
  const otherId = 'Uother0000001';
  const rawUuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

  test('askTargetUserIds excludes myUserId', () {
    final ids = askTargetUserIds(
      beaconAuthorId: authorId,
      participants: [
        _participant(userId: myUserId),
        _participant(userId: otherId),
      ],
      myUserId: myUserId,
    );
    expect(ids, contains(authorId));
    expect(ids, contains(otherId));
    expect(ids, isNot(contains(myUserId)));
  });

  test('hasPublishedAskTargets false when only self would qualify', () {
    expect(
      hasPublishedAskTargets(
        beaconAuthorId: myUserId,
        participants: [_participant(userId: myUserId)],
        myUserId: myUserId,
      ),
      isFalse,
    );
  });

  test('hasPublishedAskTargets true when another participant exists', () {
    expect(
      hasPublishedAskTargets(
        beaconAuthorId: myUserId,
        participants: [_participant(userId: otherId)],
        myUserId: myUserId,
      ),
      isTrue,
    );
  });

  group('coordinationTargetLabel', () {
    test('returns labelMe for viewer id', () {
      expect(
        coordinationTargetLabel(
          userId: myUserId,
          participants: [],
          viewerId: myUserId,
          l10n: l10n,
        ),
        l10n.labelMe,
      );
    });

    test('uses userTitle when present', () {
      expect(
        coordinationTargetLabel(
          userId: otherId,
          participants: [_participant(userId: otherId, userTitle: 'Alice')],
          viewerId: myUserId,
          l10n: l10n,
        ),
        'Alice',
      );
    });

    test('uses @handle when title missing', () {
      expect(
        coordinationTargetLabel(
          userId: otherId,
          participants: [_participant(userId: otherId, handle: 'alice')],
          viewerId: myUserId,
          l10n: l10n,
        ),
        '@alice',
      );
    });

    test('uses placeholder when identity missing', () {
      expect(
        coordinationTargetLabel(
          userId: rawUuid,
          participants: [_participant(userId: rawUuid)],
          viewerId: myUserId,
          l10n: l10n,
        ),
        l10n.unknownPerson,
      );
    });

    test('uses placeholder when participant not in list', () {
      final label = coordinationTargetLabel(
        userId: rawUuid,
        participants: [],
        viewerId: myUserId,
        l10n: l10n,
      );
      expect(label, l10n.unknownPerson);
      expect(label, isNot(contains(rawUuid)));
    });
  });

  group('Profile.displayLabel', () {
    test('prefers contact name over display name and handle', () {
      const profile = Profile(
        id: rawUuid,
        contactName: 'Local',
        displayName: 'Display',
        handle: 'handle',
      );
      expect(profile.displayLabel(l10n.unknownPerson), 'Local');
    });

    test('falls back to @handle then placeholder', () {
      const profile = Profile(id: rawUuid, handle: 'alice');
      expect(profile.displayLabel(l10n.unknownPerson), '@alice');

      const bare = Profile(id: rawUuid);
      expect(bare.displayLabel(l10n.unknownPerson), l10n.unknownPerson);
      expect(bare.displayLabel(l10n.unknownPerson), isNot(contains(rawUuid)));
    });
  });

  group('BeaconParticipant.displayLabel', () {
    test('falls back through title, handle, placeholder', () {
      final withTitle = _participant(userId: otherId, userTitle: 'Bob');
      expect(withTitle.displayLabel(l10n.unknownPerson), 'Bob');

      final withHandle = _participant(userId: otherId, handle: 'bob');
      expect(withHandle.displayLabel(l10n.unknownPerson), '@bob');

      final bare = _participant(userId: rawUuid);
      expect(bare.displayLabel(l10n.unknownPerson), l10n.unknownPerson);
    });
  });
}
