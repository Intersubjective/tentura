import 'package:flutter/widgets.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

/// Countdown with unified buckets (#1081): whole days use ceiling only when the
/// remainder is at least 24h (so composer/detail agree on day boundaries); below
/// that, hours use truncated wall time ([Duration.inHours]), minutes use
/// [Duration.inMinutes] (at least one minute when time is left).
String postRemainingLabel(
  L10n l10n,
  Duration remaining, {
  int Function(Duration d)? ceilDays,
}) {
  if (remaining.inMicroseconds <= 0) {
    return l10n.postRemainingMinutes(1);
  }
  const day = Duration(days: 1);
  if (remaining >= day) {
    final days = (ceilDays ?? _defaultCeilDays)(remaining);
    return l10n.postRemainingDays(days);
  }
  final hours = remaining.inHours;
  if (hours >= 1) return l10n.postRemainingHours(hours);
  return l10n.postRemainingMinutes(
    remaining.inMinutes < 1 ? 1 : remaining.inMinutes,
  );
}

int _defaultCeilDays(Duration d) {
  if (d.inMicroseconds <= 0) return 0;
  return (d.inMicroseconds + Duration.microsecondsPerDay - 1) ~/
      Duration.microsecondsPerDay;
}

/// Stable 3 d / 2 d boundary for tests and golden-less regression checks.
@visibleForTesting
int postRemainingCeilDaysForTests(Duration remaining) => _defaultCeilDays(remaining);

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
