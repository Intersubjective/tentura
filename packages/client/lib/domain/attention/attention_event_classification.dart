import 'dart:convert';

/// How a receipt's headline is written on a card (issue-171 card spec §6.1).
///
/// Mirrors `eventClassifications[].variants[].headlineTreatment` in
/// `docs/contracts/updates-event-contract.json`.
enum AttentionHeadlineTreatment {
  /// The Request is the subject: the title, quoted, attributed to its author.
  beacon,

  /// A person is the subject: bare name plus avatar.
  user,

  /// The system is the subject: a bare label, no actor.
  system,
}

/// The card-relevant half of one contract classification row.
class AttentionEventClassification {
  const AttentionEventClassification({
    required this.headlineTreatment,
    required this.coalescible,
  });

  final AttentionHeadlineTreatment headlineTreatment;

  /// Whether same-kind rows may be folded into one counted line (§7.3 E11).
  /// `false` means the row carries information that exists nowhere else on the
  /// card — a personal note — so folding it destroys it (K6).
  final bool coalescible;
}

/// The client mirror of the contract's `eventClassifications`, keyed by
/// `eventType`.
///
/// The server mirrors the same contract in `AttentionPolicy.placement` and
/// proves the two agree in `updates_event_contract_test.dart`; this map is the
/// card's half of that arrangement, and
/// `test/features/inbox/attention_event_classification_test.dart` reads the
/// contract file itself and fails the moment the contract declares a variant
/// this map does not know, or disagrees with one it does.
///
/// Keyed by event type alone, which the same test proves legitimate: no
/// declared event type has variants that differ in either field. If one ever
/// does, that test fails rather than this map answering with a coin flip.
const attentionEventClassifications = <String, AttentionEventClassification>{
  'relayReceived': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: false,
  ),
  'helpOfferSubmitted': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'offerAccepted': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'offerDeclined': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'offerRemoved': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'commitmentReleased': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'roomMessagePosted': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'requestStatusChanged': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'beaconHierarchyStatusChanged': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'reviewOpened': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'reviewAllPackagesIn': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'reviewWindowCancelled': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'obligationEnded': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: false,
  ),
  'mutualConnectionFormed': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.user,
    coalescible: true,
  ),
  'inviteAccepted': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.user,
    coalescible: true,
  ),
  'needsMe': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'blockerOpened': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'blockerResolved': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'promiseMade': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'promiseWithdrawn': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'coordinationChanged': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'staleReminder': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.system,
    coalescible: true,
  ),
  'commitmentAccepted': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'commitmentResolved': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'commitmentCancelled': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'commitmentRedirected': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'trustGivenChanged': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'trustReceivedChanged': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'deadlineChanged': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.beacon,
    coalescible: true,
  ),
  'deadlineReminder': AttentionEventClassification(
    headlineTreatment: AttentionHeadlineTreatment.system,
    coalescible: true,
  ),
};

/// What an unreadable or unknown `eventType` classifies as.
///
/// Written explicitly rather than defaulted implicitly, because both halves
/// are load-bearing:
///
/// * `coalescible: false` — coalescing is the only lossy operation the card
///   performs. Refusing to fold a row we cannot identify costs one line;
///   folding one that turns out to carry a note destroys the note (§7.3 K6).
/// * `headlineTreatment: beacon` — For You groups by Request, so a row that
///   reaches a card is under that Request's headline by construction. Reading
///   it as `user` or `system` would drop the attribution the card is built on.
const kUnknownAttentionEventClassification = AttentionEventClassification(
  headlineTreatment: AttentionHeadlineTreatment.beacon,
  coalescible: false,
);

/// Classification for [eventType], or [kUnknownAttentionEventClassification]
/// when it is null, empty or one the contract has not declared here.
AttentionEventClassification classifyAttentionEvent(String? eventType) {
  final key = eventType?.trim() ?? '';
  if (key.isEmpty) return kUnknownAttentionEventClassification;
  return attentionEventClassifications[key] ??
      kUnknownAttentionEventClassification;
}

/// The `eventType` the server writes into every receipt's presentation
/// payload (`AttentionPolicy._presentationPayload`). Null when the payload is
/// absent, unparseable, or carries no event type.
String? attentionEventTypeOf(String? presentationPayloadJson) {
  final raw = presentationPayloadJson?.trim() ?? '';
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final eventType = decoded['eventType'];
    if (eventType is! String) return null;
    final trimmed = eventType.trim();
    return trimmed.isEmpty ? null : trimmed;
  } on Object {
    return null;
  }
}

/// [classifyAttentionEvent] straight off a receipt's presentation payload.
AttentionEventClassification classifyAttentionEventPayload(
  String? presentationPayloadJson,
) => classifyAttentionEvent(attentionEventTypeOf(presentationPayloadJson));
