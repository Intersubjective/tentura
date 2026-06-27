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
    );

    if (presentation.isHidden) {
      return const SizedBox.shrink();
    }

    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final mutedStyle = theme.textTheme.bodySmall?.copyWith(
      color: tt.textMuted,
    );

    if (presentation.fallbackText != null) {
      return Text(
        presentation.fallbackText!,
        style: bodyStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    if (presentation.blockedOnly && presentation.blockedSegment != null) {
      return _BlockedSegmentRow(
        segment: presentation.blockedSegment!,
        bodyStyle: bodyStyle,
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
            bodyStyle: bodyStyle,
            mutedStyle: mutedStyle,
          ),
          if (presentation.segments.isNotEmpty) Text('·', style: mutedStyle),
        ],
        for (var i = 0; i < presentation.segments.length; i++) ...[
          if (i > 0) Text('·', style: mutedStyle),
          _SegmentChip(
            segment: presentation.segments[i],
            bodyStyle: bodyStyle,
            accentColor: tt.info,
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
    required this.bodyStyle,
    required this.mutedStyle,
  });

  final BeaconYouBlockedSegmentPresentation segment;
  final TextStyle? bodyStyle;
  final TextStyle? mutedStyle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: segment.semanticsLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (segment.raiserAvatar != null) ...[
            segment.raiserAvatar!,
            const SizedBox(width: 6),
          ],
          Text(segment.label, style: bodyStyle),
          if (segment.elapsedLabel != null) ...[
            Text(' · ', style: mutedStyle),
            Text(
              segment.elapsedLabel!,
              style: bodyStyle?.copyWith(
                fontFeatures: const [
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.segment,
    required this.bodyStyle,
    required this.accentColor,
  });

  final BeaconYouSegmentPresentation segment;
  final TextStyle? bodyStyle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final label = segment.label?.trim();
    final hasLabel = label != null && label.isNotEmpty;
    final children = <Widget>[
      Icon(segment.icon, size: 16, color: bodyStyle?.color),
    ];
    if (hasLabel) {
      children.addAll([
        const SizedBox(width: 4),
        Text(label, style: bodyStyle),
      ]);
    } else {
      children.addAll([
        const SizedBox(width: 4),
        Text('${segment.count}', style: bodyStyle),
      ]);
    }
    if (segment.newCount > 0) {
      children.addAll([
        const SizedBox(width: 4),
        Text(
          l10n.beaconYouNewCount(segment.newCount),
          style: bodyStyle?.copyWith(
            color: accentColor,
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
