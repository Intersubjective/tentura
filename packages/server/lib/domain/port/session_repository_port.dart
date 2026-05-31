import 'package:tentura_server/domain/entity/account_session_entity.dart';

abstract class SessionRepositoryPort {
  /// Creates a session and returns the opaque cookie token (plaintext, once).
  Future<({String token, AccountSessionEntity session})> create({
    required String accountId,
    required Duration expiresIn,
    String? credentialId,
  });

  /// Resolves [tokenHash] to an active session, or null if missing/expired/revoked.
  Future<AccountSessionEntity?> findActiveByTokenHash(String tokenHash);

  Future<void> revokeByTokenHash(String tokenHash);

  Future<void> revokeAllForAccount(String accountId);
}
