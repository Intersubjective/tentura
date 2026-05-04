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
  gqlTypeBeaconAuthorUpdate,
  gqlTypeMyForwardRecipient,
  gqlTypeBeaconInvolvement,
  gqlTypeForwardGraphEdge,
  gqlTypeForwardGraphResult,
  gqlTypeMutualScore,
  gqlTypeImagePublic,
  gqlTypeUserPresence,
  gqlTypeUserPublic,
  gqlTypeBeaconCloseReviewResult,
  gqlTypeEvaluationParticipant,
  gqlTypeEvaluationDraftRow,
  gqlTypeReviewWindowStatus,
  gqlTypeEvaluationSummary,
  gqlTypeCoordinationStatusResult,
  gqlTypeCommitmentWithCoordinationRow,
  gqlTypeRoomMessageCreatePayload,
  gqlTypeRoomMessageRow,
  gqlTypeBeaconRoomStateRow,
  gqlTypeBeaconParticipantRow,
  gqlTypeBeaconFactCardRow,
  gqlTypeBeaconActivityEventRow,
  gqlTypeInboxRoomContextRow,
  gqlTypeTagCount,
  gqlTypeTagBeaconRef,
  gqlTypeCapabilityForViewer,
  gqlTypePersonCapabilityCuesPayload,
  gqlTypeForwardReasonRow,
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
        field('attachmentsJson', graphQLString.nonNullable()),
      ]);

/// `beacon_room_state` row — one per beacon.
final gqlTypeBeaconRoomStateRow =
    GraphQLObjectType('BeaconRoomStateRow', null)
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('currentPlan', graphQLString.nonNullable()),
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
        field('role', graphQLInt.nonNullable()),
        field('status', graphQLInt.nonNullable()),
        field('roomAccess', graphQLInt.nonNullable()),
        field('offerNote', graphQLString),
        field('nextMoveText', graphQLString),
        field('nextMoveStatus', graphQLInt),
        field('nextMoveSource', graphQLInt),
        field('linkedMessageId', graphQLString),
        field('lastSeenRoomAt', graphQLString),
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
        field('diffJson', graphQLString),
        field('createdAt', graphQLString.nonNullable()),
      ]);

/// Inbox / My Work: per-beacon room visibility + unread (V2 batch).
final gqlTypeInboxRoomContextRow =
    GraphQLObjectType('InboxRoomContextRow', null)
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('isRoomMember', graphQLBoolean.nonNullable()),
        field('currentPlan', graphQLString),
        field('lastRoomMeaningfulChange', graphQLString),
        field('nextMoveText', graphQLString),
        field('roomUnreadCount', graphQLInt.nonNullable()),
        field('openBlockerTitle', graphQLString),
        field('publicFactSnippet', graphQLString),
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
        field('recipientId', graphQLString.nonNullable()),
        field('note', graphQLString.nonNullable()),
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
      'committedIds',
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

/// Result of `beaconForwardGraph`: edge set (visible + ancestor closure +
/// chains-to-committers) plus the committer ids the client should highlight.
final gqlTypeForwardGraphResult =
    GraphQLObjectType('ForwardGraphResult', null)
      ..fields.addAll([
        field('beaconId', graphQLString.nonNullable()),
        field('authorId', graphQLString.nonNullable()),
        field(
          'committerIds',
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
    field('title', graphQLString.nonNullable()),
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

/// V2-only: return payload for `beaconUpdatePost` / `beaconUpdateEdit`.
final gqlTypeBeaconAuthorUpdate = GraphQLObjectType('BeaconAuthorUpdate', null)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('beaconId', graphQLString.nonNullable()),
    field('number', graphQLInt.nonNullable()),
    field('content', graphQLString.nonNullable()),
    field('createdAt', graphQLDate.nonNullable()),
    field('author', gqlTypeUserPublic.nonNullable()),
  ]);

final gqlTypeInvitation = GraphQLObjectType('Invitation', null)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('issuer_id', graphQLString.nonNullable()),
    field('invited_id', graphQLString),
    field('created_at', graphQLString.nonNullable()),
    field('updated_at', graphQLString.nonNullable()),
    field('issuer', gqlTypeUserPublic.nonNullable()),
  ]);

/// `beaconCloseWithReview` result.
final gqlTypeBeaconCloseReviewResult = GraphQLObjectType(
  'BeaconCloseReviewResult',
  null,
)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('state', graphQLInt.nonNullable()),
    field('closesAt', graphQLString.nonNullable()),
  ]);

final gqlTypeEvaluationParticipant = GraphQLObjectType(
  'EvaluationParticipant',
  null,
)
  ..fields.addAll([
    field('userId', graphQLString.nonNullable()),
    field('title', graphQLString.nonNullable()),
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

/// One commitment row with optional author coordination response (V2).
final gqlTypeCommitmentWithCoordinationRow = GraphQLObjectType(
  'CommitmentWithCoordinationRow',
  null,
)
  ..fields.addAll([
    field('beaconId', graphQLString.nonNullable()),
    field('userId', graphQLString.nonNullable()),
    field('message', graphQLString.nonNullable()),
    field('helpType', graphQLString),
    field('status', graphQLInt.nonNullable()),
    field('uncommitReason', graphQLString),
    field('createdAt', graphQLString.nonNullable()),
    field('updatedAt', graphQLString.nonNullable()),
    field('responseType', graphQLInt),
    field('responseUpdatedAt', graphQLString),
    field('responseAuthorUserId', graphQLString),
    field('user', gqlTypeUserPublic.nonNullable()),
  ]);

/// Forward-reason slugs for one (sender, recipient) pair on a beacon.
final gqlTypeForwardReasonRow =
    GraphQLObjectType('v2_ForwardReasonRow', null)
      ..fields.addAll([
        field('senderId', graphQLString.nonNullable()),
        field('recipientId', graphQLString.nonNullable()),
        field(
          'slugs',
          GraphQLListType(graphQLString.nonNullable()).nonNullable(),
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
