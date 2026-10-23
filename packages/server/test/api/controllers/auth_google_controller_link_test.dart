import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/auth_google_controller.dart';
import 'package:tentura_server/api/http/auth_invite_required_page.dart';
import 'package:tentura_server/api/http/oauth_state_codec.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart'
    show AccountCredentialEntity, CredentialType;
import 'package:tentura_server/domain/entity/account_session_entity.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/oidc_identity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/oidc_provider_port.dart';
import 'package:tentura_server/domain/port/session_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/oidc_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/env.dart';

import '../../domain/use_case/invitation_case_mocks.mocks.dart';
import '../../support/build_test_invitation_case.dart';

const _accountId = 'Uabc123456789012345678901234567890';

final class _FakeOidcProvider implements OidcProviderPort {
  _FakeOidcProvider({this.failExchange = false});

  /// Simulates Google rejecting the authorization code (bogus/expired code).
  final bool failExchange;

  @override
  bool get isConfigured => true;

  @override
  Uri buildGoogleAuthorizeUri({
    required String redirectUri,
    required String state,
    required String codeChallenge,
    required String nonce,
  }) => Uri.parse('https://accounts.google.com/o/oauth2/v2/auth');

  @override
  Future<OidcIdentity> exchangeGoogleCode({
    required String code,
    required String redirectUri,
    required String codeVerifier,
    required String expectedNonce,
  }) async {
    if (failExchange) throw Exception('invalid_grant');
    return const OidcIdentity(sub: 'google-sub', email: 'a@b.com', name: 'Ada');
  }

  @override
  Future<OidcIdentity> verifyGoogleIdToken(
    String idToken, {
    String? expectedNonce,
  }) => throw UnimplementedError();
}

final class _FakeSessionRepository implements SessionRepositoryPort {
  String? activeAccountId;

  @override
  Future<({String token, AccountSessionEntity session})> create({
    required String accountId,
    required Duration expiresIn,
    String? credentialId,
  }) async => (
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
  late OidcCase oidcCase;
  late SessionCase sessionCase;

  setUp(() {
    env = Env(environment: Environment.test);
    codec = OAuthStateCodec(env);
    userRepo = MockUserRepositoryPort();
    sessionRepo = _FakeSessionRepository();
    final invitationRepo = MockInvitationRepositoryPort();
    final authCase = AuthCase(
      userRepo,
      invitationRepo,
      env: env,
      logger: Logger('AuthGoogleLinkTest'),
    );
    final invitationCase = buildTestInvitationCase(
      invitationRepo: invitationRepo,
      userRepo: userRepo,
      beaconRepo: MockBeaconRepositoryPort(),
      friendshipLookup: MockVoteUserFriendshipLookupPort(),
      contactRepo: MockUserContactRepositoryPort(),
      env: env,
      logger: Logger('AuthGoogleLinkTest'),
    );
    final credentialAuthCase = CredentialAuthCase(
      userRepo,
      MockVerifiedContactRepositoryPort(),
      invitationRepo,
      invitationCase,
      env: env,
      logger: Logger('AuthGoogleLinkTest'),
    );
    oidcCase = OidcCase(
      credentialAuthCase,
      userRepo,
      env: env,
      logger: Logger('AuthGoogleLinkTest'),
    );
    sessionCase = SessionCase(
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
    return raw;
  }

  Future<String> readBody(Response response) => response.readAsString();

  /// #418: a failed login callback lands on the start page carrying
  /// `?auth_error=<reason>` (and nothing else from Google's query), so the
  /// landing can say what happened instead of looking as if nothing did.
  void expectLandingWithAuthError(Response response, String reason) {
    expect(response.statusCode, 302);
    final raw = response.headers['location']!;
    final location = Uri.parse(raw);
    expect(
      raw.split('?').first,
      publicLandingUrl(env.publicOrigin),
      reason: 'must land on the public start page',
    );
    expect(location.queryParameters, {'auth_error': reason});
    expect(location.fragment, isEmpty);
    expect(setCookieHeader(response), contains(kCookieOAuthStateName));
    expect(setCookieHeader(response), isNot(contains(kCookieSessionName)));
    expect(response.headers['cache-control'], contains('no-store'));
  }

  String loginStateCookie({
    String state = 'state123',
    String returnTo = '',
  }) => codec.encode(
    OAuthStatePayload(
      state: state,
      codeVerifier: 'verifier',
      nonce: 'nonce456',
      returnTo: returnTo,
    ),
  );

  /// #601: a sign-in started from an invite page carries that page as
  /// `returnTo` (with the attempt id the landing adds).
  String inviteReturnTo(String code) => Uri.parse(env.publicOrigin)
      .replace(
        path: '/invite/$code',
        queryParameters: {'auth_attempt_id': 'G123'},
      )
      .toString();

  /// #601: a failed sign-in started from `/invite/<code>` goes back to that
  /// invite page (not the bare start page) with only `?auth_error=<reason>`.
  void expectInviteWithAuthError(
    Response response,
    String code,
    String reason,
  ) {
    expect(response.statusCode, 302);
    final raw = response.headers['location']!;
    final location = Uri.parse(raw);
    expect(
      raw.split('?').first,
      Uri.parse(env.publicOrigin).replace(path: '/invite/$code').toString(),
      reason: 'must return to the invite page the sign-in started from',
    );
    expect(location.queryParameters, {'auth_error': reason});
    expect(location.fragment, isEmpty);
    expect(setCookieHeader(response), contains(kCookieOAuthStateName));
    expect(setCookieHeader(response), isNot(contains(kCookieSessionName)));
    expect(response.headers['cache-control'], contains('no-store'));
  }

  group('callback failures (B073)', () {
    // #418: fails on the base: _callbackFailure -> _oauthStateError() redirects
    // to the bare landing URL, so the start page cannot tell a cancel apart
    // from nothing happening.
    test(
      'cancelled Google consent returns to the landing page (B073)',
      () async {
        final response = await controller.callback(
          Request(
            'GET',
            Uri.parse(
              'http://localhost/api/auth/google/callback'
              '?error=access_denied&state=state123',
            ),
          ),
        );
        expectLandingWithAuthError(response, 'google_cancelled');
      },
    );

    test(
      'cancel with a readable login state cookie says cancelled (#418)',
      () async {
        final response = await controller.callback(
          Request(
            'GET',
            Uri.parse(
              'http://localhost/api/auth/google/callback'
              '?error=access_denied&state=state123',
            ),
            headers: {
              'cookie': '$kCookieOAuthStateName=${loginStateCookie()}',
            },
          ),
        );
        expectLandingWithAuthError(response, 'google_cancelled');
      },
    );

    // Any other Google error (not a cancel) is a failure, not a cancel.
    test('a non-cancel Google error says failed (#418)', () async {
      final response = await controller.callback(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/api/auth/google/callback'
            '?error=server_error&state=state123',
          ),
        ),
      );
      expectLandingWithAuthError(response, 'google_failed');
    });

    test(
      'callback without code or state returns to the landing page',
      () async {
        final response = await controller.callback(
          Request(
            'GET',
            Uri.parse('http://localhost/api/auth/google/callback'),
          ),
        );
        expectLandingWithAuthError(response, 'google_failed');
      },
    );

    // #418 "Invalid code: 302 to the start page with no message at all".
    test(
      'failed token exchange lands on the start page saying failed (#418)',
      () async {
        final failing = AuthGoogleController(
          env,
          _FakeOidcProvider(failExchange: true),
          oidcCase,
          sessionCase,
          codec,
        );
        final response = await failing.callback(
          Request(
            'GET',
            Uri.parse(
              'http://localhost/api/auth/google/callback'
              '?code=bogus&state=state123',
            ),
            headers: {
              'cookie': '$kCookieOAuthStateName=${loginStateCookie()}',
            },
          ),
        );
        expectLandingWithAuthError(response, 'google_failed');
      },
    );

    // #418: a state that was never issued gave no visible error either.
    test(
      'state mismatch lands on the start page saying failed (#418)',
      () async {
        final response = await controller.callback(
          Request(
            'GET',
            Uri.parse(
              'http://localhost/api/auth/google/callback'
              '?code=abc&state=state123',
            ),
            headers: {
              'cookie':
                  '$kCookieOAuthStateName=${loginStateCookie(state: 'other')}',
            },
          ),
        );
        expectLandingWithAuthError(response, 'google_failed');
      },
    );

    test(
      'missing state cookie lands on the start page saying failed (#418)',
      () async {
        final response = await controller.callback(
          Request(
            'GET',
            Uri.parse(
              'http://localhost/api/auth/google/callback'
              '?code=abc&state=state123',
            ),
          ),
        );
        expectLandingWithAuthError(response, 'google_failed');
      },
    );

    test('cancel during Settings link returns to Sign-in methods', () async {
      // Fails on the base: a link-mode cancel landed on the public start page.
      final oauthCookie = codec.encode(
        const OAuthStatePayload(
          state: 'state123',
          codeVerifier: 'verifier',
          nonce: 'nonce456',
          returnTo:
              'https://app.example/#/settings/sign-in-methods?linked=google',
          linkAccountId: _accountId,
        ),
      );
      final response = await controller.callback(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/api/auth/google/callback'
            '?error=access_denied&state=state123',
          ),
          headers: {'cookie': '$kCookieOAuthStateName=$oauthCookie'},
        ),
      );
      expect(response.statusCode, 302);
      expect(
        response.headers['location'],
        endsWith('/#/settings/sign-in-methods?linked=error'),
      );
      // #418 guard: the landing-page flag must not leak into the link return.
      expect(response.headers['location'], isNot(contains('auth_error')));
      expect(setCookieHeader(response), contains(kCookieOAuthStateName));
      expect(setCookieHeader(response), isNot(contains(kCookieSessionName)));
      expect(response.headers['cache-control'], contains('no-store'));
    });

    group('started from an invite page (#601)', () {
      test('cancel returns to the invite page saying cancelled', () async {
        final response = await controller.callback(
          Request(
            'GET',
            Uri.parse(
              'http://localhost/api/auth/google/callback'
              '?error=access_denied&state=state123',
            ),
            headers: {
              'cookie':
                  '$kCookieOAuthStateName='
                  '${loginStateCookie(returnTo: inviteReturnTo('ABC123'))}',
            },
          ),
        );
        expectInviteWithAuthError(response, 'ABC123', 'google_cancelled');
      });

      test('failed token exchange returns to the invite page', () async {
        final failing = AuthGoogleController(
          env,
          _FakeOidcProvider(failExchange: true),
          oidcCase,
          sessionCase,
          codec,
        );
        final response = await failing.callback(
          Request(
            'GET',
            Uri.parse(
              'http://localhost/api/auth/google/callback'
              '?code=bogus&state=state123',
            ),
            headers: {
              'cookie':
                  '$kCookieOAuthStateName='
                  '${loginStateCookie(returnTo: inviteReturnTo('ABC123'))}',
            },
          ),
        );
        expectInviteWithAuthError(response, 'ABC123', 'google_failed');
      });

      test('state mismatch returns to the invite page', () async {
        final cookie = loginStateCookie(
          state: 'other',
          returnTo: inviteReturnTo('ABC123'),
        );
        final response = await controller.callback(
          Request(
            'GET',
            Uri.parse(
              'http://localhost/api/auth/google/callback'
              '?code=abc&state=state123',
            ),
            headers: {'cookie': '$kCookieOAuthStateName=$cookie'},
          ),
        );
        expectInviteWithAuthError(response, 'ABC123', 'google_failed');
      });

      test('an unexpected login error returns to the invite page', () async {
        when(
          userRepo.getByCredential(
            type: anyNamed('type'),
            identifier: anyNamed('identifier'),
          ),
        ).thenAnswer((_) async => const UserEntity(id: _accountId));
        when(
          userRepo.addVerifiedContacts(
            accountId: anyNamed('accountId'),
            source: anyNamed('source'),
            contacts: anyNamed('contacts'),
          ),
        ).thenThrow(StateError('db down'));
        final response = await controller.callback(
          Request(
            'GET',
            Uri.parse(
              'http://localhost/api/auth/google/callback'
              '?code=abc&state=state123',
            ),
            headers: {
              'cookie':
                  '$kCookieOAuthStateName='
                  '${loginStateCookie(returnTo: inviteReturnTo('ABC123'))}',
            },
          ),
        );
        expectInviteWithAuthError(response, 'ABC123', 'google_failed');
      });

      // Guard: a non-invite return target still lands on the start page.
      test('a non-invite returnTo still lands on the start page', () async {
        final response = await controller.callback(
          Request(
            'GET',
            Uri.parse(
              'http://localhost/api/auth/google/callback'
              '?error=access_denied&state=state123',
            ),
            headers: {
              'cookie':
                  '$kCookieOAuthStateName='
                  '${loginStateCookie(returnTo: '${env.publicOrigin}/')}',
            },
          ),
        );
        expectLandingWithAuthError(response, 'google_cancelled');
      });
    });

    test(
      'cancel with an unreadable state cookie still lands on start page',
      () async {
        final response = await controller.callback(
          Request(
            'GET',
            Uri.parse(
              'http://localhost/api/auth/google/callback?error=access_denied',
            ),
            headers: {'cookie': '$kCookieOAuthStateName=not-a-jwt'},
          ),
        );
        expectLandingWithAuthError(response, 'google_cancelled');
      },
    );
  });

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
        returnTo:
            'https://app.example/#/settings/sign-in-methods?linked=google',
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

  test(
    'login callback shows invite-required page for new user without invite',
    () async {
      env = Env(environment: Environment.test, isNeedInvite: true);
      codec = OAuthStateCodec(env);
      userRepo = MockUserRepositoryPort();
      sessionRepo = _FakeSessionRepository();
      final contactRepo = MockVerifiedContactRepositoryPort();
      final invitationRepo = MockInvitationRepositoryPort();
      final authCase = AuthCase(
        userRepo,
        invitationRepo,
        env: env,
        logger: Logger('AuthGoogleLinkTest'),
      );
      final invitationCase = buildTestInvitationCase(
        invitationRepo: invitationRepo,
        userRepo: userRepo,
        beaconRepo: MockBeaconRepositoryPort(),
        friendshipLookup: MockVoteUserFriendshipLookupPort(),
        contactRepo: MockUserContactRepositoryPort(),
        env: env,
        logger: Logger('AuthGoogleLinkTest'),
      );
      final credentialAuthCase = CredentialAuthCase(
        userRepo,
        contactRepo,
        invitationRepo,
        invitationCase,
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
    },
  );

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
