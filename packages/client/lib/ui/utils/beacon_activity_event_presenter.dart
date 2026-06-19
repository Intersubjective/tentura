import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';

enum BeaconActivityLogTier { high, medium, low }

BeaconActivityLogTier beaconActivityLogTier(BeaconActivityEvent e) {
  if (e.type >= 100 && e.type < 500) return BeaconActivityLogTier.high;
  return switch (e.type) {
    BeaconActivityEventTypeBits.blockerOpened ||
    BeaconActivityEventTypeBits.blockerResolved ||
    BeaconActivityEventTypeBits.doneMarked =>
      BeaconActivityLogTier.high,
    BeaconActivityEventTypeBits.planUpdated ||
    BeaconActivityEventTypeBits.factPinned ||
    BeaconActivityEventTypeBits.needInfoOpened ||
    BeaconActivityEventTypeBits.beaconPublished =>
      BeaconActivityLogTier.medium,
    _ => BeaconActivityLogTier.low,
  };
}

IconData beaconActivityLogIcon(BeaconActivityEvent e) {
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
    BeaconActivityEventTypeBits.beaconPublished => Icons.campaign_outlined,
    _ => Icons.hub_outlined,
  };
}

Color _coordinationSemanticAccentColor(TenturaTokens tt, int type) {
  final kind = type ~/ 100;
  final ev = type % 100;
  return switch (kind) {
    1 => switch (ev) {
        1 ||
        5 =>
          coordinationItemColor(tt, CoordinationItemKind.plan, CoordinationItemStatus.open),
        3 => coordinationItemColor(
              tt,
              CoordinationItemKind.plan,
              CoordinationItemStatus.resolved,
            ),
        6 => coordinationItemColor(
              tt,
              CoordinationItemKind.plan,
              CoordinationItemStatus.superseded,
            ),
        _ => coordinationItemColor(tt, CoordinationItemKind.plan, CoordinationItemStatus.open),
      },
    2 => switch (ev) {
        1 => coordinationItemColor(tt, CoordinationItemKind.ask, CoordinationItemStatus.open),
        2 => coordinationItemColor(
              tt,
              CoordinationItemKind.ask,
              CoordinationItemStatus.accepted,
            ),
        3 => coordinationItemColor(
              tt,
              CoordinationItemKind.ask,
              CoordinationItemStatus.resolved,
            ),
        4 => coordinationItemColor(
              tt,
              CoordinationItemKind.ask,
              CoordinationItemStatus.cancelled,
            ),
        _ => coordinationItemColor(tt, CoordinationItemKind.ask, CoordinationItemStatus.open),
      },
    3 => switch (ev) {
        1 => coordinationItemColor(
              tt,
              CoordinationItemKind.blocker,
              CoordinationItemStatus.open,
            ),
        3 => coordinationItemColor(
              tt,
              CoordinationItemKind.blocker,
              CoordinationItemStatus.resolved,
            ),
        4 => coordinationItemColor(
              tt,
              CoordinationItemKind.blocker,
              CoordinationItemStatus.cancelled,
            ),
        _ => coordinationItemColor(
              tt,
              CoordinationItemKind.blocker,
              CoordinationItemStatus.open,
            ),
      },
    4 => switch (ev) {
        1 => coordinationItemColor(
              tt,
              CoordinationItemKind.resolution,
              CoordinationItemStatus.open,
            ),
        3 => coordinationItemColor(
              tt,
              CoordinationItemKind.resolution,
              CoordinationItemStatus.resolved,
            ),
        4 => coordinationItemColor(
              tt,
              CoordinationItemKind.resolution,
              CoordinationItemStatus.cancelled,
            ),
        _ => coordinationItemColor(
              tt,
              CoordinationItemKind.resolution,
              CoordinationItemStatus.open,
            ),
      },
    _ => tt.textMuted,
  };
}

Color beaconActivityLogIconColor(ThemeData theme, BeaconActivityEvent e) {
  if (e.type == BeaconActivityEventTypeBits.beaconPublished) {
    return theme.colorScheme.primary;
  }
  final tt = theme.extension<TenturaTokens>() ?? TenturaTokens.light;
  if (e.type >= 100 && e.type < 500) {
    return _coordinationSemanticAccentColor(tt, e.type);
  }
  return switch (e.type) {
    BeaconActivityEventTypeBits.blockerOpened => tt.danger,
    BeaconActivityEventTypeBits.needInfoOpened => tt.warn,
    BeaconActivityEventTypeBits.doneMarked => tt.good,
    _ => tt.textMuted,
  };
}

String beaconActivityEventLabel(L10n l10n, BeaconActivityEvent e) {
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
    BeaconActivityEventTypeBits.beaconPublished =>
      l10n.beaconActivityBeaconPublished,
    _ => l10n.beaconActivityCoordinationFallback,
  };
}
