@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show Request;
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/mappers/constellation_gql_maps.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts.dart' show kContextJwtKey;
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/env.dart' show Env;

import '../../../support/disposable_pg_target.dart';
import '../../../support/session_database_di_harness.dart';

const _owner = 'Uhintowner001';
const _other = 'Uhintother001';
const _anna = 'Uhintperson01';
const _boris = 'Uhintperson02';
const _mira = 'Uhintperson03';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_LINK_HINTS_TEST_DB',
    defaultNamePrefix: 'tentura_test_field_link_hints',
  );
  final skip = await pgSkipReason(target);

  group('Field first sightings and same-name link suggestions', () {
    late Connection writer;
    late GraphqlController controller;

    setUpAll(() async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });
      final session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      addTearDown(() async {
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
      });

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
        maxConnectionCount: 1,
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
      );
      await configureSessionDatabaseTestGraph(env);
      controller = GraphqlController(env);
    });

    Future<void> addUser(String id, String name) => writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
      parameters: {'id': id, 'name': name, 'key': 'pk-$id'},
    );

    Future<void> addPeer(String id, String name) async {
      await addUser(id, name);
      await writer.execute(
        Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@owner, @id, 1), (@id, @owner, 1)
'''),
        parameters: {'owner': _owner, 'id': id},
      );
    }

    setUp(() async {
      await writer.execute(
        'TRUNCATE public."user", public.person_visible_set_cache CASCADE',
      );
      await addUser(_owner, 'Field owner');
      await addUser(_other, 'Other account');
    });

    Future<Map<String, Object?>> post(
      String operation, {
      String viewer = _owner,
      Map<String, Object?> variables = const {},
    }) async {
      final response = await controller.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v2/graphql'),
          headers: {'content-type': 'application/json'},
          context: {kContextJwtKey: JwtEntity(sub: viewer)},
          body: jsonEncode({'query': operation, 'variables': variables}),
        ),
      );
      expect(response.statusCode, 200);
      return jsonDecode(await response.readAsString()) as Map<String, Object?>;
    }

    Future<String> create(String name) async {
      final response = await post(
        r'mutation($name: String!) { phantomCreate(name: $name) }',
        variables: {'name': name},
      );
      expect(response['errors'], isNull, reason: jsonEncode(response));
      final data = response['data']! as Map<String, Object?>;
      final id = data['phantomCreate'];
      expect(id, matches(RegExp(r'^PH[0-9a-f]{12}$')));
      return id! as String;
    }

    Future<ConstellationFieldSnapshot> field() =>
        getIt<ConstellationFieldCase>().load(
          viewerId: _owner,
          context: kConstellationContext,
        );

    ConstellationPeerRecord peerIn(
      ConstellationFieldSnapshot snapshot,
      String peerId,
    ) {
      final matches = snapshot.peers.where((peer) => peer.id == peerId);
      expect(matches, hasLength(1), reason: '$peerId should be on the Field');
      return matches.single;
    }

    Future<bool?> pendingMarker() async {
      final rows = await writer.execute(
        Sql.named('''
SELECT backfill_pending FROM public.person_field_first_seen_init
WHERE viewer_id = @owner
'''),
        parameters: {'owner': _owner},
      );
      return rows.singleOrNull?.single as bool?;
    }

    Future<void> setPendingMarker({required bool pending}) => writer.execute(
      Sql.named('''
INSERT INTO public.person_field_first_seen_init (viewer_id, backfill_pending)
VALUES (@owner, @pending)
'''),
      parameters: {'owner': _owner, 'pending': pending},
    );

    Future<String> createAfterInitialization(String name) async {
      await setPendingMarker(pending: false);
      return create(name);
    }

    Future<Map<String, String>> firstSeenRows() async {
      final rows = await writer.execute(
        Sql.named('''
SELECT peer_id, first_seen_at::text
FROM public.person_field_first_seen WHERE viewer_id = @owner
'''),
        parameters: {'owner': _owner},
      );
      return {for (final row in rows) row[0]! as String: row[1]! as String};
    }

    Future<void> recordAtCreation(
      String peerId,
      String phantomId, {
      int microsecondsLater = 1,
    }) => writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
INSERT INTO public.person_field_first_seen (viewer_id, peer_id, first_seen_at)
SELECT @owner, @peer, created_at + @elapsed::int * interval '1 microsecond'
FROM public.phantom WHERE id = @phantom
'''),
      parameters: {
        'owner': _owner,
        'peer': peerId,
        'phantom': phantomId,
        'elapsed': microsecondsLater,
      },
    );

    // The response assertion needs only suggestion pairs, independently of the
    // full list of entries for people not on Tentura yet.
    void expectHints(
      ConstellationFieldSnapshot snapshot,
      Map<String, String> pairs,
    ) {
      expect(
        constellationFieldToGqlMap(snapshot)['linkHints'] ?? const <Object>[],
        unorderedEquals([
          for (final pair in pairs.entries)
            {'phantomId': pair.key, 'userId': pair.value},
        ]),
        reason:
            'The Field response should identify exactly the suggested pairs.',
      );
    }

    Future<String> addHintControl() async {
      final id = await create('Mira');
      await addPeer(_mira, 'Mira Jones');
      await recordAtCreation(_mira, id);
      return id;
    }

    Future<void> setContactName(String peerId, String name) async {
      final response = await post(
        r'mutation($id: String!, $name: String!) { '
        r'contactSet(subjectUserId: $id, contactName: $name) }',
        variables: {'id': peerId, 'name': name},
      );
      expect(response, {
        'data': {'contactSet': true},
      });
    }

    Future<Result> dismissals(String phantomId) => writer.execute(
      Sql.named('''
SELECT user_id FROM public.phantom_link_hint_dismissal WHERE phantom_id = @id
'''),
      parameters: {'id': phantomId},
    );

    test(
      'an empty Field read clears backfill so a later match can be suggested',
      () async {
        final anna = await create('Anna K.');
        expect(await pendingMarker(), isTrue);

        expect((await field()).peers, isEmpty);
        expect(await firstSeenRows(), isEmpty);
        expect(await pendingMarker(), isFalse);

        await addPeer(_anna, 'Anna Smith');
        final snapshot = await field();
        expect(peerIn(snapshot, _anna).isNew, isTrue);
        expectHints(snapshot, {anna: _anna});
      },
    );

    test(
      'a completed marker gives unseen peers a new tag on their first read',
      () async {
        await setPendingMarker(pending: false);
        await addPeer(_anna, 'Anna Smith');
        await addPeer(_boris, 'Boris Petrov');
        expect(await firstSeenRows(), isEmpty);

        final snapshot = await field();
        final rows = await firstSeenRows();
        expect(rows.keys, unorderedEquals([_anna, _boris]));
        for (final id in [_anna, _boris]) {
          final peer = peerIn(snapshot, id);
          expect(
            DateTime.tryParse(rows[id]!),
            isNotNull,
            reason: 'Stored first sighting for $id must be finite',
          );
          expect(peer.firstSeenAt, snapshot.loadedAt, reason: id);
          expect(peer.isNew, isTrue, reason: id);
        }
      },
    );

    test(
      'the first populated Field read backfills and creates a completed marker',
      () async {
        await addPeer(_anna, 'Anna Smith');
        await addPeer(_boris, 'Boris Petrov');
        expect(await pendingMarker(), isNull);
        expect(await firstSeenRows(), isEmpty);

        final snapshot = await field();

        for (final id in [_anna, _boris]) {
          final peer = peerIn(snapshot, id);
          expect(peer.firstSeenAt, isNull, reason: id);
          expect(peer.isNew, isFalse, reason: id);
        }
        expect(await firstSeenRows(), {
          _anna: '-infinity',
          _boris: '-infinity',
        });
        expect(await pendingMarker(), isFalse);
      },
    );

    test('initial backfill includes peers omitted by the Field cap', () async {
      await setPendingMarker(pending: true);
      // Supply a deterministic, over-cap MeritRank visibility set in this
      // disposable database. The Field read and its writes use real PostgreSQL.
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
SELECT id, 'Field peer', 'pk-' || id
FROM (
  SELECT 'Uhintcap' || lpad(n::text, 5, '0') AS id
  FROM generate_series(1, @count::int) AS n
) peers
'''),
        parameters: {'count': kConstellationPeerCap + 1},
      );
      await writer.execute('''
ALTER FUNCTION public.person_visible_peers_symmetric(text, text)
RENAME TO link_hint_test_original_visibility
''');
      addTearDown(() async {
        await writer.execute(
          'DROP FUNCTION public.person_visible_peers_symmetric(text, text)',
        );
        await writer.execute('''
ALTER FUNCTION public.link_hint_test_original_visibility(text, text)
RENAME TO person_visible_peers_symmetric
''');
      });
      await writer.execute(r'''
CREATE FUNCTION public.person_visible_peers_symmetric(viewer_id text, ctx text)
RETURNS TABLE(peer_id text) LANGUAGE sql STABLE AS $$
  SELECT id FROM public."user" WHERE starts_with(id, 'Uhintcap')
$$
''');

      final snapshot = await field();
      final shown = snapshot.peers.map((peer) => peer.id).toSet();
      final population = {
        for (var i = 1; i <= kConstellationPeerCap + 1; i++)
          'Uhintcap${i.toString().padLeft(5, '0')}',
      };
      expect(snapshot.peersCapped, isTrue);
      expect(shown, hasLength(kConstellationPeerCap));
      final omitted = population.difference(shown);
      expect(omitted, hasLength(1));
      final stored = await firstSeenRows();
      expect(
        stored[omitted.single],
        '-infinity',
        reason: 'Backfill should include the capped-out peer.',
      );
      expect(stored.keys.toSet(), population);
      expect(stored.values.toSet(), {'-infinity'});
    });

    test(
      'a peer arriving before initial backfill is never suggested',
      () async {
        await create('Anna K.');
        await addPeer(_anna, 'Anna Smith');
        expect(await pendingMarker(), isTrue);

        final initial = await field();
        expect(peerIn(initial, _anna).isNew, isFalse);
        expect(await firstSeenRows(), {_anna: '-infinity'});
        expectHints(initial, {});

        final mira = await addHintControl();
        final next = await field();
        peerIn(next, _anna);
        peerIn(next, _mira);
        expectHints(next, {mira: _mira});
        expect(await firstSeenRows(), containsPair(_anna, '-infinity'));
        expect(await pendingMarker(), isFalse);
      },
    );

    test(
      'a peer already on the Field before the add is never suggested',
      () async {
        await addPeer(_anna, 'Anna Smith');
        await setPendingMarker(pending: false);
        await writer.executeWithOwnerScopes(
          [_owner],
          Sql.named('''
INSERT INTO public.person_field_first_seen (viewer_id, peer_id, first_seen_at)
VALUES (@owner, @peer, statement_timestamp())
'''),
          parameters: {'owner': _owner, 'peer': _anna},
        );
        expect(peerIn(await field(), _anna).firstSeenAt, isNotNull);
        await create('Anna K.');

        final mira = await addHintControl();
        final snapshot = await field();
        peerIn(snapshot, _anna);
        peerIn(snapshot, _mira);
        expectHints(snapshot, {mira: _mira});
      },
    );

    test(
      'case differences and later words do not prevent a first-name match',
      () async {
        final anna = await createAfterInitialization('Anna K.');
        await addPeer(_anna, 'ANNA Smith');
        await recordAtCreation(_anna, anna);
        await setContactName(_anna, 'Different name');

        final snapshot = await field();
        expect(peerIn(snapshot, _anna).displayName, 'ANNA Smith');
        expectHints(snapshot, {anna: _anna});
      },
    );

    test(
      'the owner’s private contact name can supply the first-name match',
      () async {
        final boris = await createAfterInitialization('Boris');
        await addPeer(_boris, 'Bob');
        await recordAtCreation(_boris, boris);
        await setContactName(_boris, 'boris petrov');

        final snapshot = await field();
        peerIn(snapshot, _boris);
        expectHints(snapshot, {boris: _boris});
      },
    );

    for (final (description, savedName, peerName) in [
      (
        'one-character first names do not produce a suggestion',
        'A K.',
        'A Smith',
      ),
      (
        'a shared prefix is insufficient when the first names differ',
        'Anna',
        'Annabel',
      ),
    ]) {
      test(description, () async {
        final candidate = await createAfterInitialization(savedName);
        await addPeer(_anna, peerName);
        await recordAtCreation(_anna, candidate);
        final mira = await addHintControl();

        final snapshot = await field();
        peerIn(snapshot, _anna);
        expectHints(snapshot, {mira: _mira});
      });
    }

    test('a matching peer must be first seen strictly after the add', () async {
      final anna = await createAfterInitialization('Anna K.');
      await addPeer(_anna, 'Anna Smith');
      await recordAtCreation(_anna, anna, microsecondsLater: 0);
      final mira = await addHintControl();

      final snapshot = await field();
      peerIn(snapshot, _anna);
      expectHints(snapshot, {mira: _mira});
    });

    test('a merged entry is never suggested for a matching newcomer', () async {
      final anna = await createAfterInitialization('Anna K.');
      await writer.executeWithOwnerScopes(
        [_owner],
        Sql.named('UPDATE public.phantom SET merged_at = now() WHERE id = @id'),
        parameters: {'id': anna},
      );
      await addPeer(_anna, 'Anna Smith');
      await recordAtCreation(_anna, anna);
      final mira = await addHintControl();

      final snapshot = await field();
      peerIn(snapshot, _anna);
      expectHints(snapshot, {mira: _mira});
    });

    test(
      'a matching account outside the owner’s Field is never suggested',
      () async {
        final anna = await createAfterInitialization('Anna K.');
        await addUser(_anna, 'Anna Smith');
        await recordAtCreation(_anna, anna);
        final mira = await addHintControl();

        final snapshot = await field();
        expect(snapshot.peers.map((peer) => peer.id), isNot(contains(_anna)));
        expectHints(snapshot, {mira: _mira});
      },
    );

    test(
      'a matching newcomer is suggested on the read that first shows them',
      () async {
        final anna = await createAfterInitialization('Anna K.');
        await addPeer(_anna, 'Anna Smith');
        expect(await firstSeenRows(), isEmpty);

        final snapshot = await field();

        peerIn(snapshot, _anna);
        expectHints(snapshot, {anna: _anna});
      },
    );

    test(
      'dismissing one match leaves another match for the same entry eligible',
      () async {
        final anna = await createAfterInitialization('Anna K.');
        await addPeer(_anna, 'Anna Smith');
        await recordAtCreation(_anna, anna);
        final mira = await addHintControl();
        await writer.executeWithOwnerScopes(
          [_owner],
          Sql.named('''
INSERT INTO public.phantom_link_hint_dismissal (phantom_id, user_id)
VALUES (@phantom, @peer)
'''),
          parameters: {'phantom': anna, 'peer': _anna},
        );
        final afterDismissal = await field();
        peerIn(afterDismissal, _anna);
        expectHints(afterDismissal, {mira: _mira});

        await addPeer(_boris, 'Anna Jones');
        await recordAtCreation(_boris, anna);
        final later = await field();
        peerIn(later, _anna);
        peerIn(later, _boris);
        expectHints(later, {anna: _boris, mira: _mira});
      },
    );

    test(
      'only the owner can dismiss a pair and repeated dismissal is idempotent',
      () async {
        final anna = await createAfterInitialization('Anna K.');
        await addPeer(_anna, 'Anna Smith');
        await recordAtCreation(_anna, anna);
        final operation =
            '''
mutation { phantomHintDismiss(phantomId: "$anna", userId: "$_anna") }
''';

        await post(operation, viewer: _other);
        expect(await dismissals(anna), isEmpty);

        for (var attempt = 0; attempt < 2; attempt++) {
          final response = await post(operation);
          expect(response['errors'], isNull, reason: jsonEncode(response));
          expect((await dismissals(anna)).map((row) => row.single), [_anna]);
        }
      },
    );
  }, skip: skip);
}
