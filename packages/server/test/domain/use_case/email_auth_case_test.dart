import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/email_auth_transaction_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/email_auth_transaction_repository_port.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/email_auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import 'invitation_case_mocks.mocks.dart';

final class _FakeEmailSender implements EmailSenderPort {
  String? lastVerifyUrl;
  String? lastTo;

  @override
  Future<void> sendMagicLink({
    required String to,
    required String verifyUrl,
    String? inviterName,
  }) async {
    lastTo = to;
    lastVerifyUrl = verifyUrl;
  }
}

final class _FakeTxRepo implements EmailAuthTransactionRepositoryPort {
  final Map<String, EmailAuthTransactionEntity> _byToken = {};
  final Set<String> _consumed = {};

  @override
  Future<String> create({
    required String normalizedEmail,
    String? inviteCode,
    required Duration expiresIn,
    required String userAgentHash,
    required String ipHash,
  }) async {
    const token = 'opaque-token';
    _byToken[token] = EmailAuthTransactionEntity(
      id: 'Etest',
      normalizedEmail: normalizedEmail,
      inviteCode: inviteCode,
      createdAt: DateTime.timestamp(),
      expiresAt: DateTime.timestamp().add(expiresIn),
    );
    return token;
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

void main() {
  late MockUserRepositoryPort userRepo;
  late InvitationCase invitationCase;
  late CredentialAuthCase credentialAuthCase;
  late _FakeTxRepo txRepo;
  late _FakeEmailSender sender;
  late EmailAuthCase case_;
  late Env env;

  setUp(() {
    userRepo = MockUserRepositoryPort();
    final invitationRepo = MockInvitationRepositoryPort();
    final beaconRepo = MockBeaconRepositoryPort();
    final friendshipLookup = MockVoteUserFriendshipLookup();
    env = Env(
      environment: Environment.test,
      isNeedInvite: true,
      resendApiKey: 're_test',
      resendFromEmail: 'Tentura <auth@test.local>',
      publicOrigin: 'https://dev.tentura.io',
    );
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
      invitationCase,
      env: env,
      logger: Logger('CredentialAuthCaseTest'),
    );
    txRepo = _FakeTxRepo();
    sender = _FakeEmailSender();
    case_ = EmailAuthCase(
      txRepo,
      sender,
      credentialAuthCase,
      env: env,
      logger: Logger('EmailAuthCaseTest'),
    );
  });

  test('start sends magic link when configured', () async {
    await case_.start(
      email: 'Ada@Example.COM',
      inviteCode: 'Iabc',
      ipFingerprint: '1.2.3.4',
      userAgentFingerprint: 'Mozilla',
    );
    expect(sender.lastTo, 'ada@example.com');
    expect(sender.lastVerifyUrl, contains('/auth/email/verify?t=opaque-token'));
  });

  test('verify consumes token and creates invited account', () async {
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
      userRepo.createInvitedWithCredential(
        invitationId: anyNamed('invitationId'),
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
        displayName: anyNamed('displayName'),
        handle: anyNamed('handle'),
        publicData: anyNamed('publicData'),
      ),
    ).thenAnswer(
      (_) async => const UserEntity(id: 'Unew', displayName: 'new'),
    );

    final result = await case_.verify('opaque-token');
    expect(result.accountId, 'Unew');
    expect(result.inviteCode, 'Iabc');
    verify(
      userRepo.createInvitedWithCredential(
        invitationId: 'Iabc',
        type: CredentialType.emailOtp,
        identifier: 'new@example.com',
        displayName: 'new',
        handle: null,
        publicData: null,
      ),
    ).called(1);

    expect(
      () => case_.verify('opaque-token'),
      throwsA(isA<EmailAuthTokenInvalidException>()),
    );
  });

  test('verify rejects unknown token', () async {
    expect(
      () => case_.verify('missing'),
      throwsA(isA<EmailAuthTokenInvalidException>()),
    );
  });
}
