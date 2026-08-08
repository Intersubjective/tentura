import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/env.dart';

/// Directional `vote_user` batch lookup against live Postgres.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  late TenturaDb db;
  late VoteUserFriendshipLookup lookup;

  const viewerId = 'Uvfviewer01';
  const peerA = 'Uvfpeera001';
  const peerB = 'Uvfpeerb001';
  const peerC = 'Uvfpeerc001';
  const allIds = [viewerId, peerA, peerB, peerC];

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

  Future<void> cleanup() async {
    final idList = allIds.map((id) => "'$id'").join(', ');
    await db.customStatement(
      'DELETE FROM public.vote_user WHERE subject IN ($idList) OR object IN ($idList)',
    );
    await db.customStatement(
      '''DELETE FROM public."user" WHERE id IN ($idList)''',
    );
  }

  if (skipReason == false) {
    setUp(() async {
      db = TenturaDb(_testEnv());
      lookup = VoteUserFriendshipLookup(db);
      await cleanup();
      for (final id in allIds) {
        await insertUser(id);
      }
    });

    tearDown(() async {
      await cleanup();
      await db.close();
    });
  }

  test(
    'directionalPositiveTrustPeerIds returns independent viewer/outgoing sets',
    () async {
      await trustEdge(viewerId, peerA);
      await trustEdge(peerB, viewerId);

      final directional = await lookup.directionalPositiveTrustPeerIds(
        viewerId: viewerId,
        peerIds: [peerA, peerB, peerC],
      );

      expect(directional.viewerTrusts, {peerA});
      expect(directional.trustsViewer, {peerB});
    },
    skip: skipReason,
  );

  test(
    'reciprocalPositivePeerIds is intersection of directional sets',
    () async {
      await trustEdge(viewerId, peerA);
      await trustEdge(peerA, viewerId);
      await trustEdge(viewerId, peerB);

      final reciprocal = await lookup.reciprocalPositivePeerIds(
        viewerId: viewerId,
        peerIds: [peerA, peerB, peerC],
      );

      expect(reciprocal, {peerA});
    },
    skip: skipReason,
  );

  test(
    'isSubscribedTo and isReciprocalSubscribe derive from directional lookup',
    () async {
      await trustEdge(viewerId, peerA);
      await trustEdge(peerA, viewerId);
      await trustEdge(peerB, viewerId);

      expect(
        await lookup.isSubscribedTo(viewerId: viewerId, peerId: peerA),
        isTrue,
      );
      expect(
        await lookup.isSubscribedTo(viewerId: viewerId, peerId: peerB),
        isFalse,
      );
      expect(
        await lookup.isReciprocalSubscribe(viewerId: viewerId, peerId: peerA),
        isTrue,
      );
      expect(
        await lookup.isReciprocalSubscribe(viewerId: viewerId, peerId: peerB),
        isFalse,
      );
    },
    skip: skipReason,
  );

  test('blank viewer yields empty directional result', () async {
    final directional = await lookup.directionalPositiveTrustPeerIds(
      viewerId: '',
      peerIds: [peerA],
    );
    expect(directional.viewerTrusts, isEmpty);
    expect(directional.trustsViewer, isEmpty);
  }, skip: skipReason);
}

Env _testEnv() => Env(
  environment: Environment.test,
  pgHost: Platform.environment['POSTGRES_HOST'] ?? 'localhost',
  pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
  pgDatabase: Platform.environment['POSTGRES_DBNAME'] ?? 'postgres',
  pgUsername: Platform.environment['POSTGRES_USERNAME'] ?? 'postgres',
  pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
  genealogyNodeKeySecret: 'test-genealogy-secret',
);

Future<bool> _canConnectPostgres() async {
  try {
    final db = TenturaDb(_testEnv());
    await db.customSelect('SELECT 1').getSingle();
    await db.close();
    return true;
  } catch (_) {
    return false;
  }
}
