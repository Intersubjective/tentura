import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_received.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'received_review_body.dart';

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
                    ReceivedReviewBody(
                      wireValue: row.value,
                      acknowledgedHelpTags: row.acknowledgedHelpTags,
                      note: row.note,
                      reasonTags: row.reasonTags,
                      occurredAt: row.occurredAt,
                    ),
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
