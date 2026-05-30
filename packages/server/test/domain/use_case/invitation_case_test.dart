import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/entity/invite_preview_result.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';

import 'invitation_case_mocks.mocks.dart';

void main() {
  late MockInvitationRepositoryPort invitationRepo;
  late MockUserRepositoryPort userRepo;
  late MockBeaconRepositoryPort beaconRepo;
  late MockVoteUserFriendshipLookup friendshipLookup;
  late InvitationCase case_;

  const issuerId = 'Uissuer';
  final now = DateTime.now();

  InvitationEntity invitation({
    String id = 'Iabc',
    UserEntity? invited,
    String? beaconId,
    DateTime? createdAt,
  }) => InvitationEntity(
    id: id,
    issuer: const UserEntity(id: issuerId, displayName: 'Alice'),
    createdAt: createdAt ?? now,
    updatedAt: createdAt ?? now,
    invited: invited,
    beaconId: beaconId,
  );

  void stubGetById(InvitationEntity? inv) {
    when(
      invitationRepo.getById(invitationId: anyNamed('invitationId')),
    ).thenAnswer((_) async => inv);
  }

  setUp(() {
    invitationRepo = MockInvitationRepositoryPort();
    userRepo = MockUserRepositoryPort();
    beaconRepo = MockBeaconRepositoryPort();
    friendshipLookup = MockVoteUserFriendshipLookup();
    case_ = InvitationCase(
      invitationRepo,
      userRepo,
      beaconRepo,
      friendshipLookup,
      env: Env(environment: Environment.test),
      logger: Logger('InvitationCaseTest'),
    );
    // Default: caller is not a mutual friend of the issuer.
    when(
      friendshipLookup.isReciprocalSubscribe(
        viewerId: anyNamed('viewerId'),
        peerId: anyNamed('peerId'),
      ),
    ).thenAnswer((_) async => false);
  });

  group('InvitationCase.preview', () {
    test('unknown code -> invalid / anonymous', () async {
      stubGetById(null);
      final r = await case_.preview(code: 'Inope');
      expect(r.codeStatus, InviteCodeStatus.invalid);
      expect(r.callerStatus, InviteCallerStatus.anonymous);
      expect(r.inviter, isNull);
      expect(r.suggestedAction, 'invalid');
    });

    test('anonymous caller, available code -> accept-as-new', () async {
      stubGetById(invitation());
      final r = await case_.preview(code: 'Iabc');
      expect(r.codeStatus, InviteCodeStatus.available);
      expect(r.callerStatus, InviteCallerStatus.anonymous);
      expect(r.inviter?.id, issuerId);
      expect(r.suggestedAction, 'accept-as-new');
    });

    test('caller is the inviter -> is-inviter / self (blocked)', () async {
      stubGetById(invitation());
      final r = await case_.preview(code: 'Iabc', callerUserId: issuerId);
      expect(r.callerStatus, InviteCallerStatus.isInviter);
      expect(r.suggestedAction, 'self');
    });

    test('already-friends caller', () async {
      stubGetById(invitation());
      when(
        friendshipLookup.isReciprocalSubscribe(
          viewerId: 'Ufriend',
          peerId: issuerId,
        ),
      ).thenAnswer((_) async => true);
      final r = await case_.preview(code: 'Iabc', callerUserId: 'Ufriend');
      expect(r.callerStatus, InviteCallerStatus.alreadyFriends);
      expect(r.suggestedAction, 'already-friends');
    });

    test('existing non-friend user -> accept-as-existing', () async {
      stubGetById(invitation());
      final r = await case_.preview(code: 'Iabc', callerUserId: 'Ustranger');
      expect(r.callerStatus, InviteCallerStatus.existingUser);
      expect(r.suggestedAction, 'accept-as-existing');
    });

    test('consumed code (already accepted)', () async {
      stubGetById(invitation(invited: const UserEntity(id: 'Ujoiner')));
      final r = await case_.preview(code: 'Iabc');
      expect(r.codeStatus, InviteCodeStatus.consumed);
    });

    test('expired code', () async {
      stubGetById(
        invitation(createdAt: now.subtract(const Duration(days: 365))),
      );
      final r = await case_.preview(code: 'Iabc');
      expect(r.codeStatus, InviteCodeStatus.expired);
    });

    test('beacon-forward invite surfaces beacon in JSON', () async {
      stubGetById(invitation(beaconId: 'Bbeacon'));
      when(beaconRepo.getBeaconById(beaconId: 'Bbeacon')).thenAnswer(
        (_) async => BeaconEntity(
          id: 'Bbeacon',
          title: 'Shared beacon',
          author: const UserEntity(id: issuerId),
          createdAt: now,
          updatedAt: now,
          description: 'help needed',
        ),
      );
      final r = await case_.preview(code: 'Iabc');
      expect(r.beacon?.id, 'Bbeacon');
      final json = r.toJson();
      expect((json['beacon']! as Map)['title'], 'Shared beacon');
      expect((json['beacon']! as Map)['snippet'], 'help needed');
    });
  });

  group('InvitationCase.acceptAsExisting', () {
    void stubBindMutual({required bool result}) {
      when(
        userRepo.bindMutual(
          invitationId: anyNamed('invitationId'),
          userId: anyNamed('userId'),
        ),
      ).thenAnswer((_) async => result);
    }

    test('unknown code -> IdNotFoundException', () async {
      stubGetById(null);
      await expectLater(
        case_.acceptAsExisting(code: 'Inope', userId: 'Ustranger'),
        throwsA(isA<IdNotFoundException>()),
      );
    });

    test('self-invite -> InvitationWrongException (rejected)', () async {
      stubGetById(invitation());
      await expectLater(
        case_.acceptAsExisting(code: 'Iabc', userId: issuerId),
        throwsA(isA<InvitationWrongException>()),
      );
      verifyNever(
        userRepo.bindMutual(
          invitationId: anyNamed('invitationId'),
          userId: anyNamed('userId'),
        ),
      );
    });

    test('already-friends -> ok, never re-binds (retry-safe)', () async {
      stubGetById(invitation());
      when(
        friendshipLookup.isReciprocalSubscribe(
          viewerId: 'Ufriend',
          peerId: issuerId,
        ),
      ).thenAnswer((_) async => true);
      final ok = await case_.acceptAsExisting(code: 'Iabc', userId: 'Ufriend');
      expect(ok, isTrue);
      verifyNever(
        userRepo.bindMutual(
          invitationId: anyNamed('invitationId'),
          userId: anyNamed('userId'),
        ),
      );
    });

    test('consumed code, non-friend -> IdNotFoundException', () async {
      stubGetById(invitation(invited: const UserEntity(id: 'Ujoiner')));
      await expectLater(
        case_.acceptAsExisting(code: 'Iabc', userId: 'Ustranger'),
        throwsA(isA<IdNotFoundException>()),
      );
    });

    test('expired code, non-friend -> IdNotFoundException', () async {
      stubGetById(
        invitation(createdAt: now.subtract(const Duration(days: 365))),
      );
      await expectLater(
        case_.acceptAsExisting(code: 'Iabc', userId: 'Ustranger'),
        throwsA(isA<IdNotFoundException>()),
      );
    });

    test('available code, non-friend -> befriends via bindMutual', () async {
      stubGetById(invitation());
      stubBindMutual(result: true);
      final ok = await case_.acceptAsExisting(
        code: 'Iabc',
        userId: 'Ustranger',
      );
      expect(ok, isTrue);
      verify(
        userRepo.bindMutual(invitationId: 'Iabc', userId: 'Ustranger'),
      ).called(1);
    });
  });
}
