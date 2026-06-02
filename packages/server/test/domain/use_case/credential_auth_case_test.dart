import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import 'invitation_case_mocks.mocks.dart';

void main() {
  late MockUserRepositoryPort userRepo;
  late MockInvitationRepositoryPort invitationRepo;
  late MockBeaconRepositoryPort beaconRepo;
  late MockVoteUserFriendshipLookup friendshipLookup;
  late InvitationCase invitationCase;
  late CredentialAuthCase case_;
  late Env env;

  setUp(() {
    userRepo = MockUserRepositoryPort();
    invitationRepo = MockInvitationRepositoryPort();
    beaconRepo = MockBeaconRepositoryPort();
    friendshipLookup = MockVoteUserFriendshipLookup();
    env = Env(environment: Environment.test, isNeedInvite: true);
    invitationCase = InvitationCase(
      invitationRepo,
      userRepo,
      beaconRepo,
      friendshipLookup,
      env: env,
      logger: Logger('InvitationCaseTest'),
    );
    case_ = CredentialAuthCase(
      userRepo,
      invitationCase,
      env: env,
      logger: Logger('CredentialAuthCaseTest'),
    );
  });

  test('existing email credential logs in', () async {
    when(
      userRepo.getByCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenAnswer(
      (_) async => const UserEntity(id: 'Uabc', displayName: 'Ada'),
    );

    final id = await case_.resolveOrCreate(
      type: CredentialType.emailOtp,
      identifier: 'ada@example.com',
      displayName: 'ada',
    );

    expect(id, 'Uabc');
    verify(
      userRepo.getByCredential(
        type: 'email_otp',
        identifier: 'ada@example.com',
      ),
    ).called(1);
    verifyNever(
      userRepo.createInvitedWithCredential(
        invitationId: anyNamed('invitationId'),
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
        displayName: anyNamed('displayName'),
        handle: anyNamed('handle'),
        publicData: anyNamed('publicData'),
      ),
    );
  });

  test('new email credential with invite creates invited account', () async {
    when(
      userRepo.getByCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenThrow(const IdNotFoundException());
    when(
      userRepo.createInvitedWithCredential(
        invitationId: anyNamed('invitationId'),
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
        displayName: anyNamed('displayName'),
        handle: anyNamed('handle'),
        publicData: anyNamed('publicData'),
      ),
    ).thenAnswer(
      (_) async => const UserEntity(id: 'Unew', displayName: 'ada'),
    );

    final id = await case_.resolveOrCreate(
      type: CredentialType.emailOtp,
      identifier: 'ada@example.com',
      displayName: 'ada',
      inviteId: 'Iabc',
    );

    expect(id, 'Unew');
    verify(
      userRepo.createInvitedWithCredential(
        invitationId: 'Iabc',
        type: CredentialType.emailOtp,
        identifier: 'ada@example.com',
        displayName: 'ada',
        handle: null,
        publicData: null,
      ),
    ).called(1);
  });

  test('new credential without invite on invite-only server is rejected', () async {
    when(
      userRepo.getByCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenThrow(const IdNotFoundException());

    expect(
      () => case_.resolveOrCreate(
        type: CredentialType.emailOtp,
        identifier: 'new@example.com',
        displayName: 'new',
      ),
      throwsA(isA<OidcInviteRequiredException>()),
    );
  });
}
