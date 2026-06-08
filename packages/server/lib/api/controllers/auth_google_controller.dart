import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/api/http/cookies.dart';
import 'package:tentura_server/api/http/oauth_return_uri.dart';
import 'package:tentura_server/api/http/oauth_state_codec.dart';
import 'package:tentura_server/api/http/oauth_warmup_interstitial_page.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/oidc_provider_port.dart';
import 'package:tentura_server/domain/use_case/oidc_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';

import '_base_controller.dart';

/// Google OAuth start + callback on the app host.
@Injectable(order: 3)
final class AuthGoogleController extends BaseController {
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

  /// `GET /api/auth/google/start?invite=…&returnTo=…`
  Future<Response> start(Request request) async {
    if (!_oidcProvider.isConfigured) {
      return Response(503, body: 'Google OAuth is not configured');
    }
    final inviteId = request.url.queryParameters['invite'];
    final returnTo = sanitizeOAuthReturnTo(
      raw: request.url.queryParameters['returnTo'],
      publicOrigin: env.publicOrigin,
    );
    return _beginAuthorize(inviteId: inviteId, returnTo: returnTo);
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
    return _beginAuthorize(returnTo: _linkReturn('google'), linkAccountId: linkAccountId);
  }

  Future<Response> _beginAuthorize({
    required String returnTo,
    String? inviteId,
    String? linkAccountId,
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
      returnTo: returnTo,
    );
    final signed = _oauthStateCodec.encode(payload);
    final authorizeUri = _oidcProvider.buildGoogleAuthorizeUri(
      redirectUri: redirectUri,
      state: state,
      codeChallenge: _codeChallenge(codeVerifier),
      nonce: nonce,
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
    final state = request.url.queryParameters['state'] ?? '';
    if (code.isEmpty || state.isEmpty) {
      return Response.badRequest(body: 'missing code or state');
    }
    final oauthCookie = readCookie(request, kCookieOAuthStateName);
    if (oauthCookie == null || oauthCookie.isEmpty) {
      throw const OidcStateMismatchException();
    }
    final payload = _oauthStateCodec.decode(oauthCookie);
    if (payload.state != state) {
      throw const OidcStateMismatchException();
    }
    final redirectUri = _callbackUri().toString();
    final identity = await _oidcProvider.exchangeGoogleCode(
      code: code,
      redirectUri: redirectUri,
      codeVerifier: payload.codeVerifier,
      expectedNonce: payload.nonce,
    );

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
        return Response.found(_linkReturn('conflict'), headers: clearOauth);
      } on ContactConflictException {
        return Response.found(_linkReturn('conflict'), headers: clearOauth);
      }
      return Response.found(_linkReturn('google'), headers: clearOauth);
    }

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
  }

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
  ).sign(
    env.privateKey,
    algorithm: JWTAlgorithm.EdDSA,
    expiresIn: const Duration(minutes: 5),
  );

  String? _verifyLinkToken(String? token) {
    if (token == null || token.isEmpty) return null;
    try {
      final map = JWT.verify(token, env.publicKey).payload as Map<String, dynamic>;
      if (map['purpose'] != _linkTokenPurpose) return null;
      final lacc = map['lacc'] as String?;
      return (lacc == null || lacc.isEmpty) ? null : lacc;
    } catch (_) {
      return null;
    }
  }

  static const _linkTokenPurpose = 'google_link';

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
