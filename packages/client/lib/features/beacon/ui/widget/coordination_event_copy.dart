import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_tokens.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/coordination_item/ui/widget/item_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Shared coordination event labels/icons for room timeline and footers.
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

IconData coordinationEventTimelineIcon(
  CoordinationItemKind kind,
  CoordinationItemEventKind eventKind, {
  bool isPlanStep = false,
}) =>
    coordinationItemEventIcon(kind, eventKind, isPlanStep: isPlanStep);

Color coordinationEventTimelineColor(
  TenturaTokens tt,
  CoordinationItemKind kind,
  CoordinationItemEventKind eventKind,
) =>
    coordinationItemEventColor(tt, kind, eventKind);
