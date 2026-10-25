/// A sign-in method linked to the current account, as returned by
/// `GET /api/v2/accounts/me/credentials`.
class CredentialEntity {
  const CredentialEntity({
    required this.id,
    required this.type,
    required this.identifier,
    this.createdAt,
    this.deviceLabel,
  });

  factory CredentialEntity.fromMap(Map<String, dynamic> map) =>
      CredentialEntity(
        id: map['id'] as String,
        type: map['type'] as String,
        identifier: map['identifier'] as String,
        createdAt: switch (map['createdAt']) {
          final String s => DateTime.tryParse(s),
          _ => null,
        },
        deviceLabel: switch (map['deviceLabel']) {
          final String s when s.trim().isNotEmpty => s.trim(),
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

  /// The device/browser a device key was added on ("Chrome on Linux"), when
  /// the server recorded one (#467).
  final String? deviceLabel;
}

extension CredentialEntityListX on Iterable<CredentialEntity> {
  bool hasType(String type) => any((c) => c.type == type);
}
