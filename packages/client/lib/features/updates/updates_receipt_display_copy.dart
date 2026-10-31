import 'dart:convert';

import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/util/display_name_prompt.dart';
import 'package:tentura/domain/attention/attention_event_classification.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/plan_receipt_event_type.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/withdraw_reason_label.dart';

/// Trust-change presentation keys emitted by the server (direction-encoded).
const trustChangePresentationKeys = <String>{
  'trust_given_changed_up',
  'trust_given_changed_down',
  'trust_given_changed_neutral',
  'trust_received_changed_up',
  'trust_received_changed_down',
  'trust_received_changed_neutral',
};

/// Whether [presentationKey] is a trust-given or trust-received Updates card.
bool isTrustChangePresentationKey(String? presentationKey) =>
    presentationKey != null &&
    trustChangePresentationKeys.contains(presentationKey);

/// Whether [presentationKey] is an invite-accepted Updates card (seed prompt host).
bool isInviteAcceptedPresentationKey(String? presentationKey) =>
    presentationKey == 'invite_accepted';

enum TrustChangeDirection { up, down, neutral }

/// Direction suffix parsed from a trust-change [presentationKey].
TrustChangeDirection trustChangeDirectionFromPresentationKey(
  String presentationKey,
) {
  if (presentationKey.endsWith('_up')) return TrustChangeDirection.up;
  if (presentationKey.endsWith('_down')) return TrustChangeDirection.down;
  return TrustChangeDirection.neutral;
}

/// Resolved title/body for an Updates receipt, with presentation-key fallbacks.
class UpdatesReceiptDisplayCopy {
  const UpdatesReceiptDisplayCopy({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

/// Non-empty display copy for a receipt, keyed on [presentationKey] when server
/// copy is blank.
UpdatesReceiptDisplayCopy resolveUpdatesReceiptDisplayCopy({
  required String title,
  required String body,
  required String? presentationKey,
  required L10n l10n,
  String presentationPayloadJson = '',
}) {
  final trimmedTitle = title.trim();
  final trimmedBody = body.trim();
  return UpdatesReceiptDisplayCopy(
    title: trimmedTitle.isEmpty
        ? _fallbackTitle(presentationKey, l10n)
        : trimmedTitle,
    body: trimmedBody.isEmpty
        ? _fallbackBody(presentationKey, l10n)
        : trimmedBody,
  );
}

/// Request title carried in server [presentationPayloadJson] when available.
String? beaconTitleFromPresentationPayload(String presentationPayloadJson) {
  final trimmed = presentationPayloadJson.trim();
  if (trimmed.isEmpty || trimmed == '{}') return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    final title = decoded['beaconTitle'];
    if (title is! String) return null;
    final normalized = title.trim();
    return normalized.isEmpty ? null : normalized;
  } on Object {
    return null;
  }
}

/// The user's own words the event carries, from the server's `excerpt`
/// payload field: `''` when the event carries none, and **null** when the
/// receipt predates the field — only then is `body` worth parsing.
String? excerptFromPresentationPayload(String presentationPayloadJson) =>
    _payloadString(presentationPayloadJson, 'excerpt');

/// The actor's display name the server stored when it wrote an offer or
/// invite-answer receipt (#700); null on rows written before the field, or
/// when blank.
String? actorNameFromPresentationPayload(String presentationPayloadJson) {
  final name = _payloadString(presentationPayloadJson, 'actorName');
  // The server placeholder «New member» reads in the app language (#660).
  return name == null || name.isEmpty ? null : localizedDisplayName(name);
}

/// The [BeaconStatus] a status-change event moved the Request to.
BeaconStatus? toStatusFromPresentationPayload(String presentationPayloadJson) {
  final name = _payloadString(presentationPayloadJson, 'toStatus');
  return name == null ? null : BeaconStatus.values.asNameMap()[name];
}

bool? _payloadBool(String presentationPayloadJson, String key) {
  final trimmed = presentationPayloadJson.trim();
  if (trimmed.isEmpty || trimmed == '{}') return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    final value = decoded[key];
    return value is bool ? value : null;
  } on Object {
    return null;
  }
}

String? _payloadString(String presentationPayloadJson, String key) {
  final trimmed = presentationPayloadJson.trim();
  if (trimmed.isEmpty || trimmed == '{}') return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    final value = decoded[key];
    return value is String ? value.trim() : null;
  } on Object {
    return null;
  }
}

/// A message (or mention) in a Request's **Questions** — the only live
/// thread scope, so a room-message receipt that names a coordination item is
/// one (#656). It opens the Questions screen and says Questions, not
/// "thread".
bool isQuestionsMessageReceipt({
  required String? presentationKey,
  required String presentationPayloadJson,
}) =>
    presentationKey == 'room_message_posted' &&
    (_payloadString(
          presentationPayloadJson,
          'coordinationItemId',
        )?.isNotEmpty ??
        false);

/// [isQuestionsMessageReceipt] for a whole receipt (the typed
/// `coordinationItemId` column counts as well as the payload).
bool isQuestionsAttentionReceipt(AttentionReceipt receipt) =>
    isQuestionsMessageReceipt(
      presentationKey: receipt.presentationKey,
      presentationPayloadJson: receipt.presentationPayloadJson,
    ) ||
    (receipt.presentationKey == 'room_message_posted' &&
        (receipt.coordinationItemId?.trim().isNotEmpty ?? false));

/// English titles the server writes on a Questions notice with no actor
/// name.
const _serverQuestionsTitles = {
  'New message in Questions',
  'New thread message',
  'New mention',
};

/// Invite-accepted origin carried in server [presentationPayloadJson].
String? inviteOriginFromPresentationPayload(String presentationPayloadJson) {
  final trimmed = presentationPayloadJson.trim();
  if (trimmed.isEmpty || trimmed == '{}') return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    final origin = decoded['inviteOrigin'];
    if (origin is! String) return null;
    final normalized = origin.trim();
    if (normalized == 'new_account' || normalized == 'existing_account') {
      return normalized;
    }
    return null;
  } on Object {
    return null;
  }
}

class InviteAcceptedDisplayCopy {
  const InviteAcceptedDisplayCopy({
    required this.title,
    required this.body,
    this.secondary = '',
  });

  final String title;
  final String body;
  final String secondary;
}

/// English bodies the server writes on invite-accepted receipts, keyed to the
/// invite origin they mean. Rows stored before the server added
/// `inviteOrigin` to the payload carry only this text (#712).
const _serverInviteAcceptedBodies = <String, String>{
  'Created an account via your invitation. You are now connected.':
      'new_account',
  'Already had a Tentura account. You are now connected.': 'existing_account',
  'You are now connected on Tentura.': 'connected',
};

/// English titles the server writes on an invite-accepted receipt with no
/// accepter name.
const _serverInviteAcceptedTitles = {'Invitation accepted'};

/// The server's invite-accepted title is «Name · @handle» (or the name
/// alone); the server placeholder name «New member» reads in the app
/// language like everywhere else a name is shown (#660, #700).
String _localizedNameTitle(String title) {
  final t = title.trim();
  const sep = ' · ';
  final cut = t.indexOf(sep);
  if (cut < 0) return localizedDisplayName(t);
  final name = t.substring(0, cut);
  if (name.trim() != kNewMemberDisplayName) return t;
  return '${localizedDisplayName(name)}${t.substring(cut)}';
}

/// In-app Updates composition for invite-accepted receipts.
///
/// The body is always localized: from `inviteOrigin` in the payload, else
/// from the server's known English body, else the generic invite-accepted
/// copy — never the stored server text (#712).
InviteAcceptedDisplayCopy resolveInviteAcceptedDisplayCopy({
  required String receiptTitle,
  required String receiptBody,
  required String presentationPayloadJson,
  required String? presentationKey,
  required L10n l10n,
  Profile? profile,
}) {
  final fallback = resolveUpdatesReceiptDisplayCopy(
    title: receiptTitle,
    body: receiptBody,
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
    l10n: l10n,
  );
  final fallbackTitle = _serverInviteAcceptedTitles.contains(fallback.title)
      ? l10n.updatesFallbackTitleInviteAccepted
      : _localizedNameTitle(fallback.title);
  final origin =
      inviteOriginFromPresentationPayload(presentationPayloadJson) ??
      _serverInviteAcceptedBodies[receiptBody.trim()];
  final body = switch (origin) {
    'new_account' => l10n.updatesInviteAcceptedBodyNewAccount,
    'existing_account' => l10n.updatesInviteAcceptedBodyExistingAccount,
    'connected' => l10n.updatesFallbackBodyMutualConnectionFormed,
    _ => l10n.updatesFallbackBodyInviteAccepted,
  };
  if (profile == null) {
    return InviteAcceptedDisplayCopy(title: fallbackTitle, body: body);
  }

  final shown = profile.shownName.trim();
  final public = profile.canonicalPublicLabel;
  final title = shown.isNotEmpty
      ? shown
      : (public.isNotEmpty ? public : fallbackTitle);
  final secondary = profile.canonicalSecondaryLabel;
  return InviteAcceptedDisplayCopy(
    title: title,
    body: body,
    secondary: secondary.isNotEmpty && secondary != title ? secondary : '',
  );
}

String _fallbackTitle(
  String? presentationKey,
  L10n l10n,
) => switch (presentationKey) {
  'relay_received' => l10n.updatesFallbackTitleRelayReceived,
  'help_offer_submitted' => l10n.updatesFallbackTitleHelpOfferSubmitted,
  'offer_accepted' => l10n.updatesFallbackTitleOfferAccepted,
  'offer_declined' => l10n.updatesFallbackTitleOfferDeclined,
  'offer_removed' => l10n.updatesFallbackTitleOfferRemoved,
  'room_message_posted' => l10n.updatesFallbackTitleRoomMessagePosted,
  'request_status_changed' => l10n.updatesFallbackTitleRequestStatusChanged,
  'obligation_ended' => l10n.updatesFallbackTitleObligationEnded,
  'commitment_released' => l10n.updatesFallbackTitleCommitmentReleased,
  'beacon_hierarchy_status_changed' =>
    l10n.updatesFallbackTitleHierarchyStatusChanged,
  'mutual_connection_formed' => l10n.updatesFallbackTitleMutualConnectionFormed,
  'invite_accepted' => l10n.updatesFallbackTitleInviteAccepted,
  'needs_me' => l10n.updatesFallbackTitleNeedsMe,
  'blocker_opened' => l10n.updatesFallbackTitleBlockerOpened,
  'blocker_resolved' => l10n.updatesFallbackTitleBlockerResolved,
  'promise_made' => l10n.updatesFallbackTitlePromiseMade,
  'promise_withdrawn' => l10n.updatesFallbackTitlePromiseWithdrawn,
  'help_withdrawn' => l10n.updatesFallbackTitleHelpWithdrawn,
  'forward_declined' => l10n.updatesFallbackTitleForwardDeclined,
  'coordination_changed' => l10n.updatesFallbackTitleCoordinationChanged,
  'deadline_changed' => l10n.updatesFallbackTitleDeadlineChanged,
  'deadline_reminder' => l10n.updatesFallbackTitleDeadlineReminder,
  'stale_reminder' => l10n.updatesFallbackTitleStaleReminder,
  'post_first_response' => l10n.updatesFallbackTitlePostFirstResponse,
  'post_expiring_soon' => l10n.updatesFallbackTitlePostExpiringSoon,
  'commitment_accepted' => l10n.updatesFallbackTitleCommitmentAccepted,
  'commitment_resolved' => l10n.updatesFallbackTitleCommitmentResolved,
  'commitment_cancelled' => l10n.updatesFallbackTitleCommitmentCancelled,
  'commitment_redirected' => l10n.updatesFallbackTitleCommitmentRedirected,
  'trust_given_changed_up' ||
  'trust_given_changed_down' ||
  'trust_given_changed_neutral' => l10n.updatesFallbackTitleTrustGivenChanged,
  'trust_received_changed_up' ||
  'trust_received_changed_down' ||
  'trust_received_changed_neutral' =>
    l10n.updatesFallbackTitleTrustReceivedChanged,
  _ => l10n.updatesFallbackTitleGeneric,
};

String _fallbackBody(
  String? presentationKey,
  L10n l10n,
) => switch (presentationKey) {
  'relay_received' => l10n.updatesFallbackBodyRelayReceived,
  'help_offer_submitted' => l10n.updatesFallbackBodyHelpOfferSubmitted,
  'offer_accepted' => l10n.updatesFallbackBodyOfferAccepted,
  'offer_declined' => l10n.updatesFallbackBodyOfferDeclined,
  'offer_removed' => l10n.updatesFallbackBodyOfferRemoved,
  'room_message_posted' => l10n.updatesFallbackBodyRoomMessagePosted,
  'request_status_changed' => l10n.updatesFallbackBodyRequestStatusChanged,
  'mutual_connection_formed' => l10n.updatesFallbackBodyMutualConnectionFormed,
  'invite_accepted' => l10n.updatesFallbackBodyInviteAccepted,
  'needs_me' => l10n.updatesFallbackBodyNeedsMe,
  'blocker_opened' => l10n.updatesFallbackBodyBlockerOpened,
  'blocker_resolved' => l10n.updatesFallbackBodyBlockerResolved,
  'promise_made' => l10n.updatesFallbackBodyPromiseMade,
  'promise_withdrawn' => l10n.updatesFallbackBodyPromiseWithdrawn,
  'help_withdrawn' => l10n.updatesFallbackBodyHelpWithdrawn,
  'forward_declined' => l10n.updatesFallbackBodyForwardDeclined,
  'coordination_changed' => l10n.updatesFallbackBodyCoordinationChanged,
  'deadline_changed' => l10n.updatesFallbackBodyDeadlineChanged,
  'deadline_reminder' => l10n.updatesFallbackBodyDeadlineReminder,
  'stale_reminder' => l10n.updatesFallbackBodyStaleReminder,
  'post_first_response' => l10n.updatesFallbackBodyPostFirstResponse,
  'post_expiring_soon' => l10n.updatesFallbackBodyPostExpiringSoon,
  'commitment_accepted' => l10n.updatesFallbackBodyCommitmentAccepted,
  'commitment_resolved' => l10n.updatesFallbackBodyCommitmentResolved,
  'commitment_cancelled' => l10n.updatesFallbackBodyCommitmentCancelled,
  'commitment_redirected' => l10n.updatesFallbackBodyCommitmentRedirected,
  'trust_given_changed_up' ||
  'trust_given_changed_down' ||
  'trust_given_changed_neutral' => l10n.updatesFallbackBodyTrustGivenChanged,
  'trust_received_changed_up' ||
  'trust_received_changed_down' ||
  'trust_received_changed_neutral' =>
    l10n.updatesFallbackBodyTrustReceivedChanged,
  _ => l10n.updatesFallbackBodyGeneric,
};

/// Headline + body for a dense Updates list row.
class UpdatesFeedRowCopy {
  const UpdatesFeedRowCopy({
    required this.headline,
    required this.body,
  });

  final String headline;
  final String body;
}

/// Baton receipt copy uses only the author and the source-message excerpt.
/// Candidate lists and other payload fields never participate in presentation.
UpdatesFeedRowCopy? batonReceiptDisplayCopy({
  required String title,
  required String? presentationKey,
  required String presentationPayloadJson,
  required L10n l10n,
  String? actorName,
}) {
  final type = attentionEventTypeOf(presentationPayloadJson);
  final excerpt = excerptFromPresentationPayload(presentationPayloadJson) ?? '';
  final author = actorName?.trim();
  return switch (type ?? presentationKey) {
    'batonAsked' || 'baton_asked' => UpdatesFeedRowCopy(
      headline: l10n.batonReceiptAsked(
        author != null && author.isNotEmpty ? author : title.trim(),
      ),
      body: excerpt,
    ),
    'batonTaken' || 'baton_taken' => UpdatesFeedRowCopy(
      headline: l10n.batonReceiptTaken(excerpt),
      body: '',
    ),
    'batonAllAnswered' || 'baton_all_answered' => UpdatesFeedRowCopy(
      headline: l10n.batonReceiptAllAnswered,
      body: excerpt,
    ),
    _ => null,
  };
}

/// Who-did-what receipt copy (#516, #685, #486;
/// `docs/features/request-change-events.md`): the person and what they did,
/// in the viewer's locale, with their own words as the body. The one place
/// the author's Request card, its change line and Updates read a helper's
/// withdrawal from.
///
/// * `help_withdrawn` — «Omar left the request (Timing changed)» when they
///   were in the discussion, «… withdrew their help offer (…)» otherwise,
///   «… withdrew their help offer» when the reason is not readable; the body
///   is their note, and says so when the next step still names them.
/// * `forward_declined` — «Nina can't help»; the body is her note, which
///   only the author ever receives.
///
/// The name is [actorName] when the caller knows the person, else the
/// receipt [title] (the server writes the actor's name there) unless that is
/// a Request title in [requestTitles] or a server placeholder. Null for any
/// other receipt.
UpdatesFeedRowCopy? whoDidWhatReceiptDisplayCopy({
  required String title,
  required String? presentationKey,
  required String presentationPayloadJson,
  required L10n l10n,
  String? actorName,
  Set<String> requestTitles = const {},
}) {
  final words = _whoDidWhatWords(
    title: title,
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
    l10n: l10n,
    actorName: actorName,
    requestTitles: requestTitles,
  );
  if (words == null) return null;
  return UpdatesFeedRowCopy(
    headline: words.headline,
    body: [
      if (words.note.isNotEmpty) words.note,
      if (words.flag.isNotEmpty) words.flag,
    ].join('\n'),
  );
}

/// The who-did-what event a receipt is: `helpWithdrawn`, `forwardDeclined`,
/// or null for any other. A `promiseWithdrawn` that carries a withdraw
/// reason is a helper's withdrawal written before 7.46.0 gave it its own
/// event (main 62055251b); a coordination promise never carries one.
String? whoDidWhatEventTypeOf(
  String presentationPayloadJson, {
  String? presentationKey,
}) {
  final type = attentionEventTypeOf(presentationPayloadJson) ?? presentationKey;
  return switch (type) {
    'helpWithdrawn' || 'help_withdrawn' => 'helpWithdrawn',
    'forwardDeclined' || 'forward_declined' => 'forwardDeclined',
    'promiseWithdrawn' || 'promise_withdrawn'
        when _payloadString(
              presentationPayloadJson,
              'withdrawReason',
            )?.isNotEmpty ??
            false =>
      'helpWithdrawn',
    _ => null,
  };
}

typedef _WhoDidWhatWords = ({String headline, String note, String flag});

_WhoDidWhatWords? _whoDidWhatWords({
  required String title,
  required String? presentationKey,
  required String presentationPayloadJson,
  required L10n l10n,
  String? actorName,
  Set<String> requestTitles = const {},
}) {
  final type = whoDidWhatEventTypeOf(
    presentationPayloadJson,
    presentationKey: presentationKey,
  );
  if (type == null) return null;
  final isDecline = type == 'forwardDeclined';
  final t = title.trim();
  final fromTitle =
      t.isEmpty ||
          requestTitles.contains(t) ||
          _serverWhoDidWhatTitles.contains(t) ||
          _isServerCannedTitle(t)
      ? null
      : t;
  final name = _nonBlank(actorName) ?? fromTitle;
  final note = excerptFromPresentationPayload(presentationPayloadJson) ?? '';
  if (isDecline) {
    return (
      headline: name == null
          ? l10n.updatesFallbackTitleForwardDeclined
          : l10n.attentionEventCantHelp(name),
      note: note,
      flag: '',
    );
  }
  final flagged =
      _payloadBool(presentationPayloadJson, 'nextStepMentionsActor') ?? false;
  final flag = flagged ? l10n.attentionEventNextStepNamesLeaver : '';
  final reason = withdrawReasonLabel(
    l10n,
    _payloadString(presentationPayloadJson, 'withdrawReason'),
  );
  if (name == null) {
    // No name to hang the reason on: it leads the words instead.
    return (
      headline: l10n.updatesFallbackTitleHelpWithdrawn,
      note: [?reason, if (note.isNotEmpty) note].join(' · '),
      flag: flag,
    );
  }
  final left = _payloadBool(presentationPayloadJson, 'leftDiscussion') ?? false;
  return (
    headline: reason == null
        ? l10n.attentionEventHelpWithdrawn(name)
        : left
        ? l10n.beaconRoomParticipantLeft(name, reason)
        : l10n.attentionEventOfferWithdrawn(name, reason),
    note: note,
    flag: flag,
  );
}

/// What the server titles a who-did-what receipt with when the person has
/// no name (`BeaconNotificationCopyBuilder`, `forwardDeclined`).
const _serverWhoDidWhatTitles = {'Someone', "Can't help"};

/// Plan receipt copy: the event in the viewer's locale, and the step title
/// the server carries as `excerpt`. No clock times (plan K16): the row's own
/// age label is the only time shown. The actor's name is left to the row's
/// own prefix, so the headline never repeats it.
UpdatesFeedRowCopy? planReceiptDisplayCopy({
  required String? presentationKey,
  required String presentationPayloadJson,
  required L10n l10n,
}) {
  final type = planReceiptEventType(
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
  );
  if (type == null) return null;
  final headline = switch (type) {
    'planStepDue' => l10n.planReceiptStepDue,
    'planStepTurn' => l10n.planReceiptStepTurn,
    'planChangePending' => l10n.planReceiptChangePending,
    'planStepReminder' => l10n.planReceiptStepReminder,
    'planStepOverdue' => l10n.planReceiptStepOverdue,
    'planStepLate' => l10n.planReceiptStepLate,
    'planCantMake' => l10n.planReceiptCantMake,
    'planStepUnassigned' => l10n.planReceiptStepUnassigned,
    'planEdited' => l10n.planReceiptEdited,
    _ => l10n.planReceiptStepDone,
  };
  return UpdatesFeedRowCopy(
    headline: headline,
    body: excerptFromPresentationPayload(presentationPayloadJson) ?? '',
  );
}

/// Author-invite answers and the invitee's own invitation (#736): the
/// server titles the row with the person's name only, so the event comes
/// from the locale. The body is the person's note, else the Request title.
/// The name is [actorName] when the caller knows the person, else the
/// payload's `actorName` (#700), else the receipt [title]. Null for any
/// other receipt.
UpdatesFeedRowCopy? authorInviteReceiptDisplayCopy({
  required String title,
  required String? presentationKey,
  required String presentationPayloadJson,
  required L10n l10n,
  String? actorName,
}) {
  final type = attentionEventTypeOf(presentationPayloadJson) ?? presentationKey;
  final kind = switch (type) {
    'authorInviteReceived' || 'author_invite_received' => 'received',
    'authorInviteAccepted' || 'author_invite_accepted' => 'accepted',
    'authorInviteDeclined' || 'author_invite_declined' => 'declined',
    _ => null,
  };
  if (kind == null) return null;
  final request = beaconTitleFromPresentationPayload(presentationPayloadJson);
  final t = title.trim();
  final name =
      _nonBlank(actorName) ??
      actorNameFromPresentationPayload(presentationPayloadJson) ??
      (t.isEmpty || t == request || _isServerCannedTitle(t) ? null : t);
  final headline = switch (kind) {
    'received' =>
      name == null
          ? l10n.updatesAuthorInviteReceived
          : l10n.attentionCardInviteReceived(name),
    'accepted' =>
      name == null
          ? l10n.updatesFallbackTitleInviteAccepted
          : l10n.attentionCardInviteAccepted(name),
    _ =>
      name == null
          ? l10n.updatesFallbackTitleForwardDeclined
          : l10n.attentionCardInviteDeclined(name),
  };
  final note = excerptFromPresentationPayload(presentationPayloadJson) ?? '';
  final words = note == request ? '' : note;
  return UpdatesFeedRowCopy(
    headline: headline,
    body: request == null
        ? words
        : words.isEmpty
        ? request
        : l10n.updatesRequestNoteBody(request, words),
  );
}

/// The English (and Russian) tails written after the actor's name when an
/// offer receipt title is a sentence («Alice accepted your offer»).
const _offerAcceptedTitleTails = [
  ' accepted your offer',
  ' принял(а) ваше предложение',
];
const _offerSubmittedTitleTails = [
  ' offered help',
  ' offered to help as backup',
  ' предложил(а) помощь',
  ' предложил помощь',
  ' предложила помощь',
];

/// Offer receipts in the Updates feed (#736, #700): the author's row for a
/// help offer (`helpOfferSubmitted`, titled with the helper's name only) and
/// the helper's row for an accepted offer (`offerAccepted`, titled
/// «`<name>` accepted your offer» in English) both say what happened in the
/// reader's language. The name is [actorName] when the caller knows the
/// person, else the payload's `actorName` (#700), else read from the
/// receipt [title]. The body is the Request title, with the helper's note on
/// an offer (the receipt [body] on a row written before the payload carried
/// `excerpt`). Null for any other receipt.
UpdatesFeedRowCopy? offerReceiptDisplayCopy({
  required String title,
  required String? presentationKey,
  required String presentationPayloadJson,
  required L10n l10n,
  String body = '',
  String? actorName,
}) {
  final type = attentionEventTypeOf(presentationPayloadJson) ?? presentationKey;
  final accepted = switch (type) {
    'helpOfferSubmitted' || 'help_offer_submitted' => false,
    'offerAccepted' || 'offer_accepted' => true,
    _ => null,
  };
  if (accepted == null) return null;
  final request = beaconTitleFromPresentationPayload(presentationPayloadJson);
  var t = title.trim();
  for (final tail
      in accepted ? _offerAcceptedTitleTails : _offerSubmittedTitleTails) {
    if (t.endsWith(tail)) {
      t = t.substring(0, t.length - tail.length).trim();
      break;
    }
  }
  final name =
      _nonBlank(actorName) ??
      actorNameFromPresentationPayload(presentationPayloadJson) ??
      (t.isEmpty ||
              t == request ||
              _isServerCannedTitle(t) ||
              _serverWhoDidWhatTitles.contains(t)
          ? null
          : t);
  if (accepted) {
    return UpdatesFeedRowCopy(
      headline: name == null
          ? l10n.updatesFallbackTitleOfferAccepted
          : l10n.updatesOfferAcceptedHeadline(name),
      body: request ?? '',
    );
  }
  final legacy = body.trim();
  final note =
      excerptFromPresentationPayload(presentationPayloadJson) ??
      (legacy == title.trim() || _isServerCannedSentence(legacy) ? '' : legacy);
  final words = note == request ? '' : note;
  return UpdatesFeedRowCopy(
    headline: name == null
        ? l10n.updatesFallbackTitleHelpOfferSubmitted
        : l10n.updatesOfferReceivedHeadline(name),
    body: request == null
        ? words
        : words.isEmpty
        ? request
        : l10n.updatesRequestNoteBody(request, words),
  );
}

/// Closure receipts and the quiet-request nudge (#700): the server writes
/// fixed English copy («Request closed», «The results are in.»), so both
/// lines come from the locale by event. Null for any other receipt.
UpdatesFeedRowCopy? closureReceiptDisplayCopy({
  required String? presentationKey,
  required String presentationPayloadJson,
  required L10n l10n,
}) {
  final type = attentionEventTypeOf(presentationPayloadJson) ?? presentationKey;
  return switch (type) {
    'closureOpened' ||
    'closure_opened' ||
    'closure_opened_bookmark_only' => UpdatesFeedRowCopy(
      headline: l10n.updatesClosureOpenedTitle,
      body: l10n.updatesClosureOpenedBody,
    ),
    'closureDraftReminder' || 'closure_draft_reminder' => UpdatesFeedRowCopy(
      headline: l10n.updatesClosureDraftReminderTitle,
      body: l10n.updatesClosureDraftReminderBody,
    ),
    'closureFinalized' || 'closure_finalized' => UpdatesFeedRowCopy(
      headline: l10n.updatesClosureFinalizedTitle,
      body: l10n.updatesClosureFinalizedBody,
    ),
    'closureCancelled' || 'closure_cancelled' => UpdatesFeedRowCopy(
      headline: l10n.updatesClosureCancelledTitle,
      body: l10n.updatesClosureCancelledBody,
    ),
    'requestStale' || 'request_stale' => UpdatesFeedRowCopy(
      headline: l10n.updatesRequestStaleTitle,
      body: l10n.updatesRequestStaleBody,
    ),
    _ => null,
  };
}

/// Maps server title/body + payload into a non-duplicating two-line row.
UpdatesFeedRowCopy resolveUpdatesFeedRowCopy({
  required String title,
  required String body,
  required String? presentationKey,
  required String presentationPayloadJson,
  required L10n l10n,
  String? bodyOverride,
  String? actorName,
  bool isPost = false,
  String? postRootExcerpt,
}) {
  final shared = isPost
      ? _postSharedRowCopy(
          title: title,
          presentationKey: presentationKey,
          presentationPayloadJson: presentationPayloadJson,
          l10n: l10n,
          actorName: actorName,
          postRootExcerpt: postRootExcerpt,
        )
      : null;
  if (shared != null) return shared;
  final baton = batonReceiptDisplayCopy(
    title: title,
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
    l10n: l10n,
    actorName: actorName,
  );
  if (baton != null) return baton;
  final eventCopy =
      authorInviteReceiptDisplayCopy(
        title: title,
        presentationKey: presentationKey,
        presentationPayloadJson: presentationPayloadJson,
        l10n: l10n,
        actorName: actorName,
      ) ??
      offerReceiptDisplayCopy(
        title: title,
        body: body,
        presentationKey: presentationKey,
        presentationPayloadJson: presentationPayloadJson,
        l10n: l10n,
        actorName: actorName,
      ) ??
      closureReceiptDisplayCopy(
        presentationKey: presentationKey,
        presentationPayloadJson: presentationPayloadJson,
        l10n: l10n,
      ) ??
      _relayReceivedRowCopy(
        title: title,
        body: body,
        presentationKey: presentationKey,
        presentationPayloadJson: presentationPayloadJson,
        l10n: l10n,
        actorName: actorName,
      );
  if (eventCopy != null) return eventCopy;
  final whoDidWhatRequestTitle = beaconTitleFromPresentationPayload(
    presentationPayloadJson,
  );
  final whoDidWhat = _whoDidWhatWords(
    title: title,
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
    l10n: l10n,
    actorName: actorName,
    requestTitles: {?whoDidWhatRequestTitle},
  );
  if (whoDidWhat != null) {
    // A feed row names the Request it is about, then the person's words.
    final request = whoDidWhatRequestTitle ?? '';
    final subject = request.isEmpty
        ? whoDidWhat.note
        : whoDidWhat.note.isEmpty
        ? request
        : l10n.updatesOfferDeclinedBody(request, whoDidWhat.note);
    return UpdatesFeedRowCopy(
      headline: whoDidWhat.headline,
      body: [
        if (subject.isNotEmpty) subject,
        if (whoDidWhat.flag.isNotEmpty) whoDidWhat.flag,
      ].join(' · '),
    );
  }
  final plan = planReceiptDisplayCopy(
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
    l10n: l10n,
  );
  if (plan != null) return plan;
  if (isQuestionsMessageReceipt(
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
  )) {
    // The server title is the asker's name (never the text: Questions
    // notices carry none). It is data: the headline is the event, which
    // names Questions, not a "thread" (#736).
    final name =
        _nonBlank(actorName) ??
        questionsActorName(
          title: title,
          presentationPayloadJson: presentationPayloadJson,
        );
    return UpdatesFeedRowCopy(
      headline: name == null
          ? l10n.updatesQuestionsMessage
          : l10n.updatesQuestionsMessageFrom(name),
      body: '',
    );
  }
  final fallback = resolveUpdatesReceiptDisplayCopy(
    title: title,
    body: body,
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
    l10n: l10n,
  );
  final beaconTitle = beaconTitleFromPresentationPayload(
    presentationPayloadJson,
  );
  final eventTitle = title.trim().isEmpty ? fallback.title : title.trim();
  // #736: the headline is the event, from the key and the payload; the
  // server title (often just the actor's name, or the Request title) is data
  // and never the headline. Only a legacy row with no key at all keeps a
  // non-canned title, since nothing else says what it was.
  final headline = presentationKey == null && !_isServerCannedTitle(eventTitle)
      ? eventTitle
      : _eventHeadline(
          title: title,
          body: body,
          presentationKey: presentationKey,
          presentationPayloadJson: presentationPayloadJson,
          l10n: l10n,
          actorName: actorName,
        );

  final bodyOverrideTrim = bodyOverride?.trim();
  final structuredExcerpt = excerptFromPresentationPayload(
    presentationPayloadJson,
  );
  var excerpt = (bodyOverrideTrim != null && bodyOverrideTrim.isNotEmpty)
      ? bodyOverrideTrim
      : structuredExcerpt ?? body.trim();
  if (excerpt.isEmpty && structuredExcerpt == null) excerpt = fallback.body;

  for (final prefix in <String>{
    if (eventTitle.isNotEmpty) '$eventTitle — ',
    if (beaconTitle != null && beaconTitle.isNotEmpty) '$beaconTitle — ',
  }) {
    if (excerpt.startsWith(prefix)) {
      excerpt = excerpt.substring(prefix.length).trim();
      break;
    }
  }

  final subjectOverride =
      bodyOverrideTrim != null && bodyOverrideTrim.isNotEmpty
      ? bodyOverrideTrim
      : null;
  final String line2;
  // The author's reason for declining (#381), removing you from the
  // discussion or ending your participation (#601).
  final authorReason = _authorReasonPresentationKeys.contains(presentationKey)
      ? structuredExcerpt
      : null;
  if (subjectOverride != null && subjectOverride != headline) {
    line2 = subjectOverride;
  } else if (authorReason != null &&
      authorReason.isNotEmpty &&
      authorReason != beaconTitle) {
    // Only the structured excerpt, never the push body; the Request title
    // stays beside it.
    line2 = beaconTitle != null && beaconTitle.isNotEmpty
        ? l10n.updatesOfferDeclinedBody(beaconTitle, authorReason)
        : authorReason;
  } else if (beaconTitle != null &&
      beaconTitle.isNotEmpty &&
      beaconTitle != headline) {
    line2 = beaconTitle;
  } else if (excerpt.isNotEmpty &&
      excerpt != headline &&
      excerpt != eventTitle) {
    line2 = excerpt;
  } else {
    line2 = '';
  }

  // A fallback sentence only restates the headline, usually in English.
  return UpdatesFeedRowCopy(
    headline: headline,
    body: _isServerCannedSentence(line2) ? '' : line2,
  );
}

/// The event line of a row with no dedicated mapper (#736): status and trust
/// changes from their payload, a person's event as «`<name>` did it» when
/// the event names one, else the key's own localized line — the generic
/// «Update» for a key this client does not know. Never the bare title.
String _eventHeadline({
  required String title,
  required String body,
  required String? presentationKey,
  required String presentationPayloadJson,
  required L10n l10n,
  String? actorName,
}) {
  final canned = cannedAttentionEventLine(
    title: title,
    body: body,
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
    l10n: l10n,
  );
  if (canned != null) return canned;
  final name = _eventActorName(
    title: title,
    presentationPayloadJson: presentationPayloadJson,
    actorName: actorName,
  );
  return switch (presentationKey) {
    'room_message_posted' when name != null => l10n.updatesRoomMessageHeadline(
      name,
    ),
    'post_first_response' when name != null =>
      l10n.updatesPostFirstResponseHeadline(name),
    'invite_accepted' when name != null => l10n.attentionCardInviteAccepted(
      name,
    ),
    'mutual_connection_formed' when name != null =>
      l10n.updatesMutualConnectionHeadline(name),
    _ => _fallbackTitle(presentationKey, l10n),
  };
}

/// The person an event is about: [actorName] when the caller knows them,
/// else the payload's `actorName`, else the server title when it is a name
/// («Name» or «Name · @handle») rather than a label or the Request title.
String? _eventActorName({
  required String title,
  required String presentationPayloadJson,
  String? actorName,
}) {
  final known =
      _nonBlank(actorName) ??
      actorNameFromPresentationPayload(presentationPayloadJson);
  if (known != null) return known;
  var t = title.trim();
  final cut = t.indexOf(' · ');
  if (cut >= 0) t = t.substring(0, cut).trim();
  if (t.isEmpty ||
      t == beaconTitleFromPresentationPayload(presentationPayloadJson) ||
      _isServerCannedTitle(t) ||
      _isServerCannedSentence(t) ||
      _serverQuestionsTitles.contains(t) ||
      _serverWhoDidWhatTitles.contains(t) ||
      t == 'Кто-то') {
    return null;
  }
  return localizedDisplayName(t);
}

/// The asker named on a Questions notice (the server titles it with their
/// name), or null when the title is the server's own label.
String? questionsActorName({
  required String title,
  String presentationPayloadJson = '',
}) {
  final t = title.trim();
  return _serverQuestionsTitles.contains(t)
      ? null
      : _eventActorName(
          title: t,
          presentationPayloadJson: presentationPayloadJson,
        );
}

/// A Request forwarded to the viewer (`relay_received`, #736): the server
/// titles it with the sender's name only, so the event comes from the
/// locale — «`<name>` forwarded a request to you». The body is the Request
/// title and the forward note. Null for any other receipt.
UpdatesFeedRowCopy? _relayReceivedRowCopy({
  required String title,
  required String body,
  required String? presentationKey,
  required String presentationPayloadJson,
  required L10n l10n,
  String? actorName,
}) {
  if (presentationKey != 'relay_received') return null;
  final name = _eventActorName(
    title: title,
    presentationPayloadJson: presentationPayloadJson,
    actorName: actorName,
  );
  final request = beaconTitleFromPresentationPayload(presentationPayloadJson);
  // A row written before the payload carried `excerpt` has «Name: note».
  var legacy = body.trim();
  final prefix = '${title.trim()}: ';
  if (legacy.startsWith(prefix)) legacy = legacy.substring(prefix.length);
  final note =
      excerptFromPresentationPayload(presentationPayloadJson) ??
      (legacy == title.trim() || _isServerCannedSentence(legacy) ? '' : legacy);
  final words = note == request ? '' : note;
  return UpdatesFeedRowCopy(
    headline: name == null
        ? l10n.updatesFallbackTitleRelayReceived
        : l10n.updatesRelayReceivedHeadline(name),
    body: request == null
        ? words
        : words.isEmpty
        ? request
        : l10n.updatesRequestNoteBody(request, words),
  );
}

/// A Post shared with the viewer (`relay_received` on a Post, #736): the
/// server titles it with the sender's name and a Post has no title, so the
/// row says «`<name>` shared a post» over the Post's root message, like the
/// Activity row. Null for any other receipt or when no name is known.
UpdatesFeedRowCopy? _postSharedRowCopy({
  required String title,
  required String? presentationKey,
  required String presentationPayloadJson,
  required L10n l10n,
  String? actorName,
  String? postRootExcerpt,
}) {
  if (presentationKey != 'relay_received') return null;
  final known = actorName?.trim() ?? '';
  final name = known.isNotEmpty
      ? known
      : actorNameFromPresentationPayload(presentationPayloadJson) ??
            localizedDisplayName(title.trim());
  if (name.trim().isEmpty) return null;
  final post = postRootExcerpt?.trim() ?? '';
  final note = excerptFromPresentationPayload(presentationPayloadJson) ?? '';
  return UpdatesFeedRowCopy(
    headline: l10n.postRowSharedBy(name),
    body: [if (post.isNotEmpty) post, if (note.isNotEmpty) note].join(' · '),
  );
}

/// Receipts whose structured excerpt is the author's reason (#381, #601).
const _authorReasonPresentationKeys = {
  'offer_declined',
  'offer_removed',
  'commitment_released',
};

/// The row's second line carries the author's own reason (#381, #601): it
/// may wrap further than an ordinary second line so the reason is read
/// whole.
bool updatesReceiptCarriesAuthorReason({
  required String? presentationKey,
  required String presentationPayloadJson,
}) =>
    _authorReasonPresentationKeys.contains(presentationKey) &&
    (excerptFromPresentationPayload(presentationPayloadJson)?.isNotEmpty ??
        false);

final _statusTransitionTail = RegExp(r'from (\w+) to (\w+)\s*$');

/// The locale's line for an event whose meaning lives in its key and payload
/// rather than in words — a status change, a trust change, a help offer.
///
/// Returns null when the event is not one of those, so the caller keeps its
/// own label. On a receipt written before the server sent `excerpt` it
/// falls back to reading the English `body` («X offered help», «X moved the
/// request from a to b»).
String? cannedAttentionEventLine({
  required String title,
  required String body,
  required String? presentationKey,
  required L10n l10n,
  String presentationPayloadJson = '',
}) {
  final structured =
      excerptFromPresentationPayload(presentationPayloadJson) != null;
  final t = title.trim();
  final b = body.trim();
  if (isTrustChangePresentationKey(presentationKey)) {
    final given = presentationKey!.startsWith('trust_given');
    return switch (trustChangeDirectionFromPresentationKey(presentationKey)) {
      TrustChangeDirection.up =>
        given
            ? l10n.attentionEventTrustGivenUp
            : l10n.attentionEventTrustReceivedUp,
      TrustChangeDirection.down =>
        given
            ? l10n.attentionEventTrustGivenDown
            : l10n.attentionEventTrustReceivedDown,
      TrustChangeDirection.neutral =>
        given
            ? l10n.attentionEventTrustGivenNeutral
            : l10n.attentionEventTrustReceivedNeutral,
    };
  }
  switch (presentationKey) {
    case 'help_offer_submitted':
      final canned =
          structured || b.isEmpty || b == '$t offered help' || b == t;
      return canned ? l10n.updatesFallbackTitleHelpOfferSubmitted : null;
    case 'request_status_changed':
      final legacyTo = _statusTransitionTail.firstMatch(b)?.group(2);
      final status =
          toStatusFromPresentationPayload(presentationPayloadJson) ??
          (legacyTo == null ? null : BeaconStatus.values.asNameMap()[legacyTo]);
      return status == null
          ? l10n.updatesFallbackTitleRequestStatusChanged
          : l10n.attentionEventStatusChanged(
              requestStatusActivityLabel(l10n, status),
            );
  }
  return null;
}

/// What one event row says inside a card whose header already names the
/// Request: the event, and the words (a message, a note) it carries.
class RequestScopedEventCopy {
  const RequestScopedEventCopy({required this.event, required this.excerpt});

  final String event;

  /// Empty when the receipt carries nothing but the event itself.
  final String excerpt;
}

/// Receipt copy is written for a push notification, where nothing else on
/// screen says which Request it is: the title is an English label («Request
/// closed — close the loop», «Plan updated») or the Request title itself, and
/// the body is «`<Request title> — <excerpt>`», the bare Request title, or an
/// English fallback sentence. Under a Request header every one of those is a
/// repeat or untranslated, so the event comes from the locale by
/// [presentationKey] and only a real excerpt survives into the quote.
RequestScopedEventCopy requestScopedEventCopy({
  required String title,
  required String body,
  required String? presentationKey,
  required L10n l10n,
  String presentationPayloadJson = '',
  String? requestTitle,
  String? actorName,
}) {
  final baton = batonReceiptDisplayCopy(
    title: title,
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
    l10n: l10n,
    actorName: actorName,
  );
  if (baton != null) {
    return RequestScopedEventCopy(event: baton.headline, excerpt: baton.body);
  }
  final requestTitles = {
    ?_nonBlank(requestTitle),
    ?beaconTitleFromPresentationPayload(presentationPayloadJson),
  };
  final whoDidWhat = whoDidWhatReceiptDisplayCopy(
    title: title,
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
    l10n: l10n,
    actorName: actorName,
    requestTitles: requestTitles,
  );
  if (whoDidWhat != null) {
    return RequestScopedEventCopy(
      event: whoDidWhat.headline,
      excerpt: whoDidWhat.body,
    );
  }
  final plan = planReceiptDisplayCopy(
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
    l10n: l10n,
  );
  if (plan != null) {
    return RequestScopedEventCopy(event: plan.headline, excerpt: plan.body);
  }
  final invite = authorInviteReceiptDisplayCopy(
    title: title,
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
    l10n: l10n,
    actorName: actorName,
  );
  if (invite != null) {
    // The header already names the Request; only the person's note stays.
    final note = excerptFromPresentationPayload(presentationPayloadJson) ?? '';
    return RequestScopedEventCopy(
      event: invite.headline,
      excerpt: requestTitles.contains(note) ? '' : note,
    );
  }
  final closure = closureReceiptDisplayCopy(
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
    l10n: l10n,
  );
  if (closure != null) {
    return RequestScopedEventCopy(event: closure.headline, excerpt: '');
  }
  if (isQuestionsMessageReceipt(
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
  )) {
    // No excerpt: Questions notices never carry the message text.
    return RequestScopedEventCopy(
      event: l10n.updatesQuestionsMessage,
      excerpt: '',
    );
  }
  final t = title.trim();
  final canned = cannedAttentionEventLine(
    title: title,
    body: body,
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
    l10n: l10n,
  );
  final localized = _fallbackTitle(presentationKey, l10n);
  final isKnownKey = localized != l10n.updatesFallbackTitleGeneric;
  final String event;
  if (canned != null) {
    event = canned;
  } else if (isKnownKey) {
    event = localized;
  } else if (t.isEmpty || requestTitles.contains(t)) {
    event = localized;
  } else {
    event = t;
  }

  // The server names the words outright; `body` is push copy and is parsed
  // only for a receipt written before it did.
  final structuredExcerpt = excerptFromPresentationPayload(
    presentationPayloadJson,
  );
  if (structuredExcerpt != null) {
    return RequestScopedEventCopy(
      event: event,
      excerpt: requestTitles.contains(structuredExcerpt)
          ? ''
          : structuredExcerpt,
    );
  }

  var excerpt = body.trim();
  for (final request in requestTitles) {
    final prefix = '$request — ';
    if (excerpt.startsWith(prefix)) {
      excerpt = excerpt.substring(prefix.length).trim();
      break;
    }
  }
  final dropped =
      excerpt.isEmpty ||
      requestTitles.contains(excerpt) ||
      excerpt == t ||
      excerpt == event ||
      (canned != null &&
          (presentationKey == 'request_status_changed' ||
              isTrustChangePresentationKey(presentationKey))) ||
      _isServerCannedSentence(excerpt);
  return RequestScopedEventCopy(event: event, excerpt: dropped ? '' : excerpt);
}

String? _nonBlank(String? value) {
  final v = value?.trim() ?? '';
  return v.isEmpty ? null : v;
}

/// Legacy: receipts written before the server sent `excerpt` in the payload.
///
/// The English sentences the server writes when an event has no excerpt of
/// its own — `BeaconNotificationCopyBuilder` and `AttentionIntentCase` in
/// packages/server. They restate the event and are never user words.
const _serverCannedBodies = {
  'New thread update',
  'Review contributions',
  'Request update',
  'The request deadline changed',
  'This request deadline is tomorrow',
  'Action needed in the request discussion',
  'Promise withdrawn',
  'New promise in the request discussion',
  'Coordination changed',
  'A blocker was opened',
  'A blocker was resolved',
  'Your offer was accepted',
  'Your offer was declined',
  'You were removed from the request discussion',
  'The author ended your participation in this request',
  'Something in the request thread needs attention',
  'Open General to see your new assignment',
  'Your post expires in under 3 hours',
  'You are now connected on Tentura.',
  // Written by the account-deletion scrub (m0193), which also empties the
  // payload — so these rows always take this legacy path.
  'An account involved in this activity was deleted.',
};

final _serverCannedPatterns = [
  RegExp(
    ' (offered help|offered to help as backup|withdrew their help|'
    r'forwarded a request to you|mentioned you|accepted your invitation)$',
  ),
  RegExp(r'^(Your|The) \w+ was (accepted|resolved|cancelled)$'),
  RegExp(r'moved (the request )?from \w+ to \w+$'),
  RegExp(r'^You and .+ are now connected\.$'),
  RegExp(r'^Your trust in .+ (increased|decreased) after ".*"\.$'),
  RegExp('^No significant trust change (with|from) .+ after ".*"'),
  RegExp(r' now trusts you (more|less) after ".*" — and their network\.$'),
  RegExp('^The review window closed on ".*" before your package was sent'),
];

/// The English labels the server uses as receipt titles (same sources as
/// [_serverCannedBodies]). Anything else in a title — an actor's name, a
/// Request title, a user's words — is left alone.
const _serverCannedTitles = {
  'Deadline changed',
  'Deadline reminder',
  'Asked of you',
  'Plan updated',
  'Blocker opened',
  'Blocker resolved',
  'Offer accepted',
  'Offer declined',
  'Removed from the discussion',
  'Participation ended',
  'Request closed — close the loop',
  'Still needs attention',
  'Invitation accepted',
  'Review closed',
  'Trust update',
  'Request status changed',
  'New connection',
  'Someone trusts you more',
  'Someone trusts you less',
  'Someone reviewed you',
  'Ancestor request status changed',
  // postExpiringSoon (#700): push and email say «Пост скоро истечёт».
  'Your post is about to expire',
  'Child request status changed',
};

bool _isServerCannedTitle(String text) => _serverCannedTitles.contains(text);

bool _isServerCannedSentence(String text) =>
    _serverCannedBodies.contains(text) ||
    _serverCannedPatterns.any((p) => p.hasMatch(text));
