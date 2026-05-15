import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/coordination_log_row_chrome.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/coordination_item/ui/widget/item_card.dart';

import '../bloc/beacon_view_state.dart';

// TODO(contract): Add TimelineForward / similar when server exposes forward events on beacon timeline.

enum _ActivityTier { high, medium, low }

_ActivityTier _tierFor(TimelineEntry e) => switch (e) {
      TimelineCreation() ||
      TimelineBeaconLifecycleChanged() ||
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
    required this.onEditTimelineUpdate,
    this.roomActivityEvents = const [],
    this.actors = const {},
    this.coordinationLogOnly = false,
    super.key,
  });

  final List<TimelineEntry> timeline;
  final Beacon beacon;
  final bool isAuthorView;
  final Future<void> Function(TimelineUpdate u) onEditTimelineUpdate;
  final List<BeaconActivityEvent> roomActivityEvents;

  /// Maps userId → participant for room activity event actors/targets.
  final Map<String, BeaconParticipant> actors;

  /// When true (Log tab), show only semantic/coordination room events.
  final bool coordinationLogOnly;

  static bool _isCoordinationLogEvent(BeaconActivityEvent e) {
    if (e.type >= 100 && e.type < 500) return true;
    return switch (e.type) {
      BeaconActivityEventTypeBits.planUpdated => true,
      BeaconActivityEventTypeBits.blockerOpened => true,
      BeaconActivityEventTypeBits.blockerResolved => true,
      BeaconActivityEventTypeBits.needInfoOpened => true,
      BeaconActivityEventTypeBits.doneMarked => true,
      BeaconActivityEventTypeBits.factPinned => true,
      BeaconActivityEventTypeBits.factVisibilityChanged => true,
      _ => false,
    };
  }

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
          label: _coordinationEventLabel(context, e),
          actor: e.actorId != null ? actors[e.actorId!] : null,
          target: e.targetUserId != null ? actors[e.targetUserId!] : null,
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

enum _LogTier { high, medium, low }

_LogTier _logTierFor(BeaconActivityEvent e) {
  if (e.type >= 100 && e.type < 500) return _LogTier.high;
  return switch (e.type) {
    BeaconActivityEventTypeBits.blockerOpened ||
    BeaconActivityEventTypeBits.blockerResolved ||
    BeaconActivityEventTypeBits.doneMarked =>
      _LogTier.high,
    BeaconActivityEventTypeBits.planUpdated ||
    BeaconActivityEventTypeBits.factPinned ||
    BeaconActivityEventTypeBits.needInfoOpened =>
      _LogTier.medium,
    _ => _LogTier.low,
  };
}

IconData _logIcon(BeaconActivityEvent e) {
  if (e.type >= 100 && e.type < 500) {
    final kind = e.type ~/ 100;
    final ev = e.type % 100;
    return switch (kind) {
      1 => switch (ev) {
          6 => Icons.swap_horiz,
          3 => Icons.check_box_outlined,
          _ => Icons.checklist_rtl_rounded,
        },
      2 => switch (ev) {
          2 => Icons.thumb_up_alt_outlined,
          3 => Icons.check_circle_outline,
          4 => Icons.cancel_outlined,
          _ => Icons.contact_support_outlined,
        },
      3 => switch (ev) {
          3 => Icons.lock_open_outlined,
          4 => Icons.cancel_outlined,
          _ => Icons.warning_amber_rounded,
        },
      4 => switch (ev) {
          3 => Icons.task_alt,
          4 => Icons.highlight_off,
          _ => Icons.lightbulb_outline,
        },
      _ => Icons.hub_outlined,
    };
  }
  return switch (e.type) {
    BeaconActivityEventTypeBits.planUpdated => Icons.edit_note,
    BeaconActivityEventTypeBits.factPinned => Icons.push_pin_outlined,
    BeaconActivityEventTypeBits.blockerOpened => Icons.warning_amber_rounded,
    BeaconActivityEventTypeBits.blockerResolved => Icons.lock_open_outlined,
    BeaconActivityEventTypeBits.needInfoOpened => Icons.help_outline,
    BeaconActivityEventTypeBits.doneMarked => Icons.task_alt,
    BeaconActivityEventTypeBits.factVisibilityChanged =>
      Icons.visibility_outlined,
    _ => Icons.hub_outlined,
  };
}

Color _coordinationSemanticAccentColor(ColorScheme cs, int type) {
  final kind = type ~/ 100;
  final ev = type % 100;
  return switch (kind) {
    1 => switch (ev) {
        1 ||
        5 =>
          coordinationItemColor(cs, CoordinationItemKind.plan, CoordinationItemStatus.open),
        3 => coordinationItemColor(
              cs,
              CoordinationItemKind.plan,
              CoordinationItemStatus.resolved,
            ),
        6 => coordinationItemColor(
              cs,
              CoordinationItemKind.plan,
              CoordinationItemStatus.superseded,
            ),
        _ => coordinationItemColor(cs, CoordinationItemKind.plan, CoordinationItemStatus.open),
      },
    2 => switch (ev) {
        1 => coordinationItemColor(cs, CoordinationItemKind.ask, CoordinationItemStatus.open),
        2 => coordinationItemColor(
              cs,
              CoordinationItemKind.ask,
              CoordinationItemStatus.accepted,
            ),
        3 => coordinationItemColor(
              cs,
              CoordinationItemKind.ask,
              CoordinationItemStatus.resolved,
            ),
        4 => coordinationItemColor(
              cs,
              CoordinationItemKind.ask,
              CoordinationItemStatus.cancelled,
            ),
        _ => coordinationItemColor(cs, CoordinationItemKind.ask, CoordinationItemStatus.open),
      },
    3 => switch (ev) {
        1 => coordinationItemColor(
              cs,
              CoordinationItemKind.blocker,
              CoordinationItemStatus.open,
            ),
        3 => coordinationItemColor(
              cs,
              CoordinationItemKind.blocker,
              CoordinationItemStatus.resolved,
            ),
        4 => coordinationItemColor(
              cs,
              CoordinationItemKind.blocker,
              CoordinationItemStatus.cancelled,
            ),
        _ => coordinationItemColor(
              cs,
              CoordinationItemKind.blocker,
              CoordinationItemStatus.open,
            ),
      },
    4 => switch (ev) {
        1 => coordinationItemColor(
              cs,
              CoordinationItemKind.resolution,
              CoordinationItemStatus.open,
            ),
        3 => coordinationItemColor(
              cs,
              CoordinationItemKind.resolution,
              CoordinationItemStatus.resolved,
            ),
        4 => coordinationItemColor(
              cs,
              CoordinationItemKind.resolution,
              CoordinationItemStatus.cancelled,
            ),
        _ => coordinationItemColor(
              cs,
              CoordinationItemKind.resolution,
              CoordinationItemStatus.open,
            ),
      },
    _ => cs.onSurfaceVariant,
  };
}

Color _logIconColor(ThemeData theme, BeaconActivityEvent e) {
  final cs = theme.colorScheme;
  if (e.type >= 100 && e.type < 500) {
    return _coordinationSemanticAccentColor(cs, e.type);
  }
  return switch (e.type) {
    BeaconActivityEventTypeBits.blockerOpened => cs.error,
    BeaconActivityEventTypeBits.doneMarked => cs.tertiary,
    _ => cs.onSurfaceVariant,
  };
}

class _LogActivityTile extends StatelessWidget {
  const _LogActivityTile({
    required this.event,
    required this.label,
    required this.actor,
    required this.target,
  });

  final BeaconActivityEvent event;
  final String label;
  final BeaconParticipant? actor;
  final BeaconParticipant? target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tier = _logTierFor(event);
    final iconColor = _logIconColor(theme, event);
    final eventIcon = Icon(
      _logIcon(event),
      size: kCoordinationLogEventIconSize,
      color: iconColor,
    );
    final lead = coordinationLogLeadRow(
      eventIcon: eventIcon,
      actor: actor,
      target: target,
    );

    return Padding(
      padding: kPaddingSmallV,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          lead,
          const SizedBox(width: kSpacingSmall),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: tier == _LogTier.high ? FontWeight.w600 : null,
                color: iconColor,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            coordinationLogTimestampLabel(event.createdAt),
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
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
              Icon(iconData, size: kCoordinationLogEventIconSize, color: iconColor),
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
                coordinationLogTimestampLabel(u.timestamp),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        _ => Row(
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
      },
    );
  }
}

IconData _icon(TimelineEntry e) => switch (e) {
      TimelineCreation() => Icons.flag_rounded,
      TimelineBeaconLifecycleChanged() => Icons.flag_circle_outlined,
      TimelineBeaconCoordinationStatusChanged() => Icons.sync_alt,
      TimelineHelpOfferCreated() => Icons.handshake,
      TimelineHelpOfferUpdated() => Icons.edit_note,
      TimelineHelpOfferWithdrawn() => Icons.heart_broken,
      TimelineAuthorCoordinationResponse() => Icons.reply_rounded,
      TimelineUpdate() => Icons.campaign_outlined,
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
          ? l10n.timelineHelpOfferedWithMessage(e.helpOfferer.title, e.message)
          : l10n.timelineHelpOffered(e.helpOfferer.title),
      final TimelineHelpOfferUpdated e =>
        _timelineHelpOfferUpdatedLine(l10n, e),
      final TimelineAuthorCoordinationResponse e =>
        l10n.timelineAuthorCoordinationResponseLine(
          e.author.title,
          e.helpOfferer.title,
          coordinationResponseLabel(l10n, e.response) ?? '',
        ),
      final TimelineHelpOfferWithdrawn e => e.message.isNotEmpty
          ? l10n.timelineWithdrewWithMessage(e.helpOfferer.title, e.message)
          : l10n.timelineWithdrew(e.helpOfferer.title),
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

String _coordinationEventLabel(BuildContext context, BeaconActivityEvent e) {
  final l10n = L10n.of(context)!;
  if (e.type >= 100 && e.type < 500) {
    final kind = e.type ~/ 100;
    final ev = e.type % 100;
    return switch (kind) {
      1 => switch (ev) {
          1 => l10n.coordinationSemanticPlanOpened,
          5 => l10n.coordinationSemanticPlanOpened,
          6 => l10n.coordinationSemanticPlanSuperseded,
          3 => l10n.coordinationSemanticPlanStepResolved,
          _ => l10n.coordinationPlanCardLabel,
        },
      2 => switch (ev) {
          1 => l10n.coordinationSemanticAskOpened,
          2 => l10n.coordinationSemanticAskAccepted,
          3 => l10n.coordinationSemanticAskResolved,
          4 => l10n.coordinationSemanticAskCancelled,
          _ => l10n.coordinationAskCardLabel,
        },
      3 => switch (ev) {
          1 => l10n.coordinationSemanticBlockerOpened,
          3 => l10n.coordinationSemanticBlockerResolved,
          4 => l10n.coordinationSemanticBlockerCancelled,
          _ => l10n.coordinationBlockerCardLabel,
        },
      4 => switch (ev) {
          1 => l10n.coordinationSemanticResolutionOpened,
          3 => l10n.coordinationSemanticResolutionResolved,
          4 => l10n.coordinationSemanticResolutionCancelled,
          _ => l10n.coordinationResolutionCardLabel,
        },
      _ => l10n.beaconActivityCoordinationFallback,
    };
  }

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

String _timelineHelpOfferUpdatedLine(L10n l10n, TimelineHelpOfferUpdated e) {
  final base = l10n.timelineHelpOfferDetailsUpdated(e.helpOfferer.title);
  final help = helpTypeLabel(l10n, e.helpType);
  if (help != null && help.isNotEmpty) {
    return '$base · $help';
  }
  return base;
}

const _beaconAuthorUpdateEditWindow = Duration(hours: 1);

bool _authorUpdateEditableNow(DateTime createdAt) =>
    DateTime.now().toUtc().difference(createdAt.toUtc()) <=
    _beaconAuthorUpdateEditWindow;
