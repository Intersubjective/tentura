import 'package:graphql_schema2/graphql_schema2.dart';

import 'input/_input_types.dart';

List<GraphQLType<dynamic, dynamic>> get customTypes => [
  InputFieldCoordinates.type,
  InputFieldForwardRecipientReasons.type,
  InputFieldUpload.type,
  gqlTypeAuthResponse,
  gqlTypeInvitation,
  gqlTypeProfile,
  gqlTypeBeacon,
  gqlTypeMyForwardRecipient,
  gqlTypeBeaconInvolvement,
  gqlTypeForwardGraphEdge,
  gqlTypeForwardGraphResult,
  gqlTypeMutualScore,
  gqlTypeImagePublic,
  gqlTypeUserPresence,
  gqlTypeUserPublic,
  gqlTypeUserContact,
  gqlTypeBeaconCloseReviewResult,
  gqlTypeEvaluationParticipant,
  gqlTypeEvaluationDraftRow,
  gqlTypeReviewWindowStatus,
  gqlTypeEvaluationSummary,
  gqlTypeCoordinationStatusResult,
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
  gqlTypeCoordinationItemRow,
  gqlTypeCoordinationResponsibilityBatchRow,
  gqlTypeBeaconItemsSeenResult,
  gqlTypeMyWorkBeaconCoordinationActivityRow,
  gqlTypeMyWorkLastActivityEventRow,
  gqlTypeBeaconLineageSuggestion,
  gqlTypeBeaconLineageForwardSuggestions,
];

/// Payload returned by `RoomMessageCreate`.
final gqlTypeRoomMessageCreatePayload =
    GraphQLObjectType('RoomMessageCreatePayload', null)
      ..fields.addAll([
        field('id', graphQLString.nonNullable()),
      ]);

/// V2 room chat message row (minimal projection).
final gqlTypeRoomMessageRow =
    GraphQLObjectType('RoomMessageRow', null)
      ..fields.addAll([
        field('id', graphQLString.nonNullable()),
        field('beaconId', graphQLString.nonNullable()),
        field('authorId', graphQLString.nonNullable()),
        field('body', graphQLString.nonNullable()),
        field('createdAt', graphQLString.nonNullable()),
        field('editedAt', graphQLString),
        field('semanticMarker', graphQLInt),
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
        field(
          'mentions',
          GraphQLListType(graphQLString.nonNullable()),
        ),
        field('threadItemId', graphQLString),
      ]);

/// `beacon_room_state` row — one per beacon.
final gqlTypeBeaconRoomStateRow =
    GraphQLObjectType('BeaconRoomStateRow', null)
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
        field('createdAt', graphQLString.nonNullable()),
        field('updatedAt', graphQLString.nonNullable()),
      ]);

/// `beacon_fact_card` projection for BeaconFactCardList (V2 only).
final gqlTypeBeaconFactCardRow =
    GraphQLObjectType('BeaconFactCardRow', null)
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
    field('iconCode', graphQLString),
    field('iconBackground', graphQLInt),
    field('publicStatus', graphQLInt.nonNullable()),
    field('lastPublicMeaningfulChange', graphQLString),
  ]);

/// Per-recipient forward record from the current user's perspective.
final gqlTypeMyForwardRecipient =
    GraphQLObjectType('MyForwardRecipient', null)
      ..fields.addAll([
        field('edgeId', graphQLString.nonNullable()),
        field('recipientId', graphQLString.nonNullable()),
        field('note', graphQLString.nonNullable()),
        field('readAt', graphQLString),
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
final gqlTypeForwardGraphResult =
    GraphQLObjectType('ForwardGraphResult', null)
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

/// Matches Hasura `user` table shape for `invitationById.issuer` / `UserModel`.
final gqlTypeUserPublic = GraphQLObjectType('user', null)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('displayName', graphQLString.nonNullable()),
    field('handle', graphQLString),
    field('description', graphQLString.nonNullable()),
    field('my_vote', graphQLInt),
    field('is_mutual_friend', graphQLBoolean.nonNullable()),
    field('image', gqlTypeImagePublic),
    field(
      'scores',
      GraphQLListType(gqlTypeMutualScore.nonNullable()),
    ),
    field('user_presence', gqlTypeUserPresence),
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

/// Per-viewer private contact name (subjective profiles). Viewer-scoped:
/// only ever returned for the authenticated caller as viewer.
final gqlTypeUserContact = GraphQLObjectType('UserContact', null)
  ..fields.addAll([
    field('subjectId', graphQLString.nonNullable()),
    field('contactName', graphQLString.nonNullable()),
    field('updatedAt', graphQLString.nonNullable()),
  ]);

/// `beaconClose` result.
final gqlTypeBeaconCloseReviewResult = GraphQLObjectType(
  'BeaconCloseReviewResult',
  null,
)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('state', graphQLInt.nonNullable()),
    field('closesAt', graphQLString),
  ]);

final gqlTypeEvaluationParticipant = GraphQLObjectType(
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
  ]);

/// One saved draft row for `evaluationDrafts` query.
final gqlTypeEvaluationDraftRow = GraphQLObjectType(
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

final gqlTypeReviewWindowStatus = GraphQLObjectType(
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
  ]);

final gqlTypeEvaluationSummary = GraphQLObjectType(
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

/// Result of `setCoordinationResponse` (V2).
final gqlTypeCoordinationStatusResult = GraphQLObjectType(
  'CoordinationStatusResult',
  null,
)
  ..fields.addAll([
    field('beaconId', graphQLString.nonNullable()),
    field('coordinationStatus', graphQLInt.nonNullable()),
    field('coordinationStatusUpdatedAt', graphQLString),
  ]);

/// One help offer row with optional author coordination response (V2).
final gqlTypeHelpOfferWithCoordinationRow = GraphQLObjectType(
  'HelpOfferWithCoordinationRow',
  null,
)
  ..fields.addAll([
    field('beaconId', graphQLString.nonNullable()),
    field('userId', graphQLString.nonNullable()),
    field('message', graphQLString.nonNullable()),
    field('helpType', graphQLString),
    field('status', graphQLInt.nonNullable()),
    field('withdrawReason', graphQLString),
    field('createdAt', graphQLString.nonNullable()),
    field('updatedAt', graphQLString.nonNullable()),
    field('responseType', graphQLInt),
    field('responseUpdatedAt', graphQLString),
    field('responseAuthorUserId', graphQLString),
    field('roomAccess', graphQLInt),
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

/// Forward-reason slugs for one (sender, recipient) pair on a beacon.
final gqlTypeForwardReasonRow =
    GraphQLObjectType('v2_ForwardReasonRow', null)
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

/// Slug + beacon reference for commit-role or close-ack cues.
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
        field('reviewOpen', graphQLInt.nonNullable()),
        field('reviewNew', graphQLInt.nonNullable()),
        field('othersOpenCount', graphQLInt.nonNullable()),
      ]);

/// Result of marking beacon coordination items as seen (YOU line watermark).
final gqlTypeBeaconItemsSeenResult =
    GraphQLObjectType('BeaconItemsSeenResult', null)
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('seenAt', graphQLString.nonNullable()),
      ]);

/// Per-beacon latest active item-discussion activity (My Work dot).
final gqlTypeMyWorkBeaconCoordinationActivityRow =
    GraphQLObjectType('MyWorkBeaconCoordinationActivityRow', null)
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('lastCoordinationItemMessageAt', graphQLString),
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
          GraphQLListType(gqlTypeBeaconLineageSuggestion.nonNullable())
              .nonNullable(),
        ),
      ]);
