/// Canonical capability slug order shared by client and server.
///
/// Order matches the live client `CapabilityTag` enum. Do not reorder;
/// [canonicalFirstCapabilitySlug] and DB backfills depend on this ranking.
const kCapabilitySlugOrder = <String>[
  'transport',
  'storage',
  'pickup_delivery',
  'tools',
  'physical_help',
  'calls',
  'translation',
  'writing',
  'negotiation',
  'introductions',
  'local_knowledge',
  'legal_navigation',
  'medical_navigation',
  'documents',
  'verification',
  'pets',
  'childcare',
  'eldercare',
  'emotional_support',
  'hosting',
  'money',
  'food',
  'housing',
  'equipment',
  'workspace',
  'tech_help',
  'repair',
  'manual_work',
  'software',
  'design',
  'admin_paperwork',
  'time',
  'contact',
  'orders',
  'gig',
  'job',
  'other',
];

final kCapabilitySlugRank = <String, int>{
  for (var i = 0; i < kCapabilitySlugOrder.length; i++)
    kCapabilitySlugOrder[i]: i,
};

/// Lowest-rank slug among [slugs], or null when none are canonical.
String? canonicalFirstCapabilitySlug(Iterable<String> slugs) {
  String? result;
  var rank = kCapabilitySlugOrder.length;
  for (final slug in slugs) {
    final candidate = kCapabilitySlugRank[slug];
    if (candidate != null && candidate < rank) {
      rank = candidate;
      result = slug;
    }
  }
  return result;
}
