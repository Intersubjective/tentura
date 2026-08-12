import 'dart:convert';

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

String _fallbackTitle(String? presentationKey, L10n l10n) =>
    switch (presentationKey) {
      'relay_received' => l10n.updatesFallbackTitleRelayReceived,
      'help_offer_submitted' => l10n.updatesFallbackTitleHelpOfferSubmitted,
      'offer_accepted' => l10n.updatesFallbackTitleOfferAccepted,
      'offer_declined' => l10n.updatesFallbackTitleOfferDeclined,
      'offer_removed' => l10n.updatesFallbackTitleOfferRemoved,
      'room_message_posted' => l10n.updatesFallbackTitleRoomMessagePosted,
      'request_status_changed' =>
        l10n.updatesFallbackTitleRequestStatusChanged,
      'review_opened' => l10n.updatesFallbackTitleReviewOpened,
      'mutual_connection_formed' =>
        l10n.updatesFallbackTitleMutualConnectionFormed,
      'invite_accepted' => l10n.updatesFallbackTitleInviteAccepted,
      'needs_me' => l10n.updatesFallbackTitleNeedsMe,
      'blocker_opened' => l10n.updatesFallbackTitleBlockerOpened,
      'blocker_resolved' => l10n.updatesFallbackTitleBlockerResolved,
      'promise_made' => l10n.updatesFallbackTitlePromiseMade,
      'promise_withdrawn' => l10n.updatesFallbackTitlePromiseWithdrawn,
      'coordination_changed' => l10n.updatesFallbackTitleCoordinationChanged,
      'stale_reminder' => l10n.updatesFallbackTitleStaleReminder,
      'commitment_accepted' => l10n.updatesFallbackTitleCommitmentAccepted,
      'commitment_resolved' => l10n.updatesFallbackTitleCommitmentResolved,
      'commitment_cancelled' => l10n.updatesFallbackTitleCommitmentCancelled,
      'commitment_redirected' => l10n.updatesFallbackTitleCommitmentRedirected,
      'trust_given_changed_up' ||
      'trust_given_changed_down' ||
      'trust_given_changed_neutral' =>
        l10n.updatesFallbackTitleTrustGivenChanged,
      'trust_received_changed_up' ||
      'trust_received_changed_down' ||
      'trust_received_changed_neutral' =>
        l10n.updatesFallbackTitleTrustReceivedChanged,
      _ => l10n.updatesFallbackTitleGeneric,
    };

String _fallbackBody(String? presentationKey, L10n l10n) =>
    switch (presentationKey) {
      'relay_received' => l10n.updatesFallbackBodyRelayReceived,
      'help_offer_submitted' => l10n.updatesFallbackBodyHelpOfferSubmitted,
      'offer_accepted' => l10n.updatesFallbackBodyOfferAccepted,
      'offer_declined' => l10n.updatesFallbackBodyOfferDeclined,
      'offer_removed' => l10n.updatesFallbackBodyOfferRemoved,
      'room_message_posted' => l10n.updatesFallbackBodyRoomMessagePosted,
      'request_status_changed' => l10n.updatesFallbackBodyRequestStatusChanged,
      'review_opened' => l10n.updatesFallbackBodyReviewOpened,
      'mutual_connection_formed' =>
        l10n.updatesFallbackBodyMutualConnectionFormed,
      'invite_accepted' => l10n.updatesFallbackBodyInviteAccepted,
      'needs_me' => l10n.updatesFallbackBodyNeedsMe,
      'blocker_opened' => l10n.updatesFallbackBodyBlockerOpened,
      'blocker_resolved' => l10n.updatesFallbackBodyBlockerResolved,
      'promise_made' => l10n.updatesFallbackBodyPromiseMade,
      'promise_withdrawn' => l10n.updatesFallbackBodyPromiseWithdrawn,
      'coordination_changed' => l10n.updatesFallbackBodyCoordinationChanged,
      'stale_reminder' => l10n.updatesFallbackBodyStaleReminder,
      'commitment_accepted' => l10n.updatesFallbackBodyCommitmentAccepted,
      'commitment_resolved' => l10n.updatesFallbackBodyCommitmentResolved,
      'commitment_cancelled' => l10n.updatesFallbackBodyCommitmentCancelled,
      'commitment_redirected' => l10n.updatesFallbackBodyCommitmentRedirected,
      'trust_given_changed_up' ||
      'trust_given_changed_down' ||
      'trust_given_changed_neutral' =>
        l10n.updatesFallbackBodyTrustGivenChanged,
      'trust_received_changed_up' ||
      'trust_received_changed_down' ||
      'trust_received_changed_neutral' =>
        l10n.updatesFallbackBodyTrustReceivedChanged,
      _ => l10n.updatesFallbackBodyGeneric,
    };
