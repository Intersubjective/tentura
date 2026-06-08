import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/oidc_identity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/oidc_provider_port.dart';
import 'package:tentura_server/domain/util/oidc_claim_util.dart';
import 'package:tentura_server/env.dart';

@Injectable(as: OidcProviderPort, order: 1)
class GoogleOidcService implements OidcProviderPort {
  GoogleOidcService(this._env);

  final Env _env;

  static const _authorizeHost = 'https://accounts.google.com';
  static const _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const _jwksUrl = 'https://www.googleapis.com/oauth2/v3/certs';

  Map<String, JWTKey>? _jwksCache;

  @override
  bool get isConfigured =>
      _env.googleClientId.isNotEmpty && _env.googleClientSecret.isNotEmpty;

  @override
  Uri buildGoogleAuthorizeUri({
    required String redirectUri,
    required String state,
    required String codeChallenge,
    required String nonce,
  }) =>
      Uri.parse('$_authorizeHost/o/oauth2/v2/auth').replace(
        queryParameters: {
          'client_id': _env.googleClientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': 'openid email profile',
          'state': state,
          'nonce': nonce,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
        },
      );

  @override
  Future<OidcIdentity> exchangeGoogleCode({
    required String code,
    required String redirectUri,
    required String codeVerifier,
    required String expectedNonce,
  }) async {
    if (!isConfigured) {
      throw const OidcProviderDisabledException();
    }
    final tokenResponse = await http.post(
      Uri.parse(_tokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'client_id': _env.googleClientId,
        'client_secret': _env.googleClientSecret,
        'code_verifier': codeVerifier,
      },
    );
    if (tokenResponse.statusCode != 200) {
      throw OidcTokenExchangeFailedException(
        description: 'Google token exchange failed: ${tokenResponse.statusCode}',
      );
    }
    final tokenJson =
        jsonDecode(tokenResponse.body) as Map<String, dynamic>;
    final idToken = tokenJson['id_token'] as String?;
    if (idToken == null || idToken.isEmpty) {
      throw const OidcIdTokenInvalidException();
    }
    return _verifyIdToken(idToken, expectedNonce: expectedNonce);
  }

  @override
  Future<OidcIdentity> verifyGoogleIdToken(
    String idToken, {
    String? expectedNonce,
  }) {
    // Native verify needs only the client id (no secret / web flow config).
    if (_env.googleClientId.isEmpty) {
      throw const OidcProviderDisabledException();
    }
    return _verifyIdToken(idToken, expectedNonce: expectedNonce);
  }

  Future<OidcIdentity> _verifyIdToken(
    String idToken, {
    String? expectedNonce,
  }) async {
    final header = JWT.decode(idToken).header;
    final kid = header?['kid'] as String?;
    if (kid == null || kid.isEmpty) {
      throw const OidcIdTokenInvalidException();
    }
    final key = await _resolveJwk(kid);
    JWT jwt;
    try {
      jwt = JWT.verify(idToken, key);
    } catch (_) {
      throw const OidcIdTokenInvalidException();
    }
    final payload = jwt.payload as Map<String, dynamic>;
    // `aud` allow-list: the web/server client (= Android `serverClientId`) and
    // the iOS client id when configured. iOS `google_sign_in` tokens use the
    // iOS client as `aud`, not the web client.
    final allowedAud = <String>{
      _env.googleClientId,
      if (_env.googleIosClientId.isNotEmpty) _env.googleIosClientId,
    };
    final aud = payload['aud'];
    final audOk = (aud is String && allowedAud.contains(aud)) ||
        (aud is List && aud.any(allowedAud.contains));
    if (!audOk) {
      throw const OidcIdTokenInvalidException();
    }
    final iss = payload['iss'] as String? ?? '';
    if (iss != 'https://accounts.google.com' &&
        iss != 'accounts.google.com') {
      throw const OidcIdTokenInvalidException();
    }
    // Native id tokens carry no server-issued nonce — skip when null.
    if (expectedNonce != null && payload['nonce'] != expectedNonce) {
      throw const OidcStateMismatchException();
    }
    final sub = payload['sub'] as String? ?? '';
    if (sub.isEmpty) {
      throw const OidcIdTokenInvalidException();
    }
    return OidcIdentity(
      sub: sub,
      email: payload['email'] as String? ?? '',
      name: payload['name'] as String? ?? '',
      emailVerified: parseOidcEmailVerified(payload['email_verified']),
      publicData: {
        if (payload['picture'] != null) 'picture': payload['picture'],
        if (payload['email_verified'] != null)
          'email_verified': payload['email_verified'],
      },
    );
  }

  Future<JWTKey> _resolveJwk(String kid) async {
    _jwksCache ??= await _fetchJwks();
    final key = _jwksCache![kid];
    if (key != null) return key;
    _jwksCache = await _fetchJwks();
    final retry = _jwksCache![kid];
    if (retry == null) {
      throw const OidcIdTokenInvalidException();
    }
    return retry;
  }

  Future<Map<String, JWTKey>> _fetchJwks() async {
    final response = await http.get(Uri.parse(_jwksUrl));
    if (response.statusCode != 200) {
      throw const OidcIdTokenInvalidException();
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final keys = json['keys'] as List<dynamic>? ?? [];
    final out = <String, JWTKey>{};
    for (final raw in keys) {
      final jwk = raw as Map<String, dynamic>;
      final kid = jwk['kid'] as String?;
      if (kid == null) continue;
      out[kid] = JWTKey.fromJWK(jwk);
    }
    return out;
  }
}
