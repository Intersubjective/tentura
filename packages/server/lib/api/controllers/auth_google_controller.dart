import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/api/http/cookies.dart';
import 'package:tentura_server/api/http/auth_invite_required_page.dart';
import 'package:tentura_server/api/http/oauth_return_uri.dart';
import 'package:tentura_server/api/http/oauth_state_codec.dart';
import 'package:tentura_server/api/http/oauth_warmup_interstitial_page.dart';
import 'package:tentura_server/app/sentry/auth_telemetry.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/oidc_identity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/oidc_provider_port.dart';
import 'package:tentura_server/domain/use_case/oidc_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';

import '_base_controller.dart';

/// Google OAuth start + callback on the app host.
@Injectable(order: 3)
final class AuthGoogleController extends BaseController {
  static final _log = Logger('AuthGoogleController');
  const AuthGoogleController(
    super.env,
    this._oidcProvider,
    this._oidcCase,
    this._sessionCase,
    this._oauthStateCodec,
  );

  final OidcProviderPort _oidcProvider;
  final OidcCase _oidcCase;
  final SessionCase _sessionCase;
  final OAuthStateCodec _oauthStateCodec;

  /// `GET /api/auth/google/start?invite=…&returnTo=…&auth_attempt_id=…`
  Future<Response> start(Request request) async {
    final queryAttemptId = sanitizeAuthAttemptIdQuery(
      request.url.queryParameters['auth_attempt_id'],
    );
    if (queryAttemptId != null) {
      await tagAuthAttempt(
        request: request,
        authAttemptId: queryAttemptId,
        authMethod: 'google',
      );
    }
    if (!_oidcProvider.isConfigured) {
      await emitAuthOutcome(
        'google_start_outcome',
        authOutcome: 'misconfigured',
        authAttemptId: queryAttemptId,
        authMethod: 'google',
        request: request,
      );
      return Response(503, body: 'Google OAuth is not configured');
    }
    final inviteId = request.url.queryParameters['invite'];
    final returnTo = sanitizeOAuthReturnTo(
      raw: request.url.queryParameters['returnTo'],
      publicOrigin: env.publicOrigin,
    );
    return _beginAuthorize(
      request: request,
      inviteId: inviteId,
      returnTo: returnTo,
      authAttemptId: queryAttemptId,
    );
  }

  /// `POST /api/auth/google/link/intent` (Bearer) — mint a short-lived,
  /// signed link token (`lt`) bound to the calling account and return the
  /// top-level navigation URL the WASM client opens. The `lt` is not the
  /// security boundary: `link/start` additionally requires the caller's
  /// `__Host-tentura_session` cookie to resolve to the same account, and the
  /// final strict-link is idempotent, so a replayed `lt` is a no-op.
  Future<Response> linkIntent(Request request) async {
    final jwt = request.context[kContextJwtKey] as JwtEntity?;
    if (jwt == null || jwt.sub.isEmpty) {
      return Response.unauthorized(null);
    }
    if (!_oidcProvider.isConfigured) {
      return Response(503, body: 'Google OAuth is not configured');
    }
    final lt = _mintLinkToken(jwt.sub);
    final url = Uri.parse(env.publicOrigin)
        .replace(path: '/api/auth/google/link/start', queryParameters: {'lt': lt})
        .toString();
    return Response.ok(
      jsonEncode({'url': url}),
      headers: {
        kHeaderContentType: kContentApplicationJson,
        kHeaderCacheControl: kCacheControlNoStore,
      },
    );
  }

  /// `GET /api/auth/google/link/start?lt=…` — top-level navigation from the
  /// WASM client. Verifies the `lt`, requires a matching session cookie, then
  /// redirects to Google with `linkAccountId` carried in the signed OAuth
  /// state cookie.
  Future<Response> linkStart(Request request) async {
    if (!_oidcProvider.isConfigured) {
      return Response(503, body: 'Google OAuth is not configured');
    }
    final linkAccountId = _verifyLinkToken(request.url.queryParameters['lt']);
    if (linkAccountId == null) {
      return Response.found(_linkReturn('error'));
    }
    // The session cookie is the real boundary: only the authenticated owner of
    // the target account may attach a Google identity to it.
    final sessionAccount = await _sessionCase.resolveAccountId(
      readCookie(request, _sessionCase.sessionCookieName()),
    );
    if (sessionAccount == null || sessionAccount != linkAccountId) {
      return Response.found(_linkReturn('error'));
    }
    return _beginAuthorize(
      request: request,
      returnTo: _linkReturn('google'),
      linkAccountId: linkAccountId,
    );
  }

  Future<Response> _beginAuthorize({
    required Request request,
    required String returnTo,
    String? inviteId,
    String? linkAccountId,
    String? authAttemptId,
  }) async {
    final state = _randomUrlSafe(16);
    final codeVerifier = _randomUrlSafe(32);
    final nonce = _randomUrlSafe(16);
    final redirectUri = _callbackUri().toString();
    final payload = OAuthStatePayload(
      state: state,
      codeVerifier: codeVerifier,
      nonce: nonce,
      inviteId: inviteId,
      linkAccountId: linkAccountId,
      authAttemptId: authAttemptId,
      returnTo: returnTo,
    );
    final signed = _oauthStateCodec.encode(payload);
    final oauthStateParam = authAttemptId != null && authAttemptId.isNotEmpty
        ? '$state.$authAttemptId'
        : state;
    final authorizeUri = _oidcProvider.buildGoogleAuthorizeUri(
      redirectUri: redirectUri,
      state: oauthStateParam,
      codeChallenge: _codeChallenge(codeVerifier),
      nonce: nonce,
    );
    await emitAuthOutcome(
      'google_start_outcome',
      authOutcome: 'redirected',
      authAttemptId: authAttemptId,
      authMethod: 'google',
      request: request,
    );
    final oauthCookie = buildSetCookie(
      name: kCookieOAuthStateName,
      value: signed,
      maxAgeSeconds: kOAuthStateExpiresIn,
    );
    if (env.oauthPreloadEnabled) {
      return Response.ok(
        renderOAuthWarmupInterstitial(redirectUri: authorizeUri.toString()),
        headers: withSetCookie(
          {
            kHeaderContentType: 'text/html; charset=utf-8',
            kHeaderCacheControl: kCacheControlNoStore,
          },
          oauthCookie,
        ),
      );
    }
    return Response.found(
      authorizeUri.toString(),
      headers: withSetCookie(
        {kHeaderCacheControl: kCacheControlNoStore},
        oauthCookie,
      ),
    );
  }

  /// `GET /api/auth/google/callback?code=…&state=…`
  Future<Response> callback(Request request) async {
    if (!_oidcProvider.isConfigured) {
      return Response(503, body: 'Google OAuth is not configured');
    }
    final code = request.url.queryParameters['code'] ?? '';
    final rawState = request.url.queryParameters['state'] ?? '';
    final (csrfState, queryAttemptId) = parseOAuthStateQuery(rawState);
    if (queryAttemptId != null) {
      await tagAuthAttempt(
        request: request,
        authAttemptId: queryAttemptId,
        authMethod: 'google',
      );
    }
    if (code.isEmpty || rawState.isEmpty) {
      await emitAuthOutcome(
        'google_callback_outcome',
        authOutcome: 'missing_code_or_state',
        authAttemptId: queryAttemptId,
        authMethod: 'google',
        request: request,
      );
      return Response.badRequest(body: 'missing code or state');
    }
    final oauthCookie = readCookie(request, kCookieOAuthStateName);
    if (oauthCookie == null || oauthCookie.isEmpty) {
      await emitAuthOutcome(
        'google_callback_outcome',
        authOutcome: 'missing_state_cookie',
        authAttemptId: queryAttemptId,
        authMethod: 'google',
        request: request,
      );
      return _oauthStateError();
    }
    final payload = _oauthStateCodec.decode(oauthCookie);
    final signedAttemptId = sanitizeAuthAttemptIdQuery(payload.authAttemptId);
    final attemptId = signedAttemptId ?? queryAttemptId;
    if (attemptId != null) {
      await tagAuthAttempt(
        request: request,
        authAttemptId: attemptId,
        authMethod: 'google',
      );
    }
    if (payload.state != csrfState) {
      await emitAuthOutcome(
        'google_callback_outcome',
        authOutcome: 'state_mismatch',
        authAttemptId: attemptId,
        authMethod: 'google',
        request: request,
      );
      return _oauthStateError();
    }
    final redirectUri = _callbackUri().toString();
    OidcIdentity identity;
    try {
      identity = await _oidcProvider.exchangeGoogleCode(
        code: code,
        redirectUri: redirectUri,
        codeVerifier: payload.codeVerifier,
        expectedNonce: payload.nonce,
      );
    } catch (e, st) {
      _log.severe('Google OAuth token exchange failed', e, st);
      await emitAuthOutcome(
        'google_callback_outcome',
        authOutcome: 'token_exchange_failed',
        authAttemptId: attemptId,
        authMethod: 'google',
        request: request,
      );
      return _oauthStateError();
    }

    // Settings link mode: strict-link to the existing account; NEVER call
    // completeGoogle/createSession (that would switch/mint a session).
    final linkAccountId = payload.linkAccountId;
    if (linkAccountId != null && linkAccountId.isNotEmpty) {
      final clearOauth = withSetCookie(
        {kHeaderCacheControl: kCacheControlNoStore},
        buildClearCookie(kCookieOAuthStateName),
      );
      try {
        await _oidcCase.linkGoogle(
          accountId: linkAccountId,
          identity: identity,
        );
      } on CredentialConflictException {
        await emitAuthOutcome(
          'google_callback_outcome',
          authOutcome: 'credential_conflict',
          authAttemptId: attemptId,
          authMethod: 'google',
          request: request,
        );
        return Response.found(_linkReturn('conflict'), headers: clearOauth);
      } on ContactConflictException {
        await emitAuthOutcome(
          'google_callback_outcome',
          authOutcome: 'credential_conflict',
          authAttemptId: attemptId,
          authMethod: 'google',
          request: request,
        );
        return Response.found(_linkReturn('conflict'), headers: clearOauth);
      }
      return Response.found(_linkReturn('google'), headers: clearOauth);
    }

    try {
      final resolved = await _oidcCase.completeGoogle(
        identity,
        inviteId: payload.inviteId,
      );
      final sessionToken = await _sessionCase.createSession(
        accountId: resolved.accountId,
        credentialId: resolved.credentialId,
      );
      final destination = destinationAfterOAuthCallback(
        returnTo: payload.returnTo,
        publicOrigin: env.publicOrigin,
        isNewAccount: resolved.isNewAccount,
      );
      await emitAuthOutcome(
        'google_callback_outcome',
        authOutcome: resolved.isNewAccount ? 'success_new' : 'success_existing',
        authAttemptId: attemptId,
        authMethod: 'google',
        request: request,
      );
      final headers = withSetCookie(
        withSetCookie(
          {kHeaderCacheControl: kCacheControlNoStore},
          buildClearCookie(kCookieOAuthStateName),
        ),
        buildSetCookie(
          name: _sessionCase.sessionCookieName(),
          value: sessionToken,
          maxAgeSeconds: _sessionCase.sessionCookieMaxAge().inSeconds,
        ),
      );
      if (env.oauthPreloadEnabled) {
        return Response.ok(
          renderOAuthWarmupInterstitial(redirectUri: destination),
          headers: {
            ...headers,
            kHeaderContentType: 'text/html; charset=utf-8',
          },
        );
      }
      return Response.found(destination, headers: headers);
    } on OidcInviteRequiredException {
      await emitAuthOutcome(
        'google_callback_outcome',
        authOutcome: 'invite_required',
        authAttemptId: attemptId,
        authMethod: 'google',
        request: request,
      );
      return _inviteRequiredPage(
        returnTo: payload.returnTo,
        clearOauthCookie: true,
      );
    } catch (e, st) {
      _log.severe('Google OAuth login callback failed', e, st);
      await emitAuthOutcome(
        'google_callback_outcome',
        authOutcome: 'unexpected_error',
        authAttemptId: attemptId,
        authMethod: 'google',
        request: request,
      );
      return Response.found(
        publicLandingUrl(env.publicOrigin),
        headers: withSetCookie(
          {kHeaderCacheControl: kCacheControlNoStore},
          buildClearCookie(kCookieOAuthStateName),
        ),
      );
    }
  }

  Response _inviteRequiredPage({
    required String returnTo,
    required bool clearOauthCookie,
  }) {
    final headers = <String, Object>{
      kHeaderContentType: 'text/html; charset=utf-8',
      kHeaderCacheControl: kCacheControlNoStore,
    };
    if (clearOauthCookie) {
      return Response(
        403,
        body: renderAuthInviteRequiredPage(
          landingUrl: publicLandingUrl(env.publicOrigin),
          inviteUrl: invitePageUrlFromReturnTo(
            returnTo: returnTo,
            publicOrigin: env.publicOrigin,
          ),
        ),
        headers: withSetCookie(
          headers,
          buildClearCookie(kCookieOAuthStateName),
        ),
      );
    }
    return Response(
      403,
      body: renderAuthInviteRequiredPage(
        landingUrl: publicLandingUrl(env.publicOrigin),
        inviteUrl: invitePageUrlFromReturnTo(
          returnTo: returnTo,
          publicOrigin: env.publicOrigin,
        ),
      ),
      headers: headers,
    );
  }

  /// Friendly fail-closed response for a missing/mismatched OAuth state cookie:
  /// clears the (stale) state cookie and sends the user back to the landing page.
  Response _oauthStateError() => Response.found(
        publicLandingUrl(env.publicOrigin),
        headers: withSetCookie(
          {kHeaderCacheControl: kCacheControlNoStore},
          buildClearCookie(kCookieOAuthStateName),
        ),
      );

  Uri _callbackUri() {
    return Uri.parse(env.publicOrigin).replace(
      path: '/api/auth/google/callback',
    );
  }

  /// Hash-routed Settings credentials destination with a `linked=<status>`
  /// flag the SPA reads to flash a toast and refresh the methods list.
  String _linkReturn(String status) {
    final origin = env.publicOrigin.endsWith('/')
        ? env.publicOrigin.substring(0, env.publicOrigin.length - 1)
        : env.publicOrigin;
    return '$origin/#/settings/sign-in-methods?linked=$status';
  }

  /// Short-lived (5 min) signed token binding a Google link flow to one account.
  String _mintLinkToken(String accountId) => JWT(
    {'purpose': _linkTokenPurpose, 'lacc': accountId},
    issuer: env.publicOrigin,
    audience: Audience.one(_linkTokenAudience),
  ).sign(
    env.privateKey,
    algorithm: JWTAlgorithm.EdDSA,
    expiresIn: const Duration(minutes: 5),
  );

  String? _verifyLinkToken(String? token) {
    if (token == null || token.isEmpty) return null;
    try {
      // Bind to this server (issuer) and the link-flow audience, so an
      // EdDSA-signed token minted for any other purpose cannot be replayed here.
      final map = JWT.verify(
        token,
        env.publicKey,
        issuer: env.publicOrigin,
        audience: Audience.one(_linkTokenAudience),
      ).payload as Map<String, dynamic>;
      if (map['purpose'] != _linkTokenPurpose) return null;
      final lacc = map['lacc'] as String?;
      return (lacc == null || lacc.isEmpty) ? null : lacc;
    } catch (_) {
      return null;
    }
  }

  static const _linkTokenPurpose = 'google_link';
  static const _linkTokenAudience = 'tentura:google_link';

  static String _randomUrlSafe(int byteCount) =>
      base64UrlEncode(
        List<int>.generate(byteCount, (_) => Random.secure().nextInt(256)),
      ).replaceAll('=', '');

  static String _codeChallenge(String verifier) => base64UrlEncode(
    sha256.convert(utf8.encode(verifier)).bytes,
  ).replaceAll('=', '');

  @override
  Future<Response> handler(Request request) =>
      throw UnsupportedError('use start/callback');
}
