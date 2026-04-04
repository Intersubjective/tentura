import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Formats remaining duration for evaluation review window UI.
String formatReviewWindowRemaining(
  Duration remaining,
  L10n l10n,
) {
  if (remaining.isNegative || remaining == Duration.zero) {
    return l10n.evaluationReviewDurationLessThanMinute;
  }
  final days = remaining.inDays;
  final hoursTotal = remaining.inHours;
  final hours = hoursTotal % 24;
  final minutes = remaining.inMinutes % 60;
  if (days > 0) {
    return l10n.evaluationReviewDurationDaysHours(days, hours);
  }
  if (hoursTotal > 0) {
    return l10n.evaluationReviewDurationHoursMinutes(hoursTotal, minutes);
  }
  if (minutes > 0) {
    return l10n.evaluationReviewDurationMinutes(minutes);
  }
  return l10n.evaluationReviewDurationLessThanMinute;
}

/// Countdown line for open review windows on beacon list cards (data from Hasura `BeaconModel`).
class BeaconReviewCountdownRow extends StatefulWidget {
  const BeaconReviewCountdownRow({
    required this.beacon,
    super.key,
  });

  final Beacon beacon;

  @override
  State<BeaconReviewCountdownRow> createState() =>
      _BeaconReviewCountdownRowState();
}

class _BeaconReviewCountdownRowState extends State<BeaconReviewCountdownRow> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (_shouldShow) {
      _timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _shouldShow =>
      widget.beacon.lifecycle == BeaconLifecycle.closedReviewOpen &&
      widget.beacon.reviewClosesAt != null &&
      widget.beacon.reviewWindowStatus != 1;

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) {
      return const SizedBox.shrink();
    }
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final closesAt = widget.beacon.reviewClosesAt!;
    final closesUtc = closesAt.isUtc ? closesAt : closesAt.toUtc();
    final remaining = closesUtc.difference(DateTime.now().toUtc());
    if (remaining.isNegative) {
      return const SizedBox.shrink();
    }
    final detail = formatReviewWindowRemaining(remaining, l10n);
    return Padding(
      padding: kPaddingSmallV,
      child: Row(
        children: [
          Icon(
            Icons.schedule,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.evaluationReviewPeriodEndsIn(detail),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
