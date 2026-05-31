import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/oidc_identity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/oidc_case.dart';
import 'package:tentura_server/env.dart';

import 'invitation_case_mocks.mocks.dart';

void main() {
  late MockUserRepositoryPort userRepo;
  late MockInvitationRepositoryPort invitationRepo;
  late MockBeaconRepositoryPort beaconRepo;
  late MockVoteUserFriendshipLookup friendshipLookup;
  late InvitationCase invitationCase;
  late OidcCase case_;
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
    case_ = OidcCase(
      userRepo,
      invitationCase,
      env: env,
      logger: Logger('OidcCaseTest'),
    );
  });

  const identity = OidcIdentity(sub: 'google-sub', name: 'Ada');

  test('existing credential login without invite', () async {
    when(
      userRepo.getByCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenAnswer((_) async => const UserEntity(id: 'Uabc', displayName: 'Ada'));

    expect(await case_.completeGoogle(identity), 'Uabc');
  });

  test('new account without invite on invite-only server is rejected', () async {
    when(
      userRepo.getByCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenThrow(const IdNotFoundException());

    expect(
      () => case_.completeGoogle(identity),
      throwsA(isA<OidcInviteRequiredException>()),
    );
  });

  test('new account with invite creates invited credential account', () async {
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
    ).thenAnswer((_) async => const UserEntity(id: 'Unew', displayName: 'Ada'));

    expect(await case_.completeGoogle(identity, inviteId: 'Iabc'), 'Unew');
    verify(
      userRepo.createInvitedWithCredential(
        invitationId: 'Iabc',
        type: CredentialType.oidcGoogle,
        identifier: 'google-sub',
        displayName: 'Ada',
        handle: null,
        publicData: null,
      ),
    ).called(1);
  });
}
