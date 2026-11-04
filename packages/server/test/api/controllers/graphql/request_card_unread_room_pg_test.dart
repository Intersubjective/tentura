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
import 'package:tentura_server/domain/port/attention_query_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
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
// cards link to the oldest readable unread conversation; chat posts do not
// create a second per-message update on the card or in its timeline.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_CARD_UNREAD_ROOM_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_card_unread_room',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Postgres unavailable', () {}, skip: unavailable);
    return;
  }

  late DisposablePgWriterSession session;
  late Handler handler;

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
        ),
      );
    await configureSessionDatabaseTestGraph(env);
    final controller = GraphqlController(
      env,
      schema: TenturaGraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', 'Query root')
            ..fields.add(QueryBeaconRoom().inboxRoomContextBatch),
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

  Future<String> message({
    String id = _request,
    String by = _author,
    bool questions = true,
    bool system = false,
    DateTime? at,
  }) async {
    final result = await session.writer.execute(
      pg.Sql.named('''
INSERT INTO public.beacon_room_message
  (beacon_id, author_id, body, thread_item_id, system_message_kind, created_at)
VALUES (@id, @by, 'Message', @scope, @system, @at)
RETURNING id
'''),
      parameters: {
        'id': id,
        'by': by,
        'scope': questions ? 'Q$id' : null,
        'system': system ? 1 : null,
        'at': at ?? _fresh,
      },
    );
    return result.single[0]! as String;
  }

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

  BeaconRoomCase rooms() => getIt<BeaconRoomCase>();

  Future<Map<String, Object?>> card() async =>
      (await rooms().inboxRoomContextBatch(
        userId: _viewer,
        beaconIds: [_request],
      )).single;

  // Every attention receipt this viewer or the outbox holds for a message id.
  Future<List<Object?>> receiptsFor(Iterable<String> messageIds) async {
    final found = <Object?>[];
    final history = await getIt<AttentionQueryPort>().attentionRequestHistory(
      accountId: _viewer,
      beaconId: _request,
    );
    final ids = messageIds.toSet();
    found.addAll(
      history.items.map((r) => r.targetEntityId).where(ids.contains),
    );
    for (final id in ids) {
      final result = await session.writer.execute(
        pg.Sql.named('''
SELECT id FROM public.notification_outbox
WHERE target_entity_id = @id OR source_event_key LIKE '%' || @id || '%'
'''),
        parameters: {'id': id},
      );
      found.addAll(result.map((r) => r[0]));
    }
    return found;
  }

  // Questions rows that unread state was seeded with, and no card update,
  // timeline row or outbox receipt for any of them.
  Future<void> expectQuestionsChatLeftNoReceipts(
    Iterable<String> questionMessageIds,
  ) async {
    expect(
      await receiptsFor(questionMessageIds),
      isEmpty,
      reason: 'Questions is chat: its messages must not write any receipt',
    );
  }

  group('Request cards identify the oldest readable unread conversation', () {
    for (final role in ['author', 'admitted helper', 'Questions-only asker']) {
      test(
        '$role sees a Questions message as the unread conversation, ignoring system lines, own posts and unreadable discussion',
        () async {
          await seed(
            mine: role == 'author',
            admitted: role == 'admitted helper',
          );
          final ids = [
            await message(system: true, at: DateTime.utc(2030, 1, 1, 1)),
            await message(by: _viewer, at: DateTime.utc(2030, 1, 1, 2)),
            // This private discussion message is older, but only admitted
            // readers can see it. System lines and one's own posts are never
            // candidates.
            await message(questions: false, at: DateTime.utc(2030, 1, 1, 3)),
            await message(),
          ];
          if (role != 'Questions-only asker') {
            await seen(at: DateTime.utc(2030, 1, 1, 3));
          }
          final row = await card();
          expect(row['roomUnreadCount'], 1);
          expect(row, containsPair('unreadRoom', 'questions'));
          await expectQuestionsChatLeftNoReceipts([ids[0], ids[1], ids[3]]);
        },
      );
    }

    for (final role in ['author', 'admitted helper', 'Questions-only asker']) {
      test(
        '$role sees one counter over every room they can read when discussion and Questions are both unread',
        () async {
          await seed(
            mine: role == 'author',
            admitted: role == 'admitted helper',
          );
          final canReadDiscussion = role != 'Questions-only asker';
          await message(questions: false, at: DateTime.utc(2030, 1, 2, 1));
          final question = await message(at: DateTime.utc(2030, 1, 2, 2));
          final row = await card();
          // The asker cannot read the (older) discussion, so it neither counts
          // nor becomes the tap target.
          expect(row['roomUnreadCount'], canReadDiscussion ? 2 : 1);
          expect(
            row,
            containsPair(
              'unreadRoom',
              canReadDiscussion ? 'discussion' : 'questions',
            ),
          );
          await expectQuestionsChatLeftNoReceipts([question]);
        },
      );
    }

    for (final questionsFirst in [true, false]) {
      test(
        '${questionsFirst ? 'Questions' : 'discussion'} stays the target until its unread messages are read',
        () async {
          await seed(admitted: true);
          await seen(questions: true);
          final older = DateTime.utc(2030, 1, 2);
          final newer = DateTime.utc(2030, 1, 3);
          await message(questions: questionsFirst, at: older);
          await message(questions: !questionsFirst, at: newer);
          final before = await card();
          expect(before['roomUnreadCount'], 2);
          expect(
            before,
            containsPair(
              'unreadRoom',
              questionsFirst ? 'questions' : 'discussion',
            ),
          );
          await seen(questions: questionsFirst, at: older);
          final remaining = await card();
          expect(remaining['roomUnreadCount'], 1);
          expect(
            remaining,
            containsPair(
              'unreadRoom',
              questionsFirst ? 'discussion' : 'questions',
            ),
          );
          await seen(questions: !questionsFirst, at: newer);
          final read = await card();
          expect(read['roomUnreadCount'], 0);
          expect(read, containsPair('unreadRoom', null));
        },
      );
    }

    for (final role in ['author', 'admitted helper']) {
      test(
        '$role gets a discussion target when only the discussion has an unread message',
        () async {
          await seed(mine: role == 'author', admitted: role != 'author');
          await seen(questions: true);
          await message(questions: false);
          final row = await card();
          expect(row['roomUnreadCount'], 1);
          expect(row, containsPair('unreadRoom', 'discussion'));
        },
      );
    }

    test(
      'a card with only self and system messages explicitly has no unread target',
      () async {
        await seed(admitted: true);
        await message(system: true);
        await message(questions: false, system: true);
        await message(by: _viewer);
        await message(questions: false, by: _viewer);
        final row = await card();
        expect(row['roomUnreadCount'], 0);
        expect(row, containsPair('unreadRoom', null));
      },
    );

    const cardDocument = r'''
query($ids: [String!]!) {
  InboxRoomContextBatch(beaconIds: $ids) {
    beaconId roomUnreadCount unreadRoom
  }
}
''';

    test(
      'the card GraphQL response exposes the Questions tap target',
      () async {
        await seed();
        await message();
        final rows = await query(cardDocument, [_request]);
        expect(rows.single['roomUnreadCount'], 1);
        expect(rows.single, containsPair('unreadRoom', 'questions'));
      },
    );

    test(
      'the card GraphQL response exposes the discussion tap target',
      () async {
        await seed(admitted: true);
        await seen(questions: true);
        await message(questions: false);
        final rows = await query(cardDocument, [_request]);
        expect(rows.single['roomUnreadCount'], 1);
        expect(rows.single, containsPair('unreadRoom', 'discussion'));
      },
    );

    test(
      'the card GraphQL response has a null tap target once everything is read',
      () async {
        await seed(admitted: true);
        await message();
        await message(questions: false);
        await seen(questions: true, at: DateTime.utc(2030, 1, 3));
        await seen(at: DateTime.utc(2030, 1, 3));
        final rows = await query(cardDocument, [_request]);
        expect(rows.single['roomUnreadCount'], 0);
        expect(rows.single, containsPair('unreadRoom', null));
      },
    );
  });

  group('Questions chat stays out of per-message card updates', () {
    Future<List<Object?>> writerRowsFor(String messageId) async {
      final result = await session.writer.execute(
        pg.Sql.named('''
SELECT id FROM public.notification_outbox
WHERE target_entity_id = @id OR source_event_key LIKE '%' || @id || '%'
'''),
        parameters: {'id': messageId},
      );
      return result.map((r) => r[0]).toList();
    }

    test(
      'posting a question preserves discussion updates and the My desk obligation count',
      () async {
        await seed(mine: true);
        final attention = getIt<AttentionQueryPort>();
        // A directed discussion reply is an ordinary update and must survive.
        final root = await rooms().createMessage(
          beaconId: _request,
          userId: _viewer,
          body: 'Discussion starter',
        );
        final discussion = await rooms().createMessage(
          beaconId: _request,
          userId: _author,
          body: 'Discussion reply',
          replyToMessageId: root['id']! as String,
        );
        final before = await attention.attentionRequestHistory(
          accountId: _viewer,
          beaconId: _request,
        );
        expect(
          before.items.map((r) => r.targetEntityId),
          contains(discussion['id']),
        );
        final countBefore = (await attention.surfaceSummary(
          accountId: _viewer,
        )).myDeskCount;
        final question = await rooms().createMessage(
          beaconId: _request,
          userId: _author,
          body: 'Which Saturday?',
          threadItemId: 'Q$_request',
        );
        final messages = await rooms().listMessages(
          beaconId: _request,
          userId: _viewer,
          threadItemId: 'Q$_request',
        );
        expect(messages.map((m) => m['id']), contains(question['id']));
        expect(
          (await attention.surfaceSummary(accountId: _viewer)).myDeskCount,
          countBefore,
        );
        final questionRows = await writerRowsFor(question['id']! as String);
        expect(
          questionRows,
          isEmpty,
          reason:
              'Questions is chat: its message must not write any attention receipt',
        );
        expect(
          await writerRowsFor(discussion['id']! as String),
          isNotEmpty,
          reason: 'a discussion reply keeps its ordinary update receipt',
        );
        final after = await attention.attentionRequestHistory(
          accountId: _viewer,
          beaconId: _request,
        );
        expect(
          after.items.map((r) => r.id),
          unorderedEquals(before.items.map((r) => r.id)),
          reason:
              'Questions is chat: its message must not add a card update or timeline receipt',
        );
      },
    );

    for (final poster in ['author', 'Questions-only asker']) {
      test(
        'a Questions message from the $poster leaves no receipt for the other side',
        () async {
          // The viewer is the Request author; the asker is not admitted.
          await seed(mine: true);
          final sender = poster == 'author' ? _viewer : _author;
          final question = await rooms().createMessage(
            beaconId: _request,
            userId: sender,
            body: 'Which Saturday?',
            threadItemId: 'Q$_request',
          );
          expect(
            await receiptsFor([question['id']! as String]),
            isEmpty,
            reason:
                'Questions is chat: no card update, timeline row or outbox receipt',
          );
        },
      );
    }
  });
}
