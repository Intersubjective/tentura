import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/auth_email_controller.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/account_session_entity.dart';
import 'package:tentura_server/domain/entity/email_auth_peek.dart';
import 'package:tentura_server/domain/entity/email_auth_transaction_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/email_auth_transaction_repository_port.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/session_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/email_auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/env.dart';

import '../../domain/use_case/invitation_case_mocks.mocks.dart';

final class _FakeTxRepo implements EmailAuthTransactionRepositoryPort {
  EmailAuthTransactionEntity? _tx;
  var _consumed = false;

  void seed(EmailAuthTransactionEntity tx) {
    _tx = tx;
    _consumed = false;
  }

  @override
  Future<String> create({
    required String normalizedEmail,
    String? inviteCode,
    String? linkAccountId,
    required Duration expiresIn,
    required String userAgentHash,
    required String ipHash,
  }) async {
    _tx = EmailAuthTransactionEntity(
      id: 'Etest',
      normalizedEmail: normalizedEmail,
      inviteCode: inviteCode,
      linkAccountId: linkAccountId,
      createdAt: DateTime.timestamp(),
      expiresAt: DateTime.timestamp().add(expiresIn),
    );
    return 'opaque-token';
  }

  @override
  Future<EmailAuthTokenPeekRow> peekByToken(String plaintextToken) async {
    if (plaintextToken.isEmpty || _tx == null) {
      return (status: EmailAuthTokenStatus.missing, tx: null);
    }
    if (_consumed) {
      return (status: EmailAuthTokenStatus.consumed, tx: _tx);
    }
    return (status: EmailAuthTokenStatus.valid, tx: _tx);
  }

  @override
  Future<EmailAuthTransactionEntity?> consumeByToken(
    String plaintextToken,
  ) async {
    if (_tx == null || _consumed) return null;
    _consumed = true;
    return _tx;
  }

  @override
  Future<int> countRecentByEmail({
    required String normalizedEmail,
    required Duration window,
  }) async => 0;

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

final class _FakeEmailSender implements EmailSenderPort {
  @override
  Future<void> sendMagicLink({
    required String to,
    required String verifyUrl,
    String? inviterName,
  }) async {}
}

final class _FakeSessionRepo implements SessionRepositoryPort {
  @override
  Future<({String token, AccountSessionEntity session})> create({
    required String accountId,
    required Duration expiresIn,
    String? credentialId,
  }) async => (
    token: 'sess-tok',
    session: AccountSessionEntity(
      id: 'Ss1',
      accountId: accountId,
      tokenHash: 'h',
      expiresAt: DateTime.timestamp().add(expiresIn),
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

EmailAuthCase _buildEmailAuthCase({
  required Env env,
  required _FakeTxRepo txRepo,
  required MockUserRepositoryPort userRepo,
  required MockVerifiedContactRepositoryPort contactRepo,
}) {
  final invitationCase = InvitationCase(
    MockInvitationRepositoryPort(),
    userRepo,
    MockBeaconRepositoryPort(),
    MockVoteUserFriendshipLookup(),
    env: env,
    logger: Logger('AuthEmailControllerTest'),
  );
  final credentialAuthCase = CredentialAuthCase(
    userRepo,
    contactRepo,
    invitationCase,
    env: env,
    logger: Logger('AuthEmailControllerTest'),
  );
  final sessionCase = SessionCase(
    _FakeSessionRepo(),
    AuthCase(userRepo, env: env, logger: Logger('AuthEmailControllerTest')),
    env: env,
    logger: Logger('AuthEmailControllerTest'),
  );
  return EmailAuthCase(
    txRepo,
    _FakeEmailSender(),
    credentialAuthCase,
    userRepo,
    sessionCase,
    env: env,
    logger: Logger('AuthEmailControllerTest'),
  );
}

void main() {
  late AuthEmailController controller;
  late _FakeTxRepo txRepo;
  late Env env;

  setUp(() {
    txRepo = _FakeTxRepo();
    env = Env(
      environment: 'test',
      publicOrigin: 'https://dev.tentura.io',
      isNeedInvite: false,
    );
    final userRepo = MockUserRepositoryPort();
    when(
      userRepo.findCredentialId(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenAnswer((_) async => 'Ccred');
    final emailAuthCase = _buildEmailAuthCase(
      env: env,
      txRepo: txRepo,
      userRepo: userRepo,
      contactRepo: MockVerifiedContactRepositoryPort(),
    );
    controller = AuthEmailController(
      env,
      emailAuthCase,
      SessionCase(
        _FakeSessionRepo(),
        AuthCase(userRepo, env: env, logger: Logger('AuthEmailControllerTest')),
        env: env,
        logger: Logger('AuthEmailControllerTest'),
      ),
    );
  });

  test('GET verify renders confirm without consuming token', () async {
    txRepo.seed(
      EmailAuthTransactionEntity(
        id: 'E1',
        normalizedEmail: 'get@example.com',
        createdAt: DateTime.timestamp(),
        expiresAt: DateTime.timestamp().add(const Duration(minutes: 15)),
      ),
    );

    final res = await controller.verifyGet(
      Request(
        'GET',
        Uri.parse('https://dev.tentura.io/auth/email/verify?t=opaque-token'),
      ),
    );

    expect(res.statusCode, 200);
    expect(await res.readAsString(), contains('Continue to Tentura'));
    final peek = await txRepo.peekByToken('opaque-token');
    expect(peek.status, EmailAuthTokenStatus.valid);
  });

  test('POST verify sets session cookie and redirects', () async {
    txRepo.seed(
      EmailAuthTransactionEntity(
        id: 'E2',
        normalizedEmail: 'post@example.com',
        inviteCode: 'Iabc',
        createdAt: DateTime.timestamp(),
        expiresAt: DateTime.timestamp().add(const Duration(minutes: 15)),
      ),
    );
    final userRepo = MockUserRepositoryPort();
    final contactRepo = MockVerifiedContactRepositoryPort();
    when(
      userRepo.getByCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenThrow(const IdNotFoundException());
    when(contactRepo.findAccountIdsByContacts(any)).thenAnswer((_) async => {});
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
      (_) async => const UserEntity(id: 'Unew', displayName: 'post'),
    );
    when(
      userRepo.findCredentialId(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenAnswer((_) async => 'Ccred');

    final emailAuthCase = _buildEmailAuthCase(
      env: env,
      txRepo: txRepo,
      userRepo: userRepo,
      contactRepo: contactRepo,
    );
    final sessionCase = SessionCase(
      _FakeSessionRepo(),
      AuthCase(userRepo, env: env, logger: Logger('AuthEmailControllerTest')),
      env: env,
      logger: Logger('AuthEmailControllerTest'),
    );
    controller = AuthEmailController(env, emailAuthCase, sessionCase);

    final res = await controller.verifyPost(
      Request(
        'POST',
        Uri.parse('https://dev.tentura.io/auth/email/verify'),
        body: 't=opaque-token',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      ),
    );

    expect(res.statusCode, 302);
    expect(res.headers['location'], contains('/invite/Iabc'));
    expect(res.headers['set-cookie'], contains(kCookieSessionName));
  });
}
