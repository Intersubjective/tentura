import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_activity_event_presenter.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';
import 'package:tentura/ui/widget/coordination_log_row_chrome.dart';

import '../bloc/beacon_view_state.dart';

// TODO(contract): Add TimelineForward / similar when server exposes forward events on beacon timeline.

enum _ActivityTier { high, medium, low }

_ActivityTier _tierFor(TimelineEntry e) => switch (e) {
      TimelineCreation() ||
      TimelineBeaconCoordinationStatusChanged() =>
        _ActivityTier.high,
      TimelineHelpOfferUpdated() => _ActivityTier.low,
      _ => _ActivityTier.medium,
    };

/// Chronological timeline (newest first) for the beacon detail Timeline tab.
class BeaconActivityList extends StatelessWidget {
  const BeaconActivityList({
    required this.timeline,
    required this.beacon,
    required this.isAuthorView,
    this.roomActivityEvents = const [],
    this.actors = const {},
    this.coordinationLogOnly = false,
    this.onTapCoordinationEvent,
    super.key,
  });

  final List<TimelineEntry> timeline;
  final Beacon beacon;
  final bool isAuthorView;
  final List<BeaconActivityEvent> roomActivityEvents;

  /// Maps userId → participant for room activity event actors/targets.
  final Map<String, BeaconParticipant> actors;

  /// When true (Log tab), show only semantic/coordination room events.
  final bool coordinationLogOnly;

  /// Tapping a log row routes to the linked coordination item / participant.
  final void Function(BeaconActivityEvent event)? onTapCoordinationEvent;

  static bool _isCoordinationLogEvent(BeaconActivityEvent e) =>
      e.isCoordinationLogEvent;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final roomEvents = coordinationLogOnly
        ? roomActivityEvents.where(_isCoordinationLogEvent).toList()
        : roomActivityEvents;
    if (timeline.isEmpty && roomEvents.isEmpty) {
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
    for (final e in roomEvents) {
      rows.add((
        t: e.createdAt.toUtc(),
        tie: tie++,
        child: _LogActivityTile(
          event: e,
          label: beaconActivityEventLabel(l10n, e),
          actor: e.actorId != null ? actors[e.actorId!] : null,
          target: e.targetUserId != null ? actors[e.targetUserId!] : null,
          onTap: onTapCoordinationEvent == null
              ? null
              : () => onTapCoordinationEvent!(e),
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

enum _LogTier { high, medium, low }

_LogTier _logTierFor(BeaconActivityEvent e) => switch (beaconActivityLogTier(e)) {
      BeaconActivityLogTier.high => _LogTier.high,
      BeaconActivityLogTier.medium => _LogTier.medium,
      BeaconActivityLogTier.low => _LogTier.low,
    };

class _LogActivityTile extends StatelessWidget {
  const _LogActivityTile({
    required this.event,
    required this.label,
    required this.actor,
    required this.target,
    this.onTap,
  });

  final BeaconActivityEvent event;
  final String label;
  final BeaconParticipant? actor;
  final BeaconParticipant? target;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tier = _logTierFor(event);
    final iconColor = beaconActivityLogIconColor(theme, event);
    final eventIcon = coordinationCompoundActivityIcon(
          event,
          tt: context.tt,
        ) ??
        Icon(
          beaconActivityLogIcon(event),
          size: kCoordinationLogEventIconSize,
          color: iconColor,
        );
    final lead = coordinationLogTabLeadRow(
      eventIcon: eventIcon,
      actor: actor,
      target: target,
    );
    final bodySnippet = coordinationLogEventBodySnippet(
      event: event,
      fallback: label,
    );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        lead,
        const SizedBox(width: kSpacingSmall),
        Expanded(
          child: Text(
            bodySnippet,
            style: theme.textTheme.bodySmall?.copyWith(
              color: iconColor,
              fontWeight: tier == _LogTier.high ? FontWeight.w600 : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          coordinationLogTimestampLabel(event.createdAt),
          style: theme.textTheme.labelSmall,
        ),
        if (onTap != null) ...[
          const SizedBox(width: 2),
          Icon(
            Icons.chevron_right,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ],
    );

    if (onTap == null) {
      return Padding(padding: kPaddingSmallV, child: row);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      child: Padding(
        padding: kPaddingSmallV,
        child: row,
      ),
    );
  }
}

class _ActivityEntryTile extends StatelessWidget {
  const _ActivityEntryTile({
    required this.entry,
    required this.beacon,
    required this.isAuthorView,
    required this.tier,
  });

  final TimelineEntry entry;
  final Beacon beacon;
  final bool isAuthorView;
  final _ActivityTier tier;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final iconData = _icon(entry);
    final iconColor = _iconColor(theme, entry, tier);

    return Padding(
      padding: kPaddingSmallV,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, size: kCoordinationLogEventIconSize, color: iconColor),
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
            coordinationLogTimestampLabel(entry.timestamp),
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

IconData _icon(TimelineEntry e) => switch (e) {
      TimelineCreation() => Icons.flag_rounded,
      TimelineBeaconCoordinationStatusChanged() => Icons.sync_alt,
      TimelineHelpOfferCreated() => Icons.handshake,
      TimelineHelpOfferUpdated() => Icons.edit_note,
      TimelineHelpOfferWithdrawn() => Icons.heart_broken,
      TimelineAuthorCoordinationResponse() => Icons.reply_rounded,
    };

Color _iconColor(ThemeData theme, TimelineEntry e, _ActivityTier tier) {
  if (tier == _ActivityTier.high) {
    return theme.colorScheme.primary;
  }
  return switch (e) {
    TimelineHelpOfferWithdrawn() => theme.colorScheme.error,
    TimelineHelpOfferCreated() => theme.colorScheme.tertiary,
    TimelineAuthorCoordinationResponse() => theme.colorScheme.secondary,
    _ => theme.colorScheme.onSurfaceVariant,
  };
}

String _line(L10n l10n, TimelineEntry entry) => switch (entry) {
      final TimelineHelpOfferCreated e => e.message.isNotEmpty
          ? l10n.timelineHelpOfferedWithMessage(e.helpOfferer.shownName, e.message)
          : l10n.timelineHelpOffered(e.helpOfferer.shownName),
      final TimelineHelpOfferUpdated e =>
        _timelineHelpOfferUpdatedLine(l10n, e),
      final TimelineAuthorCoordinationResponse e =>
        l10n.timelineAuthorCoordinationResponseLine(
          e.author.shownName,
          e.helpOfferer.shownName,
          coordinationResponseLabel(l10n, e.response) ?? '',
        ),
      final TimelineHelpOfferWithdrawn e => e.message.isNotEmpty
          ? l10n.timelineWithdrewWithMessage(e.helpOfferer.shownName, e.message)
          : l10n.timelineWithdrew(e.helpOfferer.shownName),
      final TimelineBeaconCoordinationStatusChanged e =>
        l10n.timelineBeaconCoordinationStatusChanged(
          e.author.shownName,
          coordinationStatusLabel(l10n, e.status),
        ),
      final TimelineCreation e => l10n.timelineCreated(e.author.shownName),
    };

String _timelineHelpOfferUpdatedLine(L10n l10n, TimelineHelpOfferUpdated e) {
  final base = l10n.timelineHelpOfferDetailsUpdated(e.helpOfferer.shownName);
  final help = helpTypeLabel(l10n, e.helpType);
  if (help != null && help.isNotEmpty) {
    return '$base · $help';
  }
  return base;
}
