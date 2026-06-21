import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/open_blocker_cue.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_you_presentation.dart';
import 'package:tentura/ui/utils/duration_format.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';

class BeaconYouResponsibilityLine extends StatelessWidget {
  const BeaconYouResponsibilityLine({
    required this.beacon,
    required this.responsibility,
    required this.isAuthorOrSteward,
    this.showNewBadges = true,
    this.onTap,
    this.viewerUserId = '',
    this.openBlocker,
    this.phaseResult,
    super.key,
  });

  final Beacon beacon;
  final CoordinationResponsibility responsibility;
  final bool isAuthorOrSteward;
  final bool showNewBadges;
  final VoidCallback? onTap;
  final String viewerUserId;
  final OpenBlockerCue? openBlocker;
  final BeaconCoordinationPhaseResult? phaseResult;

  static const double _compactWrapWidth = 320;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final collapse = context.windowClass == WindowClass.compact &&
            constraints.maxWidth < _compactWrapWidth;
        final blockedSegment = _buildBlockedSegment(context, l10n);
        final emptyFallback = deriveBeaconYouEmptyFallbackFromBeacon(
          beacon: beacon,
          responsibility: responsibility,
          isAuthorOrSteward: isAuthorOrSteward,
          compactSurface: collapse,
          phaseResult: phaseResult,
          openBlocker: openBlocker,
          viewerUserId: viewerUserId,
        );
        final presentation = buildBeaconYouPresentation(
          l10n,
          responsibility,
          collapse: collapse,
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

        Widget content;
        if (presentation.fallbackText != null) {
          content = Text(
            presentation.fallbackText!,
            style: bodyStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        } else if (presentation.blockedOnly && presentation.blockedSegment != null) {
          content = _BlockedSegmentRow(
            segment: presentation.blockedSegment!,
            bodyStyle: bodyStyle,
            mutedStyle: mutedStyle,
          );
        } else {
          content = Wrap(
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
                if (presentation.segments.isNotEmpty)
                  Text('·', style: mutedStyle),
              ],
              for (var i = 0; i < presentation.segments.length; i++) ...[
                if (i > 0)
                  Text('·', style: mutedStyle),
                _SegmentChip(
                  segment: presentation.segments[i],
                  bodyStyle: bodyStyle,
                  accentColor: tt.info,
                ),
              ],
            ],
          );
        }

        final row = BeaconHudIconRow(
          leadIcon: BeaconHudRowIcons.you,
          semanticsLabel: l10n.beaconHudYouLabel,
          leadAlign: presentation.fallbackText != null
              ? BeaconHudRowLeadAlign.center
              : BeaconHudRowLeadAlign.start,
          minRowHeight: presentation.fallbackText != null
              ? kBeaconHudRowMinHeight
              : null,
          body: content,
        );

        if (onTap == null) {
          return row;
        }

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: Alignment.centerLeft,
                child: row,
              ),
            ),
          ),
        );
      },
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
              style: bodyStyle?.copyWith(fontFeatures: const [
                FontFeature.tabularFigures(),
              ]),
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
    final children = <Widget>[
      Icon(segment.icon, size: 16, color: bodyStyle?.color),
      const SizedBox(width: 4),
      Text('${segment.count}', style: bodyStyle),
    ];
    if (segment.label != null && segment.label!.isNotEmpty) {
      children.add(Text(' ${segment.label}', style: bodyStyle));
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
