@Tags(['pg'])
// Seeds chains per test; under a loaded runner one test can pass 30 s.
@Timeout(Duration(minutes: 2))
library;

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

const _viewer = 'Uchainvadim01';
const _d = 'Uchaind000001';
const _bai = 'Uchainbai0001';
const _low = 'Uchaina000001';
const _high = 'Uchainz000001';
const _middleA = 'Uchainm000001';
const _middleB = 'Uchainn000001';
const _hidden = 'Uchainhidden1';
const _otherViewer = 'Uchainother01';

const _names = {
  _viewer: 'Vadim',
  _d: 'D',
  _bai: 'Bai',
  _low: 'Zoe',
  _high: 'Alice',
  _middleA: 'First middle',
  _middleB: 'Second middle',
  _hidden: 'Hidden person',
  _otherViewer: 'Other viewer',
};

const _document = r'''
query($personId: String!) {
  constellationTrustChain(personId: $personId) { userId displayName }
}
''';

/// Exercises the production V2 query and its real PostgreSQL repositories.
/// Only the symmetric visible-set source is replaced, as in the mutual-trust
/// pg tests; person_visible_peer_ids_tx, trust, blocks and Field presence
/// policies remain real. No MeritRank service is needed.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_TRUST_CHAIN_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_trust_chain',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late GraphQL schema;

  Future<void> trust(
    String subject,
    String object, {
    double targetWeight = 1,
    double publishedWeight = 0,
  }) => writer.execute(
    Sql.named('''
INSERT INTO public.user_trust_edge
  (subject, object, trust_w, wall_d, target_w, prev_sent_weight)
VALUES (@subject, @object, @weight, 0, @weight, @published)
ON CONFLICT (subject, object) DO UPDATE SET
  trust_w = EXCLUDED.trust_w, target_w = EXCLUDED.target_w,
  prev_sent_weight = EXCLUDED.prev_sent_weight
'''),
    parameters: {
      'subject': subject,
      'object': object,
      'weight': targetWeight,
      'published': publishedWeight,
    },
  );

  Future<void> path(List<String> ids) async {
    for (var i = 0; i < ids.length - 1; i++) {
      await trust(ids[i], ids[i + 1]);
    }
  }

  Future<void> block(String blocker, String blocked) => writer.execute(
    Sql.named('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocker)
'''),
    parameters: {'blocker': blocker, 'blocked': blocked},
  );

  Future<void> pin(String personId) async {
    await writer.execute('''
INSERT INTO public.constellation_anchor_cursor (viewer_id, revision)
VALUES ('$_viewer', 0)
ON CONFLICT (viewer_id) DO NOTHING
''');
    await writer.execute(
      Sql.named('''
INSERT INTO public.constellation_anchor
  (id, viewer_id, person_id, x_units, y_units,
   coordinate_space_version, revision, placed_at)
VALUES ('Achainpin001', @viewer, @person, 1, 1, 1, 1, now())
'''),
      parameters: {'viewer': _viewer, 'person': personId},
    );
  }

  Future<void> requestBy(String author) => writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at, created_at, updated_at)
VALUES ('Bchainreq001', @author, 'Shared request', 'Description', 0, 0, true,
        now(), now(), now())
'''),
    parameters: {'author': author},
  );

  Future<List<Map<String, dynamic>>> chain(
    String personId, {
    String viewerId = _viewer,
  }) async {
    final data =
        await schema.parseAndExecute(
              _document,
              variableValues: {'personId': personId},
              globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewerId)},
            )
            as Map<String, dynamic>;
    // A missing query or nullable/error response must not become an empty
    // chain and accidentally pass the negative privacy cases.
    expect(data, contains('constellationTrustChain'));
    expect(data['constellationTrustChain'], isA<List<Object?>>());
    return (data['constellationTrustChain'] as List<Object?>)
        .cast<Map<String, dynamic>>();
  }

  Future<void> expectPath(String personId, List<String> ids) async {
    expect(await chain(personId), [
      for (final id in ids) {'userId': id, 'displayName': _names[id]},
    ]);
  }

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    await writer.execute('''
CREATE TABLE public._trust_chain_visible (
  viewer_id text NOT NULL, peer_id text NOT NULL,
  PRIMARY KEY (viewer_id, peer_id)
)
''');
    await writer.execute('''
ALTER FUNCTION public.person_visible_peers_symmetric(text, text)
RENAME TO _trust_chain_symmetric_impl
''');
    await writer.execute(r'''
CREATE FUNCTION public.person_visible_peers_symmetric(viewer_id text, ctx text)
RETURNS TABLE(peer_id text) LANGUAGE sql STABLE AS $$
  SELECT v.peer_id FROM public._trust_chain_visible v
  WHERE v.viewer_id = $1
$$
''');

    final db = target.databaseEnv;
    await configureDependencies(
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
    await getIt.allReady(ignorePendingAsyncCreation: true);
    schema = graphqlSchema;
  });

  tearDownAll(() async {
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  });

  setUp(() async {
    await writer.execute('TRUNCATE TABLE public."user" CASCADE');
    await writer.execute('TRUNCATE TABLE public._trust_chain_visible');
    await writer.execute('DELETE FROM public.person_visible_set_cache');
    for (final entry in _names.entries) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
        parameters: {
          'id': entry.key,
          'name': entry.value,
          'key': 'pk-${entry.key}',
        },
      );
    }
    for (final id in [_d, _bai, _low, _high, _middleA, _middleB]) {
      await writer.execute(
        Sql.named('''
INSERT INTO public._trust_chain_visible (viewer_id, peer_id)
VALUES (@viewer, @peer)
'''),
        parameters: {'viewer': _viewer, 'peer': id},
      );
    }
  });

  group('constellation trust chain', () {
    test('returns the viewer, visible intermediary and target with names in '
        'traversal order', () async {
      await path([_viewer, _d, _bai]);

      await expectPath(_bai, [_viewer, _d, _bai]);
    });

    test(
      'prefers fewer hops over a path with a lower intermediate id',
      () async {
        await path([_viewer, _low, _bai]);
        await trust(_viewer, _bai);

        await expectPath(_bai, [_viewer, _bai]);
      },
    );

    test('returns an empty list when no positive trust path exists', () async {
      await trust(_viewer, _d);

      await expectPath(_bai, []);
    });

    test('does not traverse trust edges in reverse', () async {
      await path([_bai, _d, _viewer]);

      await expectPath(_bai, []);
    });

    test('accepts positive target weight before it is published', () async {
      await trust(_viewer, _bai, targetWeight: 0.25);

      await expectPath(_bai, [_viewer, _bai]);
    });

    for (final weight in [0.0, -0.5]) {
      test(
        'excludes target weight $weight despite a positive published weight',
        () async {
          await trust(_viewer, _d);
          await trust(_d, _bai, targetWeight: weight, publishedWeight: 1);

          await expectPath(_bai, []);
        },
      );
    }

    test('accepts a chain of exactly four hops', () async {
      await path([_viewer, _d, _low, _high, _bai]);

      await expectPath(_bai, [_viewer, _d, _low, _high, _bai]);
    });

    test(
      'returns an empty list when the shortest chain exceeds four hops',
      () async {
        await path([_viewer, _d, _low, _middleA, _high, _bai]);

        await expectPath(_bai, []);
      },
    );

    test(
      'chooses the lowest id path independently of insertion order and names',
      () async {
        // The lower first hop has the higher last intermediate id and name.
        await path([_viewer, _high, _middleA, _bai]);
        await path([_viewer, _low, _middleB, _bai]);

        await expectPath(_bai, [_viewer, _low, _middleB, _bai]);
        await writer.execute('DELETE FROM public.user_trust_edge');
        await path([_viewer, _low, _middleB, _bai]);
        await path([_viewer, _high, _middleA, _bai]);
        await expectPath(_bai, [_viewer, _low, _middleB, _bai]);
      },
    );

    test('breaks equal length ties after a shared path prefix by id', () async {
      await path([_viewer, _d, _high, _bai]);
      await path([_viewer, _d, _low, _bai]);

      await expectPath(_bai, [_viewer, _d, _low, _bai]);
    });

    test(
      'returns the shortest simple chain when the trust graph has cycles',
      () async {
        await path([_viewer, _d, _low, _bai]);
        await trust(_d, _viewer);
        await trust(_low, _d);

        await expectPath(_bai, [_viewer, _d, _low, _bai]);
      },
    );

    test(
      'starts from the JWT viewer rather than another connected person',
      () async {
        await path([_viewer, _d, _bai]);

        expect(await chain(_bai, viewerId: _otherViewer), isEmpty);
      },
    );
  });

  group('constellation trust chain privacy', () {
    test('never uses an intermediate outside the viewer visible set', () async {
      await path([_viewer, _hidden, _bai]);

      await expectPath(_bai, []);
    });

    test(
      'uses a longer visible path instead of a shorter hidden path',
      () async {
        await path([_viewer, _hidden, _bai]);
        await path([_viewer, _d, _low, _bai]);

        await expectPath(_bai, [_viewer, _d, _low, _bai]);
      },
    );

    test(
      'pinning a hidden intermediate does not make it traversable',
      () async {
        await path([_viewer, _hidden, _bai]);
        await pin(_hidden);

        await expectPath(_bai, []);
      },
    );

    for (final (direction, blocker, blocked) in [
      ('forward', _d, _bai),
      ('reverse', _bai, _d),
    ]) {
      test(
        'a $direction block between consecutive people breaks the path',
        () async {
          await path([_viewer, _d, _bai]);
          await block(blocker, blocked);

          await expectPath(_bai, []);
        },
      );
    }

    for (final (direction, blocker, blocked) in [
      ('outgoing', _viewer, _d),
      ('incoming', _d, _viewer),
    ]) {
      test(
        'an $direction viewer block excludes a nonadjacent intermediate',
        () async {
          await path([_viewer, _low, _d, _bai]);
          await block(blocker, blocked);

          await expectPath(_bai, []);
        },
      );
    }

    for (final (direction, blocker, blocked) in [
      ('outgoing', _viewer, _bai),
      ('incoming', _bai, _viewer),
    ]) {
      test('an $direction viewer block hides the target', () async {
        await path([_viewer, _d, _bai]);
        await block(blocker, blocked);

        await expectPath(_bai, []);
      });
    }

    test(
      'continues along an unblocked alternative to a blocked shorter path',
      () async {
        await path([_viewer, _d, _bai]);
        await path([_viewer, _low, _high, _bai]);
        await block(_bai, _d);

        await expectPath(_bai, [_viewer, _low, _high, _bai]);
      },
    );

    test(
      'hides a target with no Field presence despite a visible trust path',
      () async {
        await path([_viewer, _d, _hidden]);

        await expectPath(_hidden, []);
      },
    );

    test('allows a pinned target outside the visible set', () async {
      await path([_viewer, _d, _hidden]);
      await pin(_hidden);

      await expectPath(_hidden, [_viewer, _d, _hidden]);
    });

    test('allows a temporary forward target outside the visible set', () async {
      await path([_viewer, _d, _hidden]);
      await requestBy(_hidden);
      await writer.execute('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES ('Bchainreq001', '$_hidden', '$_viewer')
''');
      expect(
        (await writer.execute('''
SELECT public.person_temporary_forward_visible('$_viewer', '$_hidden')
''')).single.first,
        isTrue,
      );

      await expectPath(_hidden, [_viewer, _d, _hidden]);
    });

    test('allows a bond target outside the visible set', () async {
      await path([_viewer, _d, _hidden]);
      await requestBy(_viewer);
      await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('Bchainreq001', '$_hidden', 1, 3)
''');
      expect(
        (await writer.execute('''
SELECT peer_id FROM public.person_bond_peers('$_viewer')
''')).map((row) => row.first),
        contains(_hidden),
      );

      await expectPath(_hidden, [_viewer, _d, _hidden]);
    });
  });
}
