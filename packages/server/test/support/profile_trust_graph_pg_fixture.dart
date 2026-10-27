import 'dart:convert';

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_trust_edge_repository.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_user_vote.dart';
import 'package:tentura_server/api/controllers/websocket/router/websocket_router_base.dart';
import 'package:tentura_server/api/controllers/websocket/session/qa_realtime_socket_gate.dart';
import 'package:tentura_server/api/controllers/websocket/session/websocket_session_handler_base.dart';
import 'package:tentura_server/data/service/pg_notification_connection.dart';
import 'package:tentura_server/data/service/pg_notification_service.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_trust_edge_case.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';
import 'package:tentura_server/env.dart';

import '../api/controllers/websocket/websocket_realtime_protocol_test.mocks.dart';
import 'disposable_pg_target.dart';
import 'fake_trust_maintenance_port.dart';
import 'pg_test_public_keys.dart';
import 'pg_notification_recorder.dart';
import 'pg_wait.dart';

/// Shared by server source tests and Flutter profile-path integration tests.
/// Mutation execution, projection, NOTIFY, LISTEN and websocket fan-out all
/// use production code. No projection or invalidation function is replaced.
final class ProfileTrustGraphPgFixture {
  ProfileTrustGraphPgFixture(this.target);

  static const alice = 'Uaaaaaaaaaaaa';
  static const bob = 'Ubbbbbbbbbbbb';

  static DisposablePgTarget newTarget() =>
      DisposablePgTarget.fromNamedEnvironment(
        envVarName: 'TENTURA_TRUST_GRAPH_PROFILE_UNTRUST_TEST_DB',
        defaultNamePrefix: 'tentura_test_graph_untrust',
      );

  static Future<bool> isReachable() => canReachPostgresAdmin(newTarget());

  final DisposablePgTarget target;
  late final DisposablePgWriterSession session;
  late final TenturaDb db;
  late final UserTrustEdgeRepository votes;
  late final GraphQL graphQL;
  late final PgNotificationService notifications;
  late final PgNotificationRecorder recorder;
  late final _Router _router;
  late final _RecordingSession _aliceSession;

  /// Connect the actual server-sent frames to a client's socket test seam.
  void Function(String frame)? onViewerFrame;

  List<String> get viewerFrames => _aliceSession.sent;
  List<Map<String, dynamic>> get notificationsReceived => recorder.messages;

  Future<void> open() async {
    session = await setUpDisposablePgWriter(target: target);
    db = openDisposablePgDatabase(target);
    votes = UserTrustEdgeRepository(db, MeritrankRepository(db));
    final userVote = UserTrustEdgeCase(
      _UnusedUsers(),
      votes,
      FakeTrustMaintenancePort(),
      attention: TransactionalAttentionCase(
        MutatingUnitOfWork(db),
        _NoMutualFormation(),
      ),
      env: target.databaseEnv,
      logger: Logger('TrustGraphUntrustTest'),
    );
    graphQL = GraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')
          ..fields.add(
            GraphQLObjectField(
              '_health',
              graphQLBoolean.nonNullable(),
              resolve: (_, _) => true,
            ),
          ),
        mutationType: GraphQLObjectType('Mutation', 'Mutation root')
          ..fields.addAll(MutationUserVote(trustEdgeCase: userVote).all),
      ),
    );
    notifications = await PgNotificationService.create(
      target.databaseEnv,
      const PostgresNotificationConnector(),
    );
    recorder = PgNotificationRecorder(notifications.entityChangeNotifications);
    _router = _Router(notifications);
    _aliceSession = _RecordingSession((frame) => onViewerFrame?.call(frame));
    await _router.onAuth(_aliceSession, {
      'intent': 'sign_in',
      'token': _router.authCase.issueAccessToken(alice).rawToken,
    });
    for (final (index, id) in [alice, bob].indexed) {
      await db.customStatement(
        r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ($1, $2, $3, now(), now())
''',
        [id, id, pgTestPublicKey('graphuntrust', index + 1)],
      );
    }
  }

  Future<void> seedPublishedMutualTrust() async {
    for (final (subject, object) in [(alice, bob), (bob, alice)]) {
      await votes.setVoteAmountAndApplyEvidence(
        subjectUserId: subject,
        objectUserId: object,
        newAmount: 1,
      );
    }
    // Seed an already-published graph; do not call the external MR service.
    // All subsequent mutations use the real action and committed projection.
    await db.customStatement('''
UPDATE public.user_trust_edge SET prev_sent_weight = target_w
WHERE subject IN ('$alice', '$bob') AND object IN ('$alice', '$bob')
''');
    await db.customStatement('''
DELETE FROM public.trust_publish_queue
WHERE subject_user_id IN ('$alice', '$bob')
''');
    expect(await edges(), {(alice, bob), (bob, alice)});
    await flushNotifications();
    recorder.messages.clear();
    _aliceSession.sent.clear();
  }

  /// Accepts the actual serialized request issued by LikeRemoteRepository.
  Future<Map<String, dynamic>> executeMutation(
    Map<String, dynamic> request, {
    required String actorId,
  }) async =>
      await graphQL.parseAndExecute(
            request['query']! as String,
            operationName: request['operationName']! as String,
            variableValues: request['variables']! as Map<String, dynamic>,
            globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: actorId)},
          )
          as Map<String, dynamic>;

  Future<int> voteAmount(String subject, String object) async =>
      (await db.managers.voteUsers
              .filter((v) => v.subject.id(subject) & v.object.id(object))
              .getSingleOrNull())
          ?.amount ??
      0;

  Future<List<Map<String, Object?>>> edgeRows() async => [
    for (final row in await db.customSelect(edgeQuery).get())
      Map<String, Object?>.of(row.data),
  ];

  Future<Set<(String, String)>> edges() async => {
    for (final row in await edgeRows())
      (row['src']! as String, row['dst']! as String),
  };

  Future<void> flushNotifications() => recorder.flush(
    sendBarrier: (token) => session.writer.execute(
      Sql.named("SELECT pg_notify('entity_changes', @payload)"),
      parameters: {
        'payload': jsonEncode({'entity': 'barrier', 'id': token}),
      },
    ),
    timeout: kCompletionWait,
  );

  Future<void> close() async {
    onViewerFrame = null;
    _router.removeSession(_aliceSession);
    await _router.dispose();
    await recorder.cancel();
    await notifications.dispose();
    await tearDownDisposablePgWriter(session: session, drift: db);
  }

  static const edgeQuery =
      '''
SELECT src, dst, src_score, dst_score,
       src_total_neighbor_count, dst_total_neighbor_count
FROM public.graph_edges_between(
  ARRAY['$alice', '$bob']::text[], true,
  '{"x-hasura-user-id":"$alice"}'::json)
''';
}

final class _UnusedUsers extends Fake implements UserRepositoryPort {}

final class _NoMutualFormation extends Fake implements AttentionDispatchPort {
  @override
  Future<void> record(AttentionDispatchIntent intent) async {
    fail('Withdrawing trust must not announce a newly mutual connection');
  }
}

final class _Router extends WebsocketRouterBase {
  _Router(PgNotificationService notifications)
    : super(
        Env.test(),
        Logger('TrustGraphRealtime'),
        AuthCase(
          MockUserRepositoryPort(),
          MockInvitationRepositoryPort(),
          env: Env.test(),
          logger: Logger('TrustGraphAuth'),
        ),
        UserPresenceCase(
          MockUserPresenceRepositoryPort(),
          env: Env.test(),
          logger: Logger('TrustGraphPresence'),
        ),
        MockVoteUserFriendshipLookupPort(),
        MockBeaconRoomCoParticipantLookupPort(),
        MockRoomMessageSnapshotLookupPort(),
        QaRealtimeSocketGate(),
        notifications,
      );
}

final class _RecordingSession extends WebSocketSession {
  _RecordingSession(this.onSend);
  final void Function(String frame) onSend;
  final sent = <String>[];
  @override
  void send(Object? data) {
    final frame = data! as String;
    sent.add(frame);
    onSend(frame);
  }
}
