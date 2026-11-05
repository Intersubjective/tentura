@Tags(['pg'])
library;

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';

const _viewer = 'Ufieldedge001';
const _author = 'Ufieldedge002';
const _request = 'Bfieldedge001';

// Coverage: real registered GraphQL mutations and queries, production DI and
// migrated PostgreSQL (the Field read, the hidden-items query and the per-person
// items query all go through the shared visibility predicates). Edge cases of
// the personal Field exclusion: cancelled forwards, a For-you rejection that
// must not be stuck as a hide, and unhiding after read access is lost; and a
// person's Closed tab for a Request stored with the legacy closed status.
// Input device, viewport and locale are n/a (server only).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FIELD_HIDE_EDGE_CASES_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_field_hide_edge_cases',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Postgres unavailable', () {}, skip: unavailable);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late GraphQL schema;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    final pg = target.databaseEnv;
    await configureDependencies(
      Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: pg.pgHost,
        pgPort: pg.pgPort,
        pgDatabase: pg.pgDatabase,
        pgUsername: pg.pgUsername,
        pgPassword: pg.pgPassword,
        publicOrigin: 'http://127.0.0.1:2080',
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
    await writer.execute('TRUNCATE public."user" CASCADE');
    for (final (index, id) in [_viewer, _author].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {
          'id': id,
          'key': pgTestPublicKey('field-hide-edge-cases', index + 1),
        },
      );
    }
    await writer.execute(
      Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@viewer, @author, 1), (@author, @viewer, 1)
'''),
      parameters: {'viewer': _viewer, 'author': _author},
    );
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at, expires_at)
VALUES ('$_request', '$_author', 'Help with the garden', '', 0, 0, true, now(), NULL)
''');
  });

  Future<Map<String, dynamic>> run(
    String document, {
    String as = _viewer,
  }) async =>
      await schema.parseAndExecute(
            document,
            globalVariables: {
              kGlobalInputQueryJwt: JwtEntity(sub: as),
            },
          )
          as Map<String, dynamic>;

  Future<void> change(String operation) async {
    final result = await run(
      'mutation { $operation(targetKind: 0, targetId: "$_request") }',
    );
    expect(
      result[operation],
      isTrue,
      reason: '$operation must acknowledge the viewer action: $result',
    );
  }

  Future<bool> inField() async {
    final payload =
        await QueryConstellationField().constellationField.resolve!(null, {
              kGlobalInputQueryJwt: const JwtEntity(sub: _viewer),
              'showClosed': false,
              'participatedOnly': false,
              'projection': 'FULL',
            })
            as Map<String, dynamic>;
    return (payload['requests'] as List).any(
      (row) => (row as Map)['id'] == _request,
    );
  }

  Future<List<String>> hiddenItemIds() async {
    final result = await run('query { fieldHiddenItems { targetId } }');
    expect(result['fieldHiddenItems'], isA<List<Object?>>());
    return [
      for (final row in result['fieldHiddenItems'] as List)
        (row as Map)['targetId'] as String,
    ];
  }

  Future<Map<String, dynamic>> authorItems(String bucket) async {
    final result = await run(
      'query { personFieldItems(personId: "$_author", bucket: "$bucket") '
      '{ items { id } counts { active closed hidden } } }',
    );
    expect(
      result['personFieldItems'],
      isA<Map<String, dynamic>>(),
      reason: 'personFieldItems must return a page: $result',
    );
    return result['personFieldItems'] as Map<String, dynamic>;
  }

  // The author forwards the Request to the viewer, as the app does.
  Future<void> forwardToViewer() async {
    final result = await run(
      'mutation { beaconForward(id: "$_request", recipientIds: ["$_viewer"], '
      'note: "Please take a look") { deliveredRecipientIds } }',
      as: _author,
    );
    expect(
      (result['beaconForward'] as Map)['deliveredRecipientIds'],
      [_viewer],
      reason: 'the forward must be delivered: $result',
    );
  }

  group('Cancelled forwards after a hide', () {
    test('a forward that was cancelled keeps the Request hidden', () async {
      await change('fieldHide');
      expect(await inField(), isFalse);
      await forwardToViewer();
      // The new forward brings the Request back while it is active...
      expect(await inField(), isTrue);
      final edgeId = await writer.execute('''
SELECT id FROM public.beacon_forward_edge WHERE beacon_id = '$_request'
''');
      final cancelled = await run(
        'mutation { beaconForwardCancel(id: "${edgeId.single.single}") }',
        as: _author,
      );
      expect(cancelled['beaconForwardCancel'], isTrue, reason: '$cancelled');
      // ...and a cancelled forward is no addressed event at all.
      expect(
        await inField(),
        isFalse,
        reason: 'a cancelled forward must not keep undoing the hide',
      );
      expect(await hiddenItemIds(), [_request]);
    });
  });

  group('A For-you rejection is not a Field hide', () {
    // «Can't help» on a For-you item, as the viewer sends it from the app.
    Future<void> reject() async {
      final result = await run(
        'mutation { beaconCantHelp(id: "$_request", message: "Busy this week") }',
      );
      expect(result['beaconCantHelp'], isTrue, reason: '$result');
    }

    test(
      'a rejected Request stays out of the Field without being a hide',
      () async {
        await forwardToViewer();
        expect(await inField(), isTrue, reason: 'fixture: forwarded in');
        await reject();
        expect(await inField(), isFalse);
        expect(await hiddenItemIds(), isEmpty);
        final hidden = await authorItems('hidden');
        expect(hidden['items'] as List, isEmpty);
        expect((hidden['counts'] as Map)['hidden'], 0);
      },
    );

    test(
      'unhiding a Request that was hidden and then rejected empties the Hidden bucket',
      () async {
        await change('fieldHide');
        await forwardToViewer();
        await reject();
        expect(await inField(), isFalse, reason: 'fixture: rejected');
        await change('fieldUnhide');
        final hidden = await authorItems('hidden');
        expect(
          (hidden['items'] as List).map((row) => (row as Map)['id']),
          isNot(contains(_request)),
          reason: 'unhide must not leave the item hidden forever',
        );
        expect((hidden['counts'] as Map)['hidden'], 0);
        expect(await hiddenItemIds(), isNot(contains(_request)));
        // The rejection itself is a separate stance and still applies.
        expect(await inField(), isFalse);
      },
    );
  });

  group('Unhiding after read access is lost', () {
    test('is idempotent and removes the stored hide', () async {
      await change('fieldHide');
      await writer.execute('''
UPDATE public.beacon SET is_discoverable = false WHERE id = '$_request'
''');
      final readable = await writer.execute('''
SELECT public.beacon_can_read_content('$_request', '$_viewer')
''');
      expect(
        readable.single.single,
        isFalse,
        reason: 'fixture lost read access',
      );
      await change('fieldUnhide');
      final stored = await writer.execute('''
SELECT count(*)::int FROM public.field_hidden WHERE viewer_id = '$_viewer'
''');
      expect(stored.single.single, 0);
      // A repeat is still acknowledged and leaves nothing stored.
      await change('fieldUnhide');
      final repeated = await writer.execute('''
SELECT count(*)::int FROM public.field_hidden WHERE viewer_id = '$_viewer'
''');
      expect(repeated.single.single, 0);
      expect(await inField(), isFalse);
    });
  });

  group("A person's Closed tab includes the legacy closed status", () {
    test(
      'a Request stored as status 4 is counted and listed as closed',
      () async {
        // 4 is the pre-migration "pending review" value that BeaconStatus still
        // reads as closed and that the Field already lists when closed Requests
        // are on. The current schema forbids new rows with it, so the check is
        // lifted for this throwaway database to stand in for a legacy row, and
        // restored afterwards.
        await writer.execute(
          'ALTER TABLE public.beacon DROP CONSTRAINT beacon_status_range',
        );
        addTearDown(() async {
          await writer.execute(
            "DELETE FROM public.beacon WHERE id = '$_request'",
          );
          await writer.execute('''
ALTER TABLE public.beacon ADD CONSTRAINT beacon_status_range
  CHECK (status = ANY (ARRAY[0, 1, 2, 3, 5, 6, 7, 8]))
''');
        });
        await writer.execute('''
UPDATE public.beacon SET status = 4 WHERE id = '$_request'
''');
        await writer.execute('''
INSERT INTO public.beacon_participant
  (beacon_id, user_id, role, status, room_access)
VALUES ('$_request', '$_viewer', 6, 0, 3)
''');
        final readable = await writer.execute('''
SELECT public.beacon_can_read_content('$_request', '$_viewer')
''');
        expect(readable.single.single, isTrue, reason: 'fixture: readable');

        final closed = await authorItems('closed');
        expect(
          (closed['items'] as List).map((row) => (row as Map)['id']),
          [_request],
          reason: 'a legacy closed Request belongs to the Closed tab',
        );
        expect((closed['counts'] as Map)['closed'], 1);
        expect((closed['counts'] as Map)['active'], 0);

        final active = await authorItems('active');
        expect(active['items'], isEmpty);
      },
    );
  });
}
