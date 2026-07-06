import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/asserted_contact.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/entity/verified_contact_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import 'invitation_case_mocks.mocks.dart';
import '../../support/build_test_invitation_case.dart';

void main() {
  late MockUserRepositoryPort userRepo;
  late MockVerifiedContactRepositoryPort contactRepo;
  late MockInvitationRepositoryPort invitationRepo;
  late MockBeaconRepositoryPort beaconRepo;
  late MockVoteUserFriendshipLookupPort friendshipLookup;
  late InvitationCase invitationCase;
  late CredentialAuthCase case_;
  late Env env;

  final emailContact = [
    AssertedContact.email(rawEmail: 'ada@example.com', authoritative: true)!,
  ];

  setUp(() {
    userRepo = MockUserRepositoryPort();
    contactRepo = MockVerifiedContactRepositoryPort();
    invitationRepo = MockInvitationRepositoryPort();
    beaconRepo = MockBeaconRepositoryPort();
    friendshipLookup = MockVoteUserFriendshipLookupPort();
    env = Env(environment: Environment.test, isNeedInvite: true);
    invitationCase = buildTestInvitationCase(
      invitationRepo: invitationRepo,
      userRepo: userRepo,
      beaconRepo: beaconRepo,
      friendshipLookup: friendshipLookup,
      contactRepo: MockUserContactRepositoryPort(),
      env: env,
      logger: Logger('InvitationCaseTest'),
    );
    case_ = CredentialAuthCase(
      userRepo,
      contactRepo,
      invitationCase,
      env: env,
      logger: Logger('CredentialAuthCaseTest'),
    );
  });

  test('existing email credential logs in and soft-attaches contacts', () async {
    when(
      userRepo.getByCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenAnswer(
      (_) async => const UserEntity(id: 'Uabc', displayName: 'Ada'),
    );

    final resolved = await case_.resolveOrCreate(
      type: CredentialType.emailOtp,
      identifier: 'ada@example.com',
      displayName: 'ada',
      assertedContacts: emailContact,
    );

    expect(resolved.accountId, 'Uabc');
    expect(resolved.isNewAccount, isFalse);
    verify(
      userRepo.addVerifiedContacts(
        accountId: 'Uabc',
        source: CredentialType.emailOtp,
        contacts: emailContact,
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
        contacts: anyNamed('contacts'),
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
    ).thenAnswer(
      (_) async => const UserEntity(id: 'Unew', displayName: 'ada'),
    );

    final resolved = await case_.resolveOrCreate(
      type: CredentialType.emailOtp,
      identifier: 'ada@example.com',
      displayName: 'ada',
      inviteId: 'Iabc',
      assertedContacts: emailContact,
    );

    expect(resolved.accountId, 'Unew');
    expect(resolved.isNewAccount, isTrue);
    verify(
      userRepo.createInvitedWithCredential(
        invitationId: 'Iabc',
        type: CredentialType.emailOtp,
        identifier: 'ada@example.com',
        displayName: 'ada',
        contacts: emailContact,
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
    when(
      contactRepo.findAccountIdsByContacts(any),
    ).thenAnswer((_) async => {});

    expect(
      () => case_.resolveOrCreate(
        type: CredentialType.emailOtp,
        identifier: 'new@example.com',
        displayName: 'new',
      ),
      throwsA(isA<OidcInviteRequiredException>()),
    );
  });

  test('bypassInviteForNewAccount creates account when QA simple login enabled', () async {
    final qaEnv = Env(
      environment: Environment.test,
      isNeedInvite: true,
      qaSimpleLoginMode: true,
    );
    final qaCase = CredentialAuthCase(
      userRepo,
      contactRepo,
      invitationCase,
      env: qaEnv,
      logger: Logger('CredentialAuthCaseTest'),
    );
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
      userRepo.createWithCredential(
        type: anyNamed('type'),
        identifier: 'new@test.tentura.local',
        displayName: anyNamed('displayName'),
        handle: anyNamed('handle'),
        publicData: anyNamed('publicData'),
        contacts: anyNamed('contacts'),
      ),
    ).thenAnswer(
      (_) async => const UserEntity(id: 'Unew', displayName: 'new'),
    );

    final resolved = await qaCase.resolveOrCreate(
      type: CredentialType.emailOtp,
      identifier: 'new@test.tentura.local',
      displayName: 'new',
      bypassInviteForNewAccount: true,
    );

    expect(resolved.accountId, 'Unew');
    expect(resolved.isNewAccount, isTrue);
  });

  test('bypassInviteForNewAccount is ignored in prod', () async {
    final prodEnv = Env(
      environment: Environment.prod,
      isNeedInvite: true,
      qaSimpleLoginMode: true,
      serverUri: Uri.parse('https://tentura.io'),
      publicOrigin: 'https://tentura.io',
    );
    final prodCase = CredentialAuthCase(
      userRepo,
      contactRepo,
      invitationCase,
      env: prodEnv,
      logger: Logger('CredentialAuthCaseTest'),
    );
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
      () => prodCase.resolveOrCreate(
        type: CredentialType.emailOtp,
        identifier: 'new@test.tentura.local',
        displayName: 'new',
        bypassInviteForNewAccount: true,
      ),
      throwsA(isA<OidcInviteRequiredException>()),
    );
  });

  test('email verify links into existing google account by verified contact', () async {
    when(
      userRepo.getByCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenThrow(const IdNotFoundException());
    when(
      contactRepo.findAccountIdsByContacts(any),
    ).thenAnswer((_) async => {'Ugoogle'});
    when(
      userRepo.linkCredentialWithContacts(
        accountId: anyNamed('accountId'),
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
        publicData: anyNamed('publicData'),
        contacts: anyNamed('contacts'),
      ),
    ).thenAnswer((_) async => 'Ugoogle');

    final resolved = await case_.resolveOrCreate(
      type: CredentialType.emailOtp,
      identifier: 'ada@example.com',
      displayName: 'ada',
      assertedContacts: emailContact,
    );

    expect(resolved.accountId, 'Ugoogle');
    expect(resolved.isNewAccount, isFalse);
    verify(
      userRepo.linkCredentialWithContacts(
        accountId: 'Ugoogle',
        type: CredentialType.emailOtp,
        identifier: 'ada@example.com',
        contacts: emailContact,
      ),
    ).called(1);
    verifyNever(
      userRepo.createWithCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
        displayName: anyNamed('displayName'),
        handle: anyNamed('handle'),
        publicData: anyNamed('publicData'),
        contacts: anyNamed('contacts'),
      ),
    );
  });

  test('google login links into existing email account by verified contact', () async {
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

    final resolved = await case_.resolveOrCreate(
      type: CredentialType.oidcGoogle,
      identifier: 'google-sub',
      displayName: 'Ada',
      assertedContacts: emailContact,
    );

    expect(resolved.accountId, 'Uemail');
    expect(resolved.isNewAccount, isFalse);
    verify(
      userRepo.linkCredentialWithContacts(
        accountId: 'Uemail',
        type: CredentialType.oidcGoogle,
        identifier: 'google-sub',
        contacts: emailContact,
      ),
    ).called(1);
  });

  test('ambiguous contact match throws', () async {
    when(
      userRepo.getByCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenThrow(const IdNotFoundException());
    when(
      contactRepo.findAccountIdsByContacts(any),
    ).thenAnswer((_) async => {'U1', 'U2'});

    expect(
      () => case_.resolveOrCreate(
        type: CredentialType.emailOtp,
        identifier: 'ada@example.com',
        displayName: 'ada',
        assertedContacts: emailContact,
      ),
      throwsA(isA<AmbiguousIdentityException>()),
    );
  });

  test('create retries link after contact conflict race', () async {
    when(
      userRepo.getByCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenThrow(const IdNotFoundException());
    when(contactRepo.findAccountIdsByContacts(any)).thenAnswer((invocation) async {
      final contacts = invocation.positionalArguments.first as Iterable;
      if (contacts.isEmpty) return {};
      return {'Uwinner'};
    });
    when(
      userRepo.createWithCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
        displayName: anyNamed('displayName'),
        handle: anyNamed('handle'),
        publicData: anyNamed('publicData'),
        contacts: anyNamed('contacts'),
      ),
    ).thenThrow(const ContactConflictException());
    when(
      userRepo.linkCredentialWithContacts(
        accountId: anyNamed('accountId'),
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
        publicData: anyNamed('publicData'),
        contacts: anyNamed('contacts'),
      ),
    ).thenAnswer((_) async => 'Uwinner');

    env = Env(environment: Environment.test, isNeedInvite: false);
    case_ = CredentialAuthCase(
      userRepo,
      contactRepo,
      invitationCase,
      env: env,
      logger: Logger('CredentialAuthCaseTest'),
    );

    final resolved = await case_.resolveOrCreate(
      type: CredentialType.oidcGoogle,
      identifier: 'google-sub',
      displayName: 'Ada',
      assertedContacts: emailContact,
    );

    expect(resolved.accountId, 'Uwinner');
    expect(resolved.isNewAccount, isFalse);
  });

  test('emailIsRegistered checks credential and verified contact', () async {
    when(
      userRepo.getByCredential(
        type: 'email_otp',
        identifier: 'ada@example.com',
      ),
    ).thenThrow(const IdNotFoundException());
    when(
      contactRepo.getAccountIdByContact(
        kind: ContactKind.email,
        value: 'ada@example.com',
      ),
    ).thenAnswer((_) async => 'Ugoogle');

    expect(await case_.emailIsRegistered('ada@example.com'), isTrue);
  });

  test(
    'existing account login with consumed invite does not throw',
    () async {
      when(
        userRepo.getByCredential(
          type: anyNamed('type'),
          identifier: anyNamed('identifier'),
        ),
      ).thenAnswer(
        (_) async => const UserEntity(id: 'Ugoogle', displayName: 'Ada'),
      );
      when(
        invitationRepo.getById(invitationId: anyNamed('invitationId')),
      ).thenAnswer(
        (_) async => InvitationEntity(
          id: 'Iconsumed',
          issuer: const UserEntity(id: 'Uissuer', displayName: 'Bob'),
          createdAt: DateTime.timestamp(),
          updatedAt: DateTime.timestamp(),
          invited: const UserEntity(id: 'Ugoogle', displayName: 'Ada'),
        ),
      );
      when(
        friendshipLookup.isReciprocalSubscribe(
          viewerId: anyNamed('viewerId'),
          peerId: anyNamed('peerId'),
        ),
      ).thenAnswer((_) async => false);

      final resolved = await case_.resolveOrCreate(
        type: CredentialType.emailOtp,
        identifier: 'ada@example.com',
        displayName: 'ada',
        inviteId: 'Iconsumed',
        assertedContacts: emailContact,
      );

      expect(resolved.accountId, 'Ugoogle');
      expect(resolved.isNewAccount, isFalse);
    },
  );
}
