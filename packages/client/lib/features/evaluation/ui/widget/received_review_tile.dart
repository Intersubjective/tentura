import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_received.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_capability_presenter.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_legacy_reason_presenter.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_value_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';

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
    // A future/invalid wire value must remain legible and non-positive; never
    // expose a numeric enum value to the recipient.
    final value =
        EvaluationValue.fromWire(row.value) ?? EvaluationValue.noBasis;
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TenturaAvatar.small(profile: profile),
              SizedBox(width: tt.avatarTextGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                        Flexible(
                          child: TenturaTypeLabel(
                            evaluationReceivedReviewerRoleLabel(
                              l10n,
                              row.reviewerRole,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: tt.tightGap),
                    _ImpactLine(value: value, l10n: l10n),
                    if ((value == EvaluationValue.pos1 ||
                            value == EvaluationValue.pos2) &&
                        row.acknowledgedHelpTags.isNotEmpty) ...[
                      SizedBox(height: tt.tightGap),
                      Text(
                        presentAcknowledgedCapabilities(
                          row.acknowledgedHelpTags,
                          l10n,
                        ),
                        style: TenturaText.status(tt.textMuted),
                      ),
                    ],
                    if (row.note.trim().isNotEmpty) ...[
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
                          for (final reason in row.reasonTags)
                            Text(
                              presentLegacyEvaluationReason(reason, l10n),
                              style: TenturaText.status(tt.textMuted),
                            ),
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
        ),
        if (showDivider) const TenturaHairlineDivider(),
      ],
    );
  }
}

class _ImpactLine extends StatelessWidget {
  const _ImpactLine({required this.value, required this.l10n});
  final EvaluationValue value;
  final L10n l10n;
  @override
  Widget build(BuildContext context) {
    final p = presentEvaluationValue(value, l10n);
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(p.icon, size: context.tt.iconSize, color: colors.primary),
        SizedBox(width: context.tt.iconTextGap),
        Expanded(
          child: Text(p.label, style: TenturaText.status(colors.onSurface)),
        ),
      ],
    );
  }
}
