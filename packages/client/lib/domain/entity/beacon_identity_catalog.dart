import 'package:flutter/material.dart';

/// Grouping for icon picker (English keys; UI may localize labels).
enum BeaconIdentityCategory {
  general,
  work,
  places,
  transport,
  people,
  health,
  commerce,
  nature,
}

/// One curated beacon symbol (Material icon, stable across platforms).
/// Map key in [kBeaconIdentityIcons] is the persisted `icon_code`.
@immutable
class BeaconIconDefinition {
  const BeaconIconDefinition({
    required this.icon,
    required this.category,
  });

  final IconData icon;
  final BeaconIdentityCategory category;
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

/// Curated operational symbols (keys persisted on `beacon.icon_code`).
const Map<String, BeaconIconDefinition> kBeaconIdentityIcons = {
  'alert': BeaconIconDefinition(
    icon: Icons.warning_amber_rounded,
    category: BeaconIdentityCategory.general,
  ),
  'assignment': BeaconIconDefinition(
    icon: Icons.assignment_outlined,
    category: BeaconIdentityCategory.work,
  ),
  'bolt': BeaconIconDefinition(
    icon: Icons.bolt_outlined,
    category: BeaconIdentityCategory.general,
  ),
  'bug': BeaconIconDefinition(
    icon: Icons.bug_report_outlined,
    category: BeaconIdentityCategory.work,
  ),
  'build': BeaconIconDefinition(
    icon: Icons.build_circle_outlined,
    category: BeaconIdentityCategory.work,
  ),
  'business': BeaconIconDefinition(
    icon: Icons.business_center_outlined,
    category: BeaconIdentityCategory.commerce,
  ),
  'calendar': BeaconIconDefinition(
    icon: Icons.event_outlined,
    category: BeaconIdentityCategory.general,
  ),
  'car': BeaconIconDefinition(
    icon: Icons.directions_car_outlined,
    category: BeaconIdentityCategory.transport,
  ),
  'cart': BeaconIconDefinition(
    icon: Icons.shopping_cart_outlined,
    category: BeaconIdentityCategory.commerce,
  ),
  'chat': BeaconIconDefinition(
    icon: Icons.forum_outlined,
    category: BeaconIdentityCategory.people,
  ),
  'checklist': BeaconIconDefinition(
    icon: Icons.checklist_rtl,
    category: BeaconIdentityCategory.work,
  ),
  'code': BeaconIconDefinition(
    icon: Icons.code_outlined,
    category: BeaconIdentityCategory.work,
  ),
  'credit': BeaconIconDefinition(
    icon: Icons.payments_outlined,
    category: BeaconIdentityCategory.commerce,
  ),
  'delivery': BeaconIconDefinition(
    icon: Icons.local_shipping_outlined,
    category: BeaconIdentityCategory.transport,
  ),
  'document': BeaconIconDefinition(
    icon: Icons.description_outlined,
    category: BeaconIdentityCategory.work,
  ),
  'education': BeaconIconDefinition(
    icon: Icons.school_outlined,
    category: BeaconIdentityCategory.work,
  ),
  'email': BeaconIconDefinition(
    icon: Icons.mail_outline,
    category: BeaconIdentityCategory.work,
  ),
  'event': BeaconIconDefinition(
    icon: Icons.celebration_outlined,
    category: BeaconIdentityCategory.general,
  ),
  'flag': BeaconIconDefinition(
    icon: Icons.flag_outlined,
    category: BeaconIdentityCategory.general,
  ),
  'flight': BeaconIconDefinition(
    icon: Icons.flight_outlined,
    category: BeaconIdentityCategory.transport,
  ),
  'folder': BeaconIconDefinition(
    icon: Icons.folder_outlined,
    category: BeaconIdentityCategory.work,
  ),
  'food': BeaconIconDefinition(
    icon: Icons.restaurant_outlined,
    category: BeaconIdentityCategory.commerce,
  ),
  'group': BeaconIconDefinition(
    icon: Icons.groups_2_outlined,
    category: BeaconIdentityCategory.people,
  ),
  'handshake': BeaconIconDefinition(
    icon: Icons.handshake_outlined,
    category: BeaconIdentityCategory.people,
  ),
  'heart': BeaconIconDefinition(
    icon: Icons.favorite_border,
    category: BeaconIdentityCategory.general,
  ),
  'home': BeaconIconDefinition(
    icon: Icons.home_work_outlined,
    category: BeaconIdentityCategory.places,
  ),
  'hospital': BeaconIconDefinition(
    icon: Icons.local_hospital_outlined,
    category: BeaconIdentityCategory.health,
  ),
  'inventory': BeaconIconDefinition(
    icon: Icons.inventory_2_outlined,
    category: BeaconIdentityCategory.commerce,
  ),
  'key': BeaconIconDefinition(
    icon: Icons.vpn_key_outlined,
    category: BeaconIdentityCategory.general,
  ),
  'lightbulb': BeaconIconDefinition(
    icon: Icons.lightbulb_outline,
    category: BeaconIdentityCategory.general,
  ),
  'location': BeaconIconDefinition(
    icon: Icons.location_on_outlined,
    category: BeaconIdentityCategory.places,
  ),
  'lock': BeaconIconDefinition(
    icon: Icons.lock_outline,
    category: BeaconIdentityCategory.general,
  ),
  'map': BeaconIconDefinition(
    icon: Icons.map_outlined,
    category: BeaconIdentityCategory.places,
  ),
  'medical': BeaconIconDefinition(
    icon: Icons.medical_services_outlined,
    category: BeaconIdentityCategory.health,
  ),
  'person': BeaconIconDefinition(
    icon: Icons.person_outline,
    category: BeaconIdentityCategory.people,
  ),
  'phone': BeaconIconDefinition(
    icon: Icons.phone_outlined,
    category: BeaconIdentityCategory.general,
  ),
  'plant': BeaconIconDefinition(
    icon: Icons.eco_outlined,
    category: BeaconIdentityCategory.nature,
  ),
  'schedule': BeaconIconDefinition(
    icon: Icons.schedule_outlined,
    category: BeaconIdentityCategory.general,
  ),
  'science': BeaconIconDefinition(
    icon: Icons.science_outlined,
    category: BeaconIdentityCategory.health,
  ),
  'security': BeaconIconDefinition(
    icon: Icons.security_outlined,
    category: BeaconIdentityCategory.general,
  ),
  'shield': BeaconIconDefinition(
    icon: Icons.shield_outlined,
    category: BeaconIdentityCategory.general,
  ),
  'support': BeaconIconDefinition(
    icon: Icons.support_agent_outlined,
    category: BeaconIdentityCategory.people,
  ),
  'toolbox': BeaconIconDefinition(
    icon: Icons.home_repair_service_outlined,
    category: BeaconIdentityCategory.work,
  ),
  'train': BeaconIconDefinition(
    icon: Icons.train_outlined,
    category: BeaconIdentityCategory.transport,
  ),
  'tree': BeaconIconDefinition(
    icon: Icons.park_outlined,
    category: BeaconIdentityCategory.nature,
  ),
  'water': BeaconIconDefinition(
    icon: Icons.water_drop_outlined,
    category: BeaconIdentityCategory.nature,
  ),
  'anchor': BeaconIconDefinition(
    icon: Icons.anchor_outlined,
    category: BeaconIdentityCategory.general,
  ),
  'bike': BeaconIconDefinition(
    icon: Icons.pedal_bike_outlined,
    category: BeaconIdentityCategory.transport,
  ),
  'coffee': BeaconIconDefinition(
    icon: Icons.local_cafe_outlined,
    category: BeaconIdentityCategory.commerce,
  ),
  'factory': BeaconIconDefinition(
    icon: Icons.factory_outlined,
    category: BeaconIdentityCategory.places,
  ),
  'gavel': BeaconIconDefinition(
    icon: Icons.gavel_outlined,
    category: BeaconIdentityCategory.general,
  ),
  'pets': BeaconIconDefinition(
    icon: Icons.pets_outlined,
    category: BeaconIdentityCategory.nature,
  ),
  'warehouse': BeaconIconDefinition(
    icon: Icons.warehouse_outlined,
    category: BeaconIdentityCategory.places,
  ),
  'work': BeaconIconDefinition(
    icon: Icons.work_outline,
    category: BeaconIdentityCategory.work,
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
