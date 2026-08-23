import 'package:flutter/material.dart';

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
  medicalNavigation(
    slug: 'medical_navigation',
    group: CapabilityGroup.knowledge,
  ),
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
  manualWork(slug: 'manual_work', group: CapabilityGroup.technical),
  software(slug: 'software', group: CapabilityGroup.technical),
  design(slug: 'design', group: CapabilityGroup.technical),
  adminPaperwork(slug: 'admin_paperwork', group: CapabilityGroup.technical),

  // Special / legacy aliases
  time(slug: 'time', group: CapabilityGroup.resources),
  contact(slug: 'contact', group: CapabilityGroup.communication),
  orders(slug: 'orders', group: CapabilityGroup.special),
  gig(slug: 'gig', group: CapabilityGroup.special),
  job(slug: 'job', group: CapabilityGroup.special),
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
    CapabilityTag.orders => Icons.shopping_cart_rounded,
    CapabilityTag.gig => Icons.timelapse_rounded,
    CapabilityTag.job => Icons.work_rounded,
    CapabilityTag.food => Icons.restaurant_rounded,
    CapabilityTag.housing => Icons.apartment_rounded,
    CapabilityTag.equipment => Icons.inventory_2_rounded,
    CapabilityTag.workspace => Icons.desk_rounded,
    CapabilityTag.techHelp => Icons.support_rounded,
    CapabilityTag.repair => Icons.handyman_rounded,
    CapabilityTag.manualWork => Icons.construction_rounded,
    CapabilityTag.software => Icons.code_rounded,
    CapabilityTag.design => Icons.design_services_rounded,
    CapabilityTag.adminPaperwork => Icons.admin_panel_settings_rounded,
    CapabilityTag.time => Icons.schedule_rounded,
    CapabilityTag.contact => Icons.contact_page_rounded,
    CapabilityTag.other => Icons.more_horiz_rounded,
  };
}
