@Tags(['pg', 'multi-connection', 'repo-files'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    show driftRuntimeOptions;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/pg_wait.dart';

/// Author used by every test in this file. The QA report reproduces on a
/// single existing account, so one author is enough.
const _author = 'Uaa11ce000001';

/// Holds a stable wait until released, so two `beaconCreate` calls for the
/// same draft overlap inside the server: the first INSERT is held by the
/// trigger below while the second one reaches the resolver. With the
/// current `createBeacon` (SELECT-then-INSERT-then-UPDATE) the second call
/// commits its own INSERT and then trips the
/// `beacon_author_client_op_id_key` unique index on the UPDATE — the
/// "Couldn't prepare the draft" the client surfaces from `ensureDraft`.
const _pauseKey = 'request_draft_preparation_pause';

typedef _Outcome = ({
  Map<String, dynamic>? data,
  Object? error,
  StackTrace? stack,
});

Future<_Outcome> _capture(Future<Map<String, dynamic>> operation) async {
  try {
    return (data: await operation, error: null, stack: null);
  } on Object catch (error, stack) {
    return (data: null, error: error, stack: stack);
  }
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_DRAFT_RETRY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_request_draft_retry',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Postgres unavailable', () {}, skip: unavailable);
    return;
  }

  group('Preparing a Request draft for the Recipients step', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late GraphQL schema;
    late String document;

    setUpAll(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      // The exact document the client sends from `ensureDraft` (see
      // packages/client/lib/features/beacon/data/gql/beacon_create.graphql).
      document = File(
        '../client/lib/features/beacon/data/gql/beacon_create.graphql',
      ).readAsStringSync();
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      // The scheduling barrier below holds a stable wait until released.
      // Leave it more room than the shared 30-second observation budget.
      await writer.execute(
        'ALTER DATABASE "${target.databaseName}" SET lock_timeout = \'60s\'',
      );
      await writer.execute(r'''
CREATE FUNCTION public.pause_request_draft_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('request_draft_preparation_pause'));
  RETURN NEW;
END;
$$
''');
      await writer.execute('''
CREATE TRIGGER pause_request_draft_insert
BEFORE INSERT ON public.beacon
FOR EACH ROW EXECUTE FUNCTION public.pause_request_draft_insert()
''');
      final db = target.databaseEnv;
      await configureDependencies(
        Env(
          environment: Environment.dev,
          serverUri: Uri.parse('http://127.0.0.1:2080'),
          publicOrigin: 'http://127.0.0.1:2080',
          publicKey: Env.kJwtPublicKey,
          privateKey: Env.kJwtPrivateKey,
          pgHost: db.pgHost,
          pgPort: db.pgPort,
          pgDatabase: db.pgDatabase,
          pgUsername: db.pgUsername,
          pgPassword: db.pgPassword,
          maxConnectionCount: 4,
          constellationDbMaxConcurrent: 4,
          pgStatementTimeoutMs: 60000,
          workersCount: 1,
          printEnv: false,
          isDebugModeOn: false,
        ),
      );
      await getIt.allReady(ignorePendingAsyncCreation: true);
      schema = graphqlSchema;
    });

    tearDownAll(() async {
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      await writer.execute('TRUNCATE public.beacon, public."user" CASCADE');
      await writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          'VALUES (@id, @name, @key)',
        ),
        parameters: {
          'id': _author,
          'name': 'Alice',
          'key': pgTestPublicKey('request-draft-retry', 1),
        },
      );
    });

    Future<Map<String, dynamic>> create(Map<String, Object?> variables) async =>
        await schema.parseAndExecute(
              document,
              operationName: 'BeaconCreate',
              variableValues: variables,
              globalVariables: {
                kGlobalInputQueryJwt: const JwtEntity(sub: _author),
              },
            )
            as Map<String, dynamic>;

    Future<void> waitForBlockedPreparations(int count) async {
      final clock = Stopwatch()..start();
      while (clock.elapsed < kStableStateWait) {
        final rows = await writer.execute('''
SELECT count(*) FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
  AND wait_event_type = 'Lock'
''');
        if ((rows.single.single! as int) >= count) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      fail('$count draft preparations did not reach the scheduling barrier');
    }

    /// Sends the same draft mutation twice in overlap — the way `ensureDraft`
    /// races with a "Try again" retry that reuses the persisted `clientOpId` —
    /// and returns the one draft id both calls must agree on. Before the fix
    /// the second call raises `duplicate key value violates unique constraint
    /// "beacon_author_client_op_id_key"` instead of returning the draft.
    Future<String> overlappingDrafts(Map<String, Object?> variables) async {
      final pending = <Future<_Outcome>>[];
      late List<_Outcome> outcomes;
      await writer.execute(
        Sql.named('SELECT pg_advisory_lock(hashtext(@key))'),
        parameters: {'key': _pauseKey},
      );
      try {
        // A slow first save lets a retry reach the server before its answer.
        // No failure is injected: both calls use the real resolver and DB.
        pending.add(_capture(create(variables)));
        await waitForBlockedPreparations(1);
        pending.add(_capture(create(variables)));
        // A correct retry may wait on its operation identity before INSERT.
        // Observe its database wait without requiring a particular statement.
        await waitForBlockedPreparations(2);
      } finally {
        await writer.execute(
          Sql.named('SELECT pg_advisory_unlock(hashtext(@key))'),
          parameters: {'key': _pauseKey},
        );
        outcomes = await Future.wait(pending).timeout(kCompletionWait);
      }
      for (final outcome in outcomes) {
        if (outcome.error case final error?) {
          Error.throwWithStackTrace(error, outcome.stack!);
        }
      }
      final ids = [
        for (final outcome in outcomes)
          (outcome.data!['beaconCreate'] as Map)['id'] as String,
      ];
      expect(ids, hasLength(2));
      expect(ids.first, isNotEmpty);
      expect(ids.last, ids.first);
      final count = await writer.execute('SELECT count(*) FROM public.beacon');
      expect(count.single.single, 1);
      return ids.first;
    }

    Map<String, Object?> variables({required String clientOpId}) => {
      'title': 'ValidRequest',
      'description': 'FindSupplies',
      'kind': 0,
      'forwardPolicy': 1,
      'draft': true,
      'isDiscoverable': true,
      'clientOpId': clientOpId,
    };

    // The path the acceptance criteria name, without concurrency: the user
    // saves a draft with title + description, then re-issues the same draft
    // (same persisted clientOpId, the way ensureDraft retries) now carrying a
    // When range and a Transport requirement. The single saved draft must end
    // up with every field. Before the fix the second call short-circuits on
    // the existing client_op_id and returns the draft without the new fields.
    test(
      'a retried draft preparation with the same clientOpId keeps one draft '
      'and persists the When range and the Transport requirement',
      () async {
        const clientOpId = '33333333-3333-4333-8333-333333333333';
        // First save: title + description only, as ensureDraft first runs.
        final firstId = ((await create(
          variables(clientOpId: clientOpId),
        ))['beaconCreate'] as Map<String, dynamic>)['id'] as String;
        expect(firstId, isNotEmpty);

        // Second save: the same draft, now also carrying When and a Transport
        // requirement — the retry ensureDraft reissues with the persisted
        // clientOpId after the user added a date range and a requirement.
        final startAt = DateTime.utc(2026, 12, 1, 9);
        final endAt = DateTime.utc(2026, 12, 1, 18);
        final secondId = ((await create({
          ...variables(clientOpId: clientOpId),
          'startAt': startAt.toIso8601String(),
          'endAt': endAt.toIso8601String(),
          'needs': 'transport',
          'primaryNeedSlug': 'transport',
        }))['beaconCreate'] as Map<String, dynamic>)['id'] as String;
        expect(secondId, firstId);

        final count = await writer.execute(
          Sql.named('SELECT count(*) FROM public.beacon WHERE user_id = @id'),
          parameters: {'id': _author},
        );
        expect(count.single.single, 1);

        final draft = await writer.execute(
          Sql.named(
            'SELECT title, description, status, start_at, end_at, needs, '
            'primary_need_slug FROM public.beacon WHERE id = @id',
          ),
          parameters: {'id': firstId},
        );
        expect(draft.single.toList(), [
          'ValidRequest',
          'FindSupplies',
          3,
          startAt,
          endAt,
          'transport',
          'transport',
        ]);
      },
    );

    test(
      'overlapping preparations of a Request draft with title and description '
      'return one saved draft',
      () async {
        final id = await overlappingDrafts(
          variables(clientOpId: '11111111-1111-4111-8111-111111111111'),
        );
        final rows = await writer.execute(
          Sql.named(
            'SELECT user_id, title, description, kind, status, published_at '
            'FROM public.beacon WHERE id = @id',
          ),
          parameters: {'id': id},
        );
        expect(rows.single.toList(), [
          _author,
          'ValidRequest',
          'FindSupplies',
          0,
          3,
          null,
        ]);
      },
    );

    test(
      'overlapping preparations retain the full When range and the Transport '
      'requirement on one saved draft',
      () async {
        final startAt = DateTime.utc(2026, 12, 1, 9);
        final endAt = DateTime.utc(2026, 12, 1, 18);
        final id = await overlappingDrafts({
          ...variables(clientOpId: '22222222-2222-4222-8222-222222222222'),
          'startAt': startAt.toIso8601String(),
          'endAt': endAt.toIso8601String(),
          'needs': 'transport',
          'primaryNeedSlug': 'transport',
        });
        final rows = await writer.execute(
          Sql.named(
            'SELECT user_id, title, description, kind, status, published_at, '
            'start_at, end_at, needs, primary_need_slug '
            'FROM public.beacon WHERE id = @id',
          ),
          parameters: {'id': id},
        );
        expect(rows.single.toList(), [
          _author,
          'ValidRequest',
          'FindSupplies',
          0,
          3,
          null,
          startAt,
          endAt,
          'transport',
          'transport',
        ]);
      },
    );
  });
}
