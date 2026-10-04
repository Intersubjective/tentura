import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/test_attention_harness.dart';
import 'forward_case_mocks.mocks.dart' show MockForwardEdgeRepositoryPort;
import 'invitation_case_mocks.mocks.dart';

const _authorId = 'Uauthor';
const _nonAuthorId = 'Uhelper';
const _joinerId = 'Ujoiner';
const _beaconId = 'Bbeacon';
const _invitationId = 'Iabc';

/// Records each lock and runs [onLocked], which stands for another
/// transaction committing a change while this one waited for the lock.
final class _RecordingPostLock implements PostLockPort {
  final lockedBeaconIds = <String>[];
  void Function()? onLocked;

  @override
  Future<void> lockForPostMutation(String beaconId) async {
    lockedBeaconIds.add(beaconId);
    onLocked?.call();
  }
}

/// One way an invite to a beacon is turned into a forward: issuing it or
/// accepting it. `run` performs the operation as the invite's issuer.
typedef _Operation = ({
  String name,
  Future<void> Function(String issuerId) run,
  void Function(String issuerId) verifyEffect,
  void Function() verifyNoEffect,
  Matcher refusal,
});

void main() {
  late MockInvitationRepositoryPort invitationRepo;
  late MockUserRepositoryPort userRepo;
  late MockBeaconRepositoryPort beaconRepo;
  late MockVoteUserFriendshipLookupPort friendshipLookup;
  late MockUserContactRepositoryPort contactRepo;
  late MockForwardEdgeRepositoryPort forwardEdgeRepo;
  late _RecordingPostLock postLock;
  late InvitationCase case_;
  late BeaconEntity current;

  final now = DateTime.utc(2026);

  BeaconEntity beacon({
    required BeaconKind kind,
    required BeaconForwardPolicyValue policy,
    BeaconStatus status = BeaconStatus.open,
  }) => BeaconEntity(
    id: _beaconId,
    title: kind == BeaconKind.post ? '' : 'Request title',
    author: const UserEntity(id: _authorId),
    createdAt: now,
    updatedAt: now,
    status: status,
    kind: kind,
    forwardPolicy: policy,
  );

  void stubBeacon(BeaconEntity value) => current = value;

  InvitationEntity invitation({required String issuerId}) => InvitationEntity(
    id: _invitationId,
    issuer: UserEntity(id: issuerId, displayName: 'Issuer'),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    beaconId: _beaconId,
  );

  void stubInvitation(String issuerId) {
    when(
      invitationRepo.getById(invitationId: _invitationId),
    ).thenAnswer((_) async => invitation(issuerId: issuerId));
  }

  void verifyNothingBound() {
    verifyNever(
      userRepo.bindMutual(
        invitationId: anyNamed('invitationId'),
        userId: anyNamed('userId'),
        bindFriendship: anyNamed('bindFriendship'),
      ),
    );
  }

  void verifyBound({required bool bindFriendship}) {
    verify(
      userRepo.bindMutual(
        invitationId: _invitationId,
        userId: _joinerId,
        bindFriendship: bindFriendship,
      ),
    ).called(1);
  }

  final operations = <_Operation>[
    (
      name: 'create',
      run: (issuerId) => case_.create(
        userId: issuerId,
        addresseeName: 'Friend',
        beaconId: _beaconId,
      ),
      verifyEffect: (issuerId) => verify(
        invitationRepo.create(
          issuerId: issuerId,
          addresseeName: anyNamed('addresseeName'),
          beaconId: _beaconId,
          parentForwardEdgeId: anyNamed('parentForwardEdgeId'),
        ),
      ).called(1),
      verifyNoEffect: () => verifyNever(
        invitationRepo.create(
          issuerId: anyNamed('issuerId'),
          addresseeName: anyNamed('addresseeName'),
          beaconId: anyNamed('beaconId'),
          parentForwardEdgeId: anyNamed('parentForwardEdgeId'),
        ),
      ),
      refusal: isA<UnauthorizedException>(),
    ),
    (
      name: 'accept',
      run: (issuerId) async {
        stubInvitation(issuerId);
        await case_.accept(invitationId: _invitationId, userId: _joinerId);
      },
      verifyEffect: (_) => verifyBound(bindFriendship: true),
      verifyNoEffect: verifyNothingBound,
      refusal: anyOf(isA<UnauthorizedException>(), isA<IdNotFoundException>()),
    ),
    (
      name: 'acceptAsExisting',
      run: (issuerId) async {
        stubInvitation(issuerId);
        await case_.acceptAsExisting(code: _invitationId, userId: _joinerId);
      },
      verifyEffect: (_) => verifyBound(bindFriendship: false),
      verifyNoEffect: verifyNothingBound,
      refusal: anyOf(isA<UnauthorizedException>(), isA<IdNotFoundException>()),
    ),
  ];

  setUp(() {
    invitationRepo = MockInvitationRepositoryPort();
    userRepo = MockUserRepositoryPort();
    beaconRepo = MockBeaconRepositoryPort();
    friendshipLookup = MockVoteUserFriendshipLookupPort();
    contactRepo = MockUserContactRepositoryPort();
    forwardEdgeRepo = MockForwardEdgeRepositoryPort();
    postLock = _RecordingPostLock();
    final attention = TestAttentionHarness();
    current = beacon(
      kind: BeaconKind.request,
      policy: BeaconForwardPolicyValue.open,
    );

    case_ = InvitationCase(
      invitationRepo,
      userRepo,
      beaconRepo,
      friendshipLookup,
      contactRepo,
      FakeBeaconAccessGuard(),
      forwardEdgeRepo,
      FakeUserBlockRepository(),
      postLock: postLock,
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: Env(environment: Environment.test),
      logger: Logger('InvitationCasePostPolicyTest'),
    );

    when(
      beaconRepo.getBeaconById(beaconId: anyNamed('beaconId')),
    ).thenAnswer((_) async => current);
    when(
      forwardEdgeRepo.fetchActiveInboundEdges(
        beaconId: anyNamed('beaconId'),
        recipientId: anyNamed('recipientId'),
      ),
    ).thenAnswer((_) async => []);
    when(
      friendshipLookup.isReciprocalSubscribe(
        viewerId: anyNamed('viewerId'),
        peerId: anyNamed('peerId'),
      ),
    ).thenAnswer((_) async => false);
    when(userRepo.getById(_joinerId)).thenAnswer(
      (_) async => const UserEntity(id: _joinerId, displayName: 'Joiner'),
    );
    when(
      userRepo.bindMutual(
        invitationId: anyNamed('invitationId'),
        userId: anyNamed('userId'),
        bindFriendship: anyNamed('bindFriendship'),
      ),
    ).thenAnswer((_) async => true);
    when(
      invitationRepo.create(
        issuerId: anyNamed('issuerId'),
        addresseeName: anyNamed('addresseeName'),
        beaconId: anyNamed('beaconId'),
        parentForwardEdgeId: anyNamed('parentForwardEdgeId'),
      ),
    ).thenAnswer(
      (invocation) async => invitation(
        issuerId: invocation.namedArguments[#issuerId]! as String,
      ),
    );
  });

  for (final op in operations) {
    group('InvitationCase.${op.name} for a beacon invite', () {
      group('on a Post with closed forwarding', () {
        setUp(() {
          stubBeacon(
            beacon(
              kind: BeaconKind.post,
              policy: BeaconForwardPolicyValue.closed,
            ),
          );
        });

        test('refuses a non-author issuer and creates no edge', () async {
          await expectLater(op.run(_nonAuthorId), throwsA(op.refusal));
          op.verifyNoEffect();
        });

        test('takes the Post lock before refusing a non-author', () async {
          await expectLater(op.run(_nonAuthorId), throwsA(op.refusal));
          expect(postLock.lockedBeaconIds, [_beaconId]);
        });

        test('lets the author issuer through under the Post lock', () async {
          await op.run(_authorId);

          op.verifyEffect(_authorId);
          expect(postLock.lockedBeaconIds, [_beaconId]);
        });
      });

      group('on a Post with open forwarding', () {
        test('lets a non-author issuer through under the Post lock', () async {
          stubBeacon(
            beacon(
              kind: BeaconKind.post,
              policy: BeaconForwardPolicyValue.open,
            ),
          );

          await op.run(_nonAuthorId);

          op.verifyEffect(_nonAuthorId);
          expect(postLock.lockedBeaconIds, [_beaconId]);
        });

        test('judges the policy as it stands after the Post lock is taken, '
            'when the author opened forwarding meanwhile', () async {
          stubBeacon(
            beacon(
              kind: BeaconKind.post,
              policy: BeaconForwardPolicyValue.closed,
            ),
          );
          postLock.onLocked = () => stubBeacon(
            beacon(
              kind: BeaconKind.post,
              policy: BeaconForwardPolicyValue.open,
            ),
          );

          await op.run(_nonAuthorId);

          op.verifyEffect(_nonAuthorId);
        });

        test('judges the status as it stands after the Post lock is taken, '
            'when the Post was deleted meanwhile', () async {
          stubBeacon(
            beacon(
              kind: BeaconKind.post,
              policy: BeaconForwardPolicyValue.open,
            ),
          );
          postLock.onLocked = () => stubBeacon(
            beacon(
              kind: BeaconKind.post,
              policy: BeaconForwardPolicyValue.open,
              status: BeaconStatus.deleted,
            ),
          );

          await expectLater(op.run(_authorId), throwsA(op.refusal));
          op.verifyNoEffect();
          expect(postLock.lockedBeaconIds, [_beaconId]);
        });
      });

      group('when the beacon is no longer open', () {
        test('refuses an invite to a Request', () async {
          stubBeacon(
            beacon(
              kind: BeaconKind.request,
              policy: BeaconForwardPolicyValue.open,
              status: BeaconStatus.closed,
            ),
          );

          await expectLater(op.run(_nonAuthorId), throwsA(op.refusal));
          op.verifyNoEffect();
        });

        test('refuses an invite to a Post', () async {
          stubBeacon(
            beacon(
              kind: BeaconKind.post,
              policy: BeaconForwardPolicyValue.open,
              status: BeaconStatus.closed,
            ),
          );

          await expectLater(op.run(_authorId), throwsA(op.refusal));
          op.verifyNoEffect();
        });
      });

      group('on an open Request', () {
        test('lets a non-author issuer through without a Post lock', () async {
          stubBeacon(
            beacon(
              kind: BeaconKind.request,
              policy: BeaconForwardPolicyValue.open,
            ),
          );

          await op.run(_nonAuthorId);

          op.verifyEffect(_nonAuthorId);
          expect(postLock.lockedBeaconIds, isEmpty);
        });
      });
    });
  }
}
