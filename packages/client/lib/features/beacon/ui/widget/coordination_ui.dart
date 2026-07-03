import 'dart:convert' show jsonDecode;
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// --- Semantic colors (on neutral [ColorScheme.surface] / body text) ------------
//
// Beacon coordination (beacon.coordination_status):
//   neutral                  -> onSurfaceVariant  (idle)
//   moreOrDifferentHelpNeeded -> error             (gap)
//   enoughHelpOffered     -> tertiary           (satisfied)
//
// Per-help-offer author reaction (response_type) — prefer [coordinationResponseInkColor]:
//   useful                  -> good (green)
//   overlapping             -> info (sky)
//   needDifferentSkill      -> warn (amber, semi-action)
//   needCoordination        -> warn (amber, semi-action)
//   notSuitable             -> textMuted (grey, terminal)
//   pending (null)          -> danger (red, author must review)
//
// Pills: use [coordinationResponsePillColor] for tinted fill; ink via
// [coordinationResponseInkColor] on neutral surfaces.
// ----------------------------------------------------------------------------

String coordinationStatusLabel(L10n l10n, BeaconStatus s) =>
    switch (s) {
      BeaconStatus.open => l10n.coordinationNeutral,
      BeaconStatus.needsMoreHelp => l10n.coordinationMoreHelpNeeded,
      BeaconStatus.enoughHelp => l10n.coordinationEnoughHelp,
      _ => l10n.coordinationNeutral,
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

/// Ink on neutral card/sheet surfaces (People tab footer, picker rows).
Color coordinationResponseInkColor(TenturaTokens tt, CoordinationResponseType r) =>
    switch (r) {
      CoordinationResponseType.useful => tt.good,
      CoordinationResponseType.overlapping => tt.info,
      CoordinationResponseType.needCoordination => tt.warn,
      CoordinationResponseType.needDifferentSkill => tt.warn,
      CoordinationResponseType.notSuitable => tt.textMuted,
    };

TenturaTone coordinationResponseTone(CoordinationResponseType r) => switch (r) {
      CoordinationResponseType.useful => TenturaTone.good,
      CoordinationResponseType.overlapping => TenturaTone.info,
      CoordinationResponseType.needCoordination => TenturaTone.warn,
      CoordinationResponseType.needDifferentSkill => TenturaTone.warn,
      CoordinationResponseType.notSuitable => TenturaTone.neutral,
    };

Color coordinationStatusOnSurfaceColor(
  ColorScheme scheme,
  BeaconStatus s,
) =>
    switch (s) {
      BeaconStatus.open => scheme.onSurfaceVariant,
      BeaconStatus.needsMoreHelp => scheme.error,
      BeaconStatus.enoughHelp => scheme.tertiary,
      _ => scheme.onSurfaceVariant,
    };

/// Dominant per-help-offer response takes precedence; otherwise [beaconStatus].
Color coordinationContextOnSurfaceColor(
  ColorScheme scheme, {
  required BeaconStatus beaconStatus,
  CoordinationResponseType? dominantResponse,
  TenturaTokens? tokens,
}) {
  if (dominantResponse != null) {
    if (tokens != null) {
      return coordinationResponseInkColor(tokens, dominantResponse);
    }
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
      CoordinationResponseType.needDifferentSkill => scheme.onSurfaceVariant,
      CoordinationResponseType.needCoordination => scheme.onSurfaceVariant,
      CoordinationResponseType.notSuitable => scheme.onSurfaceVariant,
    };

/// Tinted pill fill; pair with [coordinationResponseInkColor] for label ink.
({Color bg, Color fg}) coordinationResponsePillColor(
  TenturaTokens tt,
  CoordinationResponseType r,
) =>
    switch (r) {
      CoordinationResponseType.useful => (
          bg: tt.good.withValues(alpha: 0.12),
          fg: tt.good,
        ),
      CoordinationResponseType.overlapping => (
          bg: tt.info.withValues(alpha: 0.12),
          fg: tt.info,
        ),
      CoordinationResponseType.needDifferentSkill => (
          bg: tt.warn.withValues(alpha: 0.12),
          fg: tt.warn,
        ),
      CoordinationResponseType.needCoordination => (
          bg: tt.warn.withValues(alpha: 0.12),
          fg: tt.warn,
        ),
      CoordinationResponseType.notSuitable => (
          bg: tt.borderSubtle,
          fg: tt.textMuted,
        ),
    };

/// Tinted pill fill using [ColorScheme] containers (legacy).
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
          bg: scheme.surfaceContainerHighest,
          fg: scheme.onSurfaceVariant,
        ),
      CoordinationResponseType.needCoordination => (
          bg: scheme.surfaceContainerHighest,
          fg: scheme.onSurfaceVariant,
        ),
      CoordinationResponseType.notSuitable => (
          bg: scheme.surfaceContainerHighest,
          fg: scheme.onSurfaceVariant,
        ),
    };

String? withdrawReasonLabel(L10n l10n, String? wireKey) {
  if (wireKey == null || wireKey.isEmpty) return null;
  return switch (wireKey) {
    'cannot_do_it' => l10n.withdrawCantDoIt,
    'timing' => l10n.withdrawTimingChanged,
    'wrong_fit' => l10n.withdrawWrongFit,
    'someone_else' => l10n.withdrawSomeoneElseTookOver,
    'other' => l10n.withdrawOther,
    _ => wireKey,
  };
}

/// Parses `beacon_help_offers.help_type`: a single slug, or JSON array (server
/// stores jsonEncode of selected slugs; see server HelpOfferRepository).
List<String> helpOfferTypeSlugs(String? wire) {
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
  final slugs = helpOfferTypeSlugs(wireKey);
  if (slugs.isEmpty) return null;
  final parts = <String>[];
  for (final s in slugs) {
    parts.add(CapabilityTag.fromSlug(s)?.labelOf(l10n) ?? s);
  }
  return parts.join(' · ');
}
