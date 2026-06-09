import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:ferry/ferry.dart' show OperationRequest, OperationResponse;
import 'package:http/http.dart' as http;

import 'package:tentura_root/consts.dart';

import 'package:tentura/domain/exception/server_exception.dart';

import 'auth_box.dart';
import 'credentials.dart';
import 'exception.dart';
import 'session_fetch.dart';

typedef GqlFetcher =
    Stream<OperationResponse<TData, TVars>> Function<TData, TVars>(
      OperationRequest<TData, TVars> request, [
      Stream<OperationResponse<TData, TVars>> Function(
        OperationRequest<TData, TVars>,
      )?
      forward,
    ]);

abstract base class RemoteApiClientBase {
  RemoteApiClientBase({
    required this.authJwtExpiresIn,
    required this.apiEndpointUrl,
    required this.apiEndpointUrlV2,
    required this.requestTimeout,
    required this.userAgent,
  });

  final String userAgent;

  final String apiEndpointUrl;

  final String apiEndpointUrlV2;

  final Duration requestTimeout;

  final Duration authJwtExpiresIn;

  bool _tokenLocked = false;

  AuthBox? _authBox;

  bool _sessionAuth = false;

  int _authGeneration = 0;

  /// Monotonic counter bumped on every auth transition; stale async work checks this.
  int get authGeneration => _authGeneration;

  void _bumpAuthGeneration() => _authGeneration++;

  Credentials? _sessionCredentials;

  bool get isSessionAuth => _sessionAuth;

  bool get hasValidToken =>
      _sessionAuth
          ? (_sessionCredentials?.hasValidToken ?? false)
          : (_authBox?.hasValidToken ?? false);

  //
  //
  //
  @mustCallSuper
  Future<void> close() async {
    return dropAuth();
  }

  ///
  /// Returns Auth Request JWT
  ///
  @mustCallSuper
  Future<String?> setAuth({
    required String seed,
    required AuthTokenFetcher authTokenFetcher,
    AuthRequestIntent? returnAuthRequestToken,
  }) async {
    if (seed.isEmpty) {
      throw const AuthenticationNoKeyException();
    }
    _bumpAuthGeneration();
    _tokenLocked = false;
    _sessionAuth = false;
    _sessionCredentials = null;
    _authBox = AuthBox.fromSeed(
      seed: seed,
      authTokenFetcher: authTokenFetcher,
    );
    return returnAuthRequestToken == null
        ? null
        : _authBox!.getAuthRequestToken(returnAuthRequestToken);
  }

  /// Cookie-session auth (web TMB). Clears seed-based auth state.
  @mustCallSuper
  Future<void> setSessionAuth() async {
    _bumpAuthGeneration();
    _tokenLocked = false;
    _authBox = null;
    _sessionAuth = true;
    _sessionCredentials = null;
  }

  /// After seed Bearer sign-in, converge to HttpOnly session cookie (web preview).
  Future<void> establishSessionFromBearer() async {
    if (_sessionAuth) return;
    if (_authBox == null) {
      throw const AuthenticationNoKeyException();
    }
    final bearer = (await getAuthToken()).accessToken;
    await postSessionRequest(
      uri: _sessionUri('/api/v2/session/from-bearer'),
      userAgent: userAgent,
      timeout: requestTimeout,
      bearerToken: bearer,
    );
  }

  /// Revoke server session cookie (best-effort).
  Future<void> sessionLogout() async {
    if (!_sessionAuth) return;
    try {
      await _postSessionLogout();
    } on SessionHttpException {
      /* already logged out */
    }
  }

  /// Idempotent browser cookie clear; ignores [_sessionAuth] guard.
  Future<bool> clearSessionCookie() async {
    try {
      final response = await _postSessionLogout();
      await dropAuth();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      await dropAuth();
      return false;
    }
  }

  Future<http.Response> _postSessionLogout() => postSessionRequest(
    uri: _sessionUri('/api/v2/session/logout'),
    userAgent: userAgent,
    timeout: requestTimeout,
  );

  //
  //
  //
  @mustCallSuper
  Future<void> dropAuth() async {
    _bumpAuthGeneration();
    _authBox = null;
    _tokenLocked = false;
    _sessionAuth = false;
    _sessionCredentials = null;
  }

  //
  //
  //
  @mustCallSuper
  Future<Credentials> getAuthToken() async {
    final generationAtStart = _authGeneration;
    if (_sessionAuth) {
      if (_sessionCredentials != null && _sessionCredentials!.hasValidToken) {
        return _sessionCredentials!;
      }
      if (_tokenLocked) {
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration(milliseconds: 100 + 100 * i));
          if (!_tokenLocked &&
              (_sessionCredentials?.hasValidToken ?? false)) {
            return _sessionCredentials!;
          }
        }
        throw TimeoutException('Timeout while refreshing session token!');
      }
      _tokenLocked = true;
      try {
        _sessionCredentials = await _fetchSessionCredentials();
        if (generationAtStart != _authGeneration) {
          throw const AuthenticationNoKeyException();
        }
        return _sessionCredentials!;
      } finally {
        _tokenLocked = false;
      }
    }
    if (_authBox == null) {
      throw const AuthenticationNoKeyException();
    }
    if (_authBox!.hasValidToken) {
      return _authBox!.credentials!;
    }
    if (_tokenLocked) {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration(milliseconds: 100 + 100 * i));
        if (!_tokenLocked && (_authBox?.hasValidToken ?? false)) {
          return _authBox!.credentials!;
        }
      }
      throw TimeoutException('Timeout while refreshing token!');
    } else {
      _tokenLocked = true;
      try {
        final credentials = await _authBox!.fetchCredentials(request);
        if (generationAtStart != _authGeneration) {
          throw const AuthenticationNoKeyException();
        }
        _authBox = _authBox!.copyWith(credentials: credentials);
        return credentials;
      } finally {
        _tokenLocked = false;
      }
    }
  }

  /// Authenticated GET (e.g. private room attachment binary download).
  Future<Uint8List> fetchAuthenticatedBytes(Uri uri) async {
    final token = (await getAuthToken()).accessToken;
    final response = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            kHeaderUserAgent: userAgent,
            kHeaderAccept: '*/*',
          },
        )
        .timeout(requestTimeout);
    if (response.statusCode != 200) {
      throw const ServerUnknownException();
    }
    return response.bodyBytes;
  }

  /// Authenticated GET returning a decoded JSON object (REST `/api/v2/…`).
  Future<Map<String, dynamic>> getAuthenticatedJson(Uri uri) async {
    final token = (await getAuthToken()).accessToken;
    final response = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            kHeaderUserAgent: userAgent,
            kHeaderAccept: 'application/json',
          },
        )
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ServerStatusException(response.statusCode);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Authenticated POST returning a decoded JSON object (REST `/api/v2/…`).
  Future<Map<String, dynamic>> postAuthenticatedJson(
    Uri uri, {
    Object? body,
  }) async {
    final token = (await getAuthToken()).accessToken;
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            kHeaderUserAgent: userAgent,
            kHeaderAccept: 'application/json',
            if (body != null) kHeaderContentType: kContentApplicationJson,
          },
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ServerStatusException(response.statusCode);
    }
    if (response.body.isEmpty) {
      return const {};
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Authenticated DELETE; throws [ServerStatusException] on non-2xx so callers
  /// can map the status (e.g. 404/409) to a domain exception.
  Future<void> deleteAuthenticated(Uri uri) async {
    final token = (await getAuthToken()).accessToken;
    final response = await http
        .delete(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            kHeaderUserAgent: userAgent,
            kHeaderAccept: 'application/json',
          },
        )
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ServerStatusException(response.statusCode);
    }
  }

  //
  //
  //
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]);

  Uri _sessionUri(String path) =>
      Uri.parse(apiEndpointUrlV2).replace(path: path, query: '');

  Future<Credentials> _fetchSessionCredentials() async {
    final response = await postSessionRequest(
      uri: _sessionUri('/api/v2/session/access-token'),
      userAgent: userAgent,
      timeout: requestTimeout,
    );
    final json = await decodeJsonResponse(response);
    return Credentials(
      userId: json['subject'] as String,
      accessToken: json['access_token'] as String,
      expiresAt: DateTime.timestamp().add(
        Duration(seconds: json['expires_in'] as int),
      ),
    );
  }
}
