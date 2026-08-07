import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_received.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';

/// Maps server `reviewerRole` int (0–3) to a display label.
String evaluationReceivedReviewerRoleLabel(L10n l10n, int reviewerRole) =>
    switch (reviewerRole) {
      0 => l10n.evaluationRoleAuthor,
      1 => l10n.evaluationRoleHelpOfferer,
      2 => l10n.evaluationRoleForwarder,
      3 => l10n.evaluationRoleFormerCommitter,
      _ => l10n.evaluationRoleForwarder,
    };

class ReceivedReviewTile extends StatelessWidget {
  const ReceivedReviewTile({
    required this.row,
    super.key,
    this.showDivider = true,
  });

  final EvaluationReceivedRow row;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final profile = Profile(
      id: row.reviewerId,
      displayName: row.reviewerDisplayName,
      image: row.reviewerImageId.isNotEmpty
          ? ImageEntity(id: row.reviewerImageId, authorId: row.reviewerId)
          : null,
    );
    final ageLabel = compactRelativeTimeAgo(
      when: row.occurredAt,
      now: DateTime.now(),
      l10n: l10n,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: tt.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TenturaAvatar.small(profile: profile),
                  SizedBox(width: tt.avatarTextGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                row.reviewerDisplayName,
                                style: TenturaText.title(
                                  Theme.of(context).colorScheme.onSurface,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(width: tt.tightGap),
                            TenturaTypeLabel(
                              evaluationReceivedReviewerRoleLabel(
                                l10n,
                                row.reviewerRole,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: tt.tightGap),
                        _ReceivedReviewTrustLine(
                          trustTone: row.trustTone,
                          l10n: l10n,
                        ),
                        if (row.note.isNotEmpty) ...[
                          SizedBox(height: tt.rowGap),
                          Text(
                            row.note,
                            style: TenturaText.body(
                              Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                        if (row.reasonTags.isNotEmpty) ...[
                          SizedBox(height: tt.rowGap),
                          Wrap(
                            spacing: tt.tightGap,
                            runSpacing: tt.tightGap,
                            children: [
                              for (final tag in row.reasonTags)
                                TenturaTypeLabel(tag),
                            ],
                          ),
                        ],
                        SizedBox(height: tt.rowGap),
                        TenturaMetaText(ageLabel),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showDivider) const TenturaHairlineDivider(),
      ],
    );
  }
}

class _ReceivedReviewTrustLine extends StatelessWidget {
  const _ReceivedReviewTrustLine({
    required this.trustTone,
    required this.l10n,
  });

  final EvaluationReceivedTrustTone trustTone;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final label = switch (trustTone) {
      EvaluationReceivedTrustTone.up => l10n.evaluationReceivedTrustUpLabel,
      EvaluationReceivedTrustTone.down => l10n.evaluationReceivedTrustDownLabel,
      EvaluationReceivedTrustTone.noChange =>
        l10n.evaluationReceivedNeutralLabel,
      EvaluationReceivedTrustTone.noBasis => l10n.evaluationReceivedNoBasisLabel,
    };

    if (trustTone == EvaluationReceivedTrustTone.noBasis) {
      return Row(
        children: [
          _TrustToneGlyph(
            icon: Icons.help_outline,
            backgroundColor: tt.surface,
            iconColor: tt.textFaint,
          ),
          SizedBox(width: tt.iconTextGap),
          Expanded(
            child: Text(
              label,
              style: TenturaText.status(tt.textFaint),
            ),
          ),
        ],
      );
    }

    final tone = switch (trustTone) {
      EvaluationReceivedTrustTone.up => TenturaTone.good,
      EvaluationReceivedTrustTone.down => TenturaTone.danger,
      EvaluationReceivedTrustTone.noChange => TenturaTone.neutral,
      EvaluationReceivedTrustTone.noBasis => TenturaTone.neutral,
    };
    final icon = switch (trustTone) {
      EvaluationReceivedTrustTone.up => Icons.arrow_upward,
      EvaluationReceivedTrustTone.down => Icons.arrow_downward,
      EvaluationReceivedTrustTone.noChange => Icons.remove,
      EvaluationReceivedTrustTone.noBasis => Icons.help_outline,
    };
    final iconColor = tenturaToneColor(tt, tone);
    final backgroundColor = iconColor.withValues(alpha: 0.12);

    return Row(
      children: [
        _TrustToneGlyph(
          icon: icon,
          backgroundColor: backgroundColor,
          iconColor: iconColor,
        ),
        SizedBox(width: tt.iconTextGap),
        Expanded(
          child: TenturaStatusText(
            label,
            tone: tone,
            maxLines: null,
          ),
        ),
      ],
    );
  }
}

class _TrustToneGlyph extends StatelessWidget {
  const _TrustToneGlyph({
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final dimension = tt.iconSize;
    return SizedBox.square(
      dimension: dimension,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(dimension / 2),
        ),
        child: Icon(
          icon,
          size: dimension * 0.55,
          color: iconColor,
        ),
      ),
    );
  }
}
