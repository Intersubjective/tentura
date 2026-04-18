import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/inbox_item.dart';

/// Quiet text-only meta strip (mid-dot separated).
class InboxCardMetaChips extends StatelessWidget {
  const InboxCardMetaChips({
    required this.beacon,
    required this.item,
    super.key,
  });

  final Beacon beacon;
  final InboxItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.labelSmall!.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final sepStyle = style.copyWith(
      color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
    );

    final category = beacon.context.trim().isEmpty
        ? l10n.inboxCategoryGeneral
        : beacon.context.trim();

    final segments = <String>[category];
    if (beacon.commitmentCount > 0) {
      segments.add(l10n.inboxCommitmentsCount(beacon.commitmentCount));
    }
    if (item.forwardCount > 1) {
      segments.add(l10n.inboxForwardCount(item.forwardCount));
    }

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) TextSpan(text: ' · ', style: sepStyle),
            TextSpan(text: segments[i]),
          ],
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
