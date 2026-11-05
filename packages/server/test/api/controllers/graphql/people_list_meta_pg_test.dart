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

const _kindRequest = 0;
const _kindPost = 1;

const _document = '''
query {
  peopleListMeta { id newSince newReason lastInteractionAt }
}
''';

/// The People tab's sort keys, read through the real V2 schema over a real
/// Postgres: for every person the viewer trusts, why and since when the
/// relationship is "new" (last 7 days) and when the two last interacted.
///
/// Coverage: each "new" reason on its own and in competition (invite, viewer
/// trust, mutual trust), the 7-day cutoff, forwards in either direction, room
/// messages in Request and Post rooms the viewer is in or not in, trust
/// changes, invite acceptance, and the statement count for a whole list.
/// Trust is seeded as user_trust_edge rows, never through vote_user. Input
/// devices, locale, viewport and UI lifecycle are n/a for this server response.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PEOPLE_LIST_META_TEST_DB',
    defaultNamePrefix: 'tentura_test_people_list_meta',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  group('People list sort keys', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb appDatabase;
    late _StatementRecorder recorder;
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
      recorder = _StatementRecorder();
      // The server graph uses this database, so every statement the resolver
      // issues is seen by the recorder.
      appDatabase = TenturaDb.forTest(
        database: PgDatabase.opened(
          Pool<dynamic>.withEndpoints(
            [target.databaseEnv.pgEndpoint],
            settings: target.databaseEnv.pgPoolSettings,
          ),
          enableMigrations: false,
        ).interceptWith(recorder),
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

    Future<void> room(
      String id, {
      required String owner,
      required List<String> participants,
      int kind = _kindRequest,
    }) async {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, status, is_discoverable, published_at)
VALUES (@id, @owner, CASE WHEN @kind = 1 THEN '' ELSE 'Room' END, '', @kind, 0,
  @kind = 0, now())
'''),
        parameters: {'id': id, 'owner': owner, 'kind': kind},
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

    Future<void> message(String roomId, String author, DateTime at) =>
        writer.execute(
          Sql.named('''
INSERT INTO public.beacon_room_message (beacon_id, author_id, body, created_at)
VALUES (@room, @author, 'hello', @at)
'''),
          parameters: {'room': roomId, 'author': author, 'at': at},
        );

    Future<void> forward(
      String roomId, {
      required String from,
      required String to,
      required DateTime at,
    }) => writer.execute(
      Sql.named('''
INSERT INTO public.beacon_forward_edge
  (beacon_id, sender_id, recipient_id, created_at)
VALUES (@room, @from, @to, @at)
'''),
      parameters: {'room': roomId, 'from': from, 'to': to, 'at': at},
    );

    /// Runs the query as the viewer and returns the rows by person id.
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
      final byId = {for (final row in rows) row['id']! as String: row};
      expect(byId, hasLength(rows.length), reason: 'one row per person');
      return byId;
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

    /// A long-standing relationship: viewer's trust edge a month old and
    /// unchanged since, so it contributes neither "new" nor an interaction
    /// newer than the one a test adds.
    Future<void> oldTrust(String person) => trust(
      _viewer,
      person,
      created: ago(const Duration(days: 30)),
    );

    // ---- who is listed --------------------------------------------------

    test('lists exactly the people the viewer trusts', () async {
      await oldTrust(_peer);
      // _other trusts the viewer but the viewer does not trust them back.
      await trust(_other, _viewer, created: ago(const Duration(days: 1)));

      final rows = await peopleList();

      expect(rows.keys, [_peer]);
    });

    // ---- newSince / newReason ------------------------------------------

    group('new relationship', () {
      test('joined through the viewer\'s invite 2 days ago is "invite" since '
          'the acceptance time', () async {
        final accepted = ago(const Duration(days: 2));
        await trust(_viewer, _peer, created: ago(const Duration(days: 5)));
        await invite(inviter: _viewer, invited: _peer, acceptedAt: accepted);

        final row = await peerRow();

        expect(row['newReason'], 'invite');
        expect(instant(row['newSince']), accepted);
      });

      test(
        'an invite someone else sent does not make the person new',
        () async {
          await trust(_viewer, _peer, created: ago(const Duration(days: 30)));
          await invite(
            inviter: _other,
            invited: _peer,
            acceptedAt: ago(const Duration(days: 1)),
          );

          final row = await peerRow();

          expect(row['newSince'], isNull);
          expect(row['newReason'], isNull);
        },
      );

      test('trusted by the viewer 3 days ago is "trusted" since the edge '
          'was created, not since it was last updated', () async {
        final created = ago(const Duration(days: 3));
        await trust(
          _viewer,
          _peer,
          created: created,
          updated: ago(const Duration(hours: 5)),
        );

        final row = await peerRow();

        expect(row['newReason'], 'trusted');
        expect(instant(row['newSince']), created);
      });

      test('trust that became mutual yesterday is "mutual" since the later '
          'of the two edges', () async {
        final becameMutual = ago(const Duration(days: 1));
        await trust(_viewer, _peer, created: ago(const Duration(days: 4)));
        await trust(_peer, _viewer, created: becameMutual);

        final row = await peerRow();

        expect(row['newReason'], 'mutual');
        expect(instant(row['newSince']), becameMutual);
      });

      test('the viewer trusting last makes mutual trust start then', () async {
        final becameMutual = ago(const Duration(hours: 20));
        await trust(_peer, _viewer, created: ago(const Duration(days: 4)));
        await trust(_viewer, _peer, created: becameMutual);

        final row = await peerRow();

        expect(row['newReason'], 'mutual');
        expect(instant(row['newSince']), becameMutual);
      });

      test('old mutual trust is not new', () async {
        await trust(_viewer, _peer, created: ago(const Duration(days: 30)));
        await trust(_peer, _viewer, created: ago(const Duration(days: 20)));

        final row = await peerRow();

        expect(row['newSince'], isNull);
        expect(row['newReason'], isNull);
      });

      test('the latest of invite, trust and mutual wins: an invite newer '
          'than the trust edge', () async {
        final accepted = ago(const Duration(days: 1));
        await trust(_viewer, _peer, created: ago(const Duration(days: 4)));
        await invite(inviter: _viewer, invited: _peer, acceptedAt: accepted);

        final row = await peerRow();

        expect(row['newReason'], 'invite');
        expect(instant(row['newSince']), accepted);
      });

      test('the latest of invite, trust and mutual wins: a trust edge newer '
          'than the invite', () async {
        final trusted = ago(const Duration(days: 1));
        await invite(
          inviter: _viewer,
          invited: _peer,
          acceptedAt: ago(const Duration(days: 4)),
        );
        await trust(_viewer, _peer, created: trusted);

        final row = await peerRow();

        expect(row['newReason'], 'trusted');
        expect(instant(row['newSince']), trusted);
      });

      test('the latest of invite, trust and mutual wins: mutual trust newer '
          "than the invite and the viewer's edge", () async {
        final becameMutual = ago(const Duration(hours: 6));
        await invite(
          inviter: _viewer,
          invited: _peer,
          acceptedAt: ago(const Duration(days: 5)),
        );
        await trust(_viewer, _peer, created: ago(const Duration(days: 3)));
        await trust(_peer, _viewer, created: becameMutual);

        final row = await peerRow();

        expect(row['newReason'], 'mutual');
        expect(instant(row['newSince']), becameMutual);
      });

      test('everything older than 7 days gives no newSince and no '
          'newReason', () async {
        await invite(
          inviter: _viewer,
          invited: _peer,
          acceptedAt: ago(const Duration(days: 9)),
        );
        await trust(_viewer, _peer, created: ago(const Duration(days: 10)));
        await trust(_peer, _viewer, created: ago(const Duration(days: 8)));

        final row = await peerRow();

        expect(row['newSince'], isNull);
        expect(row['newReason'], isNull);
      });

      test('a person who became mutual long ago but whose invite was '
          'accepted 2 days ago is still "invite"', () async {
        final accepted = ago(const Duration(days: 2));
        await trust(_viewer, _peer, created: ago(const Duration(days: 40)));
        await trust(_peer, _viewer, created: ago(const Duration(days: 40)));
        await invite(inviter: _viewer, invited: _peer, acceptedAt: accepted);

        final row = await peerRow();

        expect(row['newReason'], 'invite');
        expect(instant(row['newSince']), accepted);
      });
    });

    // ---- lastInteractionAt ---------------------------------------------

    group('last interaction', () {
      test('is the forward the viewer sent to the person', () async {
        final forwarded = ago(const Duration(days: 2));
        await oldTrust(_peer);
        await room('Bplmforward01', owner: _viewer, participants: [_viewer]);
        await forward(
          'Bplmforward01',
          from: _viewer,
          to: _peer,
          at: forwarded,
        );

        final row = await peerRow();

        expect(instant(row['lastInteractionAt']), forwarded);
      });

      test('is the forward the person sent to the viewer', () async {
        final forwarded = ago(const Duration(days: 2));
        await oldTrust(_peer);
        await room('Bplmforward02', owner: _peer, participants: [_peer]);
        await forward(
          'Bplmforward02',
          from: _peer,
          to: _viewer,
          at: forwarded,
        );

        final row = await peerRow();

        expect(instant(row['lastInteractionAt']), forwarded);
      });

      test('is the latest forward when there are several in both '
          'directions', () async {
        final newest = ago(const Duration(days: 1));
        await oldTrust(_peer);
        // One room per forward: a person forwarding onward in a Request they
        // were forwarded into engages them, which is itself a trust change.
        for (final id in ['Bplmforward03', 'Bplmforward3b', 'Bplmforward3c']) {
          await room(id, owner: _viewer, participants: [_viewer]);
        }
        await forward(
          'Bplmforward03',
          from: _viewer,
          to: _peer,
          at: ago(const Duration(days: 6)),
        );
        await forward(
          'Bplmforward3c',
          from: _peer,
          to: _viewer,
          at: newest,
        );
        await forward(
          'Bplmforward3b',
          from: _viewer,
          to: _peer,
          at: ago(const Duration(days: 3)),
        );

        final row = await peerRow();

        expect(instant(row['lastInteractionAt']), newest);
      });

      test('ignores forwards between the person and somebody else', () async {
        final forwarded = ago(const Duration(days: 4));
        await oldTrust(_peer);
        for (final id in ['Bplmforward04', 'Bplmforward4b']) {
          await room(id, owner: _viewer, participants: [_viewer]);
        }
        await forward(
          'Bplmforward04',
          from: _viewer,
          to: _peer,
          at: forwarded,
        );
        await forward(
          'Bplmforward4b',
          from: _peer,
          to: _other,
          at: ago(const Duration(hours: 1)),
        );
        await forward(
          'Bplmforward04',
          from: _other,
          to: _viewer,
          at: ago(const Duration(hours: 2)),
        );

        final row = await peerRow();

        expect(instant(row['lastInteractionAt']), forwarded);
      });

      test('is a later message by the person in a Request room the viewer '
          'is in', () async {
        final spoke = ago(const Duration(hours: 3));
        await oldTrust(_peer);
        await room(
          'Bplmroom000001',
          owner: _other,
          participants: [_viewer, _peer],
        );
        await room('Bplmforward05', owner: _viewer, participants: [_viewer]);
        await forward(
          'Bplmforward05',
          from: _viewer,
          to: _peer,
          at: ago(const Duration(days: 2)),
        );
        await message('Bplmroom000001', _peer, spoke);

        final row = await peerRow();

        expect(instant(row['lastInteractionAt']), spoke);
      });

      test('is a later message by the person in a Post room the viewer '
          'is in', () async {
        final spoke = ago(const Duration(hours: 5));
        await oldTrust(_peer);
        await room(
          'Bplmpost000001',
          owner: _other,
          participants: [_viewer, _peer],
          kind: _kindPost,
        );
        await message('Bplmpost000001', _peer, spoke);

        final row = await peerRow();

        expect(instant(row['lastInteractionAt']), spoke);
      });

      test(
        "keeps the forward when the person's room message is older",
        () async {
          final forwarded = ago(const Duration(hours: 4));
          await oldTrust(_peer);
          await room(
            'Bplmroom000002',
            owner: _other,
            participants: [_viewer, _peer],
          );
          await message('Bplmroom000002', _peer, ago(const Duration(days: 3)));
          await room('Bplmforward06', owner: _viewer, participants: [_viewer]);
          await forward(
            'Bplmforward06',
            from: _peer,
            to: _viewer,
            at: forwarded,
          );

          final row = await peerRow();

          expect(instant(row['lastInteractionAt']), forwarded);
        },
      );

      test('does not count a message by the person in a room the viewer is '
          'not in', () async {
        final forwarded = ago(const Duration(days: 3));
        await oldTrust(_peer);
        await room('Bplmforward07', owner: _viewer, participants: [_viewer]);
        await forward(
          'Bplmforward07',
          from: _viewer,
          to: _peer,
          at: forwarded,
        );
        // Newer than the forward, but the viewer is not a participant.
        await room(
          'Bplmroom000003',
          owner: _other,
          participants: [_peer, _stranger],
        );
        await message('Bplmroom000003', _peer, ago(const Duration(minutes: 5)));
        await room(
          'Bplmpost000002',
          owner: _other,
          participants: [_peer],
          kind: _kindPost,
        );
        await message('Bplmpost000002', _peer, ago(const Duration(minutes: 4)));

        final row = await peerRow();

        expect(instant(row['lastInteractionAt']), forwarded);
      });

      test(
        'does not count messages by other people in a shared room',
        () async {
          final forwarded = ago(const Duration(days: 3));
          await oldTrust(_peer);
          await room('Bplmforward08', owner: _viewer, participants: [_viewer]);
          await forward(
            'Bplmforward08',
            from: _viewer,
            to: _peer,
            at: forwarded,
          );
          await room(
            'Bplmroom000004',
            owner: _other,
            participants: [_viewer, _peer, _other],
          );
          await message(
            'Bplmroom000004',
            _viewer,
            ago(const Duration(hours: 1)),
          );
          await message(
            'Bplmroom000004',
            _other,
            ago(const Duration(hours: 2)),
          );

          final row = await peerRow();

          expect(instant(row['lastInteractionAt']), forwarded);
        },
      );

      test('is a trust change between the two, in either direction', () async {
        final changed = ago(const Duration(hours: 8));
        await trust(
          _viewer,
          _peer,
          created: ago(const Duration(days: 30)),
        );
        await trust(
          _peer,
          _viewer,
          created: ago(const Duration(days: 29)),
          updated: changed,
        );

        final row = await peerRow();

        expect(instant(row['lastInteractionAt']), changed);
      });

      test('is the invite acceptance when nothing else is newer', () async {
        final accepted = ago(const Duration(days: 10));
        await trust(_viewer, _peer, created: ago(const Duration(days: 30)));
        await invite(inviter: _viewer, invited: _peer, acceptedAt: accepted);

        final row = await peerRow();

        expect(instant(row['lastInteractionAt']), accepted);
      });
    });

    // ---- one statement for the whole list ------------------------------

    test('reads the whole list, with correct keys for every person, in one '
        'SQL statement', () async {
      final people = [
        for (var i = 0; i < 8; i++) 'Uplmbulk${i.toString().padLeft(7, '0')}',
      ];
      for (final id in people) {
        await addUser(id);
      }
      await room(
        'Bplmbulkroom01',
        owner: _other,
        participants: [_viewer, ...people],
      );
      await room('Bplmbulkfwd001', owner: _viewer, participants: [_viewer]);
      final forwards = <String, DateTime>{};
      for (final (i, id) in people.indexed) {
        await trust(_viewer, id, created: ago(Duration(days: 30 + i)));
        final at = ago(Duration(days: 1 + i));
        forwards[id] = at;
        await forward('Bplmbulkfwd001', from: _viewer, to: id, at: at);
      }
      // Some people are also new, each for a different reason.
      final accepted = ago(const Duration(days: 2));
      await invite(inviter: _viewer, invited: people[0], acceptedAt: accepted);
      final mutual = ago(const Duration(hours: 30));
      await trust(people[1], _viewer, created: mutual);
      // Someone who spoke after the forward, in a room the viewer is in.
      final spoke = ago(const Duration(minutes: 20));
      await message('Bplmbulkroom01', people[2], spoke);

      recorder.reset();
      final rows = await peopleList();
      final statements = recorder.statements;

      expect(rows.keys, unorderedEquals(people));
      expect(instant(rows[people[0]]!['newSince']), accepted);
      expect(rows[people[0]]!['newReason'], 'invite');
      expect(instant(rows[people[1]]!['newSince']), mutual);
      expect(rows[people[1]]!['newReason'], 'mutual');
      expect(rows[people[2]]!['newSince'], isNull);
      expect(instant(rows[people[2]]!['lastInteractionAt']), spoke);
      for (final id in people.skip(3)) {
        expect(instant(rows[id]!['lastInteractionAt']), forwards[id]);
      }
      expect(
        statements,
        hasLength(1),
        reason:
            'the list must be one set-wise statement, not one per person:\n'
            '${statements.join('\n---\n')}',
      );
    });
  });
}

/// Records every statement the server graph issues to Postgres.
class _StatementRecorder extends QueryInterceptor {
  final _statements = <String>[];

  List<String> get statements => List.of(_statements);

  void reset() => _statements.clear();

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    _statements.addAll(statements.statements);
    return super.runBatched(executor, statements);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _statements.add(statement);
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _statements.add(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _statements.add(statement);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _statements.add(statement);
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _statements.add(statement);
    return super.runSelect(executor, statement, args);
  }
}
