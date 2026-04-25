import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/ui/l10n/l10n.dart';

String coordinationStatusLabel(L10n l10n, BeaconCoordinationStatus s) =>
    switch (s) {
      BeaconCoordinationStatus.noCommitmentsYet => l10n.coordinationNoCommitments,
      BeaconCoordinationStatus.commitmentsWaitingForReview =>
        l10n.coordinationWaitingForReview,
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded =>
        l10n.coordinationMoreHelpNeeded,
      BeaconCoordinationStatus.enoughHelpCommitted => l10n.coordinationEnoughHelp,
    };

String? coordinationResponseLabel(L10n l10n, CoordinationResponseType? r) {
  if (r == null) return null;
  return switch (r) {
    CoordinationResponseType.useful => l10n.coordinationUseful,
    CoordinationResponseType.overlapping => l10n.coordinationOverlapping,
    CoordinationResponseType.needDifferentSkill =>
      l10n.coordinationNeedDifferentSkill,
    CoordinationResponseType.needCoordination =>
      l10n.coordinationNeedCoordination,
      CoordinationResponseType.notSuitable => l10n.coordinationNotSuitable,
  };
}

Color coordinationStatusColor(ColorScheme scheme, BeaconCoordinationStatus s) =>
    switch (s) {
      BeaconCoordinationStatus.noCommitmentsYet => scheme.onSurfaceVariant,
      BeaconCoordinationStatus.commitmentsWaitingForReview => scheme.primary,
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded => scheme.error,
      BeaconCoordinationStatus.enoughHelpCommitted => scheme.tertiary,
    };

/// Main palette roles for emphasized text on a neutral card (e.g. My Work status strip).
/// Pills use [coordinationResponseColor] `fg` on tinted backgrounds; for plain `Text` on
/// [ColorScheme.surface], use this instead of those container-foreground colors.
Color coordinationResponseOnSurfaceColor(
  ColorScheme scheme,
  CoordinationResponseType r,
) =>
    switch (r) {
      CoordinationResponseType.useful => scheme.tertiary,
      CoordinationResponseType.overlapping => scheme.secondary,
      CoordinationResponseType.needDifferentSkill => scheme.error,
      CoordinationResponseType.needCoordination => scheme.primary,
      CoordinationResponseType.notSuitable => scheme.error,
    };

/// Background / foreground for per-commitment author reaction (pills on tinted fill).
({Color bg, Color fg}) coordinationResponseColor(
  ColorScheme scheme,
  CoordinationResponseType r,
) =>
    switch (r) {
      CoordinationResponseType.useful => (
          bg: scheme.tertiaryContainer,
          fg: scheme.onTertiaryContainer,
        ),
      CoordinationResponseType.overlapping => (
          bg: scheme.secondaryContainer,
          fg: scheme.onSecondaryContainer,
        ),
      CoordinationResponseType.needDifferentSkill => (
          bg: scheme.errorContainer,
          fg: scheme.onErrorContainer,
        ),
      CoordinationResponseType.needCoordination => (
          bg: scheme.primaryContainer,
          fg: scheme.onPrimaryContainer,
        ),
      CoordinationResponseType.notSuitable => (
          bg: scheme.errorContainer,
          fg: scheme.onErrorContainer,
        ),
    };

String? uncommitReasonLabel(L10n l10n, String? wireKey) {
  if (wireKey == null || wireKey.isEmpty) return null;
  return switch (wireKey) {
    'cannot_do_it' => l10n.uncommitCantDoIt,
    'timing' => l10n.uncommitTimingChanged,
    'wrong_fit' => l10n.uncommitWrongFit,
    'someone_else' => l10n.uncommitSomeoneElseTookOver,
    'other' => l10n.uncommitOther,
    _ => wireKey,
  };
}

String? helpTypeLabel(L10n l10n, String? wireKey) {
  if (wireKey == null || wireKey.isEmpty) return null;
  return switch (wireKey) {
    'money' => l10n.helpTypeMoney,
    'time' => l10n.helpTypeTime,
    'skill' => l10n.helpTypeSkill,
    'verification' => l10n.helpTypeVerification,
    'contact' => l10n.helpTypeContact,
    'transport' => l10n.helpTypeTransport,
    'other' => l10n.helpTypeOther,
    _ => wireKey,
  };
}
