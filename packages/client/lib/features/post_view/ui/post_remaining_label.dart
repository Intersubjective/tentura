import 'package:flutter/widgets.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

/// Countdown rounded down to whole days or hours, with at least one minute.
String postRemainingLabel(L10n l10n, Duration remaining) {
  if (remaining.inDays >= 1) return l10n.postRemainingDays(remaining.inDays);
  if (remaining.inHours >= 1) return l10n.postRemainingHours(remaining.inHours);
  return l10n.postRemainingMinutes(
    remaining.inMinutes < 1 ? 1 : remaining.inMinutes,
  );
}

/// Same duration math as [postRemainingLabel], with the hourglass shown on Post surfaces (#248).
String postRemainingVisibleLabel(L10n l10n, Duration remaining) =>
    '⏳ ${postRemainingLabel(l10n, remaining)}';

/// Lifetime line for a Post deadline at [now] (Field, list rows, map labels).
String postLifetimeLineForDeadline(
  L10n l10n, {
  required DateTime now,
  required DateTime? expiresAt,
  required bool archived,
}) {
  if (archived) return l10n.postArchivedMarker;
  final end = expiresAt;
  if (end == null) return '';
  final remaining = end.difference(now);
  if (remaining.isNegative) return l10n.postArchivedMarker;
  return postRemainingVisibleLabel(l10n, remaining);
}

/// Rebuilds while visible so an open Post's lifetime keeps counting down.
class PostLifetimeTicker extends StatelessWidget {
  const PostLifetimeTicker({
    required this.expiresAt,
    required this.archived,
    required this.builder,
    super.key,
  });

  final DateTime? expiresAt;
  final bool archived;
  final Widget Function(BuildContext context, String label) builder;

  @override
  Widget build(BuildContext context) {
    return RelativeTimestampTicker(
      builder: (context) {
        final l10n = L10n.of(context)!;
        final now = RelativeTimestampTicker.now();
        if (archived) {
          return builder(context, l10n.postArchivedMarker);
        }
        final end = expiresAt;
        if (end == null) return builder(context, '');
        final remaining = end.difference(now);
        if (remaining.isNegative) {
          return builder(context, l10n.postArchivedMarker);
        }
        return builder(
          context,
          postRemainingVisibleLabel(l10n, remaining),
        );
      },
    );
  }
}
