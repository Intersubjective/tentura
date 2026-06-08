import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/oidc_identity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/oidc_case.dart';
import 'package:tentura_server/env.dart';

import 'invitation_case_mocks.mocks.dart';

void main() {
  late MockUserRepositoryPort userRepo;
  late MockVerifiedContactRepositoryPort contactRepo;
  late MockInvitationRepositoryPort invitationRepo;
  late MockBeaconRepositoryPort beaconRepo;
  late MockVoteUserFriendshipLookup friendshipLookup;
  late InvitationCase invitationCase;
  late CredentialAuthCase credentialAuthCase;
  late OidcCase case_;
  late Env env;

  setUp(() {
    userRepo = MockUserRepositoryPort();
    contactRepo = MockVerifiedContactRepositoryPort();
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
    credentialAuthCase = CredentialAuthCase(
      userRepo,
      contactRepo,
      invitationCase,
      env: env,
      logger: Logger('CredentialAuthCaseTest'),
    );
    case_ = OidcCase(
      credentialAuthCase,
      userRepo,
      env: env,
      logger: Logger('OidcCaseTest'),
    );
    when(
      userRepo.findCredentialId(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenAnswer((_) async => 'Ccred');
  });

  const identity = OidcIdentity(sub: 'google-sub', name: 'Ada');

  test('existing credential login without invite', () async {
    when(
      userRepo.getByCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenAnswer((_) async => const UserEntity(id: 'Uabc', displayName: 'Ada'));

    expect((await case_.completeGoogle(identity)).accountId, 'Uabc');
  });

  test('new account without invite on invite-only server is rejected', () async {
    when(
      userRepo.getByCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenThrow(const IdNotFoundException());
    when(
      contactRepo.findAccountIdsByContacts(any),
    ).thenAnswer((_) async => {});

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
      contactRepo.findAccountIdsByContacts(any),
    ).thenAnswer((_) async => {});
    when(
      userRepo.createInvitedWithCredential(
        invitationId: anyNamed('invitationId'),
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
        displayName: anyNamed('displayName'),
        handle: anyNamed('handle'),
        publicData: anyNamed('publicData'),
        contacts: anyNamed('contacts'),
      ),
    ).thenAnswer((_) async => const UserEntity(id: 'Unew', displayName: 'Ada'));

    expect(
      (await case_.completeGoogle(identity, inviteId: 'Iabc')).accountId,
      'Unew',
    );
    verify(
      userRepo.createInvitedWithCredential(
        invitationId: 'Iabc',
        type: CredentialType.oidcGoogle,
        identifier: 'google-sub',
        displayName: 'Ada',
        handle: null,
        publicData: null,
        contacts: anyNamed('contacts'),
      ),
    ).called(1);
  });

  test('verified google email passes authoritative contact into resolver', () async {
    when(
      userRepo.getByCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenThrow(const IdNotFoundException());
    when(
      contactRepo.findAccountIdsByContacts(any),
    ).thenAnswer((_) async => {'Uemail'});
    when(
      userRepo.linkCredentialWithContacts(
        accountId: anyNamed('accountId'),
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
        publicData: anyNamed('publicData'),
        contacts: anyNamed('contacts'),
      ),
    ).thenAnswer((_) async => 'Uemail');

    final id = await case_.completeGoogle(
      const OidcIdentity(
        sub: 'google-sub',
        email: 'Ada@Example.COM',
        name: 'Ada',
        emailVerified: true,
      ),
    );

    expect(id.accountId, 'Uemail');
    final captured = verify(
      userRepo.linkCredentialWithContacts(
        accountId: 'Uemail',
        type: CredentialType.oidcGoogle,
        identifier: 'google-sub',
        publicData: null,
        contacts: captureAnyNamed('contacts'),
      ),
    ).captured.single as List;
    expect(captured.single.value, 'ada@example.com');
    expect(captured.single.authoritative, isTrue);
  });

  test('linkGoogle strict-links identity to account', () async {
    const identity = OidcIdentity(
      sub: 'google-sub',
      email: 'ada@example.com',
      name: 'Ada',
      emailVerified: false,
    );
    when(
      userRepo.linkCredentialToAccountStrict(
        accountId: 'Uacc',
        type: CredentialType.oidcGoogle,
        identifier: 'google-sub',
        publicData: anyNamed('publicData'),
        contacts: anyNamed('contacts'),
      ),
    ).thenAnswer(
      (_) async => const AccountCredentialEntity(
        id: 'Cgoogle',
        accountId: 'Uacc',
        type: CredentialType.oidcGoogle,
        identifier: 'google-sub',
      ),
    );

    final credential = await case_.linkGoogle(
      accountId: 'Uacc',
      identity: identity,
    );

    expect(credential.id, 'Cgoogle');
    final captured = verify(
      userRepo.linkCredentialToAccountStrict(
        accountId: 'Uacc',
        type: CredentialType.oidcGoogle,
        identifier: 'google-sub',
        publicData: null,
        contacts: captureAnyNamed('contacts'),
      ),
    ).captured.single as List;
    expect(captured, hasLength(1));
    expect(captured.single.authoritative, isFalse);
  });

  test('unverified google email does not link by contact', () async {
    when(
      userRepo.getByCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenThrow(const IdNotFoundException());
    when(
      contactRepo.findAccountIdsByContacts(any),
    ).thenAnswer((_) async => {});
    env = Env(environment: Environment.test, isNeedInvite: false);
    credentialAuthCase = CredentialAuthCase(
      userRepo,
      contactRepo,
      invitationCase,
      env: env,
      logger: Logger('CredentialAuthCaseTest'),
    );
    case_ = OidcCase(
      credentialAuthCase,
      userRepo,
      env: env,
      logger: Logger('OidcCaseTest'),
    );
    when(
      userRepo.createWithCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
        displayName: anyNamed('displayName'),
        handle: anyNamed('handle'),
        publicData: anyNamed('publicData'),
        contacts: anyNamed('contacts'),
      ),
    ).thenAnswer((_) async => const UserEntity(id: 'Unew', displayName: 'Ada'));

    await case_.completeGoogle(
      const OidcIdentity(
        sub: 'google-sub',
        email: 'ada@example.com',
        name: 'Ada',
        emailVerified: false,
      ),
    );

    final captured = verify(
      userRepo.createWithCredential(
        type: CredentialType.oidcGoogle,
        identifier: 'google-sub',
        displayName: 'Ada',
        handle: null,
        publicData: null,
        contacts: captureAnyNamed('contacts'),
      ),
    ).captured.single as List;
    expect(captured, isEmpty);
    verify(contactRepo.findAccountIdsByContacts(any)).called(1);
  });
}
