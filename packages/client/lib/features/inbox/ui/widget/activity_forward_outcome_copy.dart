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
}) {
  return switch (outcome) {
    AttentionForwardOutcome.helping => _helpingLabel(
      l10n,
      presentationPayloadJson,
      authorName,
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
) {
  final payload = _decodePayload(presentationPayloadJson);
  final stage = _string(payload, 'helperStage');
  switch (stage) {
    case 'wrappingUp':
      return l10n.activityForwardOutcomeWrappingUp;
    case 'accepted':
      final name = authorName?.trim() ?? '';
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
