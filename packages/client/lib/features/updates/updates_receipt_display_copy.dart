import 'dart:convert';

import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';

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
        ? _fallbackBody(
            presentationKey,
            l10n,
            beaconTitleFromPresentationPayload(presentationPayloadJson),
          )
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

/// In-app Updates composition for invite-accepted receipts.
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
  if (profile == null) {
    return InviteAcceptedDisplayCopy(
      title: fallback.title,
      body: fallback.body,
    );
  }

  final shown = profile.shownName.trim();
  final public = profile.canonicalPublicLabel;
  final title = shown.isNotEmpty
      ? shown
      : (public.isNotEmpty ? public : fallback.title);
  final secondary = profile.canonicalSecondaryLabel;
  final origin = inviteOriginFromPresentationPayload(presentationPayloadJson);
  final originBody = switch (origin) {
    'new_account' => l10n.updatesInviteAcceptedBodyNewAccount,
    'existing_account' => l10n.updatesInviteAcceptedBodyExistingAccount,
    _ => null,
  };
  return InviteAcceptedDisplayCopy(
    title: title,
    body: originBody ?? fallback.body,
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
  'review_opened' => l10n.updatesFallbackTitleReviewOpened,
  'review_all_packages_in' => l10n.updatesFallbackTitleReviewAllIn,
  'review_window_cancelled' => l10n.updatesFallbackTitleReviewCancelled,
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
  'coordination_changed' => l10n.updatesFallbackTitleCoordinationChanged,
  'deadline_changed' => l10n.updatesFallbackTitleDeadlineChanged,
  'deadline_reminder' => l10n.updatesFallbackTitleDeadlineReminder,
  'stale_reminder' => l10n.updatesFallbackTitleStaleReminder,
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
  String? beaconTitle,
) => switch (presentationKey) {
  'relay_received' => l10n.updatesFallbackBodyRelayReceived,
  'help_offer_submitted' => l10n.updatesFallbackBodyHelpOfferSubmitted,
  'offer_accepted' => l10n.updatesFallbackBodyOfferAccepted,
  'offer_declined' => l10n.updatesFallbackBodyOfferDeclined,
  'offer_removed' => l10n.updatesFallbackBodyOfferRemoved,
  'room_message_posted' => l10n.updatesFallbackBodyRoomMessagePosted,
  'request_status_changed' => l10n.updatesFallbackBodyRequestStatusChanged,
  'review_opened' => l10n.updatesFallbackBodyReviewOpened,
  'review_all_packages_in' when beaconTitle != null =>
    l10n.updatesFallbackBodyReviewAllIn(beaconTitle),
  'review_window_cancelled' when beaconTitle != null =>
    l10n.updatesFallbackBodyReviewCancelled(beaconTitle),
  'mutual_connection_formed' => l10n.updatesFallbackBodyMutualConnectionFormed,
  'invite_accepted' => l10n.updatesFallbackBodyInviteAccepted,
  'needs_me' => l10n.updatesFallbackBodyNeedsMe,
  'blocker_opened' => l10n.updatesFallbackBodyBlockerOpened,
  'blocker_resolved' => l10n.updatesFallbackBodyBlockerResolved,
  'promise_made' => l10n.updatesFallbackBodyPromiseMade,
  'promise_withdrawn' => l10n.updatesFallbackBodyPromiseWithdrawn,
  'coordination_changed' => l10n.updatesFallbackBodyCoordinationChanged,
  'deadline_changed' => l10n.updatesFallbackBodyDeadlineChanged,
  'deadline_reminder' => l10n.updatesFallbackBodyDeadlineReminder,
  'stale_reminder' => l10n.updatesFallbackBodyStaleReminder,
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

/// Maps server title/body + payload into a non-duplicating two-line row.
UpdatesFeedRowCopy resolveUpdatesFeedRowCopy({
  required String title,
  required String body,
  required String? presentationKey,
  required String presentationPayloadJson,
  required L10n l10n,
  String? headlineOverride,
  String? bodyOverride,
}) {
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
  final override = headlineOverride?.trim();
  final eventTitle = title.trim().isEmpty ? fallback.title : title.trim();
  // An English server label reads in the locale instead; a title that is a
  // name or a Request title is data and stays.
  final localizedHeadline = _isServerCannedTitle(eventTitle)
      ? cannedAttentionEventLine(
              title: title,
              body: body,
              presentationKey: presentationKey,
              l10n: l10n,
            ) ??
            _fallbackTitle(presentationKey, l10n)
      : eventTitle;
  final headline = (override != null && override.isNotEmpty)
      ? override
      : localizedHeadline;

  final bodyOverrideTrim = bodyOverride?.trim();
  var excerpt = (bodyOverrideTrim != null && bodyOverrideTrim.isNotEmpty)
      ? bodyOverrideTrim
      : body.trim();
  if (excerpt.isEmpty) excerpt = fallback.body;

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
  if (subjectOverride != null && subjectOverride != headline) {
    line2 = subjectOverride;
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

final _statusTransitionTail = RegExp(r'from (\w+) to (\w+)\s*$');

/// The event line for a receipt whose server copy is canned English that only
/// restates the event — «X offered help», «X moved the request from a to b».
///
/// Returns null when the copy carries something of its own (a help-offer
/// note), so the caller keeps it. A non-null result replaces both lines: the
/// canned body is never worth quoting under it.
String? cannedAttentionEventLine({
  required String title,
  required String body,
  required String? presentationKey,
  required L10n l10n,
}) {
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
      final canned = b.isEmpty || b == '$t offered help' || b == t;
      return canned ? l10n.updatesFallbackTitleHelpOfferSubmitted : null;
    case 'request_status_changed':
      final to = _statusTransitionTail.firstMatch(b)?.group(2);
      final status = to == null ? null : BeaconStatus.values.asNameMap()[to];
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
/// the body is «<Request title> — <excerpt>», the bare Request title, or an
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
}) {
  final requestTitles = {
    ?_nonBlank(requestTitle),
    ?beaconTitleFromPresentationPayload(presentationPayloadJson),
  };
  final t = title.trim();
  final canned = cannedAttentionEventLine(
    title: title,
    body: body,
    presentationKey: presentationKey,
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
  'You are now connected on Tentura.',
};

final _serverCannedPatterns = [
  RegExp(
    r' (offered help|offered to help as backup|withdrew their help|'
    r'forwarded a request to you|mentioned you|accepted your invitation)$',
  ),
  RegExp(r'^(Your|The) \w+ was (accepted|resolved|cancelled)$'),
  RegExp(r'moved (the request )?from \w+ to \w+$'),
  RegExp(r'^You and .+ are now connected\.$'),
  RegExp(r'^Your trust in .+ (increased|decreased) after ".*"\.$'),
  RegExp(r'^No significant trust change (with|from) .+ after ".*"'),
  RegExp(r' now trusts you (more|less) after ".*" — and their network\.$'),
  RegExp(r'^The review window closed on ".*" before your package was sent'),
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
  'Child request status changed',
};

bool _isServerCannedTitle(String text) => _serverCannedTitles.contains(text);

bool _isServerCannedSentence(String text) =>
    _serverCannedBodies.contains(text) ||
    _serverCannedPatterns.any((p) => p.hasMatch(text));
