import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/account_deletion_request_email_payload.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/account_session_entity.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/entity/email_auth_peek.dart';
import 'package:tentura_server/domain/entity/email_auth_transaction_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/entity/verified_contact_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/email_auth_transaction_repository_port.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/session_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/email_auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/env.dart';

import 'invitation_case_mocks.mocks.dart';
import '../../support/build_test_invitation_case.dart';
import '../../support/noop_invite_accepted_notification_port.dart';
import '../../support/test_attention_harness.dart';

final class _FakeEmailSender implements EmailSenderPort {
  String? lastVerifyUrl;
  String? lastTo;
  var throwOnSend = false;

  @override
  Future<void> sendMagicLink({
    required String to,
    required String verifyUrl,
    String? inviterName,
  }) async {
    if (throwOnSend) {
      throw Exception('simulated send failure');
    }
    lastTo = to;
    lastVerifyUrl = verifyUrl;
  }

  @override
  Future<void> sendNotificationEmail({
    required String to,
    required String locale,
    required EmailNotificationContent content,
    String? listUnsubscribeUrl,
  }) async {}

  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) async {}

  @override
  Future<void> sendAccountDeletionRequestAdminEmail({
    required String to,
    required AccountDeletionRequestEmailPayload payload,
  }) async {}

  @override
  Future<void> sendAccountDeletionRequestUserConfirmation({
    required String to,
    required AccountDeletionRequestEmailPayload payload,
  }) async {}
}

final class _FakeTxRepo implements EmailAuthTransactionRepositoryPort {
  final Map<String, EmailAuthTransactionEntity> _byToken = {};
  final Set<String> _consumed = {};
  bool resolveShouldThrow = false;
  String? lastTransactionId;
  int recentEmailCount = 0;

  @override
  Future<String> create({
    required String normalizedEmail,
    required Duration expiresIn,
    required String userAgentHash,
    required String ipHash,
    String? inviteCode,
    String? linkAccountId,
    String? transactionId,
  }) async {
    const token = 'opaque-token';
    _byToken[token] = EmailAuthTransactionEntity(
      id: transactionId ?? 'Etest',
      normalizedEmail: normalizedEmail,
      inviteCode: inviteCode,
      linkAccountId: linkAccountId,
      createdAt: DateTime.timestamp(),
      expiresAt: DateTime.timestamp().add(expiresIn),
    );
    lastTransactionId = transactionId ?? 'Etest';
    return token;
  }

  @override
  Future<EmailAuthTokenPeekRow> peekByToken(String plaintextToken) async {
    if (_consumed.contains(plaintextToken)) {
      final tx = _byToken[plaintextToken];
      return (status: EmailAuthTokenStatus.consumed, tx: tx);
    }
    final tx = _byToken[plaintextToken];
    if (tx == null) {
      return (status: EmailAuthTokenStatus.missing, tx: null);
    }
    if (!tx.expiresAt.isAfter(DateTime.timestamp())) {
      return (status: EmailAuthTokenStatus.expired, tx: tx);
    }
    return (status: EmailAuthTokenStatus.valid, tx: tx);
  }

  @override
  Future<EmailAuthTransactionEntity?> consumeByToken(
    String plaintextToken,
  ) async {
    if (_consumed.contains(plaintextToken)) return null;
    final tx = _byToken[plaintextToken];
    if (tx == null) return null;
    _consumed.add(plaintextToken);
    return tx;
  }

  @override
  Future<int> countRecentByEmail({
    required String normalizedEmail,
    required Duration window,
  }) async => recentEmailCount;

  @override
  Future<int> countRecentByIpHash({
    required String ipHash,
    required Duration window,
  }) async => 0;

  @override
  Future<int> countRecentByInviteCode({
    required String inviteCode,
    required Duration window,
  }) async => 0;
}

final class _FakeSessionRepo implements SessionRepositoryPort {
  @override
  Future<({String token, AccountSessionEntity session})> create({
    required String accountId,
    required Duration expiresIn,
    String? credentialId,
  }) async => (
    token: 'session-cookie-value',
    session: AccountSessionEntity(
      id: 'Ss1',
      accountId: accountId,
      tokenHash: 'hash',
      expiresAt: DateTime.timestamp().add(expiresIn),
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

SessionCase _fakeSessionCase(Env env, UserRepositoryPort userRepo) {
  final attention = TestAttentionHarness();
  return SessionCase(
    _FakeSessionRepo(),
    AuthCase(
      userRepo,
      MockInvitationRepositoryPort(),
      NoopInviteAcceptedNotificationPort(),
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: env,
      logger: Logger('EmailAuthCaseTest'),
    ),
    env: env,
    logger: Logger('EmailAuthCaseTest'),
  );
}

void main() {
  late MockUserRepositoryPort userRepo;
  late MockVerifiedContactRepositoryPort contactRepo;
  late InvitationCase invitationCase;
  late CredentialAuthCase credentialAuthCase;
  late _FakeTxRepo txRepo;
  late _FakeEmailSender sender;
  late EmailAuthCase case_;
  late TestAttentionHarness attention;
  late Env env;

  setUp(() {
    userRepo = MockUserRepositoryPort();
    contactRepo = MockVerifiedContactRepositoryPort();
    final invitationRepo = MockInvitationRepositoryPort();
    when(
      invitationRepo.getById(invitationId: anyNamed('invitationId')),
    ).thenAnswer((_) async => null);
    final beaconRepo = MockBeaconRepositoryPort();
    final friendshipLookup = MockVoteUserFriendshipLookupPort();
    attention = TestAttentionHarness();
    env = Env(
      environment: Environment.test,
      isNeedInvite: true,
      resendApiKey: 're_test',
      resendFromEmail: 'Tentura <auth@test.local>',
      publicOrigin: 'https://dev.tentura.io',
    );
    invitationCase = buildTestInvitationCase(
      invitationRepo: invitationRepo,
      userRepo: userRepo,
      beaconRepo: beaconRepo,
      friendshipLookup: friendshipLookup,
      contactRepo: MockUserContactRepositoryPort(),
      attention: attention,
      env: env,
      logger: Logger('InvitationCaseTest'),
    );
    credentialAuthCase = CredentialAuthCase(
      userRepo,
      contactRepo,
      invitationRepo,
      NoopInviteAcceptedNotificationPort(),
      invitationCase,
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: env,
      logger: Logger('CredentialAuthCaseTest'),
    );
    txRepo = _FakeTxRepo();
    sender = _FakeEmailSender();
    sender.throwOnSend = false;
    case_ = EmailAuthCase(
      txRepo,
      sender,
      credentialAuthCase,
      userRepo,
      _fakeSessionCase(env, userRepo),
      env: env,
      logger: Logger('EmailAuthCaseTest'),
    );
    when(
      userRepo.findCredentialId(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenAnswer((_) async => 'Ccred');
  });

  test(
    'start persists attemptId as transaction id when tx is created',
    () async {
      const attemptId = 'Eabc1234567890';
      final result = await case_.start(
        email: 'Ada@Example.COM',
        inviteCode: 'Iabc',
        ipFingerprint: '1.2.3.4',
        userAgentFingerprint: 'Mozilla',
        attemptId: attemptId,
      );
      expect(result.correlationId, attemptId);
      expect(result.outcome, EmailAuthStartOutcome.sent);
      expect(txRepo.lastTransactionId, attemptId);
      expect(sender.lastTo, 'ada@example.com');
    },
  );

  test('start sends magic link when configured', () async {
    final result = await case_.start(
      email: 'Ada@Example.COM',
      inviteCode: 'Iabc',
      ipFingerprint: '1.2.3.4',
      userAgentFingerprint: 'Mozilla',
    );
    expect(result.outcome, EmailAuthStartOutcome.sent);
    expect(sender.lastTo, 'ada@example.com');
    expect(sender.lastVerifyUrl, contains('/auth/email/verify?t=opaque-token'));
  });

  test(
    'start skips unregistered email on invite-only without invite',
    () async {
      when(
        userRepo.getByCredential(
          type: anyNamed('type'),
          identifier: anyNamed('identifier'),
        ),
      ).thenThrow(const IdNotFoundException());
      when(
        contactRepo.getAccountIdByContact(
          kind: ContactKind.email,
          value: 'new@example.com',
        ),
      ).thenAnswer((_) async => null);

      final result = await case_.start(
        email: 'new@example.com',
        ipFingerprint: '1.2.3.4',
        userAgentFingerprint: 'Mozilla',
      );

      expect(result.outcome, EmailAuthStartOutcome.inviteRequiredSkip);
      expect(sender.lastTo, isNull);
      expect(sender.lastVerifyUrl, isNull);
    },
  );

  test('start returns invalidFormat for bad email', () async {
    final result = await case_.start(
      email: 'not-an-email',
      ipFingerprint: '1.2.3.4',
      userAgentFingerprint: 'Mozilla',
    );
    expect(result.outcome, EmailAuthStartOutcome.invalidFormat);
    expect(sender.lastTo, isNull);
  });

  test('start returns rateLimited when email throttle exceeded', () async {
    txRepo.recentEmailCount = env.emailAuthMaxPerEmail;
    final result = await case_.start(
      email: 'throttled@example.com',
      inviteCode: 'Iabc',
      ipFingerprint: '1.2.3.4',
      userAgentFingerprint: 'Mozilla',
    );
    expect(result.outcome, EmailAuthStartOutcome.rateLimited);
    expect(sender.lastTo, isNull);
  });

  test('start returns mailUnconfigured when Resend is absent', () async {
    final unconfiguredEnv = Env(
      environment: Environment.test,
      isNeedInvite: true,
      resendApiKey: '',
      resendFromEmail: '',
      emailDebugSinkDir: '',
      qaAuthEnabled: false,
      qaAuthToken: '',
      publicOrigin: 'https://dev.tentura.io',
    );
    final unconfiguredCase = EmailAuthCase(
      txRepo,
      sender,
      credentialAuthCase,
      userRepo,
      _fakeSessionCase(unconfiguredEnv, userRepo),
      env: unconfiguredEnv,
      logger: Logger('EmailAuthCaseTest'),
    );
    final result = await unconfiguredCase.start(
      email: 'a@example.com',
      inviteCode: 'Iabc',
      ipFingerprint: '1.2.3.4',
      userAgentFingerprint: 'Mozilla',
    );
    expect(result.outcome, EmailAuthStartOutcome.mailUnconfigured);
    expect(sender.lastTo, isNull);
  });

  test('start returns unexpectedError when sender fails', () async {
    sender.throwOnSend = true;
    final result = await case_.start(
      email: 'fail@example.com',
      inviteCode: 'Iabc',
      ipFingerprint: '1.2.3.4',
      userAgentFingerprint: 'Mozilla',
    );
    expect(result.outcome, EmailAuthStartOutcome.unexpectedError);
  });

  test('peek does not consume token', () async {
    await case_.start(
      email: 'peek@example.com',
      inviteCode: 'Iabc',
      ipFingerprint: 'ip',
      userAgentFingerprint: 'ua',
    );
    final peek1 = await case_.peek('opaque-token');
    expect(peek1.status, EmailAuthTokenStatus.valid);
    final peek2 = await case_.peek('opaque-token');
    expect(peek2.status, EmailAuthTokenStatus.valid);
  });

  test('confirm consumes token and creates invited account', () async {
    await case_.start(
      email: 'new@example.com',
      inviteCode: 'Iabc',
      ipFingerprint: 'ip',
      userAgentFingerprint: 'ua',
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
      (_) async => const UserEntity(id: 'Unew', displayName: 'new'),
    );

    final outcome = await case_.confirm('opaque-token');
    expect(outcome, isA<EmailAuthLoginConfirmed>());
    final login = outcome as EmailAuthLoginConfirmed;
    expect(login.sessionToken, 'session-cookie-value');
    expect(login.inviteCode, 'Iabc');
    expect(login.isNewAccount, isTrue);

    expect(
      () => case_.confirm('opaque-token'),
      throwsA(isA<EmailAuthTokenAlreadyUsedException>()),
    );
  });

  test('confirm link mode strict-links without session', () async {
    const accountId = 'Uabc123456789012345678901234567890';
    final startResult = await case_.start(
      email: 'link@example.com',
      linkAccountId: accountId,
      ipFingerprint: 'ip',
      userAgentFingerprint: 'ua',
    );
    expect(startResult.outcome, EmailAuthStartOutcome.sent);
    when(
      userRepo.linkCredentialToAccountStrict(
        accountId: anyNamed('accountId'),
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
        publicData: anyNamed('publicData'),
        contacts: anyNamed('contacts'),
      ),
    ).thenAnswer(
      (_) async => const AccountCredentialEntity(
        id: 'Cemail',
        accountId: accountId,
        type: CredentialType.emailOtp,
        identifier: 'link@example.com',
      ),
    );

    final outcome = await case_.confirm('opaque-token');
    expect(outcome, isA<EmailAuthLinkConfirmed>());
  });

  test('confirm rejects missing token', () async {
    expect(
      () => case_.confirm('missing'),
      throwsA(isA<EmailAuthTokenMissingException>()),
    );
  });

  test('failed confirm before consume allows retry', () async {
    await case_.start(
      email: 'retry@example.com',
      inviteCode: 'Iabc',
      ipFingerprint: 'ip',
      userAgentFingerprint: 'ua',
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
    var createCalls = 0;
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
    ).thenAnswer((_) async {
      createCalls++;
      if (createCalls == 1) {
        throw Exception('simulated resolve failure');
      }
      return const UserEntity(id: 'Unew', displayName: 'retry');
    });

    expect(
      () => case_.confirm('opaque-token'),
      throwsA(isA<Exception>()),
    );
    final peek = await case_.peek('opaque-token');
    expect(peek.status, EmailAuthTokenStatus.valid);

    final outcome = await case_.confirm('opaque-token');
    expect(outcome, isA<EmailAuthLoginConfirmed>());
  });

  test('confirm creates account on open signup', () async {
    final openEnv = Env(
      environment: Environment.test,
      isNeedInvite: false,
      resendApiKey: 're_test',
      resendFromEmail: 'Tentura <auth@test.local>',
      publicOrigin: 'https://dev.tentura.io',
    );
    final openCredentialAuthCase = CredentialAuthCase(
      userRepo,
      contactRepo,
      MockInvitationRepositoryPort(),
      NoopInviteAcceptedNotificationPort(),
      invitationCase,
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: openEnv,
      logger: Logger('CredentialAuthCaseTest'),
    );
    final openCase = EmailAuthCase(
      txRepo,
      sender,
      openCredentialAuthCase,
      userRepo,
      _fakeSessionCase(openEnv, userRepo),
      env: openEnv,
      logger: Logger('EmailAuthCaseTest'),
    );

    await openCase.start(
      email: 'open@example.com',
      ipFingerprint: 'ip',
      userAgentFingerprint: 'ua',
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
        identifier: anyNamed('identifier'),
        displayName: anyNamed('displayName'),
        handle: anyNamed('handle'),
        publicData: anyNamed('publicData'),
        contacts: anyNamed('contacts'),
      ),
    ).thenAnswer(
      (_) async => const UserEntity(id: 'Uopen', displayName: 'open'),
    );

    final outcome = await openCase.confirm('opaque-token');
    expect(outcome, isA<EmailAuthLoginConfirmed>());
    final openLogin = outcome as EmailAuthLoginConfirmed;
    expect(openLogin.inviteCode, isNull);
    expect(openLogin.isNewAccount, isTrue);
  });

  test(
    'confirm links email_otp into existing google account by verified contact',
    () async {
      const email = 'ada@example.com';
      const googleAccountId = 'Ugoogle123456789012345678901234567';
      when(
        contactRepo.getAccountIdByContact(
          kind: ContactKind.email,
          value: email,
        ),
      ).thenAnswer((_) async => googleAccountId);
      when(
        userRepo.getByCredential(
          type: anyNamed('type'),
          identifier: anyNamed('identifier'),
        ),
      ).thenThrow(const IdNotFoundException());
      when(
        contactRepo.findAccountIdsByContacts(any),
      ).thenAnswer((_) async => {googleAccountId});
      when(
        userRepo.linkCredentialWithContacts(
          accountId: anyNamed('accountId'),
          type: anyNamed('type'),
          identifier: anyNamed('identifier'),
          publicData: anyNamed('publicData'),
          contacts: anyNamed('contacts'),
        ),
      ).thenAnswer((_) async => googleAccountId);

      await case_.start(
        email: email,
        ipFingerprint: 'ip',
        userAgentFingerprint: 'ua',
      );

      final outcome = await case_.confirm('opaque-token');

      expect(outcome, isA<EmailAuthLoginConfirmed>());
      final login = outcome as EmailAuthLoginConfirmed;
      expect(login.sessionToken, 'session-cookie-value');
      expect(login.inviteCode, isNull);
      verify(
        userRepo.linkCredentialWithContacts(
          accountId: googleAccountId,
          type: CredentialType.emailOtp,
          identifier: email,
          contacts: anyNamed('contacts'),
        ),
      ).called(1);
      expect(
        () => case_.confirm('opaque-token'),
        throwsA(isA<EmailAuthTokenAlreadyUsedException>()),
      );
    },
  );

  group('qaTestLogin', () {
    late Env qaEnv;
    late EmailAuthCase qaCase;

    setUp(() {
      qaEnv = Env(
        environment: Environment.test,
        isNeedInvite: true,
        qaSimpleLoginMode: true,
        publicOrigin: 'https://dev.tentura.io',
      );
      final qaCredentialAuthCase = CredentialAuthCase(
        userRepo,
        contactRepo,
        MockInvitationRepositoryPort(),
        NoopInviteAcceptedNotificationPort(),
        invitationCase,
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: qaEnv,
        logger: Logger('CredentialAuthCaseTest'),
      );
      qaCase = EmailAuthCase(
        txRepo,
        sender,
        qaCredentialAuthCase,
        userRepo,
        _fakeSessionCase(qaEnv, userRepo),
        env: qaEnv,
        logger: Logger('EmailAuthCaseTest'),
      );
      sender.lastTo = null;
      sender.lastVerifyUrl = null;
    });

    test('mints session for existing user without magic link', () async {
      when(
        userRepo.getByCredential(
          type: anyNamed('type'),
          identifier: 'u@test.tentura.local',
        ),
      ).thenAnswer(
        (_) async => const UserEntity(id: 'Uexist', displayName: 'u'),
      );
      when(
        userRepo.addVerifiedContacts(
          accountId: anyNamed('accountId'),
          source: anyNamed('source'),
          contacts: anyNamed('contacts'),
        ),
      ).thenAnswer((_) async {});

      final result = await qaCase.qaTestLogin(
        normalizedEmail: 'u@test.tentura.local',
      );

      expect(result.sessionToken, 'session-cookie-value');
      expect(result.isNewAccount, isFalse);
      expect(sender.lastTo, isNull);
      expect(sender.lastVerifyUrl, isNull);
      expect(txRepo.lastTransactionId, isNull);
    });

    test('creates account for new user on invite-only server', () async {
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
          identifier: 'u@test.tentura.local',
          displayName: anyNamed('displayName'),
          handle: anyNamed('handle'),
          publicData: anyNamed('publicData'),
          contacts: anyNamed('contacts'),
        ),
      ).thenAnswer(
        (_) async => const UserEntity(id: 'Unew', displayName: 'u'),
      );

      final result = await qaCase.qaTestLogin(
        normalizedEmail: 'u@test.tentura.local',
      );

      expect(result.sessionToken, 'session-cookie-value');
      expect(result.isNewAccount, isTrue);
      expect(sender.lastTo, isNull);
      expect(txRepo.lastTransactionId, isNull);
    });
  });
}
