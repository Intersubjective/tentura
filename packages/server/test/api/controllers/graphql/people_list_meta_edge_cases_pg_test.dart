@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/session_database_di_harness.dart';

const _viewer = 'Uplmviewer00001';
const _peer = 'Uplmpeer0000001';
const _other = 'Uplmother000001';
const _stranger = 'Uplmstranger001';

const _document = '''
query {
  peopleListMeta { id newSince newReason lastInteractionAt }
}
''';

/// People tab sort keys stay correct around blocks, room traffic that is not
/// a conversation, routine trust maintenance, cancelled forwards and
/// timestamp ties, read through the real V2 schema over real Postgres rows.
///
/// Input devices, locale, viewport and UI lifecycle are n/a for this server
/// response.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PEOPLE_LIST_META_CORRECTNESS_TEST_DB',
    defaultNamePrefix: 'tentura_test_people_list_meta_correct',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  group('People list sort keys under edge cases', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb appDatabase;
    late GraphQL schema;

    Future<void> addUser(String id) async {
      await writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          'VALUES (@id, @id, @key)',
        ),
        parameters: {
          'id': id,
          'key': '$id-key',
        },
      );
    }

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
      for (final id in [_viewer, _peer, _other, _stranger]) {
        await addUser(id);
      }
    });

    // ---- fixtures -------------------------------------------------------

    DateTime ago(Duration d) {
      final now = DateTime.now().toUtc();
      return DateTime.utc(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
        now.second,
      ).subtract(d);
    }

    Future<void> trust(
      String subject,
      String object, {
      required DateTime created,
      DateTime? updated,
    }) => writer.execute(
      Sql.named('''
INSERT INTO public.user_trust_edge
  (subject, object, trust_w, target_w, created_at, updated_at)
VALUES (@subject, @object, 1, 1, @created, @updated)
'''),
      parameters: {
        'subject': subject,
        'object': object,
        'created': created,
        'updated': updated ?? created,
      },
    );

    Future<void> invite({
      required String inviter,
      required String invited,
      required DateTime acceptedAt,
    }) => writer.execute(
      Sql.named('''
INSERT INTO public.invitation
  (user_id, invited_id, invite_origin, accepted_at, created_at)
VALUES (@inviter, @invited, 'new_account', @accepted, @created)
'''),
      parameters: {
        'inviter': inviter,
        'invited': invited,
        'accepted': acceptedAt,
        'created': acceptedAt.subtract(const Duration(hours: 1)),
      },
    );

    Future<void> block(String blocker, String blocked) => writer.execute(
      Sql.named(
        'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
        'VALUES (@blocker, @blocked, @blocker)',
      ),
      parameters: {'blocker': blocker, 'blocked': blocked},
    );

    Future<void> room(
      String id, {
      required String owner,
      required List<String> participants,
    }) async {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, status, is_discoverable, published_at)
VALUES (@id, @owner, 'Room', '', 0, 0, true, now())
'''),
        parameters: {'id': id, 'owner': owner},
      );
      for (final user in participants) {
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES (@id, @user, 1, 3)
'''),
          parameters: {'id': id, 'user': user},
        );
      }
    }

    Future<void> message(
      String roomId,
      String author,
      DateTime at, {
      String? threadItemId,
      int? systemKind,
      int? marker,
    }) => writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message
  (beacon_id, author_id, body, created_at, thread_item_id,
   system_message_kind, semantic_marker)
VALUES (@room, @author, 'hello', @at, @thread, @systemKind, @marker)
'''),
      parameters: {
        'room': roomId,
        'author': author,
        'at': at,
        'thread': threadItemId,
        'systemKind': systemKind,
        'marker': marker,
      },
    );

    Future<void> forward(
      String roomId, {
      required String from,
      required String to,
      required DateTime at,
      DateTime? cancelledAt,
    }) => writer.execute(
      Sql.named('''
INSERT INTO public.beacon_forward_edge
  (beacon_id, sender_id, recipient_id, created_at, cancelled_at)
VALUES (@room, @from, @to, @at, @cancelled)
'''),
      parameters: {
        'room': roomId,
        'from': from,
        'to': to,
        'at': at,
        'cancelled': cancelledAt,
      },
    );

    Future<Map<String, Map<String, dynamic>>> peopleList() async {
      final result = await schema.parseAndExecute(
        _document,
        globalVariables: {kGlobalInputQueryJwt: const JwtEntity(sub: _viewer)},
      );
      expect(
        result,
        isA<Map<String, dynamic>>().having(
          (r) => r['peopleListMeta'],
          'peopleListMeta',
          isA<List<dynamic>>(),
        ),
        reason: 'the V2 schema must answer the peopleListMeta query',
      );
      final rows = ((result! as Map)['peopleListMeta'] as List)
          .cast<Map<String, dynamic>>();
      return {for (final row in rows) row['id']! as String: row};
    }

    DateTime? instant(Object? value) {
      if (value == null) return null;
      return (value is DateTime ? value : DateTime.parse(value as String))
          .toUtc();
    }

    Future<Map<String, dynamic>> peerRow([String id = _peer]) async {
      final rows = await peopleList();
      expect(rows.keys, contains(id), reason: 'a trusted person is listed');
      return rows[id]!;
    }

    Future<void> oldTrust(String person) => trust(
      _viewer,
      person,
      created: ago(const Duration(days: 30)),
    );

    /// A Request room the viewer and the peer both sit in, plus an older
    /// forward from the viewer to the peer: the last interaction is that
    /// forward unless something newer legitimately counts.
    Future<DateTime> forwardedBaseline(String roomId) async {
      final forwarded = ago(const Duration(days: 4));
      await oldTrust(_peer);
      await room(roomId, owner: _viewer, participants: [_viewer, _peer]);
      await forward(roomId, from: _viewer, to: _peer, at: forwarded);
      return forwarded;
    }

    // ---- blocks ---------------------------------------------------------

    group('blocked people', () {
      test('a person who blocked the viewer is not listed, and the other '
          "person's keys are unchanged", () async {
        final trustedAt = ago(const Duration(days: 30));
        await trust(_viewer, _peer, created: trustedAt);
        await trust(_viewer, _other, created: trustedAt);
        await room('Bplmblocked0001', owner: _viewer, participants: [_viewer]);
        await forward(
          'Bplmblocked0001',
          from: _viewer,
          to: _peer,
          at: ago(const Duration(hours: 2)),
        );
        await block(_peer, _viewer);

        final rows = await peopleList();

        expect(rows.keys, [_other]);
        expect(rows[_other]!['newSince'], isNull);
        expect(instant(rows[_other]!['lastInteractionAt']), trustedAt);
      });

      test('a person the viewer blocked is not listed, and the other '
          "person's keys are unchanged", () async {
        final trustedAt = ago(const Duration(days: 30));
        await trust(_viewer, _peer, created: trustedAt);
        await trust(_viewer, _other, created: trustedAt);
        await room('Bplmblocked0002', owner: _viewer, participants: [_viewer]);
        await forward(
          'Bplmblocked0002',
          from: _viewer,
          to: _peer,
          at: ago(const Duration(hours: 2)),
        );
        await block(_viewer, _peer);

        final rows = await peopleList();

        expect(rows.keys, [_other]);
        expect(rows[_other]!['newSince'], isNull);
        expect(instant(rows[_other]!['lastInteractionAt']), trustedAt);
      });
    });

    // ---- what counts as the person speaking ----------------------------

    group('room messages by the person', () {
      test(
        'a General room message from the person is an interaction',
        () async {
          await forwardedBaseline('Bplmgeneral0001');
          final spoke = ago(const Duration(minutes: 10));
          await message('Bplmgeneral0001', _peer, spoke);

          final row = await peerRow();

          expect(instant(row['lastInteractionAt']), spoke);
        },
      );

      test('system lines are not a conversation', () async {
        final forwarded = await forwardedBaseline('Bplmsystem0001');
        final now = ago(const Duration(minutes: 10));
        await message('Bplmsystem0001', _peer, now, systemKind: 1);
        for (final marker in [1, 2, 3]) {
          await message('Bplmsystem0001', _peer, now, marker: marker);
        }

        final row = await peerRow();

        expect(instant(row['lastInteractionAt']), forwarded);
      });

      /// A Request room owned by someone else, where the viewer and the
      /// person both sit, with a Questions scope (coordination item kind 7).
      /// The viewer is not the author, so a lobby ban takes their Questions
      /// access away (`questions_access_levels`: banned and not author = 0).
      Future<DateTime> questionsRoom(
        String roomId, {
        bool viewerBanned = false,
      }) async {
        final forwarded = ago(const Duration(days: 4));
        await oldTrust(_peer);
        await room(roomId, owner: _other, participants: [_viewer, _peer]);
        await forward(roomId, from: _viewer, to: _peer, at: forwarded);
        await writer.execute(
          Sql.named(
            'INSERT INTO public.coordination_item '
            '(id, beacon_id, kind, status, creator_id, published) '
            'VALUES (@lobby, @room, 7, 0, @owner, true)',
          ),
          parameters: {'lobby': 'C$roomId', 'room': roomId, 'owner': _other},
        );
        if (viewerBanned) {
          await writer.execute(
            Sql.named(
              'INSERT INTO public.beacon_lobby_ban (beacon_id, user_id, '
              'banned_by) VALUES (@room, @viewer, @owner)',
            ),
            parameters: {'room': roomId, 'viewer': _viewer, 'owner': _other},
          );
        }
        return forwarded;
      }

      test('a Questions message is not a General conversation even when the '
          'viewer may read Questions', () async {
        final forwarded = await questionsRoom('Bplmquestion001');
        // Precondition: the viewer really has Questions access, so only the
        // General-room restriction can keep this message out.
        final access = await writer.execute(
          Sql.named(
            'SELECT access FROM public.questions_access_levels('
            '@room, ARRAY[@viewer]::text[])',
          ),
          parameters: {'room': 'Bplmquestion001', 'viewer': _viewer},
        );
        expect(
          access.single.single as int,
          greaterThan(0),
          reason: 'the viewer can read Questions in this room',
        );
        await message(
          'Bplmquestion001',
          _peer,
          ago(const Duration(minutes: 10)),
          threadItemId: 'CBplmquestion001',
        );

        final row = await peerRow();

        expect(instant(row['lastInteractionAt']), forwarded);
      });

      test('a Questions message does not count when the viewer has no '
          'Questions access', () async {
        final forwarded = await questionsRoom(
          'Bplmquestion002',
          viewerBanned: true,
        );
        await message(
          'Bplmquestion002',
          _peer,
          ago(const Duration(minutes: 10)),
          threadItemId: 'CBplmquestion002',
        );

        final row = await peerRow();

        expect(instant(row['lastInteractionAt']), forwarded);
      });

      test('a banned viewer still sees the person speak in General', () async {
        await questionsRoom('Bplmquestion003', viewerBanned: true);
        final spoke = ago(const Duration(minutes: 10));
        await message('Bplmquestion003', _peer, spoke);

        final row = await peerRow();

        expect(instant(row['lastInteractionAt']), spoke);
      });
    });

    // ---- trust maintenance ---------------------------------------------

    group('trust edge timestamps', () {
      test("routine maintenance of the viewer's edge is not an "
          'interaction', () async {
        final created = ago(const Duration(days: 30));
        final forwarded = ago(const Duration(days: 4));
        await trust(
          _viewer,
          _peer,
          created: created,
          updated: ago(const Duration(minutes: 5)),
        );
        await room('Bplmmaint000001', owner: _viewer, participants: [_viewer]);
        await forward(
          'Bplmmaint000001',
          from: _viewer,
          to: _peer,
          at: forwarded,
        );

        final row = await peerRow();

        // Not the maintenance rewrite of updated_at (5 minutes ago): the
        // real forward is the latest evidence.
        expect(instant(row['lastInteractionAt']), forwarded);
      });

      test("routine maintenance of the person's edge toward the viewer is "
          'not an interaction', () async {
        final viewerEdge = ago(const Duration(days: 30));
        final personEdge = ago(const Duration(days: 20));
        final forwarded = ago(const Duration(days: 4));
        await trust(_viewer, _peer, created: viewerEdge);
        await trust(
          _peer,
          _viewer,
          created: personEdge,
          updated: ago(const Duration(minutes: 5)),
        );
        await room('Bplmmaint000002', owner: _viewer, participants: [_viewer]);
        await forward(
          'Bplmmaint000002',
          from: _peer,
          to: _viewer,
          at: forwarded,
        );

        final row = await peerRow();

        // Not the maintenance rewrite of updated_at (5 minutes ago): the
        // real forward is the latest evidence.
        expect(instant(row['lastInteractionAt']), forwarded);
      });
    });

    // ---- forwards -------------------------------------------------------

    test('a cancelled forward is not an interaction', () async {
      final active = ago(const Duration(days: 10));
      await oldTrust(_peer);
      await room('Bplmcancel00001', owner: _viewer, participants: [_viewer]);
      await room('Bplmcancel00002', owner: _viewer, participants: [_viewer]);
      await forward('Bplmcancel00001', from: _viewer, to: _peer, at: active);
      await forward(
        'Bplmcancel00002',
        from: _viewer,
        to: _peer,
        at: ago(const Duration(days: 1)),
        cancelledAt: ago(const Duration(hours: 20)),
      );

      final row = await peerRow();

      expect(instant(row['lastInteractionAt']), active);
    });

    // ---- ties -----------------------------------------------------------

    test('invite acceptance at the very instant trust became mutual is '
        '"invite"', () async {
      final at = ago(const Duration(days: 1));
      await oldTrust(_peer);
      await trust(_peer, _viewer, created: at);
      await invite(inviter: _viewer, invited: _peer, acceptedAt: at);

      final row = await peerRow();

      expect(row['newReason'], 'invite');
      expect(instant(row['newSince']), at);
    });
  });
}
