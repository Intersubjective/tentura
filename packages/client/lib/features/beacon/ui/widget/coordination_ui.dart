import 'dart:convert' show jsonDecode;

import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// --- Semantic colors (on neutral [ColorScheme.surface] / body text) ------------
//
// Beacon coordination (beacon.coordination_status):
//   noCommitmentsYet          -> onSurfaceVariant  (idle)
//   commitmentsWaitingForReview -> primary         (action / review)
//   moreOrDifferentHelpNeeded -> error             (gap)
//   enoughHelpCommitted     -> tertiary           (satisfied)
//
// Per-commitment author reaction (response_type):
//   useful                  -> tertiary
//   overlapping             -> secondary
//   needDifferentSkill      -> error
//   needCoordination        -> primary
//   notSuitable             -> error
//
// Pills: use [coordinationResponseColor] for tinted fill; use
// [coordinationResponseOnSurfaceColor] for label ink so it matches list rows.
// ----------------------------------------------------------------------------

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

Color coordinationStatusOnSurfaceColor(
  ColorScheme scheme,
  BeaconCoordinationStatus s,
) =>
    switch (s) {
      BeaconCoordinationStatus.noCommitmentsYet => scheme.onSurfaceVariant,
      BeaconCoordinationStatus.commitmentsWaitingForReview => scheme.primary,
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded => scheme.error,
      BeaconCoordinationStatus.enoughHelpCommitted => scheme.tertiary,
    };

/// Dominant per-commitment response takes precedence; otherwise [beaconStatus].
Color coordinationContextOnSurfaceColor(
  ColorScheme scheme, {
  required BeaconCoordinationStatus beaconStatus,
  CoordinationResponseType? dominantResponse,
}) {
  if (dominantResponse != null) {
    return coordinationResponseOnSurfaceColor(scheme, dominantResponse);
  }
  return coordinationStatusOnSurfaceColor(scheme, beaconStatus);
}

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

/// Tinted pill fill; pair with [coordinationResponseOnSurfaceColor] for the label
/// so chip text matches status lines (avoid `fg` on neutral surfaces).
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

/// Parses `beacon_commitment.help_type`: a single slug, or JSON array (server
/// stores jsonEncode of selected slugs; see server CommitmentRepository).
List<String> commitmentHelpTypeSlugs(String? wire) {
  final t = wire?.trim() ?? '';
  if (t.isEmpty) return [];
  if (t.startsWith('[')) {
    try {
      final decoded = jsonDecode(t);
      if (decoded is List) {
        return decoded
            .map((e) => '$e'.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } on Object {
      // Malformed JSON; fall through to single slug.
    }
  }
  return [t];
}

String? helpTypeLabel(L10n l10n, String? wireKey) {
  if (wireKey == null || wireKey.isEmpty) return null;
  final slugs = commitmentHelpTypeSlugs(wireKey);
  if (slugs.isEmpty) return null;
  final parts = <String>[];
  for (final s in slugs) {
    parts.add(CapabilityTag.fromSlug(s)?.labelOf(l10n) ?? s);
  }
  return parts.join(' · ');
}
