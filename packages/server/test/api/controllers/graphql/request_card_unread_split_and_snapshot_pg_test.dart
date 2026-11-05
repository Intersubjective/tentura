@Tags(['pg'])
library;

import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart' as pg;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_beacon_room.dart';
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
import '../../../support/session_database_di_harness.dart';

const _viewer = 'Uqcardviewer01';
const _author = 'Uqcardauthor01';
const _request = 'Bqcardrequest1';
final _cursor = DateTime.utc(2030);
final _fresh = DateTime.utc(2030, 1, 2);

// Real HTTP GraphQL, generated production DI, and disposable PostgreSQL:
// a Request card keeps its Questions unread count apart from the discussion
// one (a local discussion read watermark may zero only the discussion part),
// and the count and the room that holds the oldest unread message describe
// one and the same moment even when a message lands while the card is read.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_CARD_UNREAD_SPLIT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_card_unread_split',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Postgres unavailable', () {}, skip: unavailable);
    return;
  }

  late DisposablePgWriterSession session;
  late Handler handler;
  final interceptor = _AfterNthSelectInterceptor();

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
          scopeInterceptor: () => interceptor,
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
    for (final (index, id) in [_viewer, _author].indexed) {
      await session.writer.execute(
        pg.Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {
          'id': id,
          'key': pgTestPublicKey('card-unread-split', index + 1),
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
    beaconId roomUnreadCount questionsUnreadCount unreadRoom
  }
}
''', ids);

  Future<Map<String, Object?>> card() async => (await cards([_request])).single;

  group('Request card keeps Questions unread apart from discussion unread', () {
    test(
      'an unread question is reported on its own next to the combined total',
      () async {
        await seed(admitted: true);
        await message(questions: false);
        await message();
        final row = await card();
        expect(row['roomUnreadCount'], 2);
        expect(row['questionsUnreadCount'], 1);
      },
    );

    test(
      'reading the discussion leaves the unread question counted',
      () async {
        await seed(admitted: true);
        await message(questions: false);
        await message();
        await seen(at: DateTime.utc(2030, 1, 3));
        final row = await card();
        expect(
          row['questionsUnreadCount'],
          1,
          reason: 'a discussion read cursor must not hide a Question',
        );
        expect(row['roomUnreadCount'], 1);
      },
    );

    test(
      'a Questions-only reader sees the question and no discussion',
      () async {
        await seed();
        await message(questions: false);
        await message();
        final row = await card();
        expect(row['questionsUnreadCount'], 1);
        expect(row['roomUnreadCount'], 1);
      },
    );

    test(
      'a read Questions room reports none while the discussion is unread',
      () async {
        await seed(admitted: true);
        await message(questions: false);
        await message();
        await seen(questions: true, at: _fresh);
        final row = await card();
        expect(row['questionsUnreadCount'], 0);
        expect(row['roomUnreadCount'], 1);
      },
    );
  });

  // The card is read with several statements. Rather than assume which ones,
  // a write is made to land after each of them in turn, from a second
  // connection, and the card must still agree with itself: it names a room
  // holding unread messages exactly when it counts some.
  group('Request card count and oldest unread room come from one snapshot', () {
    Future<void> expectAgreesWithItselfWhenWriteLandsAfterEachRead({
      required Future<void> Function() prepare,
      required Future<void> Function() write,
    }) async {
      await prepare();
      interceptor.reset();
      await card();
      final reads = interceptor.selectsSeen;
      expect(reads, greaterThan(0), reason: 'the card must read the database');
      for (var after = 1; after <= reads; after++) {
        await session.writer.execute('DELETE FROM public.beacon_room_message');
        await prepare();
        interceptor.reset(runAfter: after, hook: write);
        final row = await card();
        expect(interceptor.hookRan, isTrue, reason: 'write after read $after');
        expect(
          (row['roomUnreadCount']! as int) > 0,
          row['unreadRoom'] != null,
          reason:
              'write landed after read $after of $reads: count '
              '${row['roomUnreadCount']} vs room ${row['unreadRoom']}',
        );
      }
    }

    test(
      'a message arriving mid-read cannot show a room without a count',
      () async {
        await seed(admitted: true);
        await expectAgreesWithItselfWhenWriteLandsAfterEachRead(
          prepare: () async {},
          write: () => message(questions: false),
        );
      },
    );

    test(
      'a message removed mid-read cannot show a count without a room',
      () async {
        await seed(admitted: true);
        await expectAgreesWithItselfWhenWriteLandsAfterEachRead(
          prepare: () => message(questions: false),
          write: () => session.writer.execute(
            'DELETE FROM public.beacon_room_message',
          ),
        );
      },
    );
  });
}

/// Counts the card's selects and, when armed, runs its hook once right after the
/// armed index-th of them has returned, so a write can land between any two of
/// the card's reads without naming a statement.
class _AfterNthSelectInterceptor extends QueryInterceptor {
  int selectsSeen = 0;
  bool hookRan = false;
  int? _runAfter;
  Future<void> Function()? _hook;

  void reset({int? runAfter, Future<void> Function()? hook}) {
    selectsSeen = 0;
    hookRan = false;
    _runAfter = runAfter;
    _hook = hook;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await super.runSelect(executor, statement, args);
    selectsSeen++;
    final hook = _hook;
    if (hook != null && selectsSeen == _runAfter) {
      _hook = null;
      hookRan = true;
      await hook();
    }
    return rows;
  }
}
