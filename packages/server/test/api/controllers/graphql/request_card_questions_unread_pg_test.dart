@Tags(['pg'])
library;

import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart' as pg;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_beacon_room.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field_requests.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/http/request_context_io_adapter.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/query_counter.dart';
import '../../../support/session_database_di_harness.dart';

const _viewer = 'Uqcardviewer01';
const _author = 'Uqcardauthor01';
const _blocked = 'Uqcardblocked1';
const _request = 'Bqcardrequest1';
final _cursor = DateTime.utc(2030);
final _fresh = DateTime.utc(2030, 1, 2);

// Real HTTP GraphQL, generated production DI, and disposable PostgreSQL:
// a card's unread total includes precisely the rooms the viewer can read.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_CARD_QUESTIONS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_card_questions',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Postgres unavailable', () {}, skip: unavailable);
    return;
  }

  late DisposablePgWriterSession session;
  late Handler handler;
  final counter = QueryCounter();

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    final base = target.databaseEnv;
    final env = Env(
      environment: Environment.dev,
      serverUri: Uri.parse('http://127.0.0.1:2080'),
      publicOrigin: 'http://127.0.0.1:2080',
      pgHost: base.pgHost,
      pgPort: base.pgPort,
      pgDatabase: base.pgDatabase,
      pgUsername: base.pgUsername,
      pgPassword: base.pgPassword,
      publicKey: Env.kJwtPublicKey,
      privateKey: Env.kJwtPrivateKey,
      printEnv: false,
      isDebugModeOn: true,
      maxConnectionCount: 1,
    );
    getIt
      ..skipDoubleRegistration = true
      ..registerFactory<TenturaDb>(
        () => TenturaDb.scoped(
          getIt<MainDbPool>(),
          scopeInterceptor: () => counter,
        ),
      );
    await configureSessionDatabaseTestGraph(env);
    final controller = GraphqlController(
      env,
      schema: TenturaGraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', 'Query root')
            ..fields.addAll([
              QueryBeaconRoom().inboxRoomContextBatch,
              QueryConstellationFieldRequests().constellationFieldRequests,
            ]),
        ),
      ),
    );
    handler = requestContextIoAdapter(
      (request) => controller.handler(
        request.change(
          context: {kContextJwtKey: const JwtEntity(sub: _viewer)},
        ),
      ),
    );
  });

  tearDownAll(() async {
    getIt.skipDoubleRegistration = false;
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  });

  setUp(() async {
    await session.writer.execute('TRUNCATE public."user" CASCADE');
    for (final (index, id) in [_viewer, _author, _blocked].indexed) {
      await session.writer.execute(
        pg.Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {
          'id': id,
          'key': pgTestPublicKey('card-questions', index + 1),
        },
      );
    }
  });

  Future<void> seen({
    String id = _request,
    bool questions = false,
    DateTime? at,
  }) async {
    await getIt<BeaconRoomRepositoryPort>().markBeaconRoomSeen(
      userId: _viewer,
      beaconId: id,
      threadItemId: questions ? 'Q$id' : null,
      at: at ?? _cursor,
    );
  }

  Future<void> seed({
    String id = _request,
    bool mine = false,
    bool admitted = false,
  }) async {
    final author = mine ? _viewer : _author;
    await session.writer.execute(
      pg.Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable, published_at)
VALUES (@id, @author, 'Moving day', '', 0, true, now())
'''),
      parameters: {'id': id, 'author': author},
    );
    if (!mine) {
      await session.writer.execute(
        pg.Sql.named('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES (@id, @author, @viewer)
'''),
        parameters: {'id': id, 'author': author, 'viewer': _viewer},
      );
    }
    if (admitted || mine) {
      // The question sender is an admitted helper on the viewer's own Request.
      final member = mine ? _author : _viewer;
      await session.writer.execute(
        pg.Sql.named('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, status, room_access)
VALUES (@id, @viewer, 2, 0, 3)
'''),
        parameters: {'id': id, 'viewer': member},
      );
    }
    await session.writer.execute(
      pg.Sql.named('''
INSERT INTO public.coordination_item
  (id, beacon_id, kind, status, title, body, creator_id, published,
   published_at, source, ordering)
VALUES (@scope, @id, 7, 0, 'Questions', '', @author, true, now(), 0, 0)
'''),
      parameters: {'scope': 'Q$id', 'id': id, 'author': author},
    );
    await seen(id: id);
  }

  Future<void> message({
    String id = _request,
    String by = _author,
    bool questions = true,
    bool system = false,
    DateTime? at,
  }) => session.writer.execute(
    pg.Sql.named('''
INSERT INTO public.beacon_room_message
  (beacon_id, author_id, body, thread_item_id, system_message_kind, created_at)
VALUES (@id, @by, 'Message', @scope, @system, @at)
'''),
    parameters: {
      'id': id,
      'by': by,
      'scope': questions ? 'Q$id' : null,
      'system': system ? 1 : null,
      'at': at ?? _fresh,
    },
  );

  Future<List<Map<String, Object?>>> query(
    String document,
    List<String> ids,
  ) async {
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v2/graphql'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'query': document,
          'variables': {'ids': ids},
        }),
      ),
    );
    expect(response.statusCode, 200);
    final body =
        jsonDecode(await response.readAsString()) as Map<String, Object?>;
    expect(body['errors'], isNull, reason: jsonEncode(body));
    final data = body['data']! as Map<String, Object?>;
    return (data.values.single! as List<Object?>).cast<Map<String, Object?>>();
  }

  Future<List<Map<String, Object?>>> cards(List<String> ids) => query(r'''
query($ids: [String!]!) {
  InboxRoomContextBatch(beaconIds: $ids) {
    beaconId isRoomMember roomUnreadCount
  }
}
''', ids);

  Future<Map<String, Object?>> card() async => (await cards([_request])).single;

  Future<void> expectFieldUnread({required bool expected}) async {
    final rows = await query(
      r'''
query($ids: [String!]!) {
  constellationFieldRequests(ids: $ids) { id has_unread }
}
''',
      [_request],
    );
    expect(rows.single, containsPair('has_unread', expected));
  }

  group('Request card counts every readable conversation', () {
    for (final role in ['author', 'admitted helper', 'Questions-only reader']) {
      test('$role sees an unread question on the Request card', () async {
        await seed(mine: role == 'author', admitted: role == 'admitted helper');
        await message();
        final row = await card();
        expect(row['isRoomMember'], role != 'Questions-only reader');
        expect(row['roomUnreadCount'], 1);
        if (role != 'author') await expectFieldUnread(expected: true);
      });
    }

    test(
      'discussion and Questions keep independent cursors and their counts add up',
      () async {
        await seed(admitted: true);
        await seen(at: DateTime.utc(2030, 1, 3));
        await seen(questions: true);
        await message(questions: false); // older than the discussion cursor
        await message(questions: false, at: DateTime.utc(2030, 1, 4));
        await message(); // newer than the Questions cursor
        expect((await card())['roomUnreadCount'], 2);
        await seen(questions: true, at: _fresh);
        expect((await card())['roomUnreadCount'], 1);
        await expectFieldUnread(expected: true);
        await seen(at: DateTime.utc(2030, 1, 4));
        expect((await card())['roomUnreadCount'], 0);
        await expectFieldUnread(expected: false);
      },
    );

    test(
      'Questions-only readers count neither private discussion nor self, system or blocked Questions messages',
      () async {
        await seed();
        await session.writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, status, room_access)
VALUES ('$_request', '$_blocked', 2, 0, 3)
''');
        await session.writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_viewer', '$_blocked', '$_viewer')
''');
        await message(questions: false);
        await message(by: _viewer);
        await message(system: true);
        await message(by: _blocked);
        await message();
        expect((await card())['roomUnreadCount'], 1);
        await expectFieldUnread(expected: true);
      },
    );

    for (final admitted in [false, true]) {
      test(
        'removal from Questions ${admitted ? 'preserves the unread discussion count' : 'clears the Questions-only readers count'}',
        () async {
          await seed(admitted: admitted);
          await message(questions: false);
          await message();
          await session.writer.execute('''
INSERT INTO public.beacon_lobby_ban (beacon_id, user_id, banned_by)
VALUES ('$_request', '$_viewer', '$_author')
''');
          expect((await card())['roomUnreadCount'], admitted ? 1 : 0);
          await expectFieldUnread(expected: admitted);
        },
      );
    }

    test(
      'Questions unread counts for many cards use the same SQL statement count as one card',
      () async {
        final ids = [for (var i = 0; i < 12; i++) 'Bqcardbatch$i'];
        for (final id in ids) {
          await seed(id: id);
          await message(id: id);
          await message(id: id, questions: false);
        }
        await cards([ids.first]);
        counter.reset();
        final one = await cards([ids.first]);
        final oneCount = counter.count;
        counter.reset();
        final many = await cards(ids);
        expect(counter.count, oneCount);
        expect(one, hasLength(1));
        expect(many, hasLength(ids.length));
        for (final row in [...one, ...many]) {
          expect(row['isRoomMember'], isFalse);
          expect(row['roomUnreadCount'], 1);
        }
      },
    );
  });
}
