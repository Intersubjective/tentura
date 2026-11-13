@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_beacon_room.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/domain/entity/beacon_thread_record.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/session_database_di_harness.dart';

const _member = 'Uthfbmember0001';
const _room = 'Bthfbroom000001';

const _document = '''
query {
  beaconThreads(beaconId: "$_room") {
    threadId
    lastMessagePreview { kind excerpt factTitle factCount }
  }
}
''';

/// The General row's last-message preview when the last line is a
/// "facts brought" system line (semantic marker 20): listed through the
/// repository and through the real `beaconThreads` GraphQL query, over real
/// Postgres rows. Input devices, locale and viewport are n/a (server only).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_THREAD_FACTS_BROUGHT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_thfacts',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  group('thread list preview of a facts-brought line', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb appDatabase;
    late GraphQL schema;
    late CoordinationItemRepository items;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      appDatabase = TenturaDb.forTest(
        database: PgDatabase.opened(
          Pool<dynamic>.withEndpoints(
            [target.databaseEnv.pgEndpoint],
            settings: target.databaseEnv.pgPoolSettings,
          ),
          enableMigrations: false,
        ),
      );
      items = CoordinationItemRepository(appDatabase);
      getIt
        ..skipDoubleRegistration = true
        ..registerSingleton<TenturaDb>(appDatabase)
        ..registerSingleton<TenturaDb>(appDatabase, instanceName: 'auth');
      final db = target.databaseEnv;
      await configureSessionDatabaseTestGraph(
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
      schema = graphqlSchema;
    });

    tearDownAll(() async {
      getIt.skipDoubleRegistration = false;
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session, drift: appDatabase);
    });

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      await writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          'VALUES (@id, @id, @key)',
        ),
        parameters: {'id': _member, 'key': '$_member-key'},
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, status, is_discoverable, published_at)
VALUES (@id, @owner, 'Room', '', 0, 0, true, now())
'''),
        parameters: {'id': _room, 'owner': _member},
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES (@id, @user, 1, 3)
'''),
        parameters: {'id': _room, 'user': _member},
      );
    });

    Future<void> lastLine({
      required DateTime at,
      String body = '',
      int? marker,
      String? payloadJson,
    }) => writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message
  (beacon_id, author_id, body, created_at, semantic_marker, system_payload)
VALUES (@room, @author, @body, @at, @marker, CAST(@payload AS jsonb))
'''),
      parameters: {
        'room': _room,
        'author': _member,
        'body': body,
        'at': at,
        'marker': marker,
        'payload': payloadJson,
      },
    );

    /// General row preview as the repository + serializer produce it.
    Future<Map<String, Object?>> repositoryPreview() async {
      final rows = await items.listThreads(
        beaconId: _room,
        viewerUserId: _member,
        includeGeneral: true,
        itemParticipantsOnly: false,
        excerptCharacters: 140,
      );
      final general = rows.singleWhere((r) => r.threadId == 'general');
      return beaconThreadRecordToMap(general)['lastMessagePreview']!
          as Map<String, Object?>;
    }

    /// General row preview as the `beaconThreads` GraphQL query serves it.
    Future<Map<String, Object?>> graphqlPreview() async {
      final result = await schema.parseAndExecute(
        _document,
        globalVariables: {kGlobalInputQueryJwt: const JwtEntity(sub: _member)},
      );
      final rows = ((result! as Map)['beaconThreads'] as List)
          .cast<Map<String, dynamic>>();
      final general = rows.singleWhere((r) => r['threadId'] == 'general');
      return (general['lastMessagePreview'] as Map).cast<String, Object?>();
    }

    final factsBroughtMany = DateTime.utc(2026, 1, 5);

    test('several facts: lists without error, new kind, count, no fact text',
        () async {
      await lastLine(
        at: factsBroughtMany,
        marker: 20,
        payloadJson: '{"factCardIds":["Fa","Fb","Fc"],"count":3,'
            '"originBeaconKind":0}',
      );

      final viaRepository = await repositoryPreview();
      final viaGraphql = await graphqlPreview();

      for (final preview in [viaRepository, viaGraphql]) {
        expect(preview['kind'], ThreadMessagePreviewKind.factsBrought);
        expect(preview['factCount'], 3);
        expect(preview['factTitle'], isNull);
      }
      expect(viaGraphql['kind'], viaRepository['kind']);
    });

    test('one fact: count 1 and the fact text', () async {
      await lastLine(
        at: factsBroughtMany,
        marker: 20,
        payloadJson: '{"factCardIds":["Fa"],"count":1,"originBeaconKind":0,'
            '"factText":"Key is under the mat"}',
      );

      final viaRepository = await repositoryPreview();
      final viaGraphql = await graphqlPreview();

      for (final preview in [viaRepository, viaGraphql]) {
        expect(preview['kind'], ThreadMessagePreviewKind.factsBrought);
        expect(preview['factCount'], 1);
        expect(preview['factTitle'], 'Key is under the mat');
      }
      expect(viaGraphql['kind'], viaRepository['kind']);
    });

    test('a plain text last line carries no fact count', () async {
      await lastLine(at: factsBroughtMany, body: 'hello preview');

      final preview = await repositoryPreview();

      expect(preview['kind'], ThreadMessagePreviewKind.text);
      expect(preview['excerpt'], 'hello preview');
      expect(preview.containsKey('factCount'), isTrue);
      expect(preview['factCount'], isNull);
      expect((await graphqlPreview())['factCount'], isNull);
    });

    test('a fact-pinned last line keeps its kind and fact text, no count',
        () async {
      await lastLine(
        at: factsBroughtMany,
        marker: BeaconRoomSemanticMarker.pinFactPublic,
        payloadJson: '{"factText":"Pinned text"}',
      );

      final preview = await repositoryPreview();

      expect(preview['kind'], ThreadMessagePreviewKind.factPinned);
      expect(preview['factTitle'], 'Pinned text');
      expect(preview.containsKey('factCount'), isTrue);
      expect(preview['factCount'], isNull);
      expect((await graphqlPreview())['factCount'], isNull);
    });
  });
}
