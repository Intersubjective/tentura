import 'package:tentura_root/consts.dart';
import 'package:tentura_server/domain/capability/capability_tag.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

/// Shared normalization and media-independent validation for beacon creation.
abstract final class BeaconCreationPolicy {
  BeaconCreationPolicy._();

  static String? trimOrNull(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    return t.isEmpty ? null : t;
  }

  static String normalizeStandaloneDescription(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) {
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

  static void assertPublishTitle(String? raw) {
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
