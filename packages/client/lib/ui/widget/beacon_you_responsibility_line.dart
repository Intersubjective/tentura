import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/open_blocker_cue.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_you_presentation.dart';
import 'package:tentura/ui/utils/duration_format.dart';

/// YOU responsibility body for metadata table rows (no lead icon).
class BeaconYouResponsibilityLine extends StatelessWidget {
  const BeaconYouResponsibilityLine({
    required this.beacon,
    required this.responsibility,
    required this.isAuthorOrSteward,
    required this.authorUnreviewedHelpOfferCount,
    required this.tableRowWidth,
    this.showNewBadges = true,
    this.viewerUserId = '',
    this.openBlocker,
    this.phaseResult,
    this.isAwaitingAuthorReview = false,
    super.key,
  });

  final Beacon beacon;
  final CoordinationResponsibility responsibility;
  final bool isAuthorOrSteward;
  final int authorUnreviewedHelpOfferCount;
  final double tableRowWidth;
  final bool showNewBadges;
  final String viewerUserId;
  final OpenBlockerCue? openBlocker;
  final BeaconCoordinationPhaseResult? phaseResult;
  final bool isAwaitingAuthorReview;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final collapse = beaconYouCompactSurface(context, tableRowWidth);
    final isViewerBlocked = shouldShowBlockedYouSegment(
      phaseResult: phaseResult,
      openBlocker: openBlocker,
      viewerUserId: viewerUserId,
      responsibility: responsibility,
    );
    final situationInput = buildBeaconYouSituationInput(
      beacon: beacon,
      isAuthorOrSteward: isAuthorOrSteward,
      othersOpenCount: responsibility.othersOpenCount,
      compactSurface: collapse,
      hasRoomObligations: responsibility.hasAny,
      authorUnreviewedHelpOfferCount: authorUnreviewedHelpOfferCount,
      viewerBlocked: isViewerBlocked,
      isAwaitingAuthorReview: isAwaitingAuthorReview,
      rowHarmony: phaseResult?.rowHarmony ?? BeaconPhaseRowHarmony.empty,
    );
    final blockedSegment = _buildBlockedSegment(context, l10n);
    final emptyFallback = deriveBeaconYouEmptyFallback(input: situationInput);
    final presentation = buildBeaconYouPresentation(
      l10n,
      responsibility,
      collapse: collapse,
      situationInput: situationInput,
      emptyFallback: emptyFallback,
      showNewBadges: showNewBadges,
      blockedSegment: blockedSegment,
      phaseResult: phaseResult,
    );

    if (presentation.isHidden) {
      return const SizedBox.shrink();
    }

    final contentStyle = theme.textTheme.bodySmall!.copyWith(
      color: scheme.onSurface,
    );
    final mutedStyle = theme.textTheme.bodySmall!.copyWith(
      color: tt.textMuted,
    );

    if (presentation.fallbackText != null) {
      return TenturaStatusText(
        presentation.fallbackText!,
        tone: presentation.fallbackTone,
        maxLines: null,
        overflow: TextOverflow.visible,
      );
    }
    if (presentation.blockedOnly && presentation.blockedSegment != null) {
      return _BlockedSegmentRow(
        segment: presentation.blockedSegment!,
        mutedStyle: mutedStyle,
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (presentation.blockedSegment != null) ...[
          _BlockedSegmentRow(
            segment: presentation.blockedSegment!,
            mutedStyle: mutedStyle,
          ),
          if (presentation.segments.isNotEmpty) Text('·', style: mutedStyle),
        ],
        for (var i = 0; i < presentation.segments.length; i++) ...[
          if (i > 0) Text('·', style: mutedStyle),
          _SegmentChip(
            segment: presentation.segments[i],
            contentStyle: contentStyle,
            infoColor: tt.info,
          ),
        ],
      ],
    );
  }

  BeaconYouBlockedSegmentPresentation? _buildBlockedSegment(
    BuildContext context,
    L10n l10n,
  ) {
    if (!shouldShowBlockedYouSegment(
      phaseResult: phaseResult,
      openBlocker: openBlocker,
      viewerUserId: viewerUserId,
      responsibility: responsibility,
    )) {
      return null;
    }
    final cue = openBlocker!;
    final raiser = cue.raiser;
    final name = raiser?.shownName ?? '';
    final elapsed = formatCompactDurationRemaining(
      DateTime.now().toUtc().difference(cue.raisedAt.toUtc()),
      l10n,
    );
    Widget? avatar;
    if (raiser != null && raiser.id.isNotEmpty) {
      avatar = TenturaAvatar(
        profile: raiser,
        sizeBucket: TenturaAvatarSize.tiny,
        size: context.tt.metadataAvatarSize,
      );
    }
    return BeaconYouBlockedSegmentPresentation(
      label: l10n.beaconYouBlockedGeneric,
      semanticsLabel: l10n.beaconYouBlockedSemantics(
        name.isEmpty ? '…' : name,
        elapsed,
      ),
      raiserAvatar: avatar,
      elapsedLabel: elapsed,
    );
  }
}

class _BlockedSegmentRow extends StatelessWidget {
  const _BlockedSegmentRow({
    required this.segment,
    required this.mutedStyle,
  });

  final BeaconYouBlockedSegmentPresentation segment;
  final TextStyle? mutedStyle;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final labelStyle = (mutedStyle ?? const TextStyle()).copyWith(
      color: tenturaToneColor(tt, segment.labelTone),
    );
    final elapsedStyle = (mutedStyle ?? const TextStyle()).copyWith(
      color: tenturaToneColor(tt, segment.elapsedTone),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Semantics(
      label: segment.semanticsLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (segment.raiserAvatar != null) ...[
            segment.raiserAvatar!,
            const SizedBox(width: 6),
          ],
          Text(segment.label, style: labelStyle),
          if (segment.elapsedLabel != null) ...[
            Text(' · ', style: mutedStyle),
            Text(segment.elapsedLabel!, style: elapsedStyle),
          ],
        ],
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.segment,
    required this.contentStyle,
    required this.infoColor,
  });

  final BeaconYouSegmentPresentation segment;
  final TextStyle? contentStyle;
  final Color infoColor;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final label = segment.label?.trim();
    final hasLabel = label != null && label.isNotEmpty;
    final segmentColor = segment.tone == null
        ? contentStyle?.color
        : tenturaToneColor(tt, segment.tone!);
    final segmentStyle = contentStyle?.copyWith(color: segmentColor);
    final children = <Widget>[
      Icon(segment.icon, size: 16, color: segmentColor),
    ];
    if (hasLabel) {
      children.addAll([
        const SizedBox(width: 4),
        Text(label, style: segmentStyle),
      ]);
    } else {
      children.addAll([
        const SizedBox(width: 4),
        Text('${segment.count}', style: segmentStyle),
      ]);
    }
    if (segment.newCount > 0) {
      children.addAll([
        const SizedBox(width: 4),
        Text(
          l10n.beaconYouNewCount(segment.newCount),
          style: segmentStyle?.copyWith(
            color: infoColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ]);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
