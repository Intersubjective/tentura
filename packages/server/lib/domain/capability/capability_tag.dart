import 'package:tentura_root/domain/capability/capability_slugs.dart';

export 'package:tentura_root/domain/capability/capability_slugs.dart'
    show canonicalFirstCapabilitySlug, kCapabilitySlugOrder, kCapabilitySlugRank;

/// Allowed capability tag slugs. Validated server-side for every write.
final kAllowedCapabilitySlugs = kCapabilitySlugOrder.toSet();
