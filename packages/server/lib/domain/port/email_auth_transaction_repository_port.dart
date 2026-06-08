import 'package:tentura_server/domain/entity/email_auth_transaction_entity.dart';

abstract class EmailAuthTransactionRepositoryPort {
  /// Persists a new transaction; returns the opaque plaintext token (once).
  /// [linkAccountId] is set for Settings link mode (attach to that account).
  Future<String> create({
    required String normalizedEmail,
    required Duration expiresIn,
    required String userAgentHash,
    required String ipHash,
    String? inviteCode,
    String? linkAccountId,
  });

  /// Atomically marks the token consumed; null if missing, expired, or reused.
  Future<EmailAuthTransactionEntity?> consumeByToken(String plaintextToken);

  Future<int> countRecentByEmail({
    required String normalizedEmail,
    required Duration window,
  });

  Future<int> countRecentByIpHash({
    required String ipHash,
    required Duration window,
  });

  Future<int> countRecentByInviteCode({
    required String inviteCode,
    required Duration window,
  });
}
