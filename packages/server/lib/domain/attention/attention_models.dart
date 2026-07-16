import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

part 'attention_models.freezed.dart';

enum AttentionEventType {
  relayReceived,
  helpOfferSubmitted,
  offerAccepted,
  offerDeclined,
  offerRemoved,
  roomMessagePosted,
  requestStatusChanged,
  reviewOpened,
  mutualConnectionFormed,
  inviteAccepted,
  needsMe,
  blockerOpened,
  blockerResolved,
  promiseMade,
  promiseWithdrawn,
  coordinationChanged,
  staleReminder,
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
    AttentionDestinationKind.safeTerminal => 'safe_terminal',
  };
}

AttentionDestinationKind attentionDestinationKindFromWireName(String value) =>
    AttentionDestinationKind.values.firstWhere(
      (destination) => destination.wireName == value,
    );

enum AttentionFeedView { all, unread }

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
  }) = _AttentionReceipt;

  const AttentionReceipt._();

  bool get isUnread => seenAt == null;
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
  const factory AttentionSummary({required int unreadTotal}) =
      _AttentionSummary;
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
