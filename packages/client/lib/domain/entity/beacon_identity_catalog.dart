import 'package:flutter/material.dart';

/// Ontology domain for icon picker (single level; no nested sub-catalog).
/// Order: coordination-heavy domains first (see docs/beacon-icons-fluttericonpicker.md).
enum BeaconIdentityCategory {
  meta,
  community,
  essentials,
  home,
  mobility,
  communication,
  money,
  health,
  safety,
  work,
  tech,
  nature,
  weather,
  culture,
  education,
  animals,
  civic,
}

/// One curated beacon symbol (Material Rounded icon, stable across platforms).
/// Map key in [kBeaconIdentityIcons] is the persisted `icon_code`.
/// [label] is the human-readable ontology leaf (picker UI only).
@immutable
class BeaconIconDefinition {
  const BeaconIconDefinition({
    required this.icon,
    required this.category,
    required this.label,
  });

  final IconData icon;
  final BeaconIdentityCategory category;
  final String label;
}

/// Background + guaranteed foreground for icons on the tile.
@immutable
class BeaconPaletteSwatch {
  const BeaconPaletteSwatch({
    required this.backgroundArgb,
    required this.foregroundArgb,
  });

  final int backgroundArgb;
  final int foregroundArgb;

  Color get background => Color(backgroundArgb);
  Color get foreground => Color(foregroundArgb);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BeaconPaletteSwatch &&
          other.backgroundArgb == backgroundArgb &&
          other.foregroundArgb == foregroundArgb;

  @override
  int get hashCode => Object.hash(backgroundArgb, foregroundArgb);
}

/// Flutter [Color] uses unsigned 32-bit ARGB; GraphQL `Int` and Postgres
/// `INTEGER` are signed 32-bit. Reinterpret the same bit pattern so opaque
/// colors (`0xFF……`) do not overflow on the wire.
int encodeBeaconIconBackgroundArgb(int argb) => argb.toSigned(32);

int? decodeBeaconIconBackgroundArgb(int? signed) => signed?.toUnsigned(32);

/// Curated ontology leaves (keys persisted on `beacon.icon_code`).
/// From [docs/beacon-ontology-icon-mapping.md]; `essentials_water` / `nature_water`
/// disambiguate duplicate "Water" leaves.
const Map<String, BeaconIconDefinition> kBeaconIdentityIcons = {
  // Meta
  'announcement': BeaconIconDefinition(
    icon: Icons.campaign_rounded,
    category: BeaconIdentityCategory.meta,
    label: 'Announcement',
  ),
  'discussion': BeaconIconDefinition(
    icon: Icons.forum_rounded,
    category: BeaconIdentityCategory.meta,
    label: 'Discussion',
  ),
  'event': BeaconIconDefinition(
    icon: Icons.event_rounded,
    category: BeaconIdentityCategory.meta,
    label: 'Event',
  ),
  'information': BeaconIconDefinition(
    icon: Icons.info_rounded,
    category: BeaconIdentityCategory.meta,
    label: 'Information',
  ),
  'location': BeaconIconDefinition(
    icon: Icons.place_rounded,
    category: BeaconIdentityCategory.meta,
    label: 'Location',
  ),
  'question': BeaconIconDefinition(
    icon: Icons.help_rounded,
    category: BeaconIdentityCategory.meta,
    label: 'Question',
  ),
  'report_issue': BeaconIconDefinition(
    icon: Icons.report_rounded,
    category: BeaconIdentityCategory.meta,
    label: 'Report issue',
  ),
  'schedule': BeaconIconDefinition(
    icon: Icons.schedule_rounded,
    category: BeaconIdentityCategory.meta,
    label: 'Schedule',
  ),
  'task': BeaconIconDefinition(
    icon: Icons.task_alt_rounded,
    category: BeaconIdentityCategory.meta,
    label: 'Task',
  ),
  'urgent_alert': BeaconIconDefinition(
    icon: Icons.warning_rounded,
    category: BeaconIdentityCategory.meta,
    label: 'Urgent alert',
  ),

  // Community
  'accessibility': BeaconIconDefinition(
    icon: Icons.accessible_rounded,
    category: BeaconIdentityCategory.community,
    label: 'Accessibility',
  ),
  'childcare': BeaconIconDefinition(
    icon: Icons.child_care_rounded,
    category: BeaconIdentityCategory.community,
    label: 'Childcare',
  ),
  'collaboration': BeaconIconDefinition(
    icon: Icons.handshake_rounded,
    category: BeaconIdentityCategory.community,
    label: 'Collaboration',
  ),
  'eldercare': BeaconIconDefinition(
    icon: Icons.elderly_rounded,
    category: BeaconIdentityCategory.community,
    label: 'Eldercare',
  ),
  'family': BeaconIconDefinition(
    icon: Icons.family_restroom_rounded,
    category: BeaconIdentityCategory.community,
    label: 'Family',
  ),
  'group': BeaconIconDefinition(
    icon: Icons.groups_rounded,
    category: BeaconIdentityCategory.community,
    label: 'Group',
  ),
  'inclusivity': BeaconIconDefinition(
    icon: Icons.diversity_3_rounded,
    category: BeaconIdentityCategory.community,
    label: 'Inclusivity',
  ),
  'individual': BeaconIconDefinition(
    icon: Icons.person_rounded,
    category: BeaconIdentityCategory.community,
    label: 'Individual',
  ),
  'support_services': BeaconIconDefinition(
    icon: Icons.support_agent_rounded,
    category: BeaconIdentityCategory.community,
    label: 'Support services',
  ),
  'volunteer': BeaconIconDefinition(
    icon: Icons.volunteer_activism_rounded,
    category: BeaconIdentityCategory.community,
    label: 'Volunteer',
  ),

  // Essentials
  'clothing': BeaconIconDefinition(
    icon: Icons.checkroom_rounded,
    category: BeaconIdentityCategory.essentials,
    label: 'Clothing',
  ),
  'coffee': BeaconIconDefinition(
    icon: Icons.local_cafe_rounded,
    category: BeaconIdentityCategory.essentials,
    label: 'Coffee',
  ),
  'donation_goods': BeaconIconDefinition(
    icon: Icons.redeem_rounded,
    category: BeaconIdentityCategory.essentials,
    label: 'Donation goods',
  ),
  'food_aid': BeaconIconDefinition(
    icon: Icons.soup_kitchen_rounded,
    category: BeaconIdentityCategory.essentials,
    label: 'Food aid',
  ),
  'groceries': BeaconIconDefinition(
    icon: Icons.local_grocery_store_rounded,
    category: BeaconIdentityCategory.essentials,
    label: 'Groceries',
  ),
  'meals': BeaconIconDefinition(
    icon: Icons.restaurant_rounded,
    category: BeaconIdentityCategory.essentials,
    label: 'Meals',
  ),
  'shopping': BeaconIconDefinition(
    icon: Icons.shopping_cart_rounded,
    category: BeaconIdentityCategory.essentials,
    label: 'Shopping',
  ),
  'essentials_water': BeaconIconDefinition(
    icon: Icons.water_drop_rounded,
    category: BeaconIdentityCategory.essentials,
    label: 'Water',
  ),

  // Home
  'cleaning': BeaconIconDefinition(
    icon: Icons.cleaning_services_rounded,
    category: BeaconIdentityCategory.home,
    label: 'Cleaning',
  ),
  'climate_control': BeaconIconDefinition(
    icon: Icons.thermostat_rounded,
    category: BeaconIdentityCategory.home,
    label: 'Climate control',
  ),
  'construction': BeaconIconDefinition(
    icon: Icons.construction_rounded,
    category: BeaconIdentityCategory.home,
    label: 'Construction',
  ),
  'electrical': BeaconIconDefinition(
    icon: Icons.electrical_services_rounded,
    category: BeaconIdentityCategory.home,
    label: 'Electrical',
  ),
  'furniture': BeaconIconDefinition(
    icon: Icons.chair_rounded,
    category: BeaconIdentityCategory.home,
    label: 'Furniture',
  ),
  'housing': BeaconIconDefinition(
    icon: Icons.apartment_rounded,
    category: BeaconIdentityCategory.home,
    label: 'Housing',
  ),
  'kitchen_and_cooking': BeaconIconDefinition(
    icon: Icons.kitchen_rounded,
    category: BeaconIdentityCategory.home,
    label: 'Kitchen and cooking',
  ),
  'laundry': BeaconIconDefinition(
    icon: Icons.local_laundry_service_rounded,
    category: BeaconIdentityCategory.home,
    label: 'Laundry',
  ),
  'painting': BeaconIconDefinition(
    icon: Icons.format_paint_rounded,
    category: BeaconIdentityCategory.home,
    label: 'Painting',
  ),
  'plumbing': BeaconIconDefinition(
    icon: Icons.plumbing_rounded,
    category: BeaconIdentityCategory.home,
    label: 'Plumbing',
  ),
  'property_listing': BeaconIconDefinition(
    icon: Icons.real_estate_agent_rounded,
    category: BeaconIdentityCategory.home,
    label: 'Property listing',
  ),
  'repairs': BeaconIconDefinition(
    icon: Icons.home_repair_service_rounded,
    category: BeaconIdentityCategory.home,
    label: 'Repairs',
  ),
  'water_damage': BeaconIconDefinition(
    icon: Icons.water_damage_rounded,
    category: BeaconIdentityCategory.home,
    label: 'Water damage',
  ),

  // Mobility
  'bike': BeaconIconDefinition(
    icon: Icons.directions_bike_rounded,
    category: BeaconIdentityCategory.mobility,
    label: 'Bike',
  ),
  'car': BeaconIconDefinition(
    icon: Icons.directions_car_rounded,
    category: BeaconIdentityCategory.mobility,
    label: 'Car',
  ),
  'delivery': BeaconIconDefinition(
    icon: Icons.local_shipping_rounded,
    category: BeaconIdentityCategory.mobility,
    label: 'Delivery',
  ),
  'food_delivery': BeaconIconDefinition(
    icon: Icons.delivery_dining_rounded,
    category: BeaconIdentityCategory.mobility,
    label: 'Food delivery',
  ),
  'map': BeaconIconDefinition(
    icon: Icons.map_rounded,
    category: BeaconIdentityCategory.mobility,
    label: 'Map',
  ),
  'moving_help': BeaconIconDefinition(
    icon: Icons.moving_rounded,
    category: BeaconIdentityCategory.mobility,
    label: 'Moving help',
  ),
  'parking': BeaconIconDefinition(
    icon: Icons.local_parking_rounded,
    category: BeaconIdentityCategory.mobility,
    label: 'Parking',
  ),
  'public_transit': BeaconIconDefinition(
    icon: Icons.directions_bus_rounded,
    category: BeaconIdentityCategory.mobility,
    label: 'Public transit',
  ),
  'walking': BeaconIconDefinition(
    icon: Icons.directions_walk_rounded,
    category: BeaconIdentityCategory.mobility,
    label: 'Walking',
  ),

  // Communication
  'link': BeaconIconDefinition(
    icon: Icons.link_rounded,
    category: BeaconIdentityCategory.communication,
    label: 'Link',
  ),
  'phone_call': BeaconIconDefinition(
    icon: Icons.call_rounded,
    category: BeaconIdentityCategory.communication,
    label: 'Phone call',
  ),
  'send': BeaconIconDefinition(
    icon: Icons.send_rounded,
    category: BeaconIdentityCategory.communication,
    label: 'Send',
  ),
  'share': BeaconIconDefinition(
    icon: Icons.share_rounded,
    category: BeaconIdentityCategory.communication,
    label: 'Share',
  ),
  'text_message': BeaconIconDefinition(
    icon: Icons.sms_rounded,
    category: BeaconIdentityCategory.communication,
    label: 'Text message',
  ),

  // Money
  'cash': BeaconIconDefinition(
    icon: Icons.attach_money_rounded,
    category: BeaconIdentityCategory.money,
    label: 'Cash',
  ),
  'marketplace': BeaconIconDefinition(
    icon: Icons.storefront_rounded,
    category: BeaconIdentityCategory.money,
    label: 'Marketplace',
  ),
  'payment': BeaconIconDefinition(
    icon: Icons.payments_rounded,
    category: BeaconIdentityCategory.money,
    label: 'Payment',
  ),
  'receipt': BeaconIconDefinition(
    icon: Icons.receipt_long_rounded,
    category: BeaconIdentityCategory.money,
    label: 'Receipt',
  ),
  'savings': BeaconIconDefinition(
    icon: Icons.savings_rounded,
    category: BeaconIdentityCategory.money,
    label: 'Savings',
  ),

  // Health
  'hospital': BeaconIconDefinition(
    icon: Icons.local_hospital_rounded,
    category: BeaconIdentityCategory.health,
    label: 'Hospital',
  ),
  'medical_services': BeaconIconDefinition(
    icon: Icons.medical_services_rounded,
    category: BeaconIdentityCategory.health,
    label: 'Medical services',
  ),
  'mental_health': BeaconIconDefinition(
    icon: Icons.psychology_rounded,
    category: BeaconIdentityCategory.health,
    label: 'Mental health',
  ),
  'pharmacy': BeaconIconDefinition(
    icon: Icons.local_pharmacy_rounded,
    category: BeaconIdentityCategory.health,
    label: 'Pharmacy',
  ),
  'wellness': BeaconIconDefinition(
    icon: Icons.self_improvement_rounded,
    category: BeaconIdentityCategory.health,
    label: 'Wellness',
  ),

  // Safety
  'crisis': BeaconIconDefinition(
    icon: Icons.crisis_alert_rounded,
    category: BeaconIdentityCategory.safety,
    label: 'Crisis',
  ),
  'emergency': BeaconIconDefinition(
    icon: Icons.emergency_rounded,
    category: BeaconIdentityCategory.safety,
    label: 'Emergency',
  ),
  'emergency_contacts': BeaconIconDefinition(
    icon: Icons.emergency_share_rounded,
    category: BeaconIdentityCategory.safety,
    label: 'Emergency contacts',
  ),
  'fire': BeaconIconDefinition(
    icon: Icons.local_fire_department_rounded,
    category: BeaconIdentityCategory.safety,
    label: 'Fire',
  ),
  'general_safety': BeaconIconDefinition(
    icon: Icons.health_and_safety_rounded,
    category: BeaconIdentityCategory.safety,
    label: 'General safety',
  ),
  'police': BeaconIconDefinition(
    icon: Icons.local_police_rounded,
    category: BeaconIdentityCategory.safety,
    label: 'Police',
  ),
  'security': BeaconIconDefinition(
    icon: Icons.security_rounded,
    category: BeaconIdentityCategory.safety,
    label: 'Security',
  ),

  // Work
  'design': BeaconIconDefinition(
    icon: Icons.design_services_rounded,
    category: BeaconIdentityCategory.work,
    label: 'Design',
  ),
  'engineering': BeaconIconDefinition(
    icon: Icons.engineering_rounded,
    category: BeaconIdentityCategory.work,
    label: 'Engineering',
  ),
  'hiring': BeaconIconDefinition(
    icon: Icons.person_search_rounded,
    category: BeaconIdentityCategory.work,
    label: 'Hiring',
  ),
  'idea': BeaconIconDefinition(
    icon: Icons.lightbulb_rounded,
    category: BeaconIdentityCategory.work,
    label: 'Idea',
  ),
  'job': BeaconIconDefinition(
    icon: Icons.work_rounded,
    category: BeaconIdentityCategory.work,
    label: 'Job',
  ),
  'tools': BeaconIconDefinition(
    icon: Icons.build_rounded,
    category: BeaconIdentityCategory.work,
    label: 'Tools',
  ),

  // Tech
  'bug': BeaconIconDefinition(
    icon: Icons.bug_report_rounded,
    category: BeaconIdentityCategory.tech,
    label: 'Bug',
  ),
  'cloud': BeaconIconDefinition(
    icon: Icons.cloud_rounded,
    category: BeaconIdentityCategory.tech,
    label: 'Cloud',
  ),
  'coding': BeaconIconDefinition(
    icon: Icons.code_rounded,
    category: BeaconIdentityCategory.tech,
    label: 'Coding',
  ),
  'computer': BeaconIconDefinition(
    icon: Icons.computer_rounded,
    category: BeaconIdentityCategory.tech,
    label: 'Computer',
  ),
  'internet': BeaconIconDefinition(
    icon: Icons.wifi_rounded,
    category: BeaconIdentityCategory.tech,
    label: 'Internet',
  ),
  'phone': BeaconIconDefinition(
    icon: Icons.smartphone_rounded,
    category: BeaconIdentityCategory.tech,
    label: 'Phone',
  ),
  'settings': BeaconIconDefinition(
    icon: Icons.settings_rounded,
    category: BeaconIdentityCategory.tech,
    label: 'Settings',
  ),

  // Nature
  'agriculture': BeaconIconDefinition(
    icon: Icons.agriculture_rounded,
    category: BeaconIdentityCategory.nature,
    label: 'Agriculture',
  ),
  'air_quality': BeaconIconDefinition(
    icon: Icons.air_rounded,
    category: BeaconIdentityCategory.nature,
    label: 'Air quality',
  ),
  'beach': BeaconIconDefinition(
    icon: Icons.beach_access_rounded,
    category: BeaconIdentityCategory.nature,
    label: 'Beach',
  ),
  'compost': BeaconIconDefinition(
    icon: Icons.compost_rounded,
    category: BeaconIdentityCategory.nature,
    label: 'Compost',
  ),
  'environment': BeaconIconDefinition(
    icon: Icons.eco_rounded,
    category: BeaconIdentityCategory.nature,
    label: 'Environment',
  ),
  'forest': BeaconIconDefinition(
    icon: Icons.forest_rounded,
    category: BeaconIdentityCategory.nature,
    label: 'Forest',
  ),
  'gardening': BeaconIconDefinition(
    icon: Icons.yard_rounded,
    category: BeaconIdentityCategory.nature,
    label: 'Gardening',
  ),
  'mountains': BeaconIconDefinition(
    icon: Icons.terrain_rounded,
    category: BeaconIdentityCategory.nature,
    label: 'Mountains',
  ),
  'park': BeaconIconDefinition(
    icon: Icons.park_rounded,
    category: BeaconIdentityCategory.nature,
    label: 'Park',
  ),
  'recycling': BeaconIconDefinition(
    icon: Icons.recycling_rounded,
    category: BeaconIdentityCategory.nature,
    label: 'Recycling',
  ),
  'nature_water': BeaconIconDefinition(
    icon: Icons.water_rounded,
    category: BeaconIdentityCategory.nature,
    label: 'Water',
  ),

  // Weather
  'cloudy': BeaconIconDefinition(
    icon: Icons.wb_cloudy_rounded,
    category: BeaconIdentityCategory.weather,
    label: 'Cloudy',
  ),
  'storm': BeaconIconDefinition(
    icon: Icons.thunderstorm_rounded,
    category: BeaconIdentityCategory.weather,
    label: 'Storm',
  ),
  'sunny': BeaconIconDefinition(
    icon: Icons.wb_sunny_rounded,
    category: BeaconIdentityCategory.weather,
    label: 'Sunny',
  ),

  // Culture
  'art': BeaconIconDefinition(
    icon: Icons.palette_rounded,
    category: BeaconIdentityCategory.culture,
    label: 'Art',
  ),
  'celebration': BeaconIconDefinition(
    icon: Icons.celebration_rounded,
    category: BeaconIdentityCategory.culture,
    label: 'Celebration',
  ),
  'museum': BeaconIconDefinition(
    icon: Icons.museum_rounded,
    category: BeaconIdentityCategory.culture,
    label: 'Museum',
  ),
  'music': BeaconIconDefinition(
    icon: Icons.music_note_rounded,
    category: BeaconIdentityCategory.culture,
    label: 'Music',
  ),
  'sports': BeaconIconDefinition(
    icon: Icons.sports_soccer_rounded,
    category: BeaconIdentityCategory.culture,
    label: 'Sports',
  ),
  'theater': BeaconIconDefinition(
    icon: Icons.theater_comedy_rounded,
    category: BeaconIdentityCategory.culture,
    label: 'Theater',
  ),
  'worship': BeaconIconDefinition(
    icon: Icons.church_rounded,
    category: BeaconIdentityCategory.culture,
    label: 'Worship',
  ),

  // Education
  'books': BeaconIconDefinition(
    icon: Icons.menu_book_rounded,
    category: BeaconIdentityCategory.education,
    label: 'Books',
  ),
  'language': BeaconIconDefinition(
    icon: Icons.translate_rounded,
    category: BeaconIdentityCategory.education,
    label: 'Language',
  ),
  'school': BeaconIconDefinition(
    icon: Icons.school_rounded,
    category: BeaconIdentityCategory.education,
    label: 'School',
  ),
  'workshop': BeaconIconDefinition(
    icon: Icons.cast_for_education_rounded,
    category: BeaconIdentityCategory.education,
    label: 'Workshop',
  ),

  // Animals
  'animal_welfare': BeaconIconDefinition(
    icon: Icons.cruelty_free_rounded,
    category: BeaconIdentityCategory.animals,
    label: 'Animal welfare',
  ),
  'pets_and_animals': BeaconIconDefinition(
    icon: Icons.pets_rounded,
    category: BeaconIdentityCategory.animals,
    label: 'Pets and animals',
  ),

  // Civic
  'documentation': BeaconIconDefinition(
    icon: Icons.description_rounded,
    category: BeaconIdentityCategory.civic,
    label: 'Documentation',
  ),
  'government': BeaconIconDefinition(
    icon: Icons.account_balance_rounded,
    category: BeaconIdentityCategory.civic,
    label: 'Government',
  ),
  'legal': BeaconIconDefinition(
    icon: Icons.gavel_rounded,
    category: BeaconIdentityCategory.civic,
    label: 'Legal',
  ),
  'policy': BeaconIconDefinition(
    icon: Icons.policy_rounded,
    category: BeaconIdentityCategory.civic,
    label: 'Policy',
  ),
  'verified_identity': BeaconIconDefinition(
    icon: Icons.verified_user_rounded,
    category: BeaconIdentityCategory.civic,
    label: 'Verified identity',
  ),
  'voting': BeaconIconDefinition(
    icon: Icons.how_to_vote_rounded,
    category: BeaconIdentityCategory.civic,
    label: 'Voting',
  ),
};

/// Muted, accessible palette (ARGB). Foreground chosen for contrast on each swatch.
const List<BeaconPaletteSwatch> kBeaconIdentityPalette = [
  BeaconPaletteSwatch(
    backgroundArgb: 0xFF37474F,
    foregroundArgb: 0xFFECEFF1,
  ),
  BeaconPaletteSwatch(
    backgroundArgb: 0xFF1565C0,
    foregroundArgb: 0xFFE3F2FD,
  ),
  BeaconPaletteSwatch(
    backgroundArgb: 0xFF00695C,
    foregroundArgb: 0xFFE0F2F1,
  ),
  BeaconPaletteSwatch(
    backgroundArgb: 0xFF2E7D32,
    foregroundArgb: 0xFFE8F5E9,
  ),
  BeaconPaletteSwatch(
    backgroundArgb: 0xFF6A1B9A,
    foregroundArgb: 0xFFF3E5F5,
  ),
  BeaconPaletteSwatch(
    backgroundArgb: 0xFFAD1457,
    foregroundArgb: 0xFFFCE4EC,
  ),
  BeaconPaletteSwatch(
    backgroundArgb: 0xFFC62828,
    foregroundArgb: 0xFFFFEBEE,
  ),
  BeaconPaletteSwatch(
    backgroundArgb: 0xFFEF6C00,
    foregroundArgb: 0xFFFFF3E0,
  ),
  BeaconPaletteSwatch(
    backgroundArgb: 0xFF5D4037,
    foregroundArgb: 0xFFEFEBE9,
  ),
  BeaconPaletteSwatch(
    backgroundArgb: 0xFF455A64,
    foregroundArgb: 0xFFECEFF1,
  ),
  BeaconPaletteSwatch(
    backgroundArgb: 0xFF0277BD,
    foregroundArgb: 0xFFE1F5FE,
  ),
  BeaconPaletteSwatch(
    backgroundArgb: 0xFF558B2F,
    foregroundArgb: 0xFFF1F8E9,
  ),
  BeaconPaletteSwatch(
    backgroundArgb: 0xFF4527A0,
    foregroundArgb: 0xFFEDE7F6,
  ),
  BeaconPaletteSwatch(
    backgroundArgb: 0xFF4E342E,
    foregroundArgb: 0xFFD7CCC8,
  ),
];

BeaconPaletteSwatch? paletteSwatchForArgb(int? argb) {
  if (argb == null) return null;
  for (final s in kBeaconIdentityPalette) {
    if (s.backgroundArgb == argb) return s;
  }
  return null;
}

/// Icon when persisted beacon icon code is unknown or legacy.
IconData fallbackBeaconIcon() => Icons.radio_button_checked_outlined;

/// Default palette entry when author picked icon but no background yet.
BeaconPaletteSwatch get defaultBeaconPaletteSwatch =>
    kBeaconIdentityPalette.first;
