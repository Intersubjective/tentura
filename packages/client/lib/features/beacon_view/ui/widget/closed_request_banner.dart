import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Persistent, non-dismissible banner when a request is closed (status 6).
class ClosedRequestBanner extends StatelessWidget {
  const ClosedRequestBanner({
    required this.beacon,
    super.key,
  });

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    if (beacon.status != BeaconStatus.closed) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: TenturaSpacing.cardGap),
      child: Material(
        color: scheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TenturaSpacing.screenH,
            vertical: TenturaSpacing.cardGap,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
              const SizedBox(width: TenturaSpacing.cardGap),
              Expanded(
                child: Text(
                  l10n.requestClosedBannerMessage,
                  style: TenturaText.bodyMedium(scheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
