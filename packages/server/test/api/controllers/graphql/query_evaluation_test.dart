import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_evaluation.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/entity/evaluation/cross_beacon_evaluation_record.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/review_finalization_result.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/port/attention_expiry_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/review_finalization_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/use_case/attention_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_draft_purger.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_participant_graph_builder.dart';
import 'package:tentura_server/domain/use_case/evaluation_case.dart';
import 'package:tentura_server/env.dart';

import '../../../domain/evaluation/evaluation_graph_test_repos.dart';
import '../../../support/recording_commitment_repository.dart';
import '../../../support/test_attention_harness.dart';

void main() {
  test('evaluation reveal contract is additive and non-null', () {
    final participantFields = gqlTypeEvaluationParticipant.fields
        .map((field) => field.name)
        .toSet();
    expect(
      participantFields,
      containsAll(<String>[
        'acknowledgedHelpTags',
        'acknowledgeableHelpTags',
        'maxAcknowledgedHelpTags',
        'isSubmitted',
      ]),
    );
    _expectNonNullListOfNonNullStrings(
      gqlTypeEvaluationParticipant,
      'acknowledgedHelpTags',
    );
    _expectNonNullListOfNonNullStrings(
      gqlTypeEvaluationParticipant,
      'acknowledgeableHelpTags',
    );
    _expectNonNullScalar(
      gqlTypeEvaluationParticipant,
      'maxAcknowledgedHelpTags',
    );
    _expectNonNullScalar(gqlTypeEvaluationParticipant, 'isSubmitted');

    expect(
      gqlTypeEvaluationReceivedRow.fields.map((field) => field.name),
      contains('acknowledgedHelpTags'),
    );
    expect(
      gqlTypeEvaluationsWrittenAboutViewerRow.fields.map((field) => field.name),
      contains('acknowledgedHelpTags'),
    );
    _expectNonNullListOfNonNullStrings(
      gqlTypeEvaluationReceivedRow,
      'acknowledgedHelpTags',
    );
    _expectNonNullListOfNonNullStrings(
      gqlTypeEvaluationsWrittenAboutViewerRow,
      'acknowledgedHelpTags',
    );
  });

  test('resolvers pass JWT sub as evaluated/viewer identity', () async {
    final repository = _RecordingEvaluationRepository();
    final query = QueryEvaluation(
      evaluationCase: _evaluationCase(repository),
    );
    final received = query.all.singleWhere(
      (field) => field.name == 'evaluationReceived',
    );
    final written = query.all.singleWhere(
      (field) => field.name == 'evaluationsWrittenAboutMeBy',
    );
    const jwt = JwtEntity(sub: 'jwt-viewer');

    await received.resolve!(null, {
      kGlobalInputQueryJwt: jwt,
      'id': 'beacon-1',
    });
    expect(repository.receivedEvaluatedUserId, 'jwt-viewer');

    await written.resolve!(null, {
      kGlobalInputQueryJwt: jwt,
      'id': 'author-from-argument',
    });
    expect(repository.writtenViewerId, 'jwt-viewer');
    expect(repository.writtenAuthorId, 'author-from-argument');
  });

  test(
    'GraphQL ignores forged evaluated-user argument and keeps JWT identity',
    () async {
      final repository = _RecordingEvaluationRepository();
      final queryField = QueryEvaluation(
        evaluationCase: _evaluationCase(repository),
      ).all.singleWhere((field) => field.name == 'evaluationReceived');
      expect(queryField.inputs.map((input) => input.name), ['id']);
      final graph = GraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', null)..fields.add(queryField),
        ),
      );

      final result = await graph.parseAndExecute(
        '{ evaluationReceived(id: "1234567890123", evaluatedUserId: "forged") { beaconId } }',
        globalVariables: {
          kGlobalInputQueryJwt: const JwtEntity(sub: 'jwt-viewer'),
        },
      );
      // graphql_server2 6.5.0 currently ignores unknown field arguments. The
      // real resolver still derives evaluated identity exclusively from JWT.
      expect(result, isA<Map<String, dynamic>>());
      expect(repository.receivedEvaluatedUserId, 'jwt-viewer');
    },
  );

  test('GraphQL executes the real evaluationReceived resolver', () async {
    final repository = _RecordingEvaluationRepository();
    final queryField = QueryEvaluation(
      evaluationCase: _evaluationCase(repository),
    ).all.singleWhere((field) => field.name == 'evaluationReceived');
    final graph = GraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', null)..fields.add(queryField),
      ),
    );

    final result = await graph.parseAndExecute(
      '{ evaluationReceived(id: "1234567890123") { beaconId rows { evaluatorId } } }',
      globalVariables: {
        kGlobalInputQueryJwt: const JwtEntity(sub: 'jwt-viewer'),
      },
    );

    expect(repository.receivedEvaluatedUserId, 'jwt-viewer');
    expect(result, isA<Map<String, dynamic>>());
  });
}

GraphQLObjectField<dynamic, dynamic> _field(
  GraphQLObjectType type,
  String name,
) => type.fields.singleWhere((field) => field.name == name);

void _expectNonNullScalar(GraphQLObjectType type, String name) {
  expect(
    _field(type, name).type,
    isA<GraphQLNonNullableType<dynamic, dynamic>>(),
  );
}

void _expectNonNullListOfNonNullStrings(GraphQLObjectType type, String name) {
  final outer = _field(type, name).type;
  expect(outer, isA<GraphQLNonNullableType<dynamic, dynamic>>());
  final list = (outer as GraphQLNonNullableType<dynamic, dynamic>).ofType;
  expect(list, isA<GraphQLListType<dynamic, dynamic>>());
  expect(
    (list as GraphQLListType<dynamic, dynamic>).ofType,
    isA<GraphQLNonNullableType<dynamic, dynamic>>(),
  );
}

EvaluationCase _evaluationCase(_RecordingEvaluationRepository repository) {
  final attention = TestAttentionHarness();
  final finalization = _NoOpFinalization();
  final expiry = AttentionExpirySweepCase(
    _NoOpExpiryRepository(),
    finalization,
    attention.intents,
    attention.transactional,
  );
  final commitment = NoOpCommitmentRepository();
  final offers = EmptyGraphHelpOfferRepository();
  final edges = EmptyGraphForwardEdgeRepository();
  return EvaluationCase(
    _QueryBeaconRepository(),
    edges,
    repository,
    _QueryProfiles(),
    EvaluationParticipantGraphBuilder(
      commitment,
      offers,
      edges,
      StubUserRepository('User'),
    ),
    EvaluationDraftPurger(repository),
    CommitmentQueryCase(
      commitment,
      offers,
      env: Env(environment: Environment.test),
      logger: Logger('QueryEvaluationTest'),
    ),
    commitment,
    offers,
    attentionIntents: attention.intents,
    attention: attention.transactional,
    attentionExpirySweep: expiry,
    reviewFinalization: finalization,
    env: Env(environment: Environment.test),
    logger: Logger('QueryEvaluationTest'),
  );
}

final class _RecordingEvaluationRepository extends Fake
    implements EvaluationRepositoryPort {
  String? receivedEvaluatedUserId;
  String? writtenViewerId;
  String? writtenAuthorId;

  @override
  Future<BeaconReviewWindowRecord?> getReviewWindow(String beaconId) async =>
      null;

  @override
  Future<List<BeaconEvaluationRecord>> listEvaluationsForEvaluatedUser({
    required String beaconId,
    required String evaluatedUserId,
  }) async {
    receivedEvaluatedUserId = evaluatedUserId;
    return [
      BeaconEvaluationRecord(
        beaconId: beaconId,
        evaluatorId: 'reviewer',
        evaluatedUserId: evaluatedUserId,
        value: 4,
        reasonTags: '',
        note: '',
        status: BeaconEvaluationRowStatus.final_,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    ];
  }

  @override
  Future<List<BeaconEvaluationParticipantRecord>> listParticipants(
    String beaconId,
  ) async => [
    BeaconEvaluationParticipantRecord(
      beaconId: beaconId,
      userId: 'reviewer',
      role: 1,
      contributionSummary: 'reviewer',
      causalHint: 'h',
    ),
  ];

  @override
  Future<List<CrossBeaconEvaluationRecord>> listFinalizedEvaluationsBetween({
    required String evaluatorId,
    required String evaluatedUserId,
  }) async {
    writtenViewerId = evaluatedUserId;
    writtenAuthorId = evaluatorId;
    return const [];
  }
}

final class _QueryBeaconRepository extends Fake
    implements BeaconRepositoryPort {
  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async => BeaconEntity(
    id: beaconId,
    title: 'Request',
    author: const UserEntity(id: 'author'),
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: BeaconStatus.closed,
  );
}

final class _QueryProfiles extends Fake implements UserProfileBatchLookup {
  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async => {for (final id in ids) id: UserEntity(id: id, displayName: id)};
}

final class _NoOpExpiryRepository implements AttentionExpiryRepositoryPort {
  @override
  Future<List<String>> lockExpiredReviewWindowBeaconIds(DateTime now) async =>
      const [];
}

final class _NoOpFinalization implements ReviewFinalizationPort {
  @override
  Future<ReviewFinalizationResult> closeAndFinalize(
    String beaconId, {
    required String reason,
    String? actorUserId,
  }) async => const ReviewFinalizationResult(didClose: false);
}
