import 'dart:convert';

import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// #367: the stage of an accepted helper, carried by a `helping` forward row
/// in its presentation payload (`helperStage`, with `roleLabel`). An absent,
/// unknown or unreadable stage keeps the plain "You offered help".
String? activityForwardOutcomeLabel(
  L10n l10n,
  AttentionForwardOutcome? outcome, {
  String presentationPayloadJson = '',
  String? authorName,
  String? authorId,
}) {
  return switch (outcome) {
    AttentionForwardOutcome.helping => _helpingLabel(
      l10n,
      presentationPayloadJson,
      authorName,
      authorId,
    ),
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

String _helpingLabel(
  L10n l10n,
  String presentationPayloadJson,
  String? authorName,
  String? authorId,
) {
  final payload = _decodePayload(presentationPayloadJson);
  final stage = _string(payload, 'helperStage');
  switch (stage) {
    case 'wrappingUp':
      return l10n.activityForwardOutcomeWrappingUp;
    case 'accepted':
      // #507: a steward may accept; then the author is not the one to
      // credit, and the sentence names no one.
      final actorId = _string(payload, 'actorUserId') ?? '';
      final acceptedBySomeoneElse =
          actorId.isNotEmpty && actorId != (authorId?.trim() ?? '');
      final name = acceptedBySomeoneElse ? '' : authorName?.trim() ?? '';
      final role = _string(payload, 'roleLabel') ?? '';
      if (name.isEmpty) {
        return role.isEmpty
            ? l10n.activityForwardOutcomeAcceptedNoAuthor
            : l10n.activityForwardOutcomeAcceptedNoAuthorWithRole(role);
      }
      return role.isEmpty
          ? l10n.activityForwardOutcomeAccepted(name)
          : l10n.activityForwardOutcomeAcceptedWithRole(name, role);
    default:
      return l10n.activityForwardOutcomeHelping;
  }
}

Map<Object?, Object?>? _decodePayload(String json) {
  final trimmed = json.trim();
  if (trimmed.isEmpty || trimmed == '{}') return null;
  try {
    final decoded = jsonDecode(trimmed);
    return decoded is Map ? decoded : null;
  } on Object {
    return null;
  }
}

String? _string(Map<Object?, Object?>? payload, String key) {
  final value = payload?[key];
  return value is String ? value.trim() : null;
}
