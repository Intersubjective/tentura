import 'package:tentura_server/utils/id.dart';

/// Authentication method linked to an account (the `account_credential` row).
///
/// Phase 1 introduces one account + many credentials. Only [ed25519Device] is
/// exercised in the server-foundation slice (every existing user is backfilled
/// with one); the others land with their providers in later slices.
enum CredentialType {
  ed25519Device('ed25519_device'),
  webauthn('webauthn'),
  oidcGoogle('oidc:google'),
  oidcApple('oidc:apple'),
  emailOtp('email_otp');

  const CredentialType(this.wire);

  /// Stored value of the `type` column / wire representation.
  final String wire;

  static CredentialType fromWire(String wire) =>
      values.firstWhere((e) => e.wire == wire);
}

/// One credential bound to an account. The primary key [id] is internal-only
/// (lookup is by `(type, identifier)`, FKs by `accountId`); the identity that
/// matters is the unique `(type, identifier)` pair.
class AccountCredentialEntity {
  const AccountCredentialEntity({
    required this.id,
    required this.accountId,
    required this.type,
    required this.identifier,
    this.publicData,
    this.createdAt,
  });

  static String get newId => generateId('C');

  final String id;
  final String accountId;
  final CredentialType type;

  /// Device public key / OIDC `sub` / WebAuthn credential id, etc.
  final String identifier;

  /// Optional provider metadata (jsonb).
  final Map<String, Object?>? publicData;

  final DateTime? createdAt;
}
