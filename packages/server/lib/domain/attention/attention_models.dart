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

  static const int contractSchemaVersion = 3;

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

enum AttentionSuppressionClass { mandatory, standard, noisy }

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
  }) = _AttentionReceipt;

  const AttentionReceipt._();

  bool get isUnread => seenAt == null;
  bool get isLiveObligation => requiresAction && settlementKind == null;
}

@freezed
abstract class AttentionCursor with _$AttentionCursor {
  const factory AttentionCursor({
    required DateTime createdAt,
    required String id,
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
  }) = _AttentionSurfaceSummary;
}

@freezed
abstract class MyWorkBeaconAttention with _$MyWorkBeaconAttention {
  const factory MyWorkBeaconAttention({
    required String beaconId,
    required int unseenCount,
    AttentionReceipt? latestUnseen,
    required List<AttentionReceipt> liveObligations,
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
    required DateTime effectiveActivityAt,
    required DateTime latestForwardAt,
    required bool unseen,
    required int eventTotal,
    required int eventUnseenCount,
    @Default(<AttentionReceipt>[]) List<AttentionReceipt> eventsPreview,
  }) = _ActivityOfferSortRow;
}
