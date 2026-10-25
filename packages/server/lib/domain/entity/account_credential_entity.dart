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

  /// [publicData] key holding the device/browser a device key was added on
  /// ("Chrome on Linux"), as sent by the client when linking it.
  static const kDeviceLabelKey = 'deviceLabel';

  /// Longest device label kept; longer input is cut.
  static const kDeviceLabelMaxLength = 64;

  /// The device/browser this credential was added on, when one was recorded.
  String? get deviceLabel => switch (publicData?[kDeviceLabelKey]) {
    final String label when label.trim().isNotEmpty => label,
    _ => null,
  };

  /// Clean a client-sent device label for storage: control characters are
  /// dropped, whitespace collapsed, the result cut to [kDeviceLabelMaxLength].
  /// Returns null when nothing usable is left.
  static String? normalizeDeviceLabel(Object? raw) {
    if (raw is! String) return null;
    final cleaned = raw
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return null;
    return cleaned.length > kDeviceLabelMaxLength
        ? cleaned.substring(0, kDeviceLabelMaxLength).trimRight()
        : cleaned;
  }
}
