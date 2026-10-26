import 'dart:convert';

import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// #367: the stage of an accepted helper, carried by a `helping` forward row
/// in its presentation payload (`helperStage`, with `roleLabel`, and #665's
/// `acceptedInvite` and `inviterId` when the viewer accepted an invitation).
/// An absent, unknown or unreadable stage keeps the plain "You offered help".
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
    // #725: «Не смогу» on an author invitation keeps its own words; a
    // dismissed forward stays "dismissed" (#485).
    AttentionForwardOutcome.notInterested =>
      activityForwardDeclinedInvite(presentationPayloadJson)
          ? l10n.activityForwardOutcomeInviteDeclined
          : l10n.activityForwardOutcomeNotInterested,
    AttentionForwardOutcome.closedBeforeResponse =>
      l10n.activityForwardOutcomeClosed,
    AttentionForwardOutcome.deletedBeforeResponse =>
      l10n.activityForwardOutcomeDeleted,
    null => null,
  };
}

/// #725: the row's "not interested" answered an author invitation ("Can't
/// make it"), as the server marks it (`declinedInvite`).
bool activityForwardDeclinedInvite(String presentationPayloadJson) =>
    _decodePayload(presentationPayloadJson)?['declinedInvite'] == true;

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
      // #665: admitted by accepting the author's invitation (a bud invite):
      // the viewer accepted, nobody accepted an offer of theirs. The payload
      // names the inviter (`inviterId`); only when that is the Request's
      // author (or a server too old to say) is the author named.
      if (payload?['acceptedInvite'] == true) {
        final inviterId = _string(payload, 'inviterId') ?? '';
        final invitedBySomeoneElse =
            inviterId.isNotEmpty && inviterId != (authorId?.trim() ?? '');
        final inviter = invitedBySomeoneElse ? '' : authorName?.trim() ?? '';
        return inviter.isEmpty
            ? l10n.activityForwardOutcomeInviteAcceptedNoAuthor
            : l10n.activityForwardOutcomeInviteAccepted(inviter);
      }
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
