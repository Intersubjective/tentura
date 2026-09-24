import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_capability_presenter.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_legacy_reason_presenter.dart';
import 'package:tentura/features/evaluation/ui/presenter/evaluation_value_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';

/// Shared body of a received review: impact line, acknowledged help, note,
/// legacy reasons and age. Callers render their own header above it.
class ReceivedReviewBody extends StatelessWidget {
  const ReceivedReviewBody({
    required this.wireValue,
    required this.acknowledgedHelpTags,
    required this.note,
    required this.reasonTags,
    required this.occurredAt,
    super.key,
  });

  final int wireValue;
  final List<String> acknowledgedHelpTags;
  final String note;
  final List<String> reasonTags;
  final DateTime occurredAt;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    // A future/invalid wire value must remain legible and non-positive; never
    // expose a numeric enum value to the recipient.
    final value = EvaluationValue.fromWire(wireValue) ?? EvaluationValue.noBasis;
    final positive =
        value == EvaluationValue.pos1 || value == EvaluationValue.pos2;
    final impact = presentEvaluationValue(value, l10n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              impact.emoji,
              style: TextStyle(fontSize: tt.iconSize, height: 1),
            ),
            SizedBox(width: tt.iconTextGap),
            Expanded(
              child: Text(impact.label, style: TenturaText.status(onSurface)),
            ),
          ],
        ),
        if (positive && acknowledgedHelpTags.isNotEmpty) ...[
          SizedBox(height: tt.tightGap),
          Text(
            presentAcknowledgedCapabilities(acknowledgedHelpTags, l10n),
            style: TenturaText.status(tt.textMuted),
          ),
        ],
        if (note.trim().isNotEmpty) ...[
          SizedBox(height: tt.rowGap),
          Text(note, style: TenturaText.body(onSurface)),
        ],
        if (reasonTags.isNotEmpty) ...[
          SizedBox(height: tt.rowGap),
          Wrap(
            spacing: tt.tightGap,
            runSpacing: tt.tightGap,
            children: [
              for (final reason in reasonTags)
                Text(
                  presentLegacyEvaluationReason(reason, l10n),
                  style: TenturaText.status(tt.textMuted),
                ),
            ],
          ),
        ],
        SizedBox(height: tt.rowGap),
        TenturaMetaText(
          compactRelativeTimeAgo(
            when: occurredAt,
            now: DateTime.now(),
            l10n: l10n,
          ),
        ),
      ],
    );
  }
}
