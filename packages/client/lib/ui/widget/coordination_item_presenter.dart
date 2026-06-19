import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_tokens.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Shared coordination-item presentation (colors, icons, compound glyphs).
///
/// Lives in `ui/widget` (not in a single feature) so every feature and
/// `ui/utils` depends inward on one stable interface-adapter module. Maps the
/// pure domain enums ([CoordinationItemKind] / [CoordinationItemStatus] /
/// [CoordinationItemEventKind]) onto Flutter `Color` / `IconData` / `Widget`.

// --- Status accent color -----------------------------------------------------

/// Status accent for a coordination item — drives the kind label text and the
/// compound state glyph. Green ([TenturaTokens.good]) is reserved for genuine
/// completion (`resolved`); `accepted` is "in progress / owed" (`tt.info`).
Color coordinationItemColor(
  TenturaTokens tt,
  CoordinationItemKind kind,
  CoordinationItemStatus status,
) {
  if (status == CoordinationItemStatus.cancelled ||
      status == CoordinationItemStatus.superseded) {
    return tt.textMuted;
  }
  if (status == CoordinationItemStatus.resolved) {
    return tt.good;
  }
  return switch (kind) {
    CoordinationItemKind.blocker => tt.danger,
    CoordinationItemKind.ask =>
      status == CoordinationItemStatus.accepted ? tt.info : tt.warn,
    CoordinationItemKind.promise =>
      status == CoordinationItemStatus.accepted ? tt.info : tt.warn,
    CoordinationItemKind.resolution => tt.info,
    CoordinationItemKind.plan => tt.info,
  };
}

/// Accent for room-timeline / activity item events.
Color coordinationItemEventColor(
  TenturaTokens tt,
  CoordinationItemKind kind,
  CoordinationItemEventKind eventKind,
) {
  return switch (eventKind) {
    CoordinationItemEventKind.resolved =>
      coordinationItemColor(tt, kind, CoordinationItemStatus.resolved),
    CoordinationItemEventKind.cancelled ||
    CoordinationItemEventKind.superseded =>
      coordinationItemColor(tt, kind, CoordinationItemStatus.cancelled),
    CoordinationItemEventKind.accepted =>
      coordinationItemColor(tt, kind, CoordinationItemStatus.accepted),
    _ => coordinationItemColor(tt, kind, CoordinationItemStatus.open),
  };
}

// --- Compound icon slots -----------------------------------------------------

/// Slot 1: the object/kind glyph (stable; never a checkmark).
IconData coordinationKindIcon(
  CoordinationItemKind kind, {
  bool isPlanStep = false,
}) =>
    switch (kind) {
      CoordinationItemKind.blocker => Icons.block,
      CoordinationItemKind.ask => Icons.help_outline,
      CoordinationItemKind.promise => Icons.front_hand_outlined,
      CoordinationItemKind.plan =>
        isPlanStep ? Icons.checklist : Icons.edit_note,
      CoordinationItemKind.resolution => Icons.handshake_outlined,
    };

/// Slot 2: state-change glyph for a current status; `null` for `open`
/// (kind glyph stands alone). `check_circle` (green) appears only for
/// `resolved`.
IconData? coordinationStateIcon(CoordinationItemStatus status) =>
    switch (status) {
      CoordinationItemStatus.open => null,
      CoordinationItemStatus.accepted => Icons.thumb_up_alt_outlined,
      CoordinationItemStatus.resolved => Icons.check_circle,
      CoordinationItemStatus.cancelled => Icons.cancel_outlined,
      CoordinationItemStatus.superseded => Icons.swap_horiz,
    };

/// Slot 2: state-change glyph for a lifecycle event; `null` for
/// created/updated (kind glyph stands alone).
IconData? coordinationEventStateIcon(CoordinationItemEventKind eventKind) =>
    switch (eventKind) {
      CoordinationItemEventKind.created ||
      CoordinationItemEventKind.updated =>
        null,
      CoordinationItemEventKind.accepted => Icons.thumb_up_alt_outlined,
      CoordinationItemEventKind.resolved => Icons.check_circle,
      CoordinationItemEventKind.cancelled => Icons.cancel_outlined,
      CoordinationItemEventKind.superseded => Icons.swap_horiz,
    };

/// Default compound glyph size (matches the log-row event icon).
const double kCoordinationCompoundIconSize = 22;

/// Builds the side-by-side `[kind][state]` compound. Decorative: callers carry
/// meaning via the adjacent text label. Both glyphs take [accent] (kind alone
/// when [stateIcon] is null; kind and state share accent when chained).
Widget _coordinationCompound({
  required IconData kindIcon,
  required IconData? stateIcon,
  required Color accent,
  required double size,
}) {
  if (stateIcon == null) {
    return Icon(kindIcon, size: size, color: accent);
  }
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(kindIcon, size: size, color: accent),
      const SizedBox(width: 2),
      Icon(stateIcon, size: size, color: accent),
    ],
  );
}

/// Compound for a static status surface (cards, headers, situation rows).
Widget coordinationCompoundStatusIcon({
  required CoordinationItemKind kind,
  required CoordinationItemStatus status,
  required TenturaTokens tt,
  bool isPlanStep = false,
  double size = kCoordinationCompoundIconSize,
}) =>
    _coordinationCompound(
      kindIcon: coordinationKindIcon(kind, isPlanStep: isPlanStep),
      stateIcon: coordinationStateIcon(status),
      accent: coordinationItemColor(tt, kind, status),
      size: size,
    );

/// Compound for a lifecycle event (room timeline). [accentOverride] lets the
/// caller substitute the thread-mark accent for thread-entry kinds.
Widget coordinationCompoundEventIcon({
  required CoordinationItemKind kind,
  required CoordinationItemEventKind eventKind,
  required TenturaTokens tt,
  bool isPlanStep = false,
  double size = kCoordinationCompoundIconSize,
  Color? accentOverride,
}) =>
    _coordinationCompound(
      kindIcon: coordinationKindIcon(kind, isPlanStep: isPlanStep),
      stateIcon: coordinationEventStateIcon(eventKind),
      accent: accentOverride ?? coordinationItemEventColor(tt, kind, eventKind),
      size: size,
    );

/// Compound for an activity-log event; returns `null` for non-coordination
/// events so the caller can fall back to a single `beaconActivityLogIcon`.
Widget? coordinationCompoundActivityIcon(
  BeaconActivityEvent event, {
  required TenturaTokens tt,
  double size = kCoordinationCompoundIconSize,
}) {
  final kind = event.coordinationKind;
  if (kind == null) return null;
  return coordinationCompoundEventIcon(
    kind: kind,
    eventKind: event.coordinationEventKind ?? CoordinationItemEventKind.created,
    tt: tt,
    size: size,
  );
}

// --- Timeline labels (relocated from features/beacon) ------------------------

/// Shared coordination event label for room timeline and footers.
String coordinationEventTimelineLabel(
  L10n l10n,
  CoordinationItemKind kind,
  CoordinationItemEventKind eventKind, {
  bool isPlanStep = false,
}) {
  return switch (kind) {
    CoordinationItemKind.ask => switch (eventKind) {
        CoordinationItemEventKind.created =>
          l10n.coordinationSemanticAskOpened,
        CoordinationItemEventKind.accepted =>
          l10n.coordinationSemanticAskAccepted,
        CoordinationItemEventKind.resolved =>
          l10n.coordinationSemanticAskResolved,
        CoordinationItemEventKind.cancelled =>
          l10n.coordinationSemanticAskCancelled,
        _ => l10n.coordinationAskCardLabel,
      },
    CoordinationItemKind.promise => switch (eventKind) {
        CoordinationItemEventKind.created =>
          l10n.coordinationSemanticPromiseOpened,
        CoordinationItemEventKind.accepted =>
          l10n.coordinationSemanticPromiseAccepted,
        CoordinationItemEventKind.resolved =>
          l10n.coordinationSemanticPromiseResolved,
        CoordinationItemEventKind.cancelled =>
          l10n.coordinationSemanticPromiseCancelled,
        _ => l10n.coordinationPromiseCardLabel,
      },
    CoordinationItemKind.blocker => switch (eventKind) {
        CoordinationItemEventKind.created =>
          l10n.coordinationSemanticBlockerOpened,
        CoordinationItemEventKind.resolved =>
          l10n.coordinationSemanticBlockerResolved,
        CoordinationItemEventKind.cancelled =>
          l10n.coordinationSemanticBlockerCancelled,
        _ => l10n.coordinationBlockerCardLabel,
      },
    CoordinationItemKind.resolution => switch (eventKind) {
        CoordinationItemEventKind.created =>
          l10n.coordinationSemanticResolutionOpened,
        CoordinationItemEventKind.resolved =>
          l10n.coordinationSemanticResolutionResolved,
        CoordinationItemEventKind.cancelled =>
          l10n.coordinationSemanticResolutionCancelled,
        _ => l10n.coordinationResolutionCardLabel,
      },
    CoordinationItemKind.plan => switch (eventKind) {
        CoordinationItemEventKind.created ||
        CoordinationItemEventKind.updated =>
          l10n.coordinationSemanticPlanOpened,
        CoordinationItemEventKind.superseded =>
          l10n.coordinationSemanticPlanSuperseded,
        CoordinationItemEventKind.resolved =>
          isPlanStep
              ? l10n.coordinationSemanticPlanStepResolved
              : l10n.coordinationSemanticPlanOpened,
        _ => l10n.coordinationPlanCardLabel,
      },
  };
}
