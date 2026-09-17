import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// How one review target is described above the impact question.
///
/// Every line is localized here: the server never sends user-facing copy (D9).
typedef EvaluationParticipantContext = ({
  /// Main line: who this person was in the request.
  String line,

  /// Second line when their participation ended, else null.
  String? endedLine,

  /// Their help-offer message in quotes, else null.
  String? offerLine,
});

EvaluationParticipantContext presentParticipantContext({
  required L10n l10n,
  required Locale locale,
  required EvaluationParticipant participant,
}) {
  final committedAt = participant.committedAt;
  final forwarderName = participant.forwarderDisplayName;
  final String line;
  if (participant.role == EvaluationParticipantRole.forwarder) {
    line = l10n.evaluationContextForwarder;
  } else if (committedAt != null && forwarderName != null) {
    line = l10n.evaluationContextCommittedVia(
      _formatDate(committedAt, locale),
      forwarderName,
    );
  } else if (committedAt != null) {
    line = l10n.evaluationContextCommitted(_formatDate(committedAt, locale));
  } else {
    // The row was materialized before m0176 recorded a commit time.
    line = l10n.evaluationContextCommittedNoDate;
  }
  final offerMessage = participant.offerMessage;
  return (
    line: line,
    endedLine: participant.isOptional ? l10n.evaluationContextEnded : null,
    offerLine: offerMessage.isEmpty
        ? null
        : l10n.evaluationContextOffer(offerMessage),
  );
}

String _formatDate(DateTime committedAt, Locale locale) =>
    DateFormat.yMMMd(locale.toLanguageTag()).format(committedAt.toLocal());
