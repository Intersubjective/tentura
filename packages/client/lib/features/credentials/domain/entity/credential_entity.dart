/// A sign-in method linked to the current account, as returned by
/// `GET /api/v2/accounts/me/credentials`.
class CredentialEntity {
  const CredentialEntity({
    required this.id,
    required this.type,
    required this.identifier,
    this.createdAt,
  });

  factory CredentialEntity.fromMap(Map<String, dynamic> map) => CredentialEntity(
    id: map['id'] as String,
    type: map['type'] as String,
    identifier: map['identifier'] as String,
    createdAt: switch (map['createdAt']) {
      final String s => DateTime.tryParse(s),
      _ => null,
    },
  );

  /// Stable credential id (used by the remove endpoint).
  final String id;

  /// Provider type, e.g. `ed25519_device`.
  final String type;

  /// Provider-scoped identifier (the device public key for `ed25519_device`).
  final String identifier;

  final DateTime? createdAt;
}
