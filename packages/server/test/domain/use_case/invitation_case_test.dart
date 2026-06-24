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
import '../../support/build_test_invitation_case.dart';
import '../../support/fake_beacon_access_guard.dart';

void main() {
  late MockInvitationRepositoryPort invitationRepo;
  late MockUserRepositoryPort userRepo;
  late MockBeaconRepositoryPort beaconRepo;
  late MockVoteUserFriendshipLookupPort friendshipLookup;
  late MockUserContactRepositoryPort contactRepo;
  late FakeBeaconAccessGuard guard;
  late InvitationCase case_;

  const issuerId = 'Uissuer';
  final now = DateTime.now();

  InvitationEntity invitation({
    String id = 'Iabc',
    UserEntity? invited,
    String? beaconId,
    DateTime? createdAt,
    String? addresseeName,
  }) => InvitationEntity(
    id: id,
    issuer: const UserEntity(id: issuerId, displayName: 'Alice'),
    createdAt: createdAt ?? now,
    updatedAt: createdAt ?? now,
    invited: invited,
    beaconId: beaconId,
    addresseeName: addresseeName,
  );

  void stubGetById(InvitationEntity? inv) {
    when(
      invitationRepo.getById(invitationId: anyNamed('invitationId')),
    ).thenAnswer((_) async => inv);
  }

  void stubContactName(String? name) {
    when(
      contactRepo.getName(
        viewerId: anyNamed('viewerId'),
        subjectId: anyNamed('subjectId'),
      ),
    ).thenAnswer((_) async => name);
  }

  setUp(() {
    invitationRepo = MockInvitationRepositoryPort();
    userRepo = MockUserRepositoryPort();
    beaconRepo = MockBeaconRepositoryPort();
    friendshipLookup = MockVoteUserFriendshipLookupPort();
    contactRepo = MockUserContactRepositoryPort();
    guard = FakeBeaconAccessGuard();
    case_ = buildTestInvitationCase(
      invitationRepo: invitationRepo,
      userRepo: userRepo,
      beaconRepo: beaconRepo,
      friendshipLookup: friendshipLookup,
      contactRepo: contactRepo,
      guard: guard,
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
    // Default: the caller has no contact entry for the issuer.
    stubContactName(null);
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

  group('InvitationCase.create / update — addressee name', () {
    test('create trims and stores the addressee name', () async {
      when(
        invitationRepo.create(
          issuerId: anyNamed('issuerId'),
          addresseeName: anyNamed('addresseeName'),
          beaconId: anyNamed('beaconId'),
        ),
      ).thenAnswer((_) async => invitation(addresseeName: 'Bob2000'));
      await case_.create(userId: issuerId, addresseeName: '  Bob2000  ');
      verify(
        invitationRepo.create(
          issuerId: issuerId,
          addresseeName: 'Bob2000',
        ),
      ).called(1);
    });

    test('create rejects a too-short addressee name', () async {
      await expectLater(
        case_.create(userId: issuerId, addresseeName: ' B '),
        throwsA(isA<IdWrongException>()),
      );
      verifyNever(
        invitationRepo.create(
          issuerId: anyNamed('issuerId'),
          addresseeName: anyNamed('addresseeName'),
          beaconId: anyNamed('beaconId'),
        ),
      );
    });

    test('update normalizes the name and delegates', () async {
      when(
        invitationRepo.updateAddresseeName(
          invitationId: anyNamed('invitationId'),
          userId: anyNamed('userId'),
          addresseeName: anyNamed('addresseeName'),
        ),
      ).thenAnswer((_) async => invitation(addresseeName: 'Bobby'));
      await case_.update(
        invitationId: 'Iabc',
        userId: issuerId,
        addresseeName: ' Bobby ',
      );
      verify(
        invitationRepo.updateAddresseeName(
          invitationId: 'Iabc',
          userId: issuerId,
          addresseeName: 'Bobby',
        ),
      ).called(1);
    });
  });

  group('InvitationCase.preview — subjective inviter name', () {
    test('signed-in caller sees the inviter under their contact name',
        () async {
      stubGetById(invitation());
      stubContactName('My Alice');
      final r = await case_.preview(code: 'Iabc', callerUserId: 'Ustranger');
      expect(r.inviter?.displayName, 'My Alice');
      verify(
        contactRepo.getName(viewerId: 'Ustranger', subjectId: issuerId),
      ).called(1);
    });

    test('anonymous caller sees the objective name, no contact lookup',
        () async {
      stubGetById(invitation(addresseeName: 'Bob2000'));
      final r = await case_.preview(code: 'Iabc');
      expect(r.inviter?.displayName, 'Alice');
      verifyNever(
        contactRepo.getName(
          viewerId: anyNamed('viewerId'),
          subjectId: anyNamed('subjectId'),
        ),
      );
    });

    test('inviter previewing their own code keeps their objective name',
        () async {
      stubGetById(invitation());
      final r = await case_.preview(code: 'Iabc', callerUserId: issuerId);
      expect(r.inviter?.displayName, 'Alice');
      verifyNever(
        contactRepo.getName(
          viewerId: anyNamed('viewerId'),
          subjectId: anyNamed('subjectId'),
        ),
      );
    });

    test('preview JSON never leaks the addressee name (privacy guard)',
        () async {
      stubGetById(invitation(addresseeName: 'Secret Pet Name'));
      final r = await case_.preview(code: 'Iabc', callerUserId: 'Ustranger');
      final flat = r.toJson().toString();
      expect(flat, isNot(contains('Secret Pet Name')));
      expect(flat.toLowerCase(), isNot(contains('addressee')));
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
