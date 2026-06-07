import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/api/http/cookies.dart';
import 'package:tentura_server/api/http/oauth_return_uri.dart';
import 'package:tentura_server/api/http/oauth_state_codec.dart';
import 'package:tentura_server/api/http/oauth_warmup_interstitial_page.dart';
import 'package:tentura_server/consts.dart';
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
    final state = _randomUrlSafe(16);
    final codeVerifier = _randomUrlSafe(32);
    final nonce = _randomUrlSafe(16);
    final redirectUri = _callbackUri().toString();
    final payload = OAuthStatePayload(
      state: state,
      codeVerifier: codeVerifier,
      nonce: nonce,
      inviteId: inviteId,
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
    final accountId = await _oidcCase.completeGoogle(
      identity,
      inviteId: payload.inviteId,
    );
    final sessionToken = await _sessionCase.createSession(accountId: accountId);
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
