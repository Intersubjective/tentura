import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';

import '../bloc/beacon_view_state.dart';

// TODO(contract): Add TimelineForward / similar when server exposes forward events on beacon timeline.

enum _ActivityTier { high, medium, low }

_ActivityTier _tierFor(TimelineEntry e) => switch (e) {
      TimelineCreation() ||
      TimelineBeaconLifecycleChanged() ||
      TimelineBeaconCoordinationStatusChanged() =>
        _ActivityTier.high,
      TimelineCommitmentUpdated() => _ActivityTier.low,
      _ => _ActivityTier.medium,
    };

/// Chronological timeline (newest first) for the beacon detail Timeline tab.
class BeaconActivityList extends StatelessWidget {
  const BeaconActivityList({
    required this.timeline,
    required this.beacon,
    required this.isAuthorView,
    required this.onEditTimelineUpdate,
    this.roomActivityEvents = const [],
    super.key,
  });

  final List<TimelineEntry> timeline;
  final Beacon beacon;
  final bool isAuthorView;
  final Future<void> Function(TimelineUpdate u) onEditTimelineUpdate;
  final List<BeaconActivityEvent> roomActivityEvents;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    if (timeline.isEmpty && roomActivityEvents.isEmpty) {
      return Padding(
        padding: kPaddingSmallV,
        child: Text(
          l10n.beaconNoActivityYetShort,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    var tie = 0;
    final rows = <({DateTime t, int tie, Widget child})>[];
    for (final e in roomActivityEvents) {
      rows.add((
        t: e.createdAt.toUtc(),
        tie: tie++,
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.hub_outlined),
          title: Text(_coordinationTitle(context, e)),
          subtitle: Text(
            _activityTs(e.createdAt),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ));
    }
    for (final e in timeline) {
      rows.add((
        t: e.timestamp.toUtc(),
        tie: tie++,
        child: _ActivityEntryTile(
          entry: e,
          beacon: beacon,
          isAuthorView: isAuthorView,
          onEditTimelineUpdate: onEditTimelineUpdate,
          tier: _tierFor(e),
        ),
      ));
    }
    rows.sort((a, b) {
      final c = b.t.compareTo(a.t);
      if (c != 0) return c;
      return a.tie.compareTo(b.tie);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final r in rows) r.child],
    );
  }
}

class _ActivityEntryTile extends StatelessWidget {
  const _ActivityEntryTile({
    required this.entry,
    required this.beacon,
    required this.isAuthorView,
    required this.onEditTimelineUpdate,
    required this.tier,
  });

  final TimelineEntry entry;
  final Beacon beacon;
  final bool isAuthorView;
  final Future<void> Function(TimelineUpdate u) onEditTimelineUpdate;
  final _ActivityTier tier;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final iconData = _icon(entry);
    final iconColor = _iconColor(theme, entry, tier);

    return Padding(
      padding: kPaddingSmallV,
      child: switch (entry) {
        final TimelineUpdate u => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(iconData, size: 22, color: iconColor),
              const SizedBox(width: kSpacingSmall),
              Expanded(
                child: Text(
                  '${l10n.updateNumberLabel(u.number)} · ${l10n.timelineUpdate(u.author.title, u.content)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (isAuthorView &&
                  beacon.lifecycle == BeaconLifecycle.open &&
                  _authorUpdateEditableNow(u.createdAt))
                IconButton(
                  tooltip: l10n.editUpdateCTA,
                  icon: const Icon(Icons.edit_outlined),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => onEditTimelineUpdate(u),
                ),
              Text(
                _activityTs(u.timestamp),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        _ => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(iconData, size: 22, color: iconColor),
              const SizedBox(width: kSpacingSmall),
              Expanded(
                child: Text(
                  _line(l10n, entry),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight:
                        tier == _ActivityTier.high ? FontWeight.w600 : null,
                  ),
                ),
              ),
              Text(
                _activityTs(entry.timestamp),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
      },
    );
  }
}

IconData _icon(TimelineEntry e) => switch (e) {
      TimelineCreation() => Icons.flag_rounded,
      TimelineBeaconLifecycleChanged() => Icons.flag_circle_outlined,
      TimelineBeaconCoordinationStatusChanged() => Icons.sync_alt,
      TimelineCommitmentCreated() => Icons.handshake,
      TimelineCommitmentUpdated() => Icons.edit_note,
      TimelineCommitmentWithdrawn() => Icons.heart_broken,
      TimelineAuthorCoordinationResponse() => Icons.reply_rounded,
      TimelineUpdate() => Icons.campaign_outlined,
    };

Color _iconColor(ThemeData theme, TimelineEntry e, _ActivityTier tier) {
  if (tier == _ActivityTier.high) {
    return theme.colorScheme.primary;
  }
  return switch (e) {
    TimelineCommitmentWithdrawn() => theme.colorScheme.error,
    TimelineCommitmentCreated() => theme.colorScheme.tertiary,
    TimelineAuthorCoordinationResponse() => theme.colorScheme.secondary,
    _ => theme.colorScheme.onSurfaceVariant,
  };
}

String _line(L10n l10n, TimelineEntry entry) => switch (entry) {
      final TimelineCommitmentCreated e => e.message.isNotEmpty
          ? l10n.timelineCommittedWithMessage(e.committer.title, e.message)
          : l10n.timelineCommitted(e.committer.title),
      final TimelineCommitmentUpdated e =>
        _timelineCommitmentUpdatedLine(l10n, e),
      final TimelineAuthorCoordinationResponse e =>
        l10n.timelineAuthorCoordinationResponseLine(
          e.author.title,
          e.committer.title,
          coordinationResponseLabel(l10n, e.response) ?? '',
        ),
      final TimelineCommitmentWithdrawn e => e.message.isNotEmpty
          ? l10n.timelineWithdrewWithMessage(e.committer.title, e.message)
          : l10n.timelineWithdrew(e.committer.title),
      final TimelineBeaconCoordinationStatusChanged e =>
        l10n.timelineBeaconCoordinationStatusChanged(
          e.author.title,
          coordinationStatusLabel(l10n, e.status),
        ),
      final TimelineBeaconLifecycleChanged e =>
        l10n.timelineBeaconLifecycleChanged(
          e.author.title,
          _lifecycleLabel(l10n, e.lifecycle),
        ),
      final TimelineCreation e => l10n.timelineCreated(e.author.title),
      TimelineUpdate() => '',
    };

String _coordinationTitle(BuildContext context, BeaconActivityEvent e) {
  final l10n = L10n.of(context)!;
  return switch (e.type) {
    BeaconActivityEventTypeBits.planUpdated => l10n.beaconActivityPlanUpdated,
    BeaconActivityEventTypeBits.factPinned => l10n.beaconActivityFactPinned,
    BeaconActivityEventTypeBits.factVisibilityChanged =>
      l10n.beaconActivityFactVisibilityChanged,
    BeaconActivityEventTypeBits.blockerOpened =>
      l10n.beaconActivityBlockerOpened,
    BeaconActivityEventTypeBits.blockerResolved =>
      l10n.beaconActivityBlockerResolved,
    BeaconActivityEventTypeBits.needInfoOpened =>
      l10n.beaconActivityNeedInfoOpened,
    BeaconActivityEventTypeBits.doneMarked => l10n.beaconActivityDoneMarked,
    _ => l10n.beaconActivityCoordinationFallback,
  };
}

String _lifecycleLabel(L10n l10n, BeaconLifecycle lc) => switch (lc) {
      BeaconLifecycle.open => l10n.beaconLifecycleOpen,
      BeaconLifecycle.closed => l10n.beaconLifecycleClosed,
      BeaconLifecycle.deleted => l10n.beaconLifecycleDeleted,
      BeaconLifecycle.draft => l10n.beaconLifecycleDraft,
      BeaconLifecycle.pendingReview => l10n.beaconLifecyclePendingReview,
      BeaconLifecycle.closedReviewOpen => l10n.beaconLifecycleClosedReviewOpen,
      BeaconLifecycle.closedReviewComplete =>
        l10n.beaconLifecycleClosedReviewComplete,
    };

String _timelineCommitmentUpdatedLine(L10n l10n, TimelineCommitmentUpdated e) {
  final base = l10n.timelineCommitmentDetailsUpdated(e.committer.title);
  final help = helpTypeLabel(l10n, e.helpType);
  if (help != null && help.isNotEmpty) {
    return '$base · $help';
  }
  return base;
}

String _activityTs(DateTime utc) {
  final local = utc.toLocal();
  return '${dateFormatYMD(local)} ${timeFormatHm(local)}';
}

const _beaconAuthorUpdateEditWindow = Duration(hours: 1);

bool _authorUpdateEditableNow(DateTime createdAt) =>
    DateTime.now().toUtc().difference(createdAt.toUtc()) <=
    _beaconAuthorUpdateEditWindow;
