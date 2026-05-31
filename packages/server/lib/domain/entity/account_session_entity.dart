import 'package:tentura_server/utils/id.dart';

/// Server-side web session row (`account_session` table).
class AccountSessionEntity {
  const AccountSessionEntity({
    required this.id,
    required this.accountId,
    required this.tokenHash,
    this.credentialId,
    this.createdAt,
    this.expiresAt,
    this.revokedAt,
  });

  static String get newId => generateId('S');

  final String id;
  final String accountId;
  final String tokenHash;
  final String? credentialId;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? revokedAt;

  bool get isActive =>
      revokedAt == null &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.timestamp());
}
