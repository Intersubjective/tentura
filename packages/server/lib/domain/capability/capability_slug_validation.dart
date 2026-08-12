import 'package:tentura_server/domain/capability/capability_tag.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

/// Validates, deduplicates, and returns capability slugs for evidence writes.
///
/// Reject unknown slugs and payloads longer than the canonical taxonomy.
/// E1b should call this before [RoutingMutePort.setMute].
List<String> validateCapabilitySlugPayload(List<String> slugs) {
  if (slugs.length > kAllowedCapabilitySlugs.length) {
    throw ExceptionBase(
      code: const CapabilityExceptionCodes(
        CapabilityExceptionCode.invalidSlug,
      ),
      description:
          'Capability slug payload exceeds taxonomy size '
          '(${kAllowedCapabilitySlugs.length})',
    );
  }
  final seen = <String>{};
  final deduped = <String>[];
  for (final slug in slugs) {
    if (!seen.add(slug)) {
      continue;
    }
    if (!kAllowedCapabilitySlugs.contains(slug)) {
      throw ExceptionBase(
        code: const CapabilityExceptionCodes(
          CapabilityExceptionCode.invalidSlug,
        ),
        description: 'Unknown capability slug: $slug',
      );
    }
    deduped.add(slug);
  }
  return deduped;
}
