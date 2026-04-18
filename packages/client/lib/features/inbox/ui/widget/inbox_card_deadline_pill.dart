import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_card_deadline.dart';

/// Compact deadline capsule for inbox beacon header (e.g. `31d`, `4h`).
class InboxCardDeadlinePill extends StatelessWidget {
  const InboxCardDeadlinePill({
    required this.endAt,
    super.key,
  });

  final DateTime? endAt;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final meta = compactDeadlineLabel(l10n, endAt);
    if (meta == null) return const SizedBox.shrink();

    final bg = meta.urgent
        ? scheme.errorContainer
        : scheme.surfaceContainerHigh;
    final fg = meta.urgent ? scheme.onErrorContainer : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        meta.text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.1,
          color: fg,
        ),
      ),
    );
  }
}
