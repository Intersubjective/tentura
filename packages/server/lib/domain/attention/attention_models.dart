import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

part 'attention_models.freezed.dart';

/// Machine-checkable lifecycle for entries in `updates-event-contract.json`
/// `eventClassifications` (schema ≥ 3).
enum AttentionEventCatalogStatus {
  supported,
  deliberatelySilent,
  retired,
}

AttentionEventCatalogStatus attentionEventCatalogStatusFromWireName(
  String value,
) => AttentionEventCatalogStatus.values.firstWhere(
  (status) => status.name == value,
);

/// Runtime guard paired with exhaustive switches in [AttentionPolicy].
abstract final class AttentionEventTypeCatalog {
  AttentionEventTypeCatalog._();

  static const int contractSchemaVersion = 5;

  static void assertDeclared(AttentionEventType eventType) {
    switch (eventType) {
      case AttentionEventType.relayReceived:
      case AttentionEventType.helpOfferSubmitted:
      case AttentionEventType.offerAccepted:
      case AttentionEventType.offerDeclined:
      case AttentionEventType.offerRemoved:
      case AttentionEventType.roomMessagePosted:
      case AttentionEventType.requestStatusChanged:
      case AttentionEventType.beaconHierarchyStatusChanged:
      case AttentionEventType.reviewOpened:
      case AttentionEventType.reviewAllPackagesIn:
      case AttentionEventType.reviewWindowCancelled:
      case AttentionEventType.obligationEnded:
      case AttentionEventType.mutualConnectionFormed:
      case AttentionEventType.inviteAccepted:
      case AttentionEventType.needsMe:
      case AttentionEventType.blockerOpened:
      case AttentionEventType.blockerResolved:
      case AttentionEventType.promiseMade:
      case AttentionEventType.promiseWithdrawn:
      case AttentionEventType.coordinationChanged:
      case AttentionEventType.staleReminder:
      case AttentionEventType.commitmentAccepted:
      case AttentionEventType.commitmentResolved:
      case AttentionEventType.commitmentCancelled:
      case AttentionEventType.commitmentRedirected:
      case AttentionEventType.commitmentReleased:
      case AttentionEventType.trustGivenChanged:
      case AttentionEventType.trustReceivedChanged:
      case AttentionEventType.deadlineChanged:
      case AttentionEventType.deadlineReminder:
        return;
    }
  }
}

enum AttentionEventType {
  relayReceived,
  helpOfferSubmitted,
  offerAccepted,
  offerDeclined,
  offerRemoved,
  roomMessagePosted,
  requestStatusChanged,
  beaconHierarchyStatusChanged,
  reviewOpened,
  reviewAllPackagesIn,
  reviewWindowCancelled,

  /// U07b2 / §5 "nothing disappears unexplained": an obligation that ended by
  /// expiry or by someone else's cancellation, never by the person's own act.
  obligationEnded,
  mutualConnectionFormed,
  inviteAccepted,
  needsMe,
  blockerOpened,
  blockerResolved,
  promiseMade,
  promiseWithdrawn,
  coordinationChanged,
  staleReminder,
  commitmentAccepted,
  commitmentResolved,
  commitmentCancelled,
  commitmentRedirected,
  commitmentReleased,
  trustGivenChanged,
  trustReceivedChanged,
  deadlineChanged,
  deadlineReminder,
}

extension AttentionEventTypeScope on AttentionEventType {
  bool get isBeaconScoped => switch (this) {
    AttentionEventType.mutualConnectionFormed ||
    AttentionEventType.inviteAccepted => false,
    _ => true,
  };
}

AttentionEventType attentionEventTypeFromWireName(String value) =>
    AttentionEventType.values.firstWhere((event) => event.name == value);

enum AttentionRecipientReason {
  targetOfAsk,
  authorOfBeacon,
  activeParticipant,
  affectedParticipant,
  roomModeratorOrSteward,
  admittedRoomMember,
  forwardRecipient,
  reviewParticipant,
  inboxStanceHolder,
  directedChatTarget,
  reciprocalCounterpart,
  inviter,
}

extension AttentionRecipientReasonScope on AttentionRecipientReason {
  /// Whether this event-time reason proves a relationship to the Beacon.
  ///
  /// Presentation projections may use that relationship to show the Beacon on
  /// a surface, but surface membership itself is never a domain input here.
  bool get isBeaconRelationship => switch (this) {
    AttentionRecipientReason.reciprocalCounterpart ||
    AttentionRecipientReason.inviter => false,
    _ => true,
  };
}

/// Why an obligation ended by something other than the person's own act
/// (§5 "nothing disappears unexplained"). One value per explanation copy.
enum AttentionObligationEndReason {
  /// The review window's deadline passed and the window closed itself.
  ///
  /// The only value today, and deliberately so (U07b2):
  /// * `EvaluationCase.closeNow` cannot leave an expired obligation behind —
  ///   it refuses unless every author/committer participant has already sent
  ///   (`_canCloseNow`), so there is nothing unexplained to explain.
  /// * The author *cancelling* a window (`EvaluationCase.reopenFromReview`)
  ///   supersedes the obligations and already emits `reviewWindowCancelled`
  ///   to the same reviewers; a second explanation would be noise.
  reviewWindowExpired,
}

enum AttentionSuppressionClass { mandatory, standard, noisy }

/// U11 / D16 — *where* a receipt is allowed to speak, as opposed to how loudly.
///
/// "Timeline-only is a placement policy, not a third actionable class": a
/// `timelineOnly` receipt is still an ordinary optional receipt — it is
/// visible, authorized and recoverable exactly like any other — but it is
/// excluded from every **primary-surface** indicator: no dot, no count, and
/// no effect on the position of the Request it belongs to.
///
/// This is the producer half of R7. Hierarchy lifecycle notices propagated to
/// an ancestor Request exist so the ancestor's log stays complete; they must
/// never make the ancestor *ask* for attention, because the thing that
/// happened belongs to the child's own attention object.
enum AttentionPlacement { primary, timelineOnly }

extension AttentionPlacementWireName on AttentionPlacement {
  /// The literal stored in `notification_outbox.placement` and declared as
  /// `placement` in `docs/contracts/updates-event-contract.json`.
  String get wireName => switch (this) {
    AttentionPlacement.primary => 'primary',
    AttentionPlacement.timelineOnly => 'timeline_only',
  };
}

enum AttentionAccessPolicy {
  legacy,
  beaconContent,
  beaconTombstone,
  recipientSafe,
  profile,
}

extension AttentionAccessPolicyWireName on AttentionAccessPolicy {
  String get wireName => switch (this) {
    AttentionAccessPolicy.legacy => 'legacy',
    AttentionAccessPolicy.beaconContent => 'beacon_content',
    AttentionAccessPolicy.beaconTombstone => 'beacon_tombstone',
    AttentionAccessPolicy.recipientSafe => 'recipient_safe',
    AttentionAccessPolicy.profile => 'profile',
  };
}

AttentionAccessPolicy attentionAccessPolicyFromWireName(String value) =>
    AttentionAccessPolicy.values.firstWhere(
      (policy) => policy.wireName == value,
    );

enum AttentionPreferenceClass { coordinationChurn, requestProgress }

extension AttentionPreferenceClassWireName on AttentionPreferenceClass {
  String get wireName => switch (this) {
    AttentionPreferenceClass.coordinationChurn => 'coordination_churn',
    AttentionPreferenceClass.requestProgress => 'request_progress',
  };
}

AttentionPreferenceClass attentionPreferenceClassFromWireName(String value) =>
    AttentionPreferenceClass.values.firstWhere(
      (preference) => preference.wireName == value,
    );

enum AttentionDestinationKind {
  beacon,
  beaconPeopleOffer,
  beaconRoom,
  beaconRoomMessage,
  review,
  profile,
  receivedReviews,
  safeTerminal,
}

extension AttentionDestinationKindWireName on AttentionDestinationKind {
  String get wireName => switch (this) {
    AttentionDestinationKind.beacon => 'beacon',
    AttentionDestinationKind.beaconPeopleOffer => 'beacon_people_offer',
    AttentionDestinationKind.beaconRoom => 'beacon_room',
    AttentionDestinationKind.beaconRoomMessage => 'beacon_room_message',
    AttentionDestinationKind.review => 'review',
    AttentionDestinationKind.profile => 'profile',
    AttentionDestinationKind.receivedReviews => 'received_reviews',
    AttentionDestinationKind.safeTerminal => 'safe_terminal',
  };
}

AttentionDestinationKind attentionDestinationKindFromWireName(String value) =>
    AttentionDestinationKind.values.firstWhere(
      (destination) => destination.wireName == value,
    );

enum AttentionFeedView { all, unread, needsYou }

enum AttentionSurface { myWork, activity }

AttentionSurface attentionSurfaceFromWireName(String value) =>
    AttentionSurface.values.firstWhere((surface) => surface.name == value);

enum AttentionItemKind { receipt, forward, watchingDigest, requestActivity }

AttentionItemKind attentionItemKindFromWireName(String value) =>
    AttentionItemKind.values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => AttentionItemKind.receipt,
    );

/// Newest-first preview size embedded on grouped Activity rows (regular/expanded
/// visible cap). Compact UI shows the first of these.
const kActivityEventPreviewCap = 3;

enum AttentionSettlementKind {
  resolved,
  dismissed,
  superseded,
  legacyArchived,
  expired,
}

extension AttentionSettlementKindWireName on AttentionSettlementKind {
  String get wireName => switch (this) {
    AttentionSettlementKind.resolved => 'resolved',
    AttentionSettlementKind.dismissed => 'dismissed',
    AttentionSettlementKind.superseded => 'superseded',
    AttentionSettlementKind.legacyArchived => 'legacy_archived',
    AttentionSettlementKind.expired => 'expired',
  };
}

AttentionSettlementKind attentionSettlementKindFromWireName(String value) =>
    AttentionSettlementKind.values.firstWhere(
      (kind) => kind.wireName == value,
    );

abstract final class AttentionCollapseKey {
  static String none(String sourceEventKey) =>
      'v1|none|${Uri.encodeComponent(sourceEventKey)}';

  static String family(String family, Iterable<String> subjects) =>
      'v1|${Uri.encodeComponent(family)}|'
      '${subjects.map(Uri.encodeComponent).join('|')}';
}

@freezed
abstract class AttentionRecipientRoleFacts with _$AttentionRecipientRoleFacts {
  const factory AttentionRecipientRoleFacts({
    @Default(false) bool canReadBeaconContent,
    String? beaconId,
    String? coordinationItemId,
    String? targetEntityId,
    String? messageId,
    String? actorUserId,
    String? beaconTitle,

    /// Trust direction for presentation-key encoding: `up`, `down`, `noChange`.
    ///
    /// Mirrors receiver-facing trust tone naming without coupling to evaluation
    /// domain types. Null and unmapped values fall through to a neutral key.
    String? trustDirection,

    /// Wire literal `'new_account'` or `'existing_account'` on inviteAccepted.
    String? inviteOrigin,
  }) = _AttentionRecipientRoleFacts;
}

@freezed
abstract class AttentionDestination with _$AttentionDestination {
  const factory AttentionDestination({
    required AttentionDestinationKind kind,
    String? targetEntityId,
  }) = _AttentionDestination;
}

@freezed
abstract class AttentionReceiptProjection with _$AttentionReceiptProjection {
  const factory AttentionReceiptProjection({
    required NotificationCategory category,
    required AttentionSuppressionClass suppressionClass,
    required AttentionAccessPolicy accessPolicy,
    required AttentionDestination destination,
    required String presentationKey,
    required Map<String, Object?> presentationPayload,
    @Default(false) bool requiresAction,
    String? attentionThreadKey,
    AttentionPreferenceClass? inAppPreferenceClass,
  }) = _AttentionReceiptProjection;
}

@freezed
abstract class AttentionRecipientSnapshot with _$AttentionRecipientSnapshot {
  const factory AttentionRecipientSnapshot({
    required String recipientId,
    required Set<AttentionRecipientReason> reasons,
    required AttentionRecipientRoleFacts role,
    String? collapseKey,
    @Default(true) bool channelEligible,
  }) = _AttentionRecipientSnapshot;
}

@freezed
abstract class AttentionDispatchIntent with _$AttentionDispatchIntent {
  const factory AttentionDispatchIntent({
    required AttentionEventType eventType,
    required String sourceEventKey,
    required String? actorUserId,
    required NotificationPriority priority,
    required NotificationKind kind,
    required String title,
    required String body,
    required String actionUrl,
    required String collapseKey,
    required List<AttentionRecipientSnapshot> recipients,
    String? beaconId,
    String? coordinationItemId,
    String? targetEntityId,
    String? messageId,
  }) = _AttentionDispatchIntent;
}

@freezed
abstract class AttentionChannelDecision with _$AttentionChannelDecision {
  const factory AttentionChannelDecision({
    required String receiptId,
    required String recipientId,
    required NotificationKind kind,
    required NotificationPriority priority,
    required String title,
    required String body,
    required String actionUrl,
    required String dedupKey,
    required String actorUserId,
    required String reason,
    String? beaconId,
    String? coordinationItemId,
  }) = _AttentionChannelDecision;
}

final class AttentionChannelDelivery {
  const AttentionChannelDelivery({required this.id, required this.decision});

  final String id;
  final AttentionChannelDecision decision;
}

@freezed
abstract class AttentionReceipt with _$AttentionReceipt {
  const factory AttentionReceipt({
    required String id,
    required String accountId,
    required NotificationCategory category,
    required NotificationKind kind,
    required NotificationPriority priority,
    required String title,
    required String body,
    required String actionUrl,
    required DateTime createdAt,
    required int collapsedCount,
    required AttentionSuppressionClass suppressionClass,
    required AttentionAccessPolicy accessPolicy,
    required Map<String, Object?> presentationPayload,
    String? beaconId,
    String? coordinationItemId,
    String? actorUserId,
    DateTime? seenAt,
    String? sourceEventKey,
    AttentionDestinationKind? destinationKind,
    String? targetEntityId,
    String? presentationKey,
    AttentionPreferenceClass? inAppPreferenceClass,
    @Default(false) bool requiresAction,
    String? attentionThreadKey,
    AttentionSettlementKind? settlementKind,
    DateTime? settledAt,
    String? settledByUserId,
    String? settledByOccurrenceId,

    /// U06b debt, paid in U10b: when the optional axis was cleared, and why.
    ///
    /// `null` means still active. The pair is written together (m0178 CHECK),
    /// so a non-null [clearedAt] always carries a [clearReason].
    DateTime? clearedAt,
    String? clearReason,
    required AttentionSurface surface,
    @Default(AttentionItemKind.receipt) AttentionItemKind itemKind,
    String? forwardOutcome,
    int? forwardCount,
    int? digestCount,

    /// Total represented Activity child events (grouped rows only).
    int? eventTotal,

    /// Unseen count among represented Activity children (grouped rows only).
    int? eventUnseenCount,

    /// Newest-first preview of child events (cap [kActivityEventPreviewCap]).
    @Default(<AttentionReceipt>[]) List<AttentionReceipt> eventsPreview,

    /// U10d — forward provenance for a grouped `beacon:` row (§0.1a).
    ///
    /// The **verbatim** `inbox_provenance_data` JSON document: `senders[]` of
    /// `{id, displayName, imageId, notePreview, reasonSlugs[], mr}`,
    /// `totalDistinctSenders` and `strongestNotePreview`. Carried as text and
    /// not re-modelled on purpose — the card spec forbids a second provenance
    /// DTO, so `InboxProvenance.parse` keeps working unchanged.
    ///
    /// `null` on anything that is not a grouped row, and on a grouped row the
    /// viewer may not read the content of. Senders the viewer is blocked from
    /// are absent from the list *and* from the count.
    String? provenanceJson,

    /// U10d — the header's Request identity (§0.1a `beacon.{…}`).
    ///
    /// All four are gated on the same content wall as [title]: `null` when the
    /// row is rendered as a tombstone.
    String? beaconAuthorId,
    String? beaconAuthorName,
    String? beaconAuthorImageId,
    String? beaconImageId,
    DateTime? beaconEndAt,

    /// U10d — whether the action row may offer «Переслать» (§4, §6.3).
    ///
    /// The live gate, not a constant: `BeaconStatus.allowsForward` (the
    /// open family) AND the viewer being allowed to read the Request at all.
    /// `null` on non-grouped rows.
    bool? allowsForward,
  }) = _AttentionReceipt;

  const AttentionReceipt._();

  /// The read axis (D02). Kept for History; no indicator reads it since U10b.
  bool get isUnread => seenAt == null;

  /// The optional axis (D02) — the Dart half of
  /// `AttentionDismissibleSql.activeOptional`.
  bool get isActiveOptional => !requiresAction && clearedAt == null;

  bool get isLiveObligation => requiresAction && settlementKind == null;

  /// What an indicator describes (D09, §6): uncleared optional or live
  /// obligation. Mirrors `AttentionDismissibleSql.activeAttention`.
  bool get isActiveAttention => isActiveOptional || isLiveObligation;
}

/// U10c — the current sort-key generation (D08: *version the cursor when
/// changing sort keys*).
///
/// Bumped from 1 when the pinned zone and the grouped feed stopped ordering
/// by `GREATEST(latest_forward_at, max child created_at)` and started
/// ordering by the position key. A cursor minted under the old keys names a
/// point on a line that no longer exists: keyset pagination resumed from it
/// would skip or repeat whole stretches of the list, silently. It is rejected
/// at the wire boundary instead, which costs the reader one head refetch and
/// no correctness.
const kAttentionCursorVersion = 2;

@freezed
abstract class AttentionCursor with _$AttentionCursor {
  const factory AttentionCursor({
    required DateTime createdAt,
    required String id,
    @Default(kAttentionCursorVersion) int version,
  }) = _AttentionCursor;
}

@freezed
abstract class AttentionSummary with _$AttentionSummary {
  const factory AttentionSummary({
    required int unreadTotal,
    @Default(0) int needsYouTotal,
  }) = _AttentionSummary;
}

@freezed
abstract class AttentionPage with _$AttentionPage {
  const factory AttentionPage({
    required List<AttentionReceipt> items,
    AttentionCursor? nextCursor,
  }) = _AttentionPage;
}

@freezed
abstract class AttentionFeed with _$AttentionFeed {
  const factory AttentionFeed({
    required AttentionSummary summary,
    required AttentionPage page,
  }) = _AttentionFeed;
}

@freezed
abstract class AttentionSurfaceSummary with _$AttentionSurfaceSummary {
  const factory AttentionSurfaceSummary({
    required int activityUnreadTotal,
    required int myWorkUnreadTotal,
    required int needsYouTotal,

    /// §6 `my desk.dot` — any owned Request has at least one uncleared
    /// optional event or uncleared outcome. A live obligation is deliberately
    /// **not** a term: it is the number beside the dot, and D09 keeps the two
    /// independent.
    @Default(false) bool myDeskDot,

    /// §6 `for you.dot` — any dismissible attention (Set R ∪ Set O), pending
    /// forward (the `eligible_pinned` zone) or pending prompt.
    ///
    /// There is no `forYouCount`, and there must not be one: §6 says
    /// `for you.count = never`, and a field nobody can read is how that stays
    /// true structurally rather than by convention.
    @Default(false) bool forYouDot,
  }) = _AttentionSurfaceSummary;
}

@freezed
abstract class MyWorkBeaconAttention with _$MyWorkBeaconAttention {
  const factory MyWorkBeaconAttention({
    required String beaconId,
    required int unseenCount,
    AttentionReceipt? latestUnseen,
    required List<AttentionReceipt> liveObligations,

    /// U10c — `Needs you` ordering (D08 #1): the newest live obligation on
    /// this Request. `null` when it has none, which sorts it below every
    /// Request that does.
    DateTime? needsYouAt,

    /// U10c — the stable tie-break behind [needsYouAt]: when this Request
    /// first entered the viewer's attention. Replaces the incidental
    /// `Beacon.updatedAt` the desk used to fall back on.
    DateTime? firstEntryAt,
  }) = _MyWorkBeaconAttention;
}

@freezed
abstract class ActivityBeaconAttention with _$ActivityBeaconAttention {
  const factory ActivityBeaconAttention({
    required String beaconId,
    required int eventTotal,
    required int unseenCount,
    required DateTime latestAt,
    required List<AttentionReceipt> events,
    AttentionCursor? nextCursor,
  }) = _ActivityBeaconAttention;
}

@freezed
abstract class ActivityOfferPage with _$ActivityOfferPage {
  const factory ActivityOfferPage({
    required List<ActivityOfferSortRow> items,
    required int totalCount,
    AttentionCursor? nextCursor,
  }) = _ActivityOfferPage;
}

/// Server-ordered «For you» row. Client hydrates InboxItem details separately.
@freezed
abstract class ActivityOfferSortRow with _$ActivityOfferSortRow {
  const factory ActivityOfferSortRow({
    required String beaconId,

    /// U10c — the **position** key: when this Request entered the pinned
    /// zone. Only an explicit state change moves it (D08); an optional event
    /// arriving, being cleared or being swept does not.
    required DateTime listPositionAt,

    /// U10c — the **latest-event** key: how fresh the card's noise is.
    /// Rendered, never ordered by.
    required DateTime effectiveActivityAt,
    required DateTime latestForwardAt,
    required bool unseen,
    required int eventTotal,
    required int eventUnseenCount,
    @Default(<AttentionReceipt>[]) List<AttentionReceipt> eventsPreview,
  }) = _ActivityOfferSortRow;
}
