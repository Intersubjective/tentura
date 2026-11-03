// Production server fixture for the client receipt transport tests.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart' show Fake;

import 'package:tentura_root/domain/entity/auth_request_intent.dart';

import 'package:tentura_server/api/controllers/websocket/path_handler/websocket_path_entity_changes.dart';
import 'package:tentura_server/api/controllers/websocket/session/qa_realtime_socket_gate.dart';
import 'package:tentura_server/api/controllers/websocket/session/websocket_session_handler_base.dart';
import 'package:tentura_server/domain/entity/user_presence_entity.dart';
import 'package:tentura_server/domain/port/beacon_room_co_participant_lookup_port.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/room_message_snapshot_lookup_port.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';

import 'disposable_pg_target.dart';
import 'post_lifecycle_receipt_fixture.dart';

const _beaconId = 'Bseenby000001';
// Socket authentication uses production-valid user ids.
const _authorId = 'Ua00000000001';
const _stewardId = 'Ua00000000002';
const _helperId = 'Ua00000000003';
const _otherHelperId = 'Ua00000000004';
const _outsiderId = 'Ua00000000005';

void _emit(Map<String, Object?> value) =>
    stdout.writeln('TENTURA_RECEIPT_TRANSPORT ${jsonEncode(value)}');

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_RECEIPT_TRANSPORT_TEST_DB',
    defaultNamePrefix: 'tentura_test_receipt_transport',
  );
  final session = await setUpDisposablePgWriter(target: target);
  Connection? listener;
  HttpServer? httpServer;
  StreamSubscription<String>? subscription;
  _Harness? fanout;
  try {
    final db = target.databaseEnv;
    await configureDependencies(
      Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        publicOrigin: 'http://127.0.0.1:2080',
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
      ),
    );
    await getIt.allReady(ignorePendingAsyncCreation: true);
    final writer = session.writer;
    for (final id in [
      _authorId,
      _stewardId,
      _helperId,
      _otherHelperId,
      _outsiderId,
    ]) {
      await writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) VALUES (@id, @id, @key)',
        ),
        parameters: {'id': id, 'key': '$id-key'},
      );
    }
    await writer.execute(
      Sql.named(
        'INSERT INTO public.beacon (id, user_id, title, description, status) '
        "VALUES (@b, @a, 'Moving day', 'Needs help', 0)",
      ),
      parameters: {'b': _beaconId, 'a': _authorId},
    );
    await writer.execute(
      Sql.named(
        'INSERT INTO public.beacon_steward (beacon_id, user_id) VALUES (@b, @s)',
      ),
      parameters: {'b': _beaconId, 's': _stewardId},
    );
    for (final (id, role) in [
      (_helperId, 2),
      (_otherHelperId, 2),
      (_stewardId, 1),
    ]) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (@p, @b, @u, @r, 0, 3, now(), now())
'''),
        parameters: {
          'p': 'P${id.substring(1)}',
          'b': _beaconId,
          'u': id,
          'r': role,
        },
      );
    }
    final postFixture =
        Platform.environment['TENTURA_RECEIPT_POST_LIFECYCLE_FIXTURE'];
    if (postFixture != null) {
      await seedPostLifecycleReceipts(
        writer,
        closedOnly: postFixture == 'closedOnly',
        clearedClosed: postFixture == 'clearedClosed',
      );
    }
    final schema = graphqlSchema;
    Future<Object?> execute(String viewer, Map<String, dynamic> body) =>
        schema.parseAndExecute(
          body['query'] as String,
          variableValues:
              (body['variables'] as Map?)?.cast<String, dynamic>() ?? const {},
          globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
        );
    await execute(_authorId, {
      'query': r'''
      mutation SetNextStep($b: String!, $t: String!, $r: Int!) {
        BeaconRoomNowLineUpdate(beaconId: $b, text: $t, baseRevision: $r) {
          currentLineRevision
        }
      }''',
      'variables': {'b': _beaconId, 't': 'Bring the ladder', 'r': 0},
    });

    final dependencies = _Dependencies();
    final handler = _Harness(Env.test(), dependencies);
    fanout = handler;
    for (final id in [
      _authorId,
      _stewardId,
      _helperId,
      _otherHelperId,
      _outsiderId,
    ]) {
      await dependencies.authenticate(handler, _TransportSession(id), id);
    }
    listener = await Connection.open(
      db.pgEndpoint,
      settings: db.pgEndpointSettings,
    );
    await listener.execute('LISTEN entity_changes');
    subscription = listener.channels['entity_changes'].listen((payload) {
      // No event envelope is manufactured here: PostgreSQL and the production
      // websocket fanout decide both payload and recipients.
      unawaited(
        handler.fanOutEntityChange(jsonDecode(payload) as Map<String, dynamic>),
      );
    });
    final done = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    httpServer = server;
    server.listen((request) async {
      try {
        if (request.uri.path == '/close') {
          request.response.write('{}');
          await request.response.close();
          done.complete();
          return;
        }
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        final viewer = request.uri.queryParameters['viewer']!;
        final data = await execute(viewer, body);
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'data': data}));
      } on Object catch (error) {
        // Preserve the production GraphQL error payload, including the access
        // refusal. The transport adds only the ordinary GraphQL HTTP envelope.
        Object? details;
        try {
          details = jsonDecode(error.toString());
        } on Object {
          details = {'message': error.toString()};
        }
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'data': null,
              'errors': [details],
            }),
          );
      } finally {
        await request.response.close();
      }
    });
    _emit({'ready': server.port});
    await done.future;
  } finally {
    await httpServer?.close(force: true);
    await subscription?.cancel();
    await listener?.close();
    fanout?.disposeEntityChanges();
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  }
}

final class _TransportSession extends WebSocketSession {
  _TransportSession(this.userId);
  final String userId;
  @override
  void send(Object? data) {
    if (data is! String) return;
    final frame = jsonDecode(data) as Map<String, dynamic>;
    if (frame['path'] != 'entity_changes') return;
    _emit({'viewer': userId, 'frame': frame});
  }
}

final class _Dependencies {
  _Dependencies() {
    final logger = Logger('ReceiptTransportTest');
    authCase = AuthCase(
      _UnusedUserRepository(),
      _UnusedInvitationRepository(),
      env: env,
      logger: logger,
    );
    userPresenceCase = UserPresenceCase(
      _FakePresenceRepository(),
      env: env,
      logger: logger,
    );
  }

  final env = Env.test();
  late final AuthCase authCase;
  late final UserPresenceCase userPresenceCase;
  final qaRealtimeSocketGate = QaRealtimeSocketGate();
  final friendshipLookup = _FakeFriendshipLookup();
  final coParticipantLookup = _FakeCoParticipantLookup();
  final roomMessageSnapshotLookup = _FakeSnapshotLookup();

  Future<void> authenticate(
    WebsocketSessionHandlerBase handler,
    WebSocketSession session,
    String userId,
  ) async {
    final token = authCase.issueAccessToken(userId).rawToken;
    await handler.onAuth(session, {
      'intent': AuthRequestIntent.cnameSignIn,
      'token': token,
    });
  }
}

final class _Harness extends WebsocketSessionHandlerBase
    with WebsocketPathEntityChanges {
  _Harness(Env env, _Dependencies dependencies)
    : super(
        env,
        Logger('ReceiptTransportFanout'),
        dependencies.authCase,
        dependencies.userPresenceCase,
        dependencies.friendshipLookup,
        dependencies.coParticipantLookup,
        dependencies.roomMessageSnapshotLookup,
        dependencies.qaRealtimeSocketGate,
      );
}

final class _UnusedUserRepository extends Fake implements UserRepositoryPort {}

final class _UnusedInvitationRepository extends Fake
    implements InvitationRepositoryPort {}

final class _FakePresenceRepository implements UserPresenceRepositoryPort {
  @override
  Future<UserPresenceEntity?> get(String userId) async => null;

  @override
  Future<void> update(
    String userId, {
    DateTime? lastSeenAt,
    DateTime? lastNotifiedAt,
    UserPresenceStatus? status,
  }) async {}
}

final class _FakeFriendshipLookup extends Fake
    implements VoteUserFriendshipLookupPort {}

final class _FakeCoParticipantLookup extends Fake
    implements BeaconRoomCoParticipantLookupPort {}

final class _FakeSnapshotLookup extends Fake
    implements RoomMessageSnapshotLookupPort {}
