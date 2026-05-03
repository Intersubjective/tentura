import 'package:flutter/material.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'capability_group.dart';

enum CapabilityTag {
  // Logistics
  transport(slug: 'transport', group: CapabilityGroup.logistics),
  storage(slug: 'storage', group: CapabilityGroup.logistics),
  pickupDelivery(slug: 'pickup_delivery', group: CapabilityGroup.logistics),
  tools(slug: 'tools', group: CapabilityGroup.logistics),
  physicalHelp(slug: 'physical_help', group: CapabilityGroup.logistics),

  // Communication
  calls(slug: 'calls', group: CapabilityGroup.communication),
  translation(slug: 'translation', group: CapabilityGroup.communication),
  writing(slug: 'writing', group: CapabilityGroup.communication),
  negotiation(slug: 'negotiation', group: CapabilityGroup.communication),
  introductions(slug: 'introductions', group: CapabilityGroup.communication),

  // Knowledge
  localKnowledge(slug: 'local_knowledge', group: CapabilityGroup.knowledge),
  legalNavigation(slug: 'legal_navigation', group: CapabilityGroup.knowledge),
  medicalNavigation(slug: 'medical_navigation', group: CapabilityGroup.knowledge),
  documents(slug: 'documents', group: CapabilityGroup.knowledge),
  verification(slug: 'verification', group: CapabilityGroup.knowledge),

  // Care
  pets(slug: 'pets', group: CapabilityGroup.care),
  childcare(slug: 'childcare', group: CapabilityGroup.care),
  eldercare(slug: 'eldercare', group: CapabilityGroup.care),
  emotionalSupport(slug: 'emotional_support', group: CapabilityGroup.care),
  hosting(slug: 'hosting', group: CapabilityGroup.care),

  // Resources
  money(slug: 'money', group: CapabilityGroup.resources),
  food(slug: 'food', group: CapabilityGroup.resources),
  housing(slug: 'housing', group: CapabilityGroup.resources),
  equipment(slug: 'equipment', group: CapabilityGroup.resources),
  workspace(slug: 'workspace', group: CapabilityGroup.resources),

  // Technical
  techHelp(slug: 'tech_help', group: CapabilityGroup.technical),
  repair(slug: 'repair', group: CapabilityGroup.technical),
  software(slug: 'software', group: CapabilityGroup.technical),
  design(slug: 'design', group: CapabilityGroup.technical),
  adminPaperwork(slug: 'admin_paperwork', group: CapabilityGroup.technical),

  // Special / legacy aliases
  time(slug: 'time', group: CapabilityGroup.resources),
  contact(slug: 'contact', group: CapabilityGroup.communication),
  other(slug: 'other', group: CapabilityGroup.special);

  const CapabilityTag({
    required this.slug,
    required this.group,
  });

  final String slug;
  final CapabilityGroup group;

  static final _bySlug = {
    for (final t in values) t.slug: t,
  };

  static CapabilityTag? fromSlug(String slug) => _bySlug[slug];

  String labelOf(L10n l10n) => switch (this) {
    CapabilityTag.transport => l10n.capabilityTagTransport,
    CapabilityTag.storage => l10n.capabilityTagStorage,
    CapabilityTag.pickupDelivery => l10n.capabilityTagPickupDelivery,
    CapabilityTag.tools => l10n.capabilityTagTools,
    CapabilityTag.physicalHelp => l10n.capabilityTagPhysicalHelp,
    CapabilityTag.calls => l10n.capabilityTagCalls,
    CapabilityTag.translation => l10n.capabilityTagTranslation,
    CapabilityTag.writing => l10n.capabilityTagWriting,
    CapabilityTag.negotiation => l10n.capabilityTagNegotiation,
    CapabilityTag.introductions => l10n.capabilityTagIntroductions,
    CapabilityTag.localKnowledge => l10n.capabilityTagLocalKnowledge,
    CapabilityTag.legalNavigation => l10n.capabilityTagLegalNavigation,
    CapabilityTag.medicalNavigation => l10n.capabilityTagMedicalNavigation,
    CapabilityTag.documents => l10n.capabilityTagDocuments,
    CapabilityTag.verification => l10n.capabilityTagVerification,
    CapabilityTag.pets => l10n.capabilityTagPets,
    CapabilityTag.childcare => l10n.capabilityTagChildcare,
    CapabilityTag.eldercare => l10n.capabilityTagEldercare,
    CapabilityTag.emotionalSupport => l10n.capabilityTagEmotionalSupport,
    CapabilityTag.hosting => l10n.capabilityTagHosting,
    CapabilityTag.money => l10n.capabilityTagMoney,
    CapabilityTag.food => l10n.capabilityTagFood,
    CapabilityTag.housing => l10n.capabilityTagHousing,
    CapabilityTag.equipment => l10n.capabilityTagEquipment,
    CapabilityTag.workspace => l10n.capabilityTagWorkspace,
    CapabilityTag.techHelp => l10n.capabilityTagTechHelp,
    CapabilityTag.repair => l10n.capabilityTagRepair,
    CapabilityTag.software => l10n.capabilityTagSoftware,
    CapabilityTag.design => l10n.capabilityTagDesign,
    CapabilityTag.adminPaperwork => l10n.capabilityTagAdminPaperwork,
    CapabilityTag.time => l10n.capabilityTagTime,
    CapabilityTag.contact => l10n.capabilityTagContact,
    CapabilityTag.other => l10n.capabilityTagOther,
  };

  IconData get icon => switch (this) {
    CapabilityTag.transport => Icons.directions_car_rounded,
    CapabilityTag.storage => Icons.warehouse_rounded,
    CapabilityTag.pickupDelivery => Icons.local_shipping_rounded,
    CapabilityTag.tools => Icons.build_rounded,
    CapabilityTag.physicalHelp => Icons.fitness_center_rounded,
    CapabilityTag.calls => Icons.call_rounded,
    CapabilityTag.translation => Icons.translate_rounded,
    CapabilityTag.writing => Icons.drive_file_rename_outline_rounded,
    CapabilityTag.negotiation => Icons.gavel_rounded,
    CapabilityTag.introductions => Icons.group_add_rounded,
    CapabilityTag.localKnowledge => Icons.map_rounded,
    CapabilityTag.legalNavigation => Icons.balance_rounded,
    CapabilityTag.medicalNavigation => Icons.medical_services_rounded,
    CapabilityTag.documents => Icons.description_rounded,
    CapabilityTag.verification => Icons.verified_rounded,
    CapabilityTag.pets => Icons.pets_rounded,
    CapabilityTag.childcare => Icons.child_care_rounded,
    CapabilityTag.eldercare => Icons.elderly_rounded,
    CapabilityTag.emotionalSupport => Icons.psychology_rounded,
    CapabilityTag.hosting => Icons.home_rounded,
    CapabilityTag.money => Icons.payments_rounded,
    CapabilityTag.food => Icons.restaurant_rounded,
    CapabilityTag.housing => Icons.apartment_rounded,
    CapabilityTag.equipment => Icons.inventory_2_rounded,
    CapabilityTag.workspace => Icons.desk_rounded,
    CapabilityTag.techHelp => Icons.support_rounded,
    CapabilityTag.repair => Icons.handyman_rounded,
    CapabilityTag.software => Icons.code_rounded,
    CapabilityTag.design => Icons.design_services_rounded,
    CapabilityTag.adminPaperwork => Icons.admin_panel_settings_rounded,
    CapabilityTag.time => Icons.schedule_rounded,
    CapabilityTag.contact => Icons.contact_page_rounded,
    CapabilityTag.other => Icons.more_horiz_rounded,
  };
}
