import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/port/session_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';

import '_use_case_base.dart';

@Injectable(order: 2)
final class SessionCase extends UseCaseBase {
  SessionCase(
    this._sessionRepository,
    this._authCase, {
    required super.env,
    required super.logger,
  });

  final SessionRepositoryPort _sessionRepository;
  final AuthCase _authCase;

  static String hashToken(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  /// Creates a DB session and returns the opaque cookie value.
  Future<String> createSession({
    required String accountId,
    String? credentialId,
  }) async {
    final result = await _sessionRepository.create(
      accountId: accountId,
      expiresIn: env.sessionExpiresIn,
      credentialId: credentialId,
    );
    return result.token;
  }

  /// Resolves the session cookie token to an account id, or null.
  Future<String?> resolveAccountId(String? sessionToken) async {
    if (sessionToken == null || sessionToken.isEmpty) {
      return null;
    }
    final session = await _sessionRepository.findActiveByTokenHash(
      hashToken(sessionToken),
    );
    return session?.accountId;
  }

  Future<void> revokeSession(String? sessionToken) async {
    if (sessionToken == null || sessionToken.isEmpty) return;
    await _sessionRepository.revokeByTokenHash(
      hashToken(sessionToken),
    );
  }

  /// Mint a short-lived Bearer access token for API/Hasura (unchanged shape).
  Future<Map<String, Object>> accessTokenForAccount(String accountId) async =>
      _authCase.issueAccessToken(accountId).asOauth2Map;

  String sessionCookieName() => kCookieSessionName;

  Duration sessionCookieMaxAge() => env.sessionExpiresIn;
}
