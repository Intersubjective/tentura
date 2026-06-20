import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';

/// Icon + label for finished-but-unarchived My Work cards (never color-only).
class MyWorkFinishedStatusRow extends StatelessWidget {
  const MyWorkFinishedStatusRow({required this.beacon, super.key});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final cancelled = beacon.lifecycle == BeaconLifecycle.cancelled;
    final label = cancelled
        ? l10n.myWorkFinishedStatusCancelled
        : l10n.myWorkFinishedStatusClosed;
    final icon = cancelled ? Icons.cancel_outlined : Icons.check_circle_outline;
    final baseStyle = beaconCardUpdatedLineTextStyle(theme);

    return BeaconCardMetaItem(
      icon: icon,
      child: Text(
        label,
        style: baseStyle.copyWith(color: tt.textMuted),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// One-time inline hint above the first finished card section.
class MyWorkFinishedArchiveHint extends StatelessWidget {
  const MyWorkFinishedArchiveHint({
    required this.onDismiss,
    super.key,
  });

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;

    return Padding(
      padding: EdgeInsets.only(bottom: kSpacingSmall),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  l10n.myWorkFinishedHint,
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
              ),
              IconButton(
                tooltip: l10n.beaconViewBannerDismiss,
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 20),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
