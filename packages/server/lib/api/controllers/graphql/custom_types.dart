import 'package:graphql_schema2/graphql_schema2.dart';

import 'input/_input_types.dart';

List<GraphQLType<dynamic, dynamic>> get customTypes => [
  InputFieldCoordinates.type,
  InputFieldForwardRecipientReasons.type,
  InputFieldUpload.type,
  gqlTypeAuthResponse,
  gqlTypeInvitation,
  gqlTypeInviteGenealogy,
  gqlTypeInviteGenealogyChildrenPage,
  gqlTypeInviteGenealogyChildCount,
  gqlTypeInviteGenealogyNode,
  gqlTypeInviteGenealogyEdge,
  gqlTypeProfile,
  gqlTypeBeacon,
  gqlTypeBeaconImageAdded,
  gqlTypeBeaconImageStaged,
  gqlTypeMyForwardRecipient,
  gqlTypeBeaconInvolvement,
  gqlTypeForwardDeliveryResult,
  gqlTypeForwardGraphEdge,
  gqlTypeForwardGraphResult,
  gqlTypeForwardCandidateConnectionNode,
  gqlTypeForwardCandidateContext,
  gqlTypeConstellationPeer,
  gqlTypeConstellationEdge,
  gqlTypeConstellationRequest,
  gqlEnumConstellationProjection,
  gqlEnumConstellationAnchorTargetKind,
  gqlTypeConstellationAnchor,
  gqlTypeConstellationAnchorProjection,
  gqlTypeConstellationAnchorUpsertResult,
  gqlTypeConstellationAnchorDeleteResult,
  gqlTypeConstellationField,
  gqlTypeMutualScore,
  gqlTypeImagePublic,
  gqlTypeUserPresence,
  gqlTypeUserPublic,
  gqlTypeUserContact,
  gqlTypeBlockIntent,
  gqlTypeBlockPreview,
  gqlTypeBeaconCloseReviewResult,
  gqlTypeBeaconExtendReviewResult,
  gqlTypeEvaluationParticipant,
  gqlTypeEvaluationDraftRow,
  gqlTypeReviewWindowStatus,
  gqlTypeEvaluationSummary,
  gqlTypeEvaluationReceived,
  gqlTypeEvaluationReceivedRow,
  gqlTypeEvaluationsWrittenAboutViewerRow,
  gqlTypeCoordinationStatusResult,
  gqlTypeBeaconDisplayStatus,
  gqlTypeHelpOfferWithCoordinationRow,
  gqlTypeRoomMessageCreatePayload,
  gqlTypeRoomMessageRow,
  gqlTypeBeaconRoomStateRow,
  gqlTypeBeaconParticipantRow,
  gqlTypeBeaconFactCardRow,
  gqlTypeBeaconActivityEventRow,
  gqlTypeInboxRoomContextRow,
  gqlTypeBeaconRoomSeenResult,
  gqlTypeTagCount,
  gqlTypeTagBeaconRef,
  gqlTypeCapabilityForViewer,
  gqlTypePersonCapabilityCuesPayload,
  gqlTypeForwardReasonRow,
  gqlTypePersonTopCapabilities,
  gqlTypePersonFriendContext,
  gqlTypePersonSharedContext,
  gqlTypeTagProjection,
  gqlTypeForwardBandRow,
  gqlTypeInviteSeedPromptState,
  gqlTypeCoordinationItemRow,
  gqlTypeCoordinationResponsibilityBatchRow,
  gqlTypeBeaconItemsSeenResult,
  gqlTypeMyWorkLastActivityEventRow,
  gqlTypeThreadMessagePreview,
  gqlTypeBeaconThreadRow,
  gqlTypeBeaconLineageSuggestion,
  gqlTypeBeaconLineageForwardSuggestions,
  gqlTypeBeaconHierarchyCapabilities,
  gqlTypeBeaconHierarchyOwnerSummary,
  gqlTypeBeaconHierarchySummary,
  gqlTypeBeaconHierarchyPage,
  gqlTypeBeaconParentReference,
  gqlTypeBeaconPromotionSource,
  gqlTypeBeaconChildCreateResult,
  gqlTypeNotificationPreferences,
  gqlTypeFcmTestSendResult,
  gqlTypeEmailTestSendResult,
  gqlTypeUserRecalculateBookkeepingResult,
];

/// Account notification preferences (channel × category matrix + controls).
final gqlTypeNotificationPreferences =
    GraphQLObjectType('NotificationPreferences', null)
      ..fields.addAll([
        field('accountId', graphQLString.nonNullable()),
        field(
          'pushCategories',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field(
          'emailCategories',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field(
          'mutedInAppEventClasses',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field('quietHoursStart', graphQLInt),
        field('quietHoursEnd', graphQLInt),
        field('tzOffsetMinutes', graphQLInt.nonNullable()),
        field('emailDigest', graphQLString.nonNullable()),
        field('snoozeUntil', graphQLString),
        field('lockScreenSafe', graphQLBoolean.nonNullable()),
        field('locale', graphQLString.nonNullable()),
      ]);

final GraphQLObjectType gqlTypeAttentionReceipt = () {
  final type = GraphQLObjectType('AttentionReceipt', null);
  type.fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('category', graphQLString.nonNullable()),
    field('kind', graphQLString.nonNullable()),
    field('priority', graphQLString.nonNullable()),
    field('title', graphQLString.nonNullable()),
    field('body', graphQLString.nonNullable()),
    field('actionUrl', graphQLString.nonNullable()),
    field('createdAt', graphQLString.nonNullable()),
    field('seenAt', graphQLString),
    field('collapsedCount', graphQLInt.nonNullable()),
    field('beaconId', graphQLString),
    field('coordinationItemId', graphQLString),
    field('actorUserId', graphQLString),
    field('sourceEventKey', graphQLString),
    field('destinationKind', graphQLString),
    field('targetEntityId', graphQLString),
    field('presentationKey', graphQLString),
    field('presentationPayloadJson', graphQLString.nonNullable()),
    field('inAppPreferenceClass', graphQLString),
    field('requiresAction', graphQLBoolean.nonNullable()),
    field('attentionThreadKey', graphQLString),
    field('settlementKind', graphQLString),
    field('settledAt', graphQLString),
    field('clearedAt', graphQLString),
    field('clearReason', graphQLString),
    field('surface', graphQLString.nonNullable()),
    field('itemKind', graphQLString.nonNullable()),
    field('forwardOutcome', graphQLString),
    field('forwardCount', graphQLInt),
    field('digestCount', graphQLInt),
    field('eventTotal', graphQLInt),
    field('eventUnseenCount', graphQLInt),
    field(
      'eventsPreview',
      GraphQLListType(type.nonNullable()).nonNullable(),
    ),
    // U10d (§0.1a) — grouped `beacon:` rows only. `provenanceJson` is the
    // verbatim `inbox_provenance_data` document, so the client parses it with
    // the `InboxProvenance` it already has rather than a second DTO.
    field('provenanceJson', graphQLString),
    field('beaconAuthorId', graphQLString),
    field('beaconAuthorName', graphQLString),
    field('beaconAuthorImageId', graphQLString),
    field('beaconImageId', graphQLString),
    field('beaconEndAt', graphQLString),
    field('allowsForward', graphQLBoolean),
  ]);
  return type;
}();
final gqlTypeAttentionSurfaceSummary =
    GraphQLObjectType('AttentionSurfaceSummary', null)
      ..fields.addAll([
        field('activityUnreadTotal', graphQLInt.nonNullable()),
        field('myWorkUnreadTotal', graphQLInt.nonNullable()),
        field('needsYouTotal', graphQLInt.nonNullable()),
        // §6 indicators. The three above are the legacy totals and retire in
        // U18; these three are the rules §6 actually states. There is no
        // `forYouCount` field because §6 says `for you.count = never`.
        field('myDeskDot', graphQLBoolean.nonNullable()),
        field('myDeskCount', graphQLInt.nonNullable()),
        field('forYouDot', graphQLBoolean.nonNullable()),
        // U16c-1 — enablement for the For You *Dismiss all* control. Not
        // `forYouDot`: that includes the pinned decision zone the sweep never
        // touches.
        field('forYouSweepEligible', graphQLBoolean.nonNullable()),
      ]);

final gqlTypeAttentionReconcileResult =
    GraphQLObjectType('AttentionReconcileResult', null)
      ..fields.addAll([
        field('createdObligationCount', graphQLInt.nonNullable()),
        field('settledObligationCount', graphQLInt.nonNullable()),
        field('unrepairableObligationCount', graphQLInt.nonNullable()),
        field('summary', gqlTypeAttentionSurfaceSummary.nonNullable()),
      ]);

final gqlTypeAttentionClearSnapshot =
    GraphQLObjectType('AttentionClearSnapshot', null)
      ..fields.addAll([
        field('snapshotToken', graphQLString.nonNullable()),
        field(
          'receiptIds',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field('outcomeGeneration', graphQLInt.nonNullable()),
        field('decisionRevision', graphQLInt.nonNullable()),
      ]);

final gqlTypeAttentionClearResult =
    GraphQLObjectType('AttentionClearResult', null)
      ..fields.addAll([
        field('operationId', graphQLString.nonNullable()),
        field(
          'appliedReceiptIds',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field(
          'skippedReceiptIds',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field(
          'deniedReceiptIds',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field('status', graphQLString.nonNullable()),
        // U15R-a / R3: an explicit dismissal is undoable for a bounded window
        // (contract §4, D13), so it carries the same offer a sweep does. Null
        // when the operation cleared nothing — there is no affordance then.
        field('undoToken', graphQLString),
        field('undoDeadline', graphQLString),
      ]);

/// One member a sweep refused, and why. A skip without a reason is not a
/// report: "the forward is awaiting your answer again" and "you may no longer
/// read this" are different facts about the world.
final gqlTypeAttentionSweepMember =
    GraphQLObjectType('AttentionSweepMember', null)
      ..fields.addAll([
        field('kind', graphQLString.nonNullable()),
        field('id', graphQLString.nonNullable()),
        field('reason', graphQLString),
      ]);

/// Result of `attentionDismissAll`. `appliedCount` counts both axes, because
/// one sweep spans both: receipts on `cleared_at`, outcomes on
/// `tombstone_dismissed_at`.
final gqlTypeAttentionDismissAllResult =
    GraphQLObjectType('AttentionDismissAllResult', null)
      ..fields.addAll([
        field('operationId', graphQLString.nonNullable()),
        field(
          'appliedReceiptIds',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field(
          'appliedOutcomeBeaconIds',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field('appliedCount', graphQLInt.nonNullable()),
        field(
          'skipped',
          GraphQLListType(
            gqlTypeAttentionSweepMember.nonNullable(),
          ).nonNullable(),
        ),
        field(
          'failed',
          GraphQLListType(
            gqlTypeAttentionSweepMember.nonNullable(),
          ).nonNullable(),
        ),
        field('pendingCount', graphQLInt.nonNullable()),
        field('status', graphQLString.nonNullable()),
        // The undo window this sweep opened, if it cleared anything. Both are
        // null together: no token means no undo affordance to offer.
        field('undoToken', graphQLString),
        field('undoDeadline', graphQLString),
      ]);

/// One member an undo did not restore, and why. Same shape as the sweep's
/// member, different vocabulary: a sweep refuses to clear, an undo refuses to
/// put back, and the reasons are not interchangeable.
final gqlTypeAttentionUndoMember =
    GraphQLObjectType('AttentionUndoMember', null)
      ..fields.addAll([
        field('kind', graphQLString.nonNullable()),
        field('id', graphQLString.nonNullable()),
        field('reason', graphQLString),
      ]);

/// Result of `attentionUndo`.
///
/// `refusal` is set only when the whole operation was refused — an expired
/// window, an operation that is not the caller's, one that never applied
/// anything. It is a value rather than an error precisely because "the undo
/// window has passed" is a thing a person is told, not a thing that fails.
final gqlTypeAttentionUndoResult =
    GraphQLObjectType('AttentionUndoResult', null)
      ..fields.addAll([
        field('operationId', graphQLString.nonNullable()),
        field(
          'restoredReceiptIds',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field(
          'restoredOutcomeBeaconIds',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field('restoredCount', graphQLInt.nonNullable()),
        field(
          'skipped',
          GraphQLListType(
            gqlTypeAttentionUndoMember.nonNullable(),
          ).nonNullable(),
        ),
        field(
          'failed',
          GraphQLListType(
            gqlTypeAttentionUndoMember.nonNullable(),
          ).nonNullable(),
        ),
        field('status', graphQLString.nonNullable()),
        field('refusal', graphQLString),
      ]);

final gqlTypeAttentionSummary = GraphQLObjectType('AttentionSummary', null)
  ..fields.addAll([
    field('unreadTotal', graphQLInt.nonNullable()),
    field('needsYouTotal', graphQLInt.nonNullable()),
  ]);

final gqlTypeAttentionPage = GraphQLObjectType('AttentionPage', null)
  ..fields.addAll([
    field(
      'items',
      GraphQLListType(gqlTypeAttentionReceipt.nonNullable()).nonNullable(),
    ),
    field('nextCursor', graphQLString),
  ]);

final gqlTypeAttentionFeed = GraphQLObjectType('AttentionFeed', null)
  ..fields.addAll([
    field('summary', gqlTypeAttentionSummary.nonNullable()),
    field('page', gqlTypeAttentionPage.nonNullable()),
  ]);

final gqlTypeAttentionMarkers = GraphQLObjectType('AttentionMarkers', null)
  ..fields.addAll([
    field(
      'unreadBeaconIds',
      GraphQLListType(graphQLString.nonNullable()).nonNullable(),
    ),
  ]);

final gqlTypeMyWorkBeaconAttention =
    GraphQLObjectType('MyWorkBeaconAttention', null)
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('unseenCount', graphQLInt.nonNullable()),
        field('latestUnseen', gqlTypeAttentionReceipt),
        field(
          'liveObligations',
          GraphQLListType(gqlTypeAttentionReceipt.nonNullable()).nonNullable(),
        ),
        // U10c - the `Needs you` sort keys, exposed so the desk orders by the
        // contract's key instead of `Beacon.updatedAt`.
        field('needsYouAt', graphQLString),
        field('firstEntryAt', graphQLString),
      ]);

final gqlTypeActivityOfferSortRow =
    GraphQLObjectType('ActivityOfferSortRow', null)
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        // U10c - the position key the zone is ordered by; the field below is
        // the latest-event key, which is rendered and never ordered by.
        field('listPositionAt', graphQLString.nonNullable()),
        field('effectiveActivityAt', graphQLString.nonNullable()),
        field('latestForwardAt', graphQLString.nonNullable()),
        field('unseen', graphQLBoolean.nonNullable()),
        field('eventTotal', graphQLInt.nonNullable()),
        field('eventUnseenCount', graphQLInt.nonNullable()),
        field(
          'eventsPreview',
          GraphQLListType(gqlTypeAttentionReceipt.nonNullable()).nonNullable(),
        ),
      ]);

final gqlTypeActivityOfferPage = GraphQLObjectType('ActivityOfferPage', null)
  ..fields.addAll([
    field(
      'items',
      GraphQLListType(gqlTypeActivityOfferSortRow.nonNullable()).nonNullable(),
    ),
    field('totalCount', graphQLInt.nonNullable()),
    field('nextCursor', graphQLString),
  ]);

final gqlTypeActivityBeaconAttention =
    GraphQLObjectType('ActivityBeaconAttention', null)
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('eventTotal', graphQLInt.nonNullable()),
        field('unseenCount', graphQLInt.nonNullable()),
        field('latestAt', graphQLString.nonNullable()),
        field(
          'events',
          GraphQLListType(gqlTypeAttentionReceipt.nonNullable()).nonNullable(),
        ),
        field('nextCursor', graphQLString),
      ]);

/// Payload returned by `RoomMessageCreate`.
final gqlTypeRoomMessageCreatePayload =
    GraphQLObjectType('RoomMessageCreatePayload', null)
      ..fields.addAll([
        field('id', graphQLString.nonNullable()),
      ]);

/// V2 room chat message row (minimal projection).
final gqlTypeRoomMessageRow = GraphQLObjectType('RoomMessageRow', null)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('beaconId', graphQLString.nonNullable()),
    field('authorId', graphQLString.nonNullable()),
    field('body', graphQLString.nonNullable()),
    field('createdAt', graphQLString.nonNullable()),
    field('editedAt', graphQLString),
    field('semanticMarker', graphQLInt),
    field('systemMessageKind', graphQLInt),
    field('linkedBlockerId', graphQLString),
    field('linkedFactCardId', graphQLString),
    field('linkedPollingId', graphQLString),
    field('linkedItemId', graphQLString),
    field('linkedEventKind', graphQLInt),
    field('linkedItemKind', graphQLInt),
    field('linkedItemStatus', graphQLInt),
    field('linkedItemTitle', graphQLString),
    field('linkedItemBody', graphQLString),
    field('linkedItemCreatorId', graphQLString),
    field('linkedItemTargetPersonId', graphQLString),
    field('linkedItemCreatedAt', graphQLString),
    field('linkedItemUpdatedAt', graphQLString),
    field('linkedItemLinkedMessageId', graphQLString),
    field('linkedItemResolvedAt', graphQLString),
    field('pollDataJson', graphQLString),
    field('systemPayloadJson', graphQLString),
    field('authorTitle', graphQLString.nonNullable()),
    field('authorHasPicture', graphQLBoolean.nonNullable()),
    field('authorPicHeight', graphQLInt.nonNullable()),
    field('authorPicWidth', graphQLInt.nonNullable()),
    field('authorBlurHash', graphQLString.nonNullable()),
    field('authorImageId', graphQLString.nonNullable()),
    field('reactionsJson', graphQLString),
    field('myReaction', graphQLString),
    field('reactorsJson', graphQLString),
    field('attachmentsJson', graphQLString.nonNullable()),
    field('mentionSpansJson', graphQLString.nonNullable()),
    field(
      'mentions',
      GraphQLListType(graphQLString.nonNullable()),
    ),
    field('threadItemId', graphQLString),
    field('replyToMessageId', graphQLString),
    field('replyToAuthorId', graphQLString),
    field('replyToAuthorTitle', graphQLString),
    field('replyToBodyExcerpt', graphQLString),
    field('replyToHasAttachments', graphQLBoolean),
  ]);

/// `beacon_room_state` row — one per beacon.
final gqlTypeBeaconRoomStateRow = GraphQLObjectType('BeaconRoomStateRow', null)
  ..fields.addAll([
    field('beaconId', graphQLString.nonNullable()),
    field('currentLine', graphQLString.nonNullable()),
    field('openBlockerId', graphQLString),
    field('openBlockerTitle', graphQLString),
    field('lastRoomMeaningfulChange', graphQLString),
    field('updatedAt', graphQLString.nonNullable()),
    field('updatedBy', graphQLString),
  ]);

/// Participant row for BeaconParticipantList (selection via V2 only).
final gqlTypeBeaconParticipantRow =
    GraphQLObjectType('BeaconParticipantRow', null)
      ..fields.addAll([
        field('id', graphQLString.nonNullable()),
        field('beaconId', graphQLString.nonNullable()),
        field('userId', graphQLString.nonNullable()),
        field('userTitle', graphQLString.nonNullable()),
        field('userHasPicture', graphQLBoolean.nonNullable()),
        field('userPicHeight', graphQLInt.nonNullable()),
        field('userPicWidth', graphQLInt.nonNullable()),
        field('userBlurHash', graphQLString.nonNullable()),
        field('userImageId', graphQLString.nonNullable()),
        field('userHandle', graphQLString),
        field('role', graphQLInt.nonNullable()),
        field('status', graphQLInt.nonNullable()),
        field('roomAccess', graphQLInt.nonNullable()),
        field('offerNote', graphQLString),
        field('nextMoveText', graphQLString),
        field('nextMoveStatus', graphQLInt),
        field('nextMoveSource', graphQLInt),
        field('linkedMessageId', graphQLString),
        field('lastSeenRoomAt', graphQLString),
        field('helpType', graphQLString),
        field('roleLabel', graphQLString),
        field('createdAt', graphQLString.nonNullable()),
        field('updatedAt', graphQLString.nonNullable()),
      ]);

/// `beacon_fact_card` projection for BeaconFactCardList (V2 only).
final gqlTypeBeaconFactCardRow = GraphQLObjectType('BeaconFactCardRow', null)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('beaconId', graphQLString.nonNullable()),
    field('factText', graphQLString.nonNullable()),
    field('visibility', graphQLInt.nonNullable()),
    field('pinnedBy', graphQLString.nonNullable()),
    field('pinnedByTitle', graphQLString.nonNullable()),
    field('sourceMessageId', graphQLString),
    field('status', graphQLInt.nonNullable()),
    field('createdAt', graphQLString.nonNullable()),
    field('updatedAt', graphQLString),
    field('attachmentsJson', graphQLString.nonNullable()),
  ]);

/// `beacon_activity_event` projection for BeaconActivityEventList (V2).
final gqlTypeBeaconActivityEventRow =
    GraphQLObjectType('BeaconActivityEventRow', null)
      ..fields.addAll([
        field('id', graphQLString.nonNullable()),
        field('beaconId', graphQLString.nonNullable()),
        field('visibility', graphQLInt.nonNullable()),
        field('type', graphQLInt.nonNullable()),
        field('actorId', graphQLString),
        field('targetUserId', graphQLString),
        field('sourceMessageId', graphQLString),
        field('coordinationItemId', graphQLString),
        field('diffJson', graphQLString),
        field('createdAt', graphQLString.nonNullable()),
      ]);

/// Inbox / My Work: per-beacon room visibility + unread (V2 batch).
final gqlTypeInboxRoomContextRow =
    GraphQLObjectType('InboxRoomContextRow', null)
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('isRoomMember', graphQLBoolean.nonNullable()),
        field('currentLine', graphQLString),
        field('lastRoomMeaningfulChange', graphQLString),
        field('nextMoveText', graphQLString),
        field('roomUnreadCount', graphQLInt.nonNullable()),
        field('lastSeenAt', graphQLString),
        field('openBlockerTitle', graphQLString),
        field('openBlockerCreatorId', graphQLString),
        field('openBlockerTargetPersonId', graphQLString),
        field('openBlockerResponsibleUserId', graphQLString),
        field('openBlockerCreatedAt', graphQLString),
        field('openBlockerCreatorDisplayName', graphQLString),
        field('openBlockerCreatorImageId', graphQLString),
        field('openBlockerCreatorHasPicture', graphQLBoolean),
        field('publicFactSnippet', graphQLString),
      ]);

/// Result of marking a beacon room (or thread) as seen.
final gqlTypeBeaconRoomSeenResult =
    GraphQLObjectType('BeaconRoomSeenResult', null)
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('threadItemId', graphQLString),
        field('seenAt', graphQLString.nonNullable()),
      ]);

final gqlTypeAuthResponse = GraphQLObjectType('AuthResponse', null)
  ..fields.addAll([
    field('subject', graphQLString.nonNullable()),
    field('expires_in', graphQLInt.nonNullable()),
    field('token_type', graphQLString.nonNullable()),
    field('access_token', graphQLString.nonNullable()),
    field('refresh_token', graphQLString),
  ]);

final gqlTypeBeacon = GraphQLObjectType('Beacon', null)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('addressLabel', graphQLString),
    field('primaryNeedSlug', graphQLString),
    field('coverImageId', graphQLString),
    field('coverSource', graphQLInt.nonNullable()),
    field('coverThumbImageId', graphQLString),
    field('isDiscoverable', graphQLBoolean.nonNullable()),
  ]);

/// `beaconAddImage` result: legacy compatibility `id` (beacon id) plus the
/// exact uploaded `imageId` and the refreshed beacon (§2.3).
final gqlTypeBeaconImageAdded = GraphQLObjectType('BeaconImageAdded', null)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('imageId', graphQLString.nonNullable()),
    field('beacon', gqlTypeBeacon.nonNullable()),
  ]);

/// `beaconStageImage` result: the staged image is invisible until
/// `beaconSetMedia` promotes it (§2.3, §3.3).
final gqlTypeBeaconImageStaged = GraphQLObjectType('BeaconImageStaged', null)
  ..fields.addAll([
    field('imageId', graphQLString.nonNullable()),
    field('beaconId', graphQLString.nonNullable()),
  ]);

/// Per-recipient forward record from the current user's perspective.
final gqlTypeMyForwardRecipient = GraphQLObjectType('MyForwardRecipient', null)
  ..fields.addAll([
    field('edgeId', graphQLString.nonNullable()),
    field('recipientId', graphQLString.nonNullable()),
    field('note', graphQLString.nonNullable()),
    field('readAt', graphQLString),
    field('hasOnwardChild', graphQLBoolean.nonNullable()),
    field('recipientRejected', graphQLBoolean.nonNullable()),
  ]);

/// V2-only: forward-screen involvement id sets (see `beaconInvolvement` query).
/// List fields are nullable in GraphQL to match Hasura remote-schema merge; resolver always returns lists.
final gqlTypeBeaconInvolvement = GraphQLObjectType('BeaconInvolvement', null)
  ..fields.addAll([
    field(
      'forwardedToIds',
      GraphQLListType(graphQLString.nonNullable()),
    ),
    field(
      'helpOfferedIds',
      GraphQLListType(graphQLString.nonNullable()),
    ),
    field(
      'withdrawnIds',
      GraphQLListType(graphQLString.nonNullable()),
    ),
    field(
      'rejectedIds',
      GraphQLListType(graphQLString.nonNullable()),
    ),
    field(
      'watchingIds',
      GraphQLListType(graphQLString.nonNullable()),
    ),
    field(
      'onwardForwarderIds',
      GraphQLListType(graphQLString.nonNullable()),
    ),
    field(
      'myForwardedRecipients',
      GraphQLListType(gqlTypeMyForwardRecipient.nonNullable()),
    ),
  ]);

/// Result of `beaconForward`.
final gqlTypeForwardDeliveryResult =
    GraphQLObjectType('ForwardDeliveryResult', null)
      ..fields.addAll([
        field('batchId', graphQLString.nonNullable()),
        field(
          'deliveredRecipientIds',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field(
          'availabilitySkippedRecipientIds',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
      ]);

/// One forward edge for the forwards-graph view (V2 `beaconForwardGraph`).
final gqlTypeForwardGraphEdge = GraphQLObjectType('ForwardGraphEdge', null)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('beaconId', graphQLString.nonNullable()),
    field('senderId', graphQLString.nonNullable()),
    field('recipientId', graphQLString.nonNullable()),
    field('parentEdgeId', graphQLString),
    field('batchId', graphQLString),
  ]);

/// Result of `beaconForwardGraph` and `beaconHelpOffererForwardPath`: edge set
/// plus the help offerer ids the client should highlight. `viewerId` is non-null
/// only for `beaconHelpOffererForwardPath` (so the client can derive whether the
/// viewer is the beacon author, the focused help offerer, or an "involved
/// other"). Callers of the older `beaconForwardGraph` ignore the field.
final gqlTypeForwardGraphResult = GraphQLObjectType('ForwardGraphResult', null)
  ..fields.addAll([
    field('beaconId', graphQLString.nonNullable()),
    field('authorId', graphQLString.nonNullable()),
    field('viewerId', graphQLString),
    field(
      'helpOffererIds',
      GraphQLListType(graphQLString.nonNullable()).nonNullable(),
    ),
    field(
      'edges',
      GraphQLListType(gqlTypeForwardGraphEdge.nonNullable()).nonNullable(),
    ),
  ]);

/// Bounded network provenance for one Forward candidate.
final gqlTypeForwardCandidateConnectionNode =
    GraphQLObjectType(
        'ForwardCandidateConnectionNode',
        null,
      )
      ..fields.addAll([
        field('kind', graphQLString.nonNullable()),
        field('id', graphQLString),
        field('displayName', graphQLString),
        field('image', gqlTypeImagePublic),
      ]);

final gqlTypeForwardCandidateContext =
    GraphQLObjectType(
        'ForwardCandidateContext',
        null,
      )
      ..fields.addAll([
        field('status', graphQLString.nonNullable()),
        field(
          'nodes',
          GraphQLListType(
            gqlTypeForwardCandidateConnectionNode.nonNullable(),
          ).nonNullable(),
        ),
      ]);

/// Constellation field peer profile (display only — no scores).
final gqlTypeConstellationPeer =
    GraphQLObjectType(
        'ConstellationPeer',
        null,
      )
      ..fields.addAll([
        field('id', graphQLString.nonNullable()),
        field('displayName', graphQLString),
        field('handle', graphQLString),
        field('image', gqlTypeImagePublic),
      ]);

/// Two-tier trust edge between constellation peers (ids + tier only).
final gqlTypeConstellationEdge =
    GraphQLObjectType(
        'ConstellationEdge',
        null,
      )
      ..fields.addAll([
        field('src', graphQLString.nonNullable()),
        field('dst', graphQLString.nonNullable()),
        field('tier', graphQLInt.nonNullable()),
      ]);

/// Authorized request row in the constellation field.
final gqlTypeConstellationRequest =
    GraphQLObjectType(
        'ConstellationRequest',
        null,
      )
      ..fields.addAll([
        field('id', graphQLString.nonNullable()),
        field('authorId', graphQLString.nonNullable()),
        field('title', graphQLString.nonNullable()),
        field('status', graphQLInt.nonNullable()),
        field(
          'needs',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field('primaryNeedSlug', graphQLString),
        field('startAt', graphQLString),
        field('endAt', graphQLString),
        field('addressLabel', graphQLString),
        field('hasCoordinates', graphQLBoolean.nonNullable()),
        field('isMine', graphQLBoolean.nonNullable()),
        field('viewerHasActiveHelpOffer', graphQLBoolean.nonNullable()),
        field('viewerIsRoomParticipant', graphQLBoolean.nonNullable()),
        field('viewerHasForwardEdge', graphQLBoolean.nonNullable()),
        field('helpOfferCount', graphQLInt.nonNullable()),
        field('coverSource', graphQLInt.nonNullable()),
        field('coverThumb', gqlTypeImagePublic),
      ]);

final gqlEnumConstellationProjection = enumTypeFromStrings(
  'ConstellationProjection',
  const ['FULL', 'ANCHORS'],
);

final gqlEnumConstellationAnchorTargetKind = enumTypeFromStrings(
  'ConstellationAnchorTargetKind',
  const ['PERSON', 'BEACON'],
);

final gqlTypeConstellationAnchor =
    GraphQLObjectType(
        'ConstellationAnchor',
        null,
      )
      ..fields.addAll([
        field(
          'targetKind',
          gqlEnumConstellationAnchorTargetKind.nonNullable(),
        ),
        field('targetId', graphQLString.nonNullable()),
        field('xUnits', graphQLFloat.nonNullable()),
        field('yUnits', graphQLFloat.nonNullable()),
        field('coordinateSpaceVersion', graphQLInt.nonNullable()),
        field('revision', graphQLString.nonNullable()),
        field('placedAt', graphQLString.nonNullable()),
      ]);

final gqlTypeConstellationAnchorProjection =
    GraphQLObjectType(
        'ConstellationAnchorProjection',
        null,
      )
      ..fields.addAll([
        field('revision', graphQLString.nonNullable()),
        field(
          'anchors',
          GraphQLListType(
            gqlTypeConstellationAnchor.nonNullable(),
          ).nonNullable(),
        ),
        field(
          'pinnedPeers',
          GraphQLListType(gqlTypeConstellationPeer.nonNullable()).nonNullable(),
        ),
        field(
          'pinnedRequests',
          GraphQLListType(
            gqlTypeConstellationRequest.nonNullable(),
          ).nonNullable(),
        ),
        field(
          'supportPeers',
          GraphQLListType(gqlTypeConstellationPeer.nonNullable()).nonNullable(),
        ),
        field(
          'supportEdges',
          GraphQLListType(gqlTypeConstellationEdge.nonNullable()).nonNullable(),
        ),
        field(
          'serverFilteredBeaconIds',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field('serverFilteredBeaconCount', graphQLInt.nonNullable()),
      ]);

final gqlTypeConstellationAnchorUpsertResult =
    GraphQLObjectType(
        'ConstellationAnchorUpsertResult',
        null,
      )
      ..fields.addAll([
        field('anchor', gqlTypeConstellationAnchor.nonNullable()),
        field('revision', graphQLString.nonNullable()),
      ]);

final gqlTypeConstellationAnchorDeleteResult =
    GraphQLObjectType(
        'ConstellationAnchorDeleteResult',
        null,
      )
      ..fields.addAll([
        field(
          'targetKind',
          gqlEnumConstellationAnchorTargetKind.nonNullable(),
        ),
        field('targetId', graphQLString.nonNullable()),
        field('revision', graphQLString.nonNullable()),
      ]);

/// Full constellation field snapshot for the JWT viewer.
final gqlTypeConstellationField =
    GraphQLObjectType(
        'ConstellationField',
        null,
      )
      ..fields.addAll([
        field('loadedAt', graphQLString.nonNullable()),
        field('context', graphQLString.nonNullable()),
        field(
          'peers',
          GraphQLListType(gqlTypeConstellationPeer.nonNullable()).nonNullable(),
        ),
        field(
          'edges',
          GraphQLListType(gqlTypeConstellationEdge.nonNullable()).nonNullable(),
        ),
        field(
          'requests',
          GraphQLListType(
            gqlTypeConstellationRequest.nonNullable(),
          ).nonNullable(),
        ),
        field('peersCapped', graphQLBoolean.nonNullable()),
        field('requestsCapped', graphQLBoolean.nonNullable()),
        field(
          'anchorProjection',
          gqlTypeConstellationAnchorProjection.nonNullable(),
        ),
      ]);

/// Return type for `userUpdate` / remote-schema mutations (minimal).
final gqlTypeProfile = GraphQLObjectType('User', null)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('handle', graphQLString),
  ]);

/// Matches Hasura `mutual_score` for `UserModel.scores { src_score, dst_score }`.
final gqlTypeMutualScore = GraphQLObjectType('mutual_score', null)
  ..fields.addAll([
    field('src_score', graphQLFloat),
    field('dst_score', graphQLFloat),
  ]);

/// Matches Hasura `image` table shape for `UserModel.image`.
final gqlTypeImagePublic = GraphQLObjectType('image', null)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('hash', graphQLString.nonNullable()),
    field('height', graphQLInt.nonNullable()),
    field('width', graphQLInt.nonNullable()),
    field('author_id', graphQLString.nonNullable()),
    // Use built-in `Date` scalar so graphql_server2 introspection lists it
    // (custom `timestamptz` name is not merged into __Schema.types; Hasura
    // then fails: "Could not find type timestamptz"). Ferry maps `Date` → DateTime.
    // Resolver maps for nested `image` must use Dart DateTime here — not
    // toIso8601String(); graphql_schema2 validates before JSON serialization.
    field('created_at', graphQLDate.nonNullable()),
  ]);

/// Matches Hasura `user_presence` for `UserModel.user_presence` on merged `v2_user`.
final gqlTypeUserPresence = GraphQLObjectType('user_presence', null)
  ..fields.addAll([
    field('last_seen_at', graphQLString.nonNullable()),
    field('status', graphQLInt.nonNullable()),
  ]);

/// Matches Hasura `user_availability` for `UserModel.user_availability` on merged `v2_user`.
final gqlTypeUserAvailability = GraphQLObjectType('user_availability', null)
  ..fields.addAll([
    field('is_limited', graphQLBoolean.nonNullable()),
    field('resume_on', graphQLString),
  ]);

/// Matches Hasura `user` table shape for `invitationById.issuer` / `UserModel`.
final gqlTypeUserPublic = GraphQLObjectType('user', null)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('displayName', graphQLString.nonNullable()),
    field('handle', graphQLString),
    field('description', graphQLString.nonNullable()),
    field('my_vote', graphQLInt),
    field('is_mutual_friend', graphQLBoolean.nonNullable()),
    field('trusts_viewer', graphQLBoolean.nonNullable()),
    field('shares_active_context', graphQLBoolean),
    field('image', gqlTypeImagePublic),
    field(
      'scores',
      GraphQLListType(gqlTypeMutualScore.nonNullable()),
    ),
    field('user_presence', gqlTypeUserPresence),
    field('user_availability', gqlTypeUserAvailability),
  ]);

final gqlTypeInvitation = GraphQLObjectType('Invitation', null)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('issuer_id', graphQLString.nonNullable()),
    field('invited_id', graphQLString),
    field('beacon_id', graphQLString),
    // Issuer's private name for the invitee; nullable for legacy rows.
    field('addressee_name', graphQLString),
    field('created_at', graphQLString.nonNullable()),
    field('updated_at', graphQLString.nonNullable()),
    field('issuer', gqlTypeUserPublic.nonNullable()),
  ]);

final gqlTypeInviteGenealogyNode =
    GraphQLObjectType('InviteGenealogyNode', null)
      ..fields.addAll([
        field('node_key', graphQLString.nonNullable()),
        field('user', gqlTypeUserPublic),
        field('deleted_at', graphQLString),
        field('user_created_at', graphQLString),
      ]);

final gqlTypeInviteGenealogyEdge =
    GraphQLObjectType('InviteGenealogyEdge', null)
      ..fields.addAll([
        field('ancestor_node_key', graphQLString.nonNullable()),
        field('descendant_node_key', graphQLString.nonNullable()),
        field('ancestor_user_created_at', graphQLString.nonNullable()),
        field('descendant_user_created_at', graphQLString.nonNullable()),
        field('created_at', graphQLString.nonNullable()),
      ]);

final gqlTypeInviteGenealogy = GraphQLObjectType('InviteGenealogy', null)
  ..fields.addAll([
    field('viewer_node_key', graphQLString.nonNullable()),
    field('target_node_key', graphQLString),
    field('common_ancestor_node_key', graphQLString),
    field(
      'nodes',
      GraphQLListType(gqlTypeInviteGenealogyNode.nonNullable()),
    ),
    field(
      'edges',
      GraphQLListType(gqlTypeInviteGenealogyEdge.nonNullable()),
    ),
  ]);

final gqlTypeInviteGenealogyChildrenPage =
    GraphQLObjectType('InviteGenealogyChildrenPage', null)
      ..fields.addAll([
        field(
          'nodes',
          GraphQLListType(gqlTypeInviteGenealogyNode.nonNullable()),
        ),
        field(
          'edges',
          GraphQLListType(gqlTypeInviteGenealogyEdge.nonNullable()),
        ),
      ]);

final gqlTypeInviteGenealogyChildCount =
    GraphQLObjectType('InviteGenealogyChildCount', null)
      ..fields.addAll([
        field('node_key', graphQLString.nonNullable()),
        field('total_children', graphQLInt.nonNullable()),
      ]);

/// Per-viewer private contact name (subjective profiles). Viewer-scoped:
/// only ever returned for the authenticated caller as viewer.
final gqlTypeUserContact = GraphQLObjectType('UserContact', null)
  ..fields.addAll([
    field('subjectId', graphQLString.nonNullable()),
    field('contactName', graphQLString.nonNullable()),
    field('updatedAt', graphQLString.nonNullable()),
  ]);

/// Direct block intent row for `myBlocks` (blocked profile + cascade metadata).
final gqlTypeBlockIntent = GraphQLObjectType('BlockIntent', null)
  ..fields.addAll([
    field('blocked', gqlTypeUserPublic.nonNullable()),
    field('cascadeMode', graphQLInt.nonNullable()),
    field('inheritedCount', graphQLInt.nonNullable()),
    field('cascadeCapped', graphQLBoolean.nonNullable()),
    field('cascadePending', graphQLBoolean.nonNullable()),
  ]);

/// Pre-block impact preview for `blockPreview`.
final gqlTypeBlockPreview = GraphQLObjectType('BlockPreview', null)
  ..fields.addAll([
    field('cascadeCandidateCount', graphQLInt.nonNullable()),
    field('cascadeCapped', graphQLBoolean.nonNullable()),
    field('openCommitmentCount', graphQLInt.nonNullable()),
    field('willWithdrawEdge', graphQLBoolean.nonNullable()),
  ]);

/// `beaconClose` result.
final gqlTypeBeaconCloseReviewResult =
    GraphQLObjectType(
        'BeaconCloseReviewResult',
        null,
      )
      ..fields.addAll([
        field('id', graphQLString.nonNullable()),
        field('status', graphQLInt.nonNullable()),
        field('closesAt', graphQLString),
      ]);

final gqlTypeBeaconExtendReviewResult =
    GraphQLObjectType(
        'BeaconExtendReviewResult',
        null,
      )
      ..fields.addAll([
        field('id', graphQLString.nonNullable()),
        field('closesAt', graphQLString.nonNullable()),
        field('extensionsRemaining', graphQLInt.nonNullable()),
      ]);

final gqlTypeEvaluationParticipant =
    GraphQLObjectType(
        'EvaluationParticipant',
        null,
      )
      ..fields.addAll([
        field('userId', graphQLString.nonNullable()),
        field('displayName', graphQLString.nonNullable()),
        field('imageId', graphQLString.nonNullable()),
        field('role', graphQLInt.nonNullable()),
        field('contributionSummary', graphQLString.nonNullable()),
        field('causalHint', graphQLString.nonNullable()),
        field('value', graphQLInt),
        field(
          'reasonTags',
          GraphQLListType(graphQLString.nonNullable()),
        ),
        field('note', graphQLString.nonNullable()),
        field('promptVariant', graphQLString.nonNullable()),
        field(
          'acknowledgedHelpTags',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field(
          'acknowledgeableHelpTags',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field('maxAcknowledgedHelpTags', graphQLInt.nonNullable()),
        field('isSubmitted', graphQLBoolean.nonNullable()),
        field('isOptional', graphQLBoolean.nonNullable()),
        field('rowStatus', graphQLInt.nonNullable()),
        field('committedAt', graphQLString),
        field('offerMessage', graphQLString.nonNullable()),
        field('forwarderDisplayName', graphQLString),
      ]);

/// One saved draft row for `evaluationDrafts` query.
final gqlTypeEvaluationDraftRow =
    GraphQLObjectType(
        'EvaluationDraftRow',
        null,
      )
      ..fields.addAll([
        field('evaluatedUserId', graphQLString.nonNullable()),
        field('value', graphQLInt.nonNullable()),
        field(
          'reasonTags',
          GraphQLListType(graphQLString.nonNullable()),
        ),
        field('note', graphQLString.nonNullable()),
      ]);

final gqlTypeReviewWindowStatus =
    GraphQLObjectType(
        'ReviewWindowStatus',
        null,
      )
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('hasWindow', graphQLBoolean.nonNullable()),
        field('beaconTitle', graphQLString.nonNullable()),
        field('openedAt', graphQLString),
        field('closesAt', graphQLString),
        field('windowComplete', graphQLBoolean),
        field('userReviewStatus', graphQLInt),
        field('reviewedCount', graphQLInt),
        field('totalCount', graphQLInt),
        field('extensionsUsed', graphQLInt),
        field('canCloseNow', graphQLBoolean),
        field('canReopen', graphQLBoolean),
        field('requiredTotal', graphQLInt),
        field('requiredReviewed', graphQLInt),
        field('optionalTotal', graphQLInt),
        field('optionalReviewed', graphQLInt),
        field('viewerPackageOptional', graphQLBoolean),
        field('sentAt', graphQLString),
        field('allRequiredSent', graphQLBoolean),
        field('unsentStartedPackages', graphQLInt),
        field('sentReviewerCount', graphQLInt),
      ]);

final gqlTypeEvaluationSummary =
    GraphQLObjectType(
        'EvaluationSummary',
        null,
      )
      ..fields.addAll([
        field('suppressed', graphQLBoolean.nonNullable()),
        field('tone', graphQLString.nonNullable()),
        field('message', graphQLString.nonNullable()),
        field(
          'topReasonTags',
          GraphQLListType(graphQLString.nonNullable()),
        ),
        field('neg2', graphQLInt),
        field('neg1', graphQLInt),
        field('zero', graphQLInt),
        field('pos1', graphQLInt),
        field('pos2', graphQLInt),
        field('roleSummaryLine', graphQLString.nonNullable()),
      ]);

/// Named per-reviewer received reviews for one beacon (V2).
final gqlTypeEvaluationReceived =
    GraphQLObjectType(
        'EvaluationReceived',
        null,
      )
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('beaconTitle', graphQLString.nonNullable()),
        field('windowClosed', graphQLBoolean.nonNullable()),
        field(
          'rows',
          GraphQLListType(
            gqlTypeEvaluationReceivedRow.nonNullable(),
          ).nonNullable(),
        ),
      ]);

/// One named review received by the evaluated participant (V2).
final gqlTypeEvaluationReceivedRow =
    GraphQLObjectType(
        'EvaluationReceivedRow',
        null,
      )
      ..fields.addAll([
        field('reviewerId', graphQLString.nonNullable()),
        field('reviewerDisplayName', graphQLString.nonNullable()),
        field('reviewerImageId', graphQLString.nonNullable()),
        field('reviewerRole', graphQLInt.nonNullable()),
        field('value', graphQLInt.nonNullable()),
        field('tone', graphQLString.nonNullable()),
        field(
          'reasonTags',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field(
          'acknowledgedHelpTags',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field('note', graphQLString.nonNullable()),
        field('occurredAt', graphQLString.nonNullable()),
      ]);

/// One finalized review a profile owner wrote about the viewer (V2).
final gqlTypeEvaluationsWrittenAboutViewerRow =
    GraphQLObjectType(
        'EvaluationsWrittenAboutViewerRow',
        null,
      )
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('beaconTitle', graphQLString.nonNullable()),
        field('beaconClosedAt', graphQLString),
        field('evaluatorId', graphQLString.nonNullable()),
        field('evaluatedUserId', graphQLString.nonNullable()),
        field('value', graphQLInt.nonNullable()),
        field('tone', graphQLString.nonNullable()),
        field(
          'reasonTags',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field(
          'acknowledgedHelpTags',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
        field('note', graphQLString.nonNullable()),
        field('occurredAt', graphQLString.nonNullable()),
      ]);

/// Result of coordination/status mutations (V2).
final gqlTypeBeaconStatusResult =
    GraphQLObjectType(
        'BeaconStatusResult',
        null,
      )
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('status', graphQLInt.nonNullable()),
        field('statusChangedAt', graphQLString),
      ]);

/// Server-derived display projection per beacon (V2).
final gqlTypeBeaconDisplayStatus =
    GraphQLObjectType(
        'BeaconDisplayStatus',
        null,
      )
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('status', graphQLInt.nonNullable()),
        field('phase', graphQLString.nonNullable()),
        field('suggestedAction', graphQLString.nonNullable()),
        field('slot2Kind', graphQLString.nonNullable()),
        field('tier', graphQLString.nonNullable()),
        field('reviewClosesAt', graphQLString),
        field('lastActivityAt', graphQLString),
        field('lifecycleEndedAt', graphQLString),
        field('canCancel', graphQLBoolean.nonNullable()),
        field('canDelete', graphQLBoolean.nonNullable()),
        field('everAcknowledgedCommitterCount', graphQLInt.nonNullable()),
      ]);

/// Result of `setCoordinationResponse` (V2) — legacy name retained for compat.
final gqlTypeCoordinationStatusResult = gqlTypeBeaconStatusResult;

/// One help offer row with optional author coordination response (V2).
final gqlTypeHelpOfferWithCoordinationRow =
    GraphQLObjectType(
        'HelpOfferWithCoordinationRow',
        null,
      )
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('userId', graphQLString.nonNullable()),
        field('message', graphQLString.nonNullable()),
        field('helpType', graphQLString),
        field('roleLabel', graphQLString),
        field('status', graphQLInt.nonNullable()),
        field('withdrawReason', graphQLString),
        field('createdAt', graphQLString.nonNullable()),
        field('updatedAt', graphQLString.nonNullable()),
        field('responseType', graphQLInt),
        field('responseUpdatedAt', graphQLString),
        field('responseAuthorUserId', graphQLString),
        field('roomAccess', graphQLInt),
        field('admissionAction', graphQLInt),
        field('lastDeclineReason', graphQLString),
        field('lastRemoveReason', graphQLString),
        field('stakeState', graphQLInt.nonNullable()),
        field('offerKind', graphQLInt.nonNullable()),
        field('isDirectAuthorForward', graphQLBoolean.nonNullable()),
        field('user', gqlTypeUserPublic.nonNullable()),
      ]);

/// Top-N capabilities for one subject user (batch hint result).
final gqlTypePersonTopCapabilities =
    GraphQLObjectType('v2_PersonTopCapabilities', null)
      ..fields.addAll([
        field('subjectId', graphQLString.nonNullable()),
        field(
          'slugs',
          GraphQLListType(graphQLString.nonNullable()),
        ),
      ]);

final gqlTypePersonFriendContext =
    GraphQLObjectType('v2_PersonFriendContext', null)
      ..fields.addAll([
        field('subjectId', graphQLString.nonNullable()),
        field('activeForwardsToCount', graphQLInt.nonNullable()),
        field('coInvolvedBeaconsCount', graphQLInt.nonNullable()),
      ]);

final gqlTypePersonSharedContext =
    GraphQLObjectType('PersonSharedContext', null)
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('title', graphQLString.nonNullable()),
      ]);

final gqlTypeTagProjection = GraphQLObjectType('v2_TagProjection', null)
  ..fields.addAll([
    field('subjectUserId', graphQLString.nonNullable()),
    field('tagSlug', graphQLString.nonNullable()),
    field('tier', graphQLString.nonNullable()),
  ]);

final gqlTypeForwardBandRow = GraphQLObjectType('v2_ForwardBandRow', null)
  ..fields.addAll([
    field('userId', graphQLString.nonNullable()),
    field('rowTier', graphQLString),
    field(
      'labels',
      GraphQLListType(gqlTypeTagProjection.nonNullable()).nonNullable(),
    ),
    field('rank', graphQLInt.nonNullable()),
    field('isExploration', graphQLBoolean.nonNullable()),
  ]);

final gqlTypeInviteSeedPromptState =
    GraphQLObjectType('v2_InviteSeedPromptState', null)
      ..fields.addAll([
        field('inviterUserId', graphQLString.nonNullable()),
        field('inviteeUserId', graphQLString.nonNullable()),
        field('state', graphQLString.nonNullable()),
        field(
          'slugs',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
      ]);

/// Forward-reason slugs for one (sender, recipient) pair on a beacon.
final gqlTypeForwardReasonRow = GraphQLObjectType('v2_ForwardReasonRow', null)
  ..fields.addAll([
    field('senderId', graphQLString.nonNullable()),
    field('recipientId', graphQLString.nonNullable()),
    field(
      'slugs',
      GraphQLListType(graphQLString.nonNullable()),
    ),
  ]);

/// One capability visible to a specific viewer, with source metadata.
final gqlTypeCapabilityForViewer =
    GraphQLObjectType('v2_CapabilityForViewer', null)
      ..fields.addAll([
        field('slug', graphQLString.nonNullable()),
        field('hasManualLabel', graphQLBoolean.nonNullable()),
      ]);

/// Slug + aggregated count for forward-reason cues.
final gqlTypeTagCount = GraphQLObjectType('v2_TagCount', null)
  ..fields.addAll([
    field('slug', graphQLString.nonNullable()),
    field('count', graphQLInt.nonNullable()),
    field('lastSeenAt', graphQLString.nonNullable()),
  ]);

/// Slug + beacon reference for close-ack cues.
final gqlTypeTagBeaconRef = GraphQLObjectType('v2_TagBeaconRef', null)
  ..fields.addAll([
    field('slug', graphQLString.nonNullable()),
    field('beaconId', graphQLString.nonNullable()),
    field('beaconTitle', graphQLString.nonNullable()),
    field('createdAt', graphQLString.nonNullable()),
  ]);

/// Aggregated capability cues payload returned by `personCapabilityCues`.
final gqlTypePersonCapabilityCuesPayload =
    GraphQLObjectType('v2_PersonCapabilityCuesPayload', null)
      ..fields.addAll([
        field(
          'privateLabels',
          GraphQLListType(graphQLString.nonNullable()),
        ),
        field(
          'forwardReasonsByMe',
          GraphQLListType(gqlTypeTagCount.nonNullable()),
        ),
        field(
          'commitRoles',
          GraphQLListType(gqlTypeTagBeaconRef.nonNullable()),
        ),
        field(
          'closeAckByMe',
          GraphQLListType(gqlTypeTagBeaconRef.nonNullable()),
        ),
        field(
          'closeAckAboutMe',
          GraphQLListType(gqlTypeTagBeaconRef.nonNullable()),
        ),
        field(
          'viewerVisible',
          GraphQLListType(gqlTypeCapabilityForViewer.nonNullable()),
        ),
      ]);

/// `coordination_item` row projection (V2).
final gqlTypeCoordinationItemRow =
    GraphQLObjectType('CoordinationItemRow', null)
      ..fields.addAll([
        field('id', graphQLString.nonNullable()),
        field('beaconId', graphQLString.nonNullable()),
        field('kind', graphQLInt.nonNullable()),
        field('status', graphQLInt.nonNullable()),
        field('title', graphQLString.nonNullable()),
        field('body', graphQLString.nonNullable()),
        field('creatorId', graphQLString.nonNullable()),
        field('targetPersonId', graphQLString),
        field('acceptedById', graphQLString),
        field('targetItemId', graphQLString),
        field('targetMessageId', graphQLString),
        field('linkedMessageId', graphQLString),
        field('linkedParentItemId', graphQLString),
        field('ordering', graphQLInt.nonNullable()),
        field('createdAt', graphQLString.nonNullable()),
        field('updatedAt', graphQLString.nonNullable()),
        field('resolvedAt', graphQLString),
        field('cancelledAt', graphQLString),
        field('staleAt', graphQLString),
        field('lastRemindedAt', graphQLString),
        field('staleAfterDays', graphQLInt),
        field('source', graphQLInt.nonNullable()),
        field('published', graphQLBoolean.nonNullable()),
        field('messageCount', graphQLInt.nonNullable()),
        field('unreadCount', graphQLInt.nonNullable()),
        field('lastSeenAt', graphQLString),
      ]);

/// Per-beacon responsibility counts for the YOU line.
final gqlTypeCoordinationResponsibilityBatchRow =
    GraphQLObjectType('CoordinationResponsibilityBatchRow', null)
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('askOpen', graphQLInt.nonNullable()),
        field('askNew', graphQLInt.nonNullable()),
        field('promiseOpen', graphQLInt.nonNullable()),
        field('promiseNew', graphQLInt.nonNullable()),
        field('blockerOpen', graphQLInt.nonNullable()),
        field('blockerNew', graphQLInt.nonNullable()),
        field('othersOpenCount', graphQLInt.nonNullable()),
      ]);

/// Result of marking beacon coordination items as seen (YOU line watermark).
final gqlTypeBeaconItemsSeenResult =
    GraphQLObjectType('BeaconItemsSeenResult', null)
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('seenAt', graphQLString.nonNullable()),
      ]);

/// Last-message preview for a thread list row (single object, never a union).
final gqlTypeThreadMessagePreview =
    GraphQLObjectType('ThreadMessagePreview', null)
      ..fields.addAll([
        field('kind', graphQLInt.nonNullable()),
        field('excerpt', graphQLString),
        field('hasAttachment', graphQLBoolean.nonNullable()),
        field('joinedUserId', graphQLString),
        field('admissionReason', graphQLString),
        field('linkedItemId', graphQLString),
        field('linkedEventKind', graphQLInt),
        field('itemKind', graphQLInt),
        field('itemTitle', graphQLString),
        field('pollTitle', graphQLString),
        field('factTitle', graphQLString),
        field('factVisibility', graphQLInt),
      ]);

/// One row in the beacon thread list (General or item thread).
final gqlTypeBeaconThreadRow = GraphQLObjectType('BeaconThreadRow', null)
  ..fields.addAll([
    field('threadId', graphQLString.nonNullable()),
    field('threadKind', graphQLString.nonNullable()),
    field('unreadCount', graphQLInt.nonNullable()),
    field('messageCount', graphQLInt.nonNullable()),
    field('lastSeenAt', graphQLString),
    field('lastMessageAt', graphQLString),
    field('lastMessageAuthorId', graphQLString),
    field('lastMessagePreview', gqlTypeThreadMessagePreview),
  ]);

final gqlTypeMyWorkLastActivityEventRow =
    GraphQLObjectType('MyWorkLastActivityEventRow', null)
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('id', graphQLString),
        field('type', graphQLInt),
        field('actorId', graphQLString),
        field('actorTitle', graphQLString),
        field('actorImageId', graphQLString),
        field('createdAt', graphQLString),
        field('diffJson', graphQLString),
      ]);

final gqlTypeBeaconLineageSuggestion =
    GraphQLObjectType('BeaconLineageSuggestion', null)
      ..fields.addAll([
        field('userId', graphQLString.nonNullable()),
        field('group', graphQLString.nonNullable()),
        field('reasonCode', graphQLString.nonNullable()),
        field('reasonArg', graphQLString),
        field('autoSelect', graphQLBoolean.nonNullable()),
      ]);

final gqlTypeBeaconLineageForwardSuggestions =
    GraphQLObjectType('BeaconLineageForwardSuggestions', null)
      ..fields.addAll([
        field('sourceBeaconId', graphQLString.nonNullable()),
        field('rootBeaconId', graphQLString.nonNullable()),
        field('suggestedNote', graphQLString.nonNullable()),
        field(
          'suggestions',
          GraphQLListType(
            gqlTypeBeaconLineageSuggestion.nonNullable(),
          ).nonNullable(),
        ),
      ]);

final gqlTypeBeaconHierarchyOwnerSummary =
    GraphQLObjectType('BeaconHierarchyOwnerSummary', null)
      ..fields.addAll([
        field('id', graphQLString.nonNullable()),
        field('displayName', graphQLString.nonNullable()),
        field('avatarImageId', graphQLString),
      ]);

final gqlTypeBeaconHierarchySummary =
    GraphQLObjectType('BeaconHierarchySummary', null)
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('title', graphQLString),
        field('description', graphQLString),
        field('owner', gqlTypeBeaconHierarchyOwnerSummary),
        field('status', graphQLInt.nonNullable()),
        field('publishedAt', graphQLString.nonNullable()),
        field('statusChangedAt', graphQLString),
        field('isTombstone', graphQLBoolean.nonNullable()),
        field('coverSource', graphQLInt.nonNullable()),
        field('coverImageId', graphQLString),
        field('coverThumbImageId', graphQLString),
        field('primaryNeedSlug', graphQLString),
        field('needs', graphQLString.nonNullable()),
        field(
          'admittedHelperPreviews',
          GraphQLListType(
            gqlTypeBeaconHierarchyOwnerSummary.nonNullable(),
          ).nonNullable(),
        ),
        field('admittedHelperCount', graphQLInt.nonNullable()),
      ]);

final gqlTypeBeaconHierarchyPage =
    GraphQLObjectType('BeaconHierarchyPage', null)
      ..fields.addAll([
        field(
          'summaries',
          GraphQLListType(
            gqlTypeBeaconHierarchySummary.nonNullable(),
          ).nonNullable(),
        ),
        field('nextCursor', graphQLString),
      ]);

final gqlTypeBeaconHierarchyCapabilities =
    GraphQLObjectType('BeaconHierarchyCapabilities', null)
      ..fields.addAll([
        field('canListChildren', graphQLBoolean.nonNullable()),
        field('canCreateChild', graphQLBoolean.nonNullable()),
        field('denialCode', graphQLString),
      ]);

final gqlTypeBeaconParentReference =
    GraphQLObjectType('BeaconParentReference', null)
      ..fields.addAll([
        field('state', graphQLString.nonNullable()),
        field('beaconId', graphQLString),
        field('title', graphQLString),
      ]);

final gqlTypeBeaconPromotionSource =
    GraphQLObjectType('BeaconPromotionSource', null)
      ..fields.addAll([
        field('sourceBeaconId', graphQLString.nonNullable()),
        field('sourceMessageId', graphQLString.nonNullable()),
        field('textPreview', graphQLString.nonNullable()),
        field('author', gqlTypeBeaconHierarchyOwnerSummary.nonNullable()),
      ]);

final gqlTypeBeaconChildCreateResult =
    GraphQLObjectType('BeaconChildCreateResult', null)
      ..fields.addAll([
        field('outcome', graphQLString.nonNullable()),
        field('beaconId', graphQLString),
        field('beacon', gqlTypeBeacon),
      ]);

/// Result of a debug FCM test push to all registered devices.
final gqlTypeFcmTestSendResult = GraphQLObjectType('FcmTestSendResult', null)
  ..fields.addAll([
    field('ok', graphQLBoolean.nonNullable()),
    field('devices', graphQLInt.nonNullable()),
    field('sent', graphQLInt.nonNullable()),
    field('mock', graphQLBoolean.nonNullable()),
    field('reason', graphQLString),
  ]);

/// Result of a debug email test send to the verified primary email.
final gqlTypeEmailTestSendResult =
    GraphQLObjectType('EmailTestSendResult', null)
      ..fields.addAll([
        field('ok', graphQLBoolean.nonNullable()),
        field('mock', graphQLBoolean.nonNullable()),
        field('reason', graphQLString),
      ]);

/// Result of repairing user-scoped counter projections and coordination rows.
final gqlTypeUserRecalculateBookkeepingResult =
    GraphQLObjectType('UserRecalculateBookkeepingResult', null)
      ..fields.addAll([
        field('coordinationRepairedCount', graphQLInt.nonNullable()),
        field('inboxRowsRepairedCount', graphQLInt.nonNullable()),
        field('inboxRowsInsertedCount', graphQLInt.nonNullable()),
        field(
          'affectedBeaconIds',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        ),
      ]);
