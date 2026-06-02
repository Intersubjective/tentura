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
  });

  final String id;
  final String normalizedEmail;
  final String? inviteCode;
  final DateTime createdAt;
  final DateTime expiresAt;
}

/// Result of a successful email verify (HTTP-free).
class EmailAuthVerifyResult {
  const EmailAuthVerifyResult({
    required this.accountId,
    this.inviteCode,
  });

  final String accountId;
  final String? inviteCode;
}
