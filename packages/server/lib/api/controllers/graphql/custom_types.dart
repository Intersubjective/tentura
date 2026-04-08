import 'package:graphql_schema2/graphql_schema2.dart';

import 'input/_input_types.dart';

List<GraphQLType<dynamic, dynamic>> get customTypes => [
  InputFieldCoordinates.type,
  InputFieldPolling.type,
  InputFieldUpload.type,
  gqlTypeAuthResponse,
  gqlTypeInvitation,
  gqlTypeProfile,
  gqlTypeBeacon,
  gqlTypeBeaconInvolvement,
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
];

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
    field('user', gqlTypeUserPublic.nonNullable()),
  ]);
