@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 3))
library;

// Public API contract: beaconInvolvements(ids) returns keyed beaconId rows;
// unreadable and nonexistent ids are OMITTED (never empty involvement rows).
// Single-Request callers retain beaconInvolvement(id) and its existing shape.
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart' as pg;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/http/request_context_io_adapter.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _author = 'Uinbatchauthor';
const _dave = 'Uinbatchdave01';
const _other = 'Uinbatchother1';
const _hidden = 'Binbatchhidden';
const _missing = 'Binbatchmissing';
String _id(int i) => 'Binbatch${i.toString().padLeft(5, '0')}';

const _fields = '''
  forwardedToIds helpOfferedIds withdrawnIds declinedOfferIds
  rejectedIds watchingIds onwardForwarderIds
  myForwardedRecipients {
    edgeId recipientId note readAt hasOnwardChild recipientRejected
  }
''';
const _single =
    '''
query SingleInvolvement(\$id: String!) {
  beaconInvolvement(id: \$id) { $_fields }
}
''';
const _batch =
    '''
query BatchInvolvements(\$ids: [String!]!) {
  beaconInvolvements(ids: \$ids) { beaconId $_fields }
}
''';

final class _ReadCounter extends QueryInterceptor {
  int selects = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    return executor.runSelect(statement, args);
  }
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_INVOLVEMENTS_BATCH_TEST_DB',
    defaultNamePrefix: 'tentura_test_involvements_batch',
  );
  final unavailable = await pgSkipReason(target);
  // Required baseline runs must never silently pass because PG was skipped.
  if (unavailable != null) {
    test('involvement batch requires reachable Postgres', () {
      fail(unavailable);
    });
    return;
  }

  group('Batched involvement for Forward to person', () {
    late DisposablePgWriterSession session;
    late Handler graphql;
    final counter = _ReadCounter();
    var leases = 0;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      await _seed(session.writer);
      final db = target.databaseEnv;
      final env = Env(
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
        // Existing single reads fan out internally; allow them to establish
        // the parity oracle without admission noise.
        maxConnectionCount: 8,
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
      );
      getIt
        ..skipDoubleRegistration = true
        ..registerFactory<TenturaDb>(
          () => TenturaDb.scoped(
            getIt<MainDbPool>(),
            // TenturaDb calls this hook once inside each admitted
            // connection lease, independently of the number of SELECTs.
            scopeInterceptor: () {
              leases++;
              return counter;
            },
          ),
        );
      await configureSessionDatabaseTestGraph(env);
      final controller = GraphqlController(env);
      graphql = requestContextIoAdapter(
        (request) => controller.handler(
          request.change(
            context: {kContextJwtKey: const JwtEntity(sub: _author)},
          ),
        ),
      );
    });

    tearDownAll(() async {
      getIt.skipDoubleRegistration = false;
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    Future<Map<String, dynamic>> post(
      String query,
      String operation,
      Map<String, Object?> variables,
    ) async {
      final response = await graphql(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v2/graphql'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'query': query,
            'operationName': operation,
            'variables': variables,
          }),
        ),
      );
      expect(response.statusCode, 200);
      return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    }

    Future<Map<String, dynamic>> single(String id) async {
      final body = await post(_single, 'SingleInvolvement', {'id': id});
      expect(body['errors'], isNull, reason: jsonEncode(body));
      return (body['data'] as Map<String, dynamic>)['beaconInvolvement']
          as Map<String, dynamic>;
    }

    Future<List<Map<String, dynamic>>> batch(List<String> ids) async {
      final body = await post(_batch, 'BatchInvolvements', {'ids': ids});
      expect(
        body['errors'],
        isNull,
        reason:
            'the screen needs a successful batched involvement read: ${jsonEncode(body)}',
      );
      final data = body['data'] as Map<String, dynamic>;
      expect(
        data,
        containsPair('beaconInvolvements', isA<List<Object?>>()),
        reason:
            'the batch query must return involvement rows, not an absent field',
      );
      return (data['beaconInvolvements'] as List).cast<Map<String, dynamic>>();
    }

    test(
      'one batch matches single reads for sent, helping, rejected, author-declined and unseen Requests while omitting unreadable ids',
      () async {
        final readable = [for (var i = 0; i < 5; i++) _id(i)];
        final expected = <String, Map<String, dynamic>>{};
        for (final id in readable) {
          expected[id] = await single(id);
        }
        // Positive fixture assertions prevent parity from passing on empty data.
        expect(expected[_id(0)]!['forwardedToIds'], contains(_dave));
        expect(
          (expected[_id(0)]!['myForwardedRecipients'] as List).single,
          containsPair('recipientId', _dave),
        );
        expect(expected[_id(1)]!['helpOfferedIds'], contains(_dave));
        expect(expected[_id(2)]!['rejectedIds'], contains(_dave));
        expect(expected[_id(4)]!['declinedOfferIds'], contains(_dave));
        expect(expected[_id(4)]!['rejectedIds'], isNot(contains(_dave)));
        expect(expected[_id(4)]!['withdrawnIds'], isNot(contains(_dave)));
        expect(expected[_id(4)]!['helpOfferedIds'], isNot(contains(_dave)));
        expect(expected[_id(3)]!['forwardedToIds'], isEmpty);
        expect(expected[_id(3)]!['helpOfferedIds'], isEmpty);
        for (final id in [_hidden, _missing]) {
          final denied = await post(_single, 'SingleInvolvement', {'id': id});
          expect(
            denied['errors'],
            isNotEmpty,
            reason: 'single read must confirm the fixture is inaccessible',
          );
        }

        final rows = await batch([_hidden, ...readable.reversed, _missing]);
        expect(rows.map((r) => r['beaconId']), unorderedEquals(readable));
        final declinedOffer = rows.singleWhere((r) => r['beaconId'] == _id(4));
        expect(declinedOffer['declinedOfferIds'], contains(_dave));
        expect(declinedOffer['rejectedIds'], isNot(contains(_dave)));
        expect(declinedOffer['withdrawnIds'], isNot(contains(_dave)));
        expect(declinedOffer['helpOfferedIds'], isNot(contains(_dave)));
        for (final row in rows) {
          final id = row['beaconId']! as String;
          final involvement = Map<String, dynamic>.of(row)..remove('beaconId');
          expect(
            involvement,
            expected[id],
            reason: 'single/batch parity for $id',
          );
        }
      },
    );

    test(
      'one admitted database round and constant SQL reads serve one, eleven and fifty Requests',
      () async {
        final reads = <int>[];
        // These assertions are independent of parity: N single-query calls
        // fail either the one-lease check or the constant-read check, even
        // if their merged involvement happens to be exactly correct.
        for (final size in [1, 11, 50]) {
          leases = 0;
          counter.selects = 0;
          final ids = [for (var i = 0; i < size; i++) _id(i)];
          final rows = await batch(ids);
          expect(rows.map((r) => r['beaconId']), unorderedEquals(ids));
          expect(
            leases,
            1,
            reason:
                '$size Requests must share one admission slot and connection scope',
          );
          reads.add(counter.selects);
        }
        expect(reads.first, greaterThan(0));
        expect(
          reads,
          everyElement(reads.first),
          reason: 'SQL reads must stay set-based as the screen grows: $reads',
        );
      },
    );

    test(
      'fifty ids are accepted and fifty one are rejected before any database read',
      () async {
        final ids = [for (var i = 0; i < 50; i++) _id(i)];
        expect(await batch(ids), hasLength(50));
        leases = 0;
        counter.selects = 0;
        final denied = await post(_batch, 'BatchInvolvements', {
          'ids': [...ids, _id(50)],
        });
        expect(denied['errors'], isNotEmpty);
        expect((denied['data'] as Map?)?['beaconInvolvements'], isNull);
        expect(leases, 0, reason: 'reject oversize input before admission');
        expect(counter.selects, 0);
      },
    );
  });
}

Future<void> _seed(pg.Connection writer) async {
  for (final (i, id) in [_author, _dave, _other].indexed) {
    await writer.execute(
      pg.Sql.named('''
      INSERT INTO public."user" (id, display_name, public_key)
      VALUES (@id, @id, @key)
    '''),
      parameters: {'id': id, 'key': pgTestPublicKey('inbatch', i + 1)},
    );
  }
  await writer.execute('''
    INSERT INTO public.beacon (id, user_id, title, description, status)
    SELECT 'Binbatch' || lpad(n::text, 5, '0'), '$_author',
           'Request ' || n, 'Batch involvement fixture', 0
    FROM generate_series(0, 50) n
  ''');
  await writer.execute('''
    INSERT INTO public.beacon (id, user_id, title, description, status, is_discoverable)
    VALUES ('$_hidden', '$_other', 'Private draft', '', 0, false)
  ''');
  await writer.execute('''
    INSERT INTO public.beacon_forward_edge
      (id, beacon_id, sender_id, recipient_id)
    VALUES ('Finbatchsent01', '${_id(0)}', '$_author', '$_dave')
  ''');
  await writer.execute('''
    INSERT INTO public.beacon_help_offer (beacon_id, user_id, status)
    VALUES ('${_id(1)}', '$_dave', 0),
           ('${_id(4)}', '$_dave', 1)
  ''');
  await writer.execute('''
    INSERT INTO public.beacon_help_offer_admission_event
      (id, beacon_id, offer_user_id, actor_user_id, action, reason)
    VALUES ('HAinbatchdecline', '${_id(4)}', '$_dave', '$_author', 2, 'Not a fit')
  ''');
  await writer.execute('''
    INSERT INTO public.inbox_item (user_id, beacon_id, status)
    VALUES ('$_dave', '${_id(2)}', 2)
  ''');
}
