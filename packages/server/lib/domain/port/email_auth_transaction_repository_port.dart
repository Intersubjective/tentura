import 'package:tentura_server/domain/entity/email_auth_peek.dart';
import 'package:tentura_server/domain/entity/email_auth_transaction_entity.dart';

/// Read-only peek of a magic-link token row.
typedef EmailAuthTokenPeekRow = ({
  EmailAuthTokenStatus status,
  EmailAuthTransactionEntity? tx,
});

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

  /// Read-only token lookup; never mutates the row.
  Future<EmailAuthTokenPeekRow> peekByToken(String plaintextToken);

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
