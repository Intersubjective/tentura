import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/ui/l10n/l10n.dart';

String? activityForwardOutcomeLabel(
  L10n l10n,
  AttentionForwardOutcome? outcome,
) {
  return switch (outcome) {
    AttentionForwardOutcome.helping => l10n.activityForwardOutcomeHelping,
    AttentionForwardOutcome.watching => l10n.activityForwardOutcomeWatching,
    AttentionForwardOutcome.notInterested =>
      l10n.activityForwardOutcomeNotInterested,
    AttentionForwardOutcome.closedBeforeResponse =>
      l10n.activityForwardOutcomeClosed,
    AttentionForwardOutcome.deletedBeforeResponse =>
      l10n.activityForwardOutcomeDeleted,
    null => null,
  };
}
