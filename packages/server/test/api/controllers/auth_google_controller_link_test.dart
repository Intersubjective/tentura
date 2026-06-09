import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/auth_google_controller.dart';
import 'package:tentura_server/api/http/oauth_state_codec.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart'
    show AccountCredentialEntity, CredentialType;
import 'package:tentura_server/domain/entity/account_session_entity.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/oidc_identity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/oidc_provider_port.dart';
import 'package:tentura_server/domain/port/session_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/oidc_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/env.dart';

import '../../domain/use_case/invitation_case_mocks.mocks.dart';

const _accountId = 'Uabc123456789012345678901234567890';

final class _FakeOidcProvider implements OidcProviderPort {
  @override
  bool get isConfigured => true;

  @override
  Uri buildGoogleAuthorizeUri({
    required String redirectUri,
    required String state,
    required String codeChallenge,
    required String nonce,
  }) =>
      Uri.parse('https://accounts.google.com/o/oauth2/v2/auth');

  @override
  Future<OidcIdentity> exchangeGoogleCode({
    required String code,
    required String redirectUri,
    required String codeVerifier,
    required String expectedNonce,
  }) async =>
      const OidcIdentity(sub: 'google-sub', email: 'a@b.com', name: 'Ada');

  @override
  Future<OidcIdentity> verifyGoogleIdToken(
    String idToken, {
    String? expectedNonce,
  }) =>
      throw UnimplementedError();
}

final class _FakeSessionRepository implements SessionRepositoryPort {
  String? activeAccountId;

  @override
  Future<({String token, AccountSessionEntity session})> create({
    required String accountId,
    required Duration expiresIn,
    String? credentialId,
  }) async =>
      (
        token: 'session-tok',
        session: AccountSessionEntity(
          id: 'Ss1',
          accountId: accountId,
          tokenHash: 'h',
          expiresAt: DateTime.timestamp().add(expiresIn),
        ),
      );

  @override
  Future<AccountSessionEntity?> findActiveByTokenHash(String tokenHash) async {
    if (activeAccountId == null) return null;
    return AccountSessionEntity(
      id: 'Ss1',
      accountId: activeAccountId!,
      tokenHash: tokenHash,
      expiresAt: DateTime.timestamp().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<void> revokeByTokenHash(String tokenHash) async {}

  @override
  Future<void> revokeAllForAccount(String accountId) async {}

  @override
  Future<void> revokeByCredentialId(String credentialId) async {}
}

void main() {
  late Env env;
  late OAuthStateCodec codec;
  late AuthGoogleController controller;
  late MockUserRepositoryPort userRepo;
  late _FakeSessionRepository sessionRepo;

  setUp(() {
    env = Env(environment: Environment.test);
    codec = OAuthStateCodec(env);
    userRepo = MockUserRepositoryPort();
    sessionRepo = _FakeSessionRepository();
    final authCase = AuthCase(
      userRepo,
      env: env,
      logger: Logger('AuthGoogleLinkTest'),
    );
    final credentialAuthCase = CredentialAuthCase(
      userRepo,
      MockVerifiedContactRepositoryPort(),
      InvitationCase(
        MockInvitationRepositoryPort(),
        userRepo,
        MockBeaconRepositoryPort(),
        MockVoteUserFriendshipLookup(),
        env: env,
        logger: Logger('AuthGoogleLinkTest'),
      ),
      env: env,
      logger: Logger('AuthGoogleLinkTest'),
    );
    final oidcCase = OidcCase(
      credentialAuthCase,
      userRepo,
      env: env,
      logger: Logger('AuthGoogleLinkTest'),
    );
    final sessionCase = SessionCase(
      sessionRepo,
      authCase,
      env: env,
      logger: Logger('AuthGoogleLinkTest'),
    );
    controller = AuthGoogleController(
      env,
      _FakeOidcProvider(),
      oidcCase,
      sessionCase,
      codec,
    );
  });

  String setCookieHeader(Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null) return '';
    if (raw is String) return raw;
    return raw.toString();
  }

  Future<String> readBody(Response response) => response.readAsString();

  test('linkIntent returns a signed link/start URL', () async {
    final response = await controller.linkIntent(
      Request(
        'POST',
        Uri.parse('http://localhost/api/auth/google/link/intent'),
        context: {
          kContextJwtKey: const JwtEntity(sub: _accountId),
        },
      ),
    );
    expect(response.statusCode, 200);
    final body = jsonDecode(await readBody(response)) as Map<String, dynamic>;
    expect(body['url'], contains('/api/auth/google/link/start?lt='));
  });

  test('link callback strict-links without minting a session cookie', () async {
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
        id: 'Cgoogle',
        accountId: _accountId,
        type: CredentialType.oidcGoogle,
        identifier: 'google-sub',
      ),
    );

    const state = 'state123';
    final oauthCookie = codec.encode(
      const OAuthStatePayload(
        state: state,
        codeVerifier: 'verifier',
        nonce: 'nonce456',
        returnTo: 'https://app.example/#/settings/sign-in-methods?linked=google',
        linkAccountId: _accountId,
      ),
    );

    final response = await controller.callback(
      Request(
        'GET',
        Uri.parse(
          'http://localhost/api/auth/google/callback?code=abc&state=$state',
        ),
        headers: {'cookie': '$kCookieOAuthStateName=$oauthCookie'},
      ),
    );

    expect(response.statusCode, 302);
    expect(response.headers['location'], contains('linked=google'));
    final setCookie = setCookieHeader(response);
    expect(setCookie, isNot(contains(kCookieSessionName)));
    expect(setCookie, contains(kCookieOAuthStateName));
    verify(
      userRepo.linkCredentialToAccountStrict(
        accountId: _accountId,
        type: CredentialType.oidcGoogle,
        identifier: 'google-sub',
        publicData: anyNamed('publicData'),
        contacts: anyNamed('contacts'),
      ),
    ).called(1);
    verifyNever(
      userRepo.linkCredentialWithContacts(
        accountId: anyNamed('accountId'),
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
        publicData: anyNamed('publicData'),
        contacts: anyNamed('contacts'),
      ),
    );
  });

  test('login callback shows invite-required page for new user without invite', () async {
    env = Env(environment: Environment.test, isNeedInvite: true);
    codec = OAuthStateCodec(env);
    userRepo = MockUserRepositoryPort();
    sessionRepo = _FakeSessionRepository();
    final contactRepo = MockVerifiedContactRepositoryPort();
    final authCase = AuthCase(
      userRepo,
      env: env,
      logger: Logger('AuthGoogleLinkTest'),
    );
    final credentialAuthCase = CredentialAuthCase(
      userRepo,
      contactRepo,
      InvitationCase(
        MockInvitationRepositoryPort(),
        userRepo,
        MockBeaconRepositoryPort(),
        MockVoteUserFriendshipLookup(),
        env: env,
        logger: Logger('AuthGoogleLinkTest'),
      ),
      env: env,
      logger: Logger('AuthGoogleLinkTest'),
    );
    final oidcCase = OidcCase(
      credentialAuthCase,
      userRepo,
      env: env,
      logger: Logger('AuthGoogleLinkTest'),
    );
    final sessionCase = SessionCase(
      sessionRepo,
      authCase,
      env: env,
      logger: Logger('AuthGoogleLinkTest'),
    );
    controller = AuthGoogleController(
      env,
      _FakeOidcProvider(),
      oidcCase,
      sessionCase,
      codec,
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

    const state = 'state-invite-required';
    final oauthCookie = codec.encode(
      const OAuthStatePayload(
        state: state,
        codeVerifier: 'verifier',
        nonce: 'nonce789',
        returnTo: '',
      ),
    );

    final response = await controller.callback(
      Request(
        'GET',
        Uri.parse(
          'http://localhost/api/auth/google/callback?code=abc&state=$state',
        ),
        headers: {'cookie': '$kCookieOAuthStateName=$oauthCookie'},
      ),
    );

    expect(response.statusCode, 403);
    final body = await readBody(response);
    expect(body, contains('No account found for this sign-in'));
    expect(body, contains('Back to sign in'));
    expect(setCookieHeader(response), contains(kCookieOAuthStateName));
  });

  test('linkStart rejects when session account mismatches lt', () async {
    sessionRepo.activeAccountId = 'Uother123456789012345678901234567890';
    final intent = await controller.linkIntent(
      Request(
        'POST',
        Uri.parse('http://localhost/api/auth/google/link/intent'),
        context: {
          kContextJwtKey: const JwtEntity(sub: _accountId),
        },
      ),
    );
    final url = jsonDecode(await readBody(intent))['url'] as String;
    final lt = Uri.parse(url).queryParameters['lt']!;

    final response = await controller.linkStart(
      Request(
        'GET',
        Uri.parse('http://localhost/api/auth/google/link/start?lt=$lt'),
        headers: {'cookie': '$kCookieSessionName=opaque'},
      ),
    );

    expect(response.statusCode, 302);
    expect(response.headers['location'], contains('linked=error'));
  });
}
