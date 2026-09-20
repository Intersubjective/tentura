@Tags(['pg', 'mr'])
library;

import 'dart:io';
import 'dart:math';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/env.dart';

/// Live Postgres proof of m0161 symmetric mutual visibility (D14).
Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb db;

  const viewerId = 'Upvsymviewer1';
  const peerAId = 'Upvsympeera1';
  const reciprocalId = 'Upvsymrecip1';
  const oneWayId = 'Upvsymoneway1';

  final propertyPeers = List.generate(
    12,
    (i) => 'Upvsymprop${i.toString().padLeft(2, '0')}',
  );

  final allUserIds = [
    viewerId,
    peerAId,
    reciprocalId,
    oneWayId,
    ...propertyPeers,
  ];

  Future<void> insertUser(String id) => db.customStatement(
    '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
  );

  Future<void> trustEdge(String subject, String object) => db.customStatement(
    '''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$subject', '$object', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''',
  );

  Future<void> mrEdge(String subject, String object) => db.customStatement(
    "SELECT mr_put_edge('$subject', '$object', 0.75::double precision, ''::text, 0)",
  );

  Future<void> clearMrEdge(String subject, String object) => db.customStatement(
    "SELECT mr_put_edge('$subject', '$object', 0::double precision, ''::text, 0)",
  );

  Future<bool> personIsMutuallyVisible(
    String aId,
    String bId, {
    String ctx = '',
  }) async {
    final row = await db
        .customSelect(
          r'''
SELECT public.person_is_mutually_visible($1, $2, $3) AS mutual
''',
          variables: [
            Variable<String>(aId),
            Variable<String>(bId),
            Variable<String>(ctx),
          ],
        )
        .getSingle();
    return row.read<bool>('mutual');
  }

  Future<bool> personAreMutuallyVisible(
    String aId,
    String bId, {
    String ctx = '',
  }) async {
    final row = await db
        .customSelect(
          r'''
SELECT public.person_are_mutually_visible($1, $2, $3) AS mutual
''',
          variables: [
            Variable<String>(aId),
            Variable<String>(bId),
            Variable<String>(ctx),
          ],
        )
        .getSingle();
    return row.read<bool>('mutual');
  }

  Future<Set<String>> symmetricPeerIds(String viewer, {String ctx = ''}) async {
    final rows = await db
        .customSelect(
          r'''
SELECT peer_id
FROM public.person_visible_peers_symmetric($1, $2)
''',
          variables: [
            Variable<String>(viewer),
            Variable<String>(ctx),
          ],
        )
        .get();
    return {for (final row in rows) row.read<String>('peer_id')};
  }

  Future<Set<String>> candidatePeerIds(String viewer, {String ctx = ''}) async {
    final rows = await db
        .customSelect(
          r'''
SELECT peer_id::text AS peer_id
FROM public.person_visibility_peers($1, $2)
WHERE peer_id::text <> $1
''',
          variables: [
            Variable<String>(viewer),
            Variable<String>(ctx),
          ],
        )
        .get();
    return {for (final row in rows) row.read<String>('peer_id')};
  }

  Future<void> cleanup() async {
    final idList = allUserIds.map((id) => "'$id'").join(', ');
    await db.customStatement(
      'DELETE FROM public.vote_user WHERE subject IN ($idList) OR object IN ($idList)',
    );
    for (final peerId in allUserIds) {
      if (peerId == viewerId) continue;
      await clearMrEdge(viewerId, peerId);
      await clearMrEdge(peerId, viewerId);
    }
    await db.customStatement(
      '''DELETE FROM public."user" WHERE id IN ($idList)''',
    );
  }

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      await migrateDbSchema(writer);
      db = TenturaDb(target.databaseEnv);
    });

    setUp(() async {
      await cleanup();
      for (final id in allUserIds) {
        await insertUser(id);
      }
    });

    tearDownAll(() async {
      await db.close();
      await writer.close();
      await target.drop();
    });
  }

  test(
    'explicit V→A plus MR A→V documents old asymmetry; symmetric wrapper repairs',
    () async {
      await trustEdge(viewerId, peerAId);
      await mrEdge(peerAId, viewerId);

      final forward = await personIsMutuallyVisible(viewerId, peerAId);
      final reverse = await personIsMutuallyVisible(peerAId, viewerId);
      expect(forward, isNot(equals(reverse)));
      expect(forward, isFalse);
      expect(reverse, isTrue);

      expect(await personAreMutuallyVisible(viewerId, peerAId), isTrue);
      expect(await personAreMutuallyVisible(peerAId, viewerId), isTrue);
    },
    skip: skipReason,
  );

  test(
    'reciprocal explicit trust is symmetric without any MR row',
    () async {
      await trustEdge(viewerId, reciprocalId);
      await trustEdge(reciprocalId, viewerId);

      expect(await personAreMutuallyVisible(viewerId, reciprocalId), isTrue);
      expect(await personAreMutuallyVisible(reciprocalId, viewerId), isTrue);
    },
    skip: skipReason,
  );

  test(
    'person_visible_peers_symmetric matches symmetric predicate on candidates',
    () async {
      await trustEdge(viewerId, peerAId);
      await mrEdge(peerAId, viewerId);
      await trustEdge(viewerId, reciprocalId);
      await trustEdge(reciprocalId, viewerId);
      await trustEdge(viewerId, oneWayId);

      final candidates = await candidatePeerIds(viewerId);
      final expected = <String>{
        for (final peerId in candidates)
          if (await personAreMutuallyVisible(viewerId, peerId)) peerId,
      };

      expect(await symmetricPeerIds(viewerId), expected);
      expect(expected, contains(peerAId));
      expect(expected, contains(reciprocalId));
      expect(expected, isNot(contains(oneWayId)));
      expect(expected, isNot(contains(viewerId)));
    },
    skip: skipReason,
  );

  test('person_visible_peers_symmetric is empty for blank viewer', () async {
    await trustEdge(viewerId, reciprocalId);
    await trustEdge(reciprocalId, viewerId);

    expect(await symmetricPeerIds(''), isEmpty);
    expect(await symmetricPeerIds('   '), isEmpty);
  }, skip: skipReason);

  test(
    'one-directional explicit trust without MR is false in both orders',
    () async {
      await trustEdge(viewerId, oneWayId);

      expect(await personAreMutuallyVisible(viewerId, oneWayId), isFalse);
      expect(await personAreMutuallyVisible(oneWayId, viewerId), isFalse);
    },
    skip: skipReason,
  );

  test('self and empty ids are false for person_are_mutually_visible', () async {
    expect(await personAreMutuallyVisible(viewerId, viewerId), isFalse);
    expect(await personAreMutuallyVisible('', peerAId), isFalse);
    expect(await personAreMutuallyVisible(peerAId, ''), isFalse);
    expect(await personAreMutuallyVisible('   ', peerAId), isFalse);
    expect(await personAreMutuallyVisible(peerAId, '   '), isFalse);

    final nullA = await db
        .customSelect(
          r"SELECT public.person_are_mutually_visible(NULL, $1, '') AS mutual",
          variables: [Variable<String>(peerAId)],
        )
        .getSingle();
    final nullB = await db
        .customSelect(
          r"SELECT public.person_are_mutually_visible($1, NULL, '') AS mutual",
          variables: [Variable<String>(peerAId)],
        )
        .getSingle();
    expect(nullA.read<bool>('mutual'), isFalse);
    expect(nullB.read<bool>('mutual'), isFalse);
  }, skip: skipReason);

  test(
    'person_are_mutually_visible is symmetric for 200 random ordered pairs',
    () async {
      final rng = Random(42);
      for (var i = 0; i < propertyPeers.length; i++) {
        final peerId = propertyPeers[i];
        if (i.isEven) {
          await trustEdge(viewerId, peerId);
        }
        if (i % 3 == 0) {
          await trustEdge(peerId, viewerId);
        }
        if (i % 5 == 0) {
          await mrEdge(viewerId, peerId);
        }
        if (i % 7 == 0) {
          await mrEdge(peerId, viewerId);
        }
      }

      final ids = [viewerId, ...propertyPeers];
      for (var i = 0; i < 200; i++) {
        final a = ids[rng.nextInt(ids.length)];
        final b = ids[rng.nextInt(ids.length)];
        final ab = await personAreMutuallyVisible(a, b);
        final ba = await personAreMutuallyVisible(b, a);
        expect(ab, ba, reason: 'pair ($a, $b) must be symmetric');
      }
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

final class _DisposablePgTarget {
  _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_PERSON_VISIBILITY_SYM_TEST_DB'] ??
        'tentura_test_person_visibility_sym_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );
    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}
