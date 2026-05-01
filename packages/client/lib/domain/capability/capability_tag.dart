import 'capability_group.dart';

enum CapabilityTag {
  // Logistics
  transport(slug: 'transport', group: CapabilityGroup.logistics, isCommitRoleEligible: true),
  storage(slug: 'storage', group: CapabilityGroup.logistics),
  pickupDelivery(slug: 'pickup_delivery', group: CapabilityGroup.logistics),
  tools(slug: 'tools', group: CapabilityGroup.logistics, isCommitRoleEligible: true),
  physicalHelp(slug: 'physical_help', group: CapabilityGroup.logistics, isCommitRoleEligible: true),

  // Communication
  calls(slug: 'calls', group: CapabilityGroup.communication),
  translation(slug: 'translation', group: CapabilityGroup.communication),
  writing(slug: 'writing', group: CapabilityGroup.communication),
  negotiation(slug: 'negotiation', group: CapabilityGroup.communication),
  introductions(slug: 'introductions', group: CapabilityGroup.communication, isCommitRoleEligible: true),

  // Knowledge
  localKnowledge(slug: 'local_knowledge', group: CapabilityGroup.knowledge),
  legalNavigation(slug: 'legal_navigation', group: CapabilityGroup.knowledge),
  medicalNavigation(slug: 'medical_navigation', group: CapabilityGroup.knowledge),
  documents(slug: 'documents', group: CapabilityGroup.knowledge, isCommitRoleEligible: true),
  verification(slug: 'verification', group: CapabilityGroup.knowledge, isCommitRoleEligible: true),

  // Care
  pets(slug: 'pets', group: CapabilityGroup.care),
  childcare(slug: 'childcare', group: CapabilityGroup.care),
  eldercare(slug: 'eldercare', group: CapabilityGroup.care),
  emotionalSupport(slug: 'emotional_support', group: CapabilityGroup.care),
  hosting(slug: 'hosting', group: CapabilityGroup.care),

  // Resources
  money(slug: 'money', group: CapabilityGroup.resources, isCommitRoleEligible: true),
  food(slug: 'food', group: CapabilityGroup.resources),
  housing(slug: 'housing', group: CapabilityGroup.resources, isCommitRoleEligible: true),
  equipment(slug: 'equipment', group: CapabilityGroup.resources),
  workspace(slug: 'workspace', group: CapabilityGroup.resources, isCommitRoleEligible: true),

  // Technical
  techHelp(slug: 'tech_help', group: CapabilityGroup.technical),
  repair(slug: 'repair', group: CapabilityGroup.technical),
  software(slug: 'software', group: CapabilityGroup.technical),
  design(slug: 'design', group: CapabilityGroup.technical),
  adminPaperwork(slug: 'admin_paperwork', group: CapabilityGroup.technical),

  // Special / legacy aliases
  time(slug: 'time', group: CapabilityGroup.resources, isCommitRoleEligible: true),
  contact(slug: 'contact', group: CapabilityGroup.communication, isCommitRoleEligible: true),
  other(slug: 'other', group: CapabilityGroup.special, isCommitRoleEligible: true);

  const CapabilityTag({
    required this.slug,
    required this.group,
    this.isCommitRoleEligible = false,
  });

  final String slug;
  final CapabilityGroup group;
  final bool isCommitRoleEligible;

  static final _bySlug = {
    for (final t in values) t.slug: t,
  };

  static CapabilityTag? fromSlug(String slug) => _bySlug[slug];
}
