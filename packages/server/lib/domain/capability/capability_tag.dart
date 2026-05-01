/// Allowed capability tag slugs.  Validated server-side for every write.
const kAllowedCapabilitySlugs = {
  // Logistics
  'transport',
  'storage',
  'pickup_delivery',
  'tools',
  'physical_help',
  // Communication
  'calls',
  'translation',
  'writing',
  'negotiation',
  'introductions',
  // Knowledge
  'local_knowledge',
  'legal_navigation',
  'medical_navigation',
  'documents',
  'verification',
  // Care
  'pets',
  'childcare',
  'eldercare',
  'emotional_support',
  'hosting',
  // Resources
  'money',
  'food',
  'housing',
  'equipment',
  'workspace',
  // Technical
  'tech_help',
  'repair',
  'software',
  'design',
  'admin_paperwork',
  // Special / legacy aliases
  'time',
  'contact',
  'other',
};
