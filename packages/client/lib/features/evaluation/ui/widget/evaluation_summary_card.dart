import 'package:flutter/material.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_summary.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class EvaluationSummaryCard extends StatelessWidget {
  const EvaluationSummaryCard({required this.summary, super.key});

  final EvaluationSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final toneLabel = switch (summary.tone) {
      'positive' => l10n.evaluationTonePositive,
      'negative' => l10n.evaluationToneNegative,
      _ => l10n.evaluationToneMixed,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.evaluationSummaryTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              toneLabel,
              style: theme.textTheme.bodyMedium,
            ),
            if (summary.message.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                summary.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (!summary.suppressed && summary.topReasonTags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in summary.topReasonTags)
                    Chip(
                      label: Text(t, style: theme.textTheme.labelSmall),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
