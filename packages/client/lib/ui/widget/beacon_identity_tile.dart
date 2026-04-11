import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_identity_catalog.dart';

final _log = Logger('BeaconIdentityTile');

/// Symbolic beacon identity: icon on colored rounded square (not a photo thumbnail).
class BeaconIdentityTile extends StatelessWidget {
  const BeaconIdentityTile({
    required this.beacon,
    this.size = 48,
    super.key,
  });

  final Beacon beacon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(size * 0.2);
    final iconSize = size * 0.52;

    final hasCustomIcon = beacon.hasIdentityTile;
    final def = hasCustomIcon ? kBeaconIdentityIcons[beacon.iconCode!] : null;
    if (hasCustomIcon && def == null) {
      _log.warning('Unknown beacon icon_code "${beacon.iconCode}"');
    }
    final icon = def?.icon ?? fallbackBeaconIcon();

    final swatch = paletteSwatchForArgb(beacon.iconBackground) ??
        (hasCustomIcon && beacon.iconBackground == null
            ? defaultBeaconPaletteSwatch
            : null);

    late final Color bg;
    late final Color fg;
    if (swatch != null) {
      bg = swatch.background;
      fg = swatch.foreground;
    } else if (beacon.iconBackground != null) {
      bg = Color(beacon.iconBackground!);
      fg = bg.computeLuminance() > 0.5
          ? Colors.black.withValues(alpha: 0.87)
          : Colors.white;
    } else {
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant;
    }

    return Semantics(
      label: beacon.title,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: iconSize,
          color: fg,
        ),
      ),
    );
  }
}
