import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../entity/verified_contact_entity.dart';
import 'email_auth_util.dart';

typedef ContactMatchHash = ({int version, Digest digest});

/// Immutable keys used for email contact matching across key rotations.
final class ContactMatchKeyRing {
  ContactMatchKeyRing._(Map<int, Hmac> keys, this.newestVersion)
    : _keys = Map.unmodifiable(keys);

  factory ContactMatchKeyRing.parse(String? value) {
    final keys = <int, Hmac>{};
    int? newest;
    if (value != null && value.trim().isNotEmpty) {
      for (final entry in value.split(',')) {
        final separator = entry.indexOf(':');
        final version = separator < 0
            ? null
            : int.tryParse(entry.substring(0, separator).trim(), radix: 10);
        if (version == null || version < 1 || version > 32767) {
          throw StateError('$envName requires positive smallint key versions.');
        }
        final secret = entry.substring(separator + 1);
        if (secret.trim().isEmpty || keys.containsKey(version)) {
          throw StateError(
            '$envName requires a unique, non-empty secret entry for version '
            '$version.',
          );
        }
        keys[version] = Hmac(sha256, utf8.encode(secret));
        if (newest == null || version > newest) newest = version;
      }
    }
    return ContactMatchKeyRing._(keys, newest);
  }

  static const envName = 'CONTACT_MATCH_HMAC_KEYS';

  final Map<int, Hmac> _keys;
  Iterable<int> get versions => _keys.keys;
  final int? newestVersion;

  ContactMatchHash? hashForWrite(ContactKind kind, String value) {
    if (kind != ContactKind.email) return null;
    return hashNormalizedEmailForWrite(normalizeAuthEmail(value));
  }

  ContactMatchHash hashNormalizedEmailForWrite(String email) {
    final version = newestVersion;
    final key = _keys[version];
    if (version == null || key == null) {
      throw StateError('$envName must contain a key to hash email contacts.');
    }
    return (version: version, digest: key.convert(utf8.encode(email)));
  }

  Iterable<ContactMatchHash> candidateHashes(
    ContactKind kind,
    String value,
    Set<int> referencedVersions,
  ) => kind == ContactKind.email
      ? candidateHashesForNormalizedEmail(
          normalizeAuthEmail(value),
          referencedVersions,
        )
      : const [];

  Iterable<ContactMatchHash> candidateHashesForNormalizedEmail(
    String email,
    Iterable<int> referencedVersions,
  ) sync* {
    final message = utf8.encode(email);
    for (final version in referencedVersions) {
      final key = _keys[version];
      if (key != null) yield (version: version, digest: key.convert(message));
    }
  }
}
