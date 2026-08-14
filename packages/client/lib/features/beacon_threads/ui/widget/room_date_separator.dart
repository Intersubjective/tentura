import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tentura/design_system/tentura_tokens.dart';
import 'package:tentura/ui/l10n/l10n.dart';

bool roomMessageSameLocalDay(DateTime a, DateTime b) {
  final la = a.toLocal();
  final lb = b.toLocal();
  return la.year == lb.year && la.month == lb.month && la.day == lb.day;
}

/// Telegram-style centered date pill between messages when the local day changes.
class RoomDateSeparator extends StatelessWidget {
  const RoomDateSeparator({required this.date, super.key});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt =
        theme.extension<TenturaTokens>() ??
        (theme.brightness == Brightness.dark
            ? TenturaTokens.dark
            : TenturaTokens.light);
    final scheme = theme.colorScheme;
    final locale = l10n.localeName;
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d0 = DateTime(local.year, local.month, local.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final String label;
    if (d0 == today) {
      label = l10n.beaconRoomDateToday;
    } else if (d0 == yesterday) {
      label = l10n.beaconRoomDateYesterday;
    } else if (local.year == now.year) {
      label = DateFormat.EEEE(locale).add_MMMd().format(local);
    } else {
      label = DateFormat.yMMMd(locale).format(local);
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: tt.rowGap),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tt.surface,
            borderRadius: BorderRadius.circular(tt.cardRadius),
            border: Border.all(color: tt.borderSubtle),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tt.sectionGap,
              vertical: tt.iconTextGap,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
