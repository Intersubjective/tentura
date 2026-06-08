import 'package:tentura_server/utils/id.dart';

/// Consumed email magic-link transaction row (domain view).
class EmailAuthTransactionEntity {
  static String get newId => generateId('E');

  const EmailAuthTransactionEntity({
    required this.id,
    required this.normalizedEmail,
    required this.createdAt,
    required this.expiresAt,
    this.inviteCode,
    this.linkAccountId,
  });

  final String id;
  final String normalizedEmail;
  final String? inviteCode;

  /// Non-null when this transaction links the email to an existing account
  /// (Settings link mode) instead of resolve-or-create login.
  final String? linkAccountId;
  final DateTime createdAt;
  final DateTime expiresAt;
}

/// Result of a successful email verify (HTTP-free).
class EmailAuthVerifyResult {
  const EmailAuthVerifyResult({
    required this.accountId,
    this.inviteCode,
    this.credentialId,
    this.isLink = false,
  });

  final String accountId;
  final String? inviteCode;

  /// `email_otp` credential id, used to attribute the minted session.
  final String? credentialId;

  /// True when this was a Settings link-mode verify (mints NO session).
  final bool isLink;
}
