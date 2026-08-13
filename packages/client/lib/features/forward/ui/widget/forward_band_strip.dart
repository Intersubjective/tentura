import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/capability/projection_tier.dart';
import 'package:tentura/domain/capability/tag_projection.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'forward_recipient_row.dart';
import '../model/forward_recipient_row_host.dart';

/// Contextual evidence band above the MR-ordered forward list (architecture §8).
class ForwardBandStrip extends StatelessWidget {
  const ForwardBandStrip({
    required this.band,
    required this.candidates,
    required this.selectedIds,
    required this.onToggle,
    required this.onEditReasons,
    required this.recipientReasons,
    this.beacon,
    this.onTogglePersonalizedNoteEditor,
    this.personalizedNoteEditorOpenIds = const {},
    super.key,
  });

  final List<ForwardBandRow> band;
  final List<ForwardCandidate> candidates;
  final Set<String> selectedIds;
  final void Function(String userId) onToggle;
  final void Function(String userId) onEditReasons;
  final Map<String, List<String>> recipientReasons;
  final Beacon? beacon;
  final void Function(String userId)? onTogglePersonalizedNoteEditor;
  final Set<String> personalizedNoteEditorOpenIds;

  static String tagSlugDisplayLabel(L10n l10n, String slug) {
    final tag = CapabilityTag.fromSlug(slug.trim());
    return tag?.labelOf(l10n) ?? slug.trim();
  }

  static String joinedTagLabels(L10n l10n, List<TagProjection> labels) {
    return labels
        .map((label) => tagSlugDisplayLabel(l10n, label.tagSlug))
        .join(' · ');
  }

  static String tierEvidenceCopy(
    L10n l10n,
    ProjectionTier tier,
    List<TagProjection> labels,
  ) {
    final tagText = joinedTagLabels(l10n, labels);
    return switch (tier) {
      ProjectionTier.ownOutcome => l10n.forwardBandTierOwnOutcome(tagText),
      ProjectionTier.ownRouting => l10n.forwardBandTierOwnRouting(tagText),
      ProjectionTier.networkOutcome =>
        l10n.forwardBandTierNetworkOutcome(tagText),
      ProjectionTier.networkSeed => l10n.forwardBandTierNetworkSeed(tagText),
    };
  }

  static TenturaTone tierEvidenceTone(ProjectionTier tier) => switch (tier) {
    ProjectionTier.ownOutcome => TenturaTone.good,
    ProjectionTier.ownRouting => TenturaTone.info,
    ProjectionTier.networkOutcome => TenturaTone.info,
    ProjectionTier.networkSeed => TenturaTone.neutral,
  };

  ForwardCandidate? _candidateFor(String userId) {
    for (final candidate in candidates) {
      if (candidate.id == userId) {
        return candidate;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (band.isEmpty) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final needs = beacon?.needs ?? const {};
    final evidenceRows = band.where((row) => !row.isExploration).toList();
    final explorationRows = band.where((row) => row.isExploration).toList();

    final children = <Widget>[
      Padding(
        padding: EdgeInsets.fromLTRB(
          tt.screenHPadding,
          tt.rowGap,
          tt.screenHPadding,
          tt.rowGap * 0.5,
        ),
        child: Text(
          l10n.forwardBandSectionTitle,
          style: theme.textTheme.titleSmall,
        ),
      ),
    ];

    void addBandRow(ForwardBandRow row, {required bool exploration}) {
      final candidate = _candidateFor(row.userId);
      if (candidate == null) {
        return;
      }
      final tierLabel = exploration || row.rowTier == null || row.labels.isEmpty
          ? null
          : tierEvidenceCopy(l10n, row.rowTier!, row.labels);
      children.add(
        ForwardRecipientRow(
          host: ForwardRecipientRowHost.pickerBand,
          candidate: candidate,
          requiredCapabilitySlugs: needs,
          isSelected: selectedIds.contains(candidate.id),
          onToggle: () => onToggle(candidate.id),
          personalizedNoteEditorOpen:
              personalizedNoteEditorOpenIds.contains(candidate.id),
          onTogglePersonalizedNoteEditor: onTogglePersonalizedNoteEditor == null
              ? null
              : () => onTogglePersonalizedNoteEditor!(candidate.id),
          reasonSlugs: recipientReasons[candidate.id] ?? const [],
          onEditReasons: () => onEditReasons(candidate.id),
          tierEvidenceLabel: tierLabel,
          tierEvidenceTone: row.rowTier == null
              ? null
              : tierEvidenceTone(row.rowTier!),
          showPresenceLine: !exploration,
        ),
      );
    }

    for (var i = 0; i < evidenceRows.length; i++) {
      if (i > 0) {
        children.add(const TenturaHairlineDivider());
      }
      addBandRow(evidenceRows[i], exploration: false);
    }

    if (evidenceRows.isNotEmpty && explorationRows.isNotEmpty) {
      children.addAll([
        const TenturaHairlineDivider(),
        Padding(
          padding: EdgeInsets.fromLTRB(
            tt.screenHPadding,
            tt.rowGap,
            tt.screenHPadding,
            tt.rowGap * 0.5,
          ),
          child: Text(
            l10n.forwardBandExplorationDivider,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
        ),
      ]);
    }

    for (var i = 0; i < explorationRows.length; i++) {
      if (i > 0 || evidenceRows.isNotEmpty) {
        children.add(const TenturaHairlineDivider());
      }
      addBandRow(explorationRows[i], exploration: true);
    }

    children.add(const TenturaHairlineDivider());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
