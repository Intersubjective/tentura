import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:test/test.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_forward_candidate_context.dart';
import 'package:tentura_server/domain/entity/forward_candidate_graph_snapshot.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/forward_candidate_context_repository_port.dart';
import 'package:tentura_server/domain/use_case/forward_candidate_context_case.dart';
import 'package:tentura_server/env.dart';

void main() {
  const auth = {kGlobalInputQueryJwt: JwtEntity(sub: 'viewer')};
  late _RecordingRepository repository;
  late QueryForwardCandidateContext query;

  setUp(() {
    repository = _RecordingRepository();
    query = QueryForwardCandidateContext(
      forwardCandidateContextCase: ForwardCandidateContextCase(
        repository,
        env: Env(environment: Environment.test),
        logger: Logger('QueryForwardCandidateContextTest'),
      ),
    );
  });

  test('exposes the dedicated query field', () {
    expect(query.all.map((field) => field.name), ['forwardCandidateContext']);
  });

  test('uses viewer identity only from JWT', () async {
    final result =
        await query.forwardCandidateContext.resolve!(null, {
              ...auth,
              'viewerId': 'attacker-value',
              'candidateId': 'candidate',
              'context': ' Personal ',
            })
            as Map<String, dynamic>;

    expect(repository.viewerId, 'viewer');
    expect(repository.candidateId, 'candidate');
    expect(repository.context, ' Personal ');
    expect(result, {'status': 'unavailable', 'nodes': <Object>[]});
  });

  test('missing JWT is unauthorized', () {
    expect(
      () => query.forwardCandidateContext.resolve!(null, {
        'candidateId': 'candidate',
        'context': 'personal',
      }),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('candidate and context arguments are non-null in the schema', () {
    final inputs = query.forwardCandidateContext.inputs;
    expect(
      inputs.singleWhere((input) => input.name == 'candidateId').type,
      isA<GraphQLNonNullableType<dynamic, dynamic>>(),
    );
    expect(
      inputs.singleWhere((input) => input.name == 'context').type,
      isA<GraphQLNonNullableType<dynamic, dynamic>>(),
    );
  });

  test('missing candidate is rejected before repository access', () {
    expect(
      () => query.forwardCandidateContext.resolve!(null, {
        ...auth,
        'context': 'personal',
      }),
      throwsA(isA<TypeError>()),
    );
    expect(repository.viewerId, isNull);
  });

  test('privacy-equivalent unavailable responses have no nodes', () async {
    for (final snapshot in [
      const ForwardCandidateGraphSnapshot.unavailable(),
      const ForwardCandidateGraphSnapshot(
        candidateEligible: false,
        edges: [ForwardCandidateGraphEdge('viewer', 'candidate')],
        people: {},
      ),
    ]) {
      repository.snapshot = snapshot;
      final result =
          await query.forwardCandidateContext.resolve!(null, {
                ...auth,
                'candidateId': 'candidate',
                'context': 'personal',
              })
              as Map<String, dynamic>;
      expect(result, {'status': 'unavailable', 'nodes': <Object>[]});
    }
  });

  test('repository failures propagate as operation errors', () async {
    final failure = StateError('database unavailable');
    repository.error = failure;

    await expectLater(
      query.forwardCandidateContext.resolve!(null, {
        ...auth,
        'candidateId': 'candidate',
        'context': 'personal',
      }),
      throwsA(same(failure)),
    );
  });
}

final class _RecordingRepository
    implements ForwardCandidateContextRepositoryPort {
  String? viewerId;
  String? candidateId;
  String? context;
  ForwardCandidateGraphSnapshot snapshot =
      const ForwardCandidateGraphSnapshot.unavailable();
  Object? error;

  @override
  Future<ForwardCandidateGraphSnapshot> loadSnapshot({
    required String viewerId,
    required String candidateId,
    required String context,
  }) async {
    this.viewerId = viewerId;
    this.candidateId = candidateId;
    this.context = context;
    if (error != null) throw error!;
    return snapshot;
  }
}
