import 'package:tentura_root/consts.dart';
import 'package:tentura_server/domain/capability/capability_tag.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/exception.dart';

/// Shared normalization and media-independent validation for beacon creation.
abstract final class BeaconCreationPolicy {
  BeaconCreationPolicy._();

  static String? trimOrNull(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    return t.isEmpty ? null : t;
  }

  static String normalizeStandaloneDescription(
    String? raw, {
    BeaconKind kind = BeaconKind.request,
  }) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) {
      if (kind == BeaconKind.post) return '';
      throw const BeaconCreateException(description: 'Description is required');
    }
    if (t.length > kBeaconDescriptionMaxLength) {
      throw const BeaconCreateException(description: 'Description is too long');
    }
    return t;
  }

  static String normalizeChildDescription(String? raw) {
    final t = (raw ?? '').trim();
    if (t.length > kBeaconDescriptionMaxLength) {
      throw const BeaconCreateException(description: 'Description is too long');
    }
    return t;
  }

  /// Kind-specific field rules: a Post carries no content, a Request needs
  /// a title.
  static void assertKindFields({
    required BeaconKind kind,
    required String? title,
    required String? description,
    required bool isDiscoverable,
    Set<String>? needs,
    String? primaryNeedSlug,
    DateTime? startAt,
    DateTime? endAt,
    bool hasCover = false,
    String? parentBeaconId,
  }) {
    if (kind == BeaconKind.request) {
      assertPublishTitle(title, kind: kind);
      return;
    }
    void reject(String what) => throw BeaconCreateException(
      description: 'A Post must not have $what',
    );
    if ((title ?? '').trim().isNotEmpty) reject('a title');
    if ((description ?? '').trim().isNotEmpty) reject('a description');
    if (needs != null && needs.isNotEmpty) reject('needs');
    if (primaryNeedSlug != null) reject('a primary need');
    if (startAt != null || endAt != null) reject('a schedule');
    if (hasCover) reject('a cover image');
    if (isDiscoverable) reject('discoverable set');
    if (parentBeaconId != null) reject('a parent');
  }

  static void assertPublishTitle(
    String? raw, {
    BeaconKind kind = BeaconKind.request,
  }) {
    if (kind == BeaconKind.post) return;
    final t = (raw ?? '').trim();
    if (t.isEmpty) {
      throw const BeaconCreateException(description: 'Title is required');
    }
  }

  static Set<String>? normalizeNeeds(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final slugs = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    for (final slug in slugs) {
      if (!kAllowedCapabilitySlugs.contains(slug)) {
        throw BeaconCreateException(
          description: 'Unknown capability slug: $slug',
        );
      }
    }
    return slugs.isEmpty ? null : slugs;
  }

  static String? resolvePrimaryNeedSlug({
    required Set<String>? needs,
    required String? primaryNeedSlug,
    required bool primaryNeedSlugProvided,
  }) {
    final needsSet = needs ?? const <String>{};
    if (!primaryNeedSlugProvided) {
      return canonicalFirstCapabilitySlug(needsSet);
    }
    if (primaryNeedSlug == null) {
      if (needsSet.isNotEmpty) {
        throw const BeaconPrimaryNeedNotInNeedsException();
      }
      return null;
    }
    if (!kAllowedCapabilitySlugs.contains(primaryNeedSlug)) {
      throw const BeaconPrimaryNeedInvalidException();
    }
    if (!needsSet.contains(primaryNeedSlug)) {
      throw const BeaconPrimaryNeedNotInNeedsException();
    }
    return primaryNeedSlug;
  }
}
