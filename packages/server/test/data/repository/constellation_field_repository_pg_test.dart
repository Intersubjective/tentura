@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb db;
  late ConstellationFieldRepository repository;
  late ConstellationFieldCase case_;

  const egoId = 'Ucfviewer001';
  const ctx = '';

  Future<void> insertUser(String id) => db.customStatement(
    '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
  );

  Future<void> reciprocalTrust(String a, String b) async {
    await db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$a', '$b', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
       ('$b', '$a', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');
  }

  Future<void> insertBlock(String blocker, String blocked) => db.customStatement(
    '''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blocker', '$blocked', '$blocked')
ON CONFLICT DO NOTHING
''',
  );

  Future<void> insertBeacon({
    required String id,
    required String authorId,
    int status = 0,
    bool isDiscoverable = true,
    bool published = true,
  }) =>
      db.customStatement('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  '$id', '$authorId', 'title-$id', 'desc', $status, $isDiscoverable,
  ${published ? "'2026-01-01T00:00:00Z'" : 'NULL'},
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO UPDATE SET
  status = EXCLUDED.status,
  is_discoverable = EXCLUDED.is_discoverable,
  published_at = EXCLUDED.published_at
''');

  Future<ConstellationFieldSnapshot> loadField(String viewerId) =>
      case_.load(viewerId: viewerId, context: ctx);

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
      repository = ConstellationFieldRepository(db, _PgProfileLookup(db));
      case_ = ConstellationFieldCase(
        repository,
        env: Env(environment: Environment.test),
        logger: Logger('ConstellationFieldRepositoryPgTest'),
      );
    });

    setUp(() async {
      await db.customStatement('DELETE FROM public.beacon_help_offer');
      await db.customStatement('DELETE FROM public.beacon_forward_edge');
      await db.customStatement('DELETE FROM public.beacon_participant');
      await db.customStatement('DELETE FROM public.beacon');
      await db.customStatement('DELETE FROM public.user_block');
      await db.customStatement('DELETE FROM public.vote_user');
      await db.customStatement('DELETE FROM public."user"');
      await insertUser(egoId);
    });

    tearDownAll(() async {
      await db.close();
      await writer.close();
      await target.drop();
    });
  }

  group('ConstellationFieldRepository', () {
    test('repository ordering is stable under shuffled fixture insert order',
        () async {
      final peerIds = List.generate(
        5,
        (i) => 'Ucfpeer${(4 - i).toString().padLeft(3, '0')}',
      );
      for (final id in peerIds) {
        await insertUser(id);
      }
      for (final id in peerIds.reversed) {
        await reciprocalTrust(egoId, id);
      }

      final graph = await repository.visibleGraphPeerIds(
        viewerId: egoId,
        context: ctx,
        cap: kConstellationPeerCap,
      );
      expect(graph.ids.toList(), peerIds..sort());
    }, skip: skipReason);

    test('D10 and publication filters on discoverable requests', () async {
      const peerId = 'Ucfpeer001';
      await insertUser(peerId);
      await reciprocalTrust(egoId, peerId);

      await insertBeacon(
        id: 'Bopen001',
        authorId: peerId,
        status: 0,
        isDiscoverable: true,
        published: true,
      );
      await insertBeacon(
        id: 'Bhidden001',
        authorId: peerId,
        isDiscoverable: false,
      );
      await insertBeacon(id: 'Bdraft001', authorId: peerId, status: 3);
      await insertBeacon(id: 'Bcancel001', authorId: peerId, status: 1);
      await insertBeacon(
        id: 'Bunpub001',
        authorId: peerId,
        published: false,
      );

      final rows = await repository.discoverableRequests(
        viewerId: egoId,
        context: ctx,
        cap: kConstellationRequestCap,
      );

      expect(rows.map((r) => r.id), ['Bopen001']);
    }, skip: skipReason);

    test('ego own non-discoverable request is always returned', () async {
      await insertBeacon(
        id: 'Bmine001',
        authorId: egoId,
        isDiscoverable: false,
      );

      final rows = await repository.ownRequests(viewerId: egoId);

      expect(rows.single.id, 'Bmine001');
    }, skip: skipReason);

    test('blocked author outside graph prefix — author blocks viewer', () async {
      for (var i = 0; i < kConstellationPeerCap; i++) {
        final id = 'Ucfgraph${i.toString().padLeft(3, '0')}';
        await insertUser(id);
        await reciprocalTrust(egoId, id);
      }
      const overflowPeer = 'Ucfgraph200';
      await insertUser(overflowPeer);
      await reciprocalTrust(egoId, overflowPeer);
      const blockedAuthor = 'Ucfblocked999';
      await insertUser(blockedAuthor);
      await reciprocalTrust(egoId, blockedAuthor);
      await insertBeacon(id: 'Bblocked999', authorId: blockedAuthor);
      await insertBlock(blockedAuthor, egoId);

      final snapshot = await loadField(egoId);

      expect(snapshot.peersCapped, isTrue);
      expect(snapshot.peers.map((p) => p.id), isNot(contains(blockedAuthor)));
      expect(snapshot.requests.map((r) => r.authorId), isNot(contains(blockedAuthor)));
    }, skip: skipReason);

    test('blocked author outside graph prefix — viewer blocks author', () async {
      for (var i = 0; i < kConstellationPeerCap; i++) {
        final id = 'Ucfgraph${i.toString().padLeft(3, '0')}';
        await insertUser(id);
        await reciprocalTrust(egoId, id);
      }
      const overflowPeer = 'Ucfgraph200';
      await insertUser(overflowPeer);
      await reciprocalTrust(egoId, overflowPeer);
      const blockedAuthor = 'Ucfblocked888';
      await insertUser(blockedAuthor);
      await reciprocalTrust(egoId, blockedAuthor);
      await insertBeacon(id: 'Bblocked888', authorId: blockedAuthor);
      await insertBlock(egoId, blockedAuthor);

      final snapshot = await loadField(egoId);

      expect(snapshot.peersCapped, isTrue);
      expect(snapshot.peers.map((p) => p.id), isNot(contains(blockedAuthor)));
      expect(snapshot.requests.map((r) => r.authorId), isNot(contains(blockedAuthor)));
    }, skip: skipReason);

    test('peer overflow keeps graph cap, edges inside graph, authors in peers',
        () async {
      final graphPeerIds = [
        for (var i = 0; i < kConstellationPeerCap + 1; i++)
          'Ucfpeer${i.toString().padLeft(3, '0')}',
      ];
      for (final id in graphPeerIds) {
        await insertUser(id);
        await reciprocalTrust(egoId, id);
      }
      await insertBeacon(
        id: 'Boutside001',
        authorId: graphPeerIds.last,
      );

      final snapshot = await loadField(egoId);

      expect(snapshot.peersCapped, isTrue);
      final graphSet = graphPeerIds.take(kConstellationPeerCap).toSet();
      final edgeAllowed = graphSet.union({egoId});
      expect(snapshot.peers.map((p) => p.id).toSet(), graphSet.union({graphPeerIds.last}));
      expect(snapshot.peers.length, kConstellationPeerCap + 1);
      for (final edge in snapshot.edges) {
        expect(edgeAllowed, contains(edge.src));
        expect(edgeAllowed, contains(edge.dst));
      }
      expect(snapshot.requests.single.authorId, graphPeerIds.last);
    }, skip: skipReason);

    test('ego requests survive peer-request cap', () async {
      const lateEgo = 'Ucfegozzz999';
      await insertUser(lateEgo);
      for (var i = 0; i < kConstellationRequestCap + 1; i++) {
        final peerId = 'Ucfreq${i.toString().padLeft(3, '0')}';
        await insertUser(peerId);
        await reciprocalTrust(lateEgo, peerId);
        await insertBeacon(id: 'Bpeer$i', authorId: peerId);
      }
      await insertBeacon(id: 'Bego999', authorId: lateEgo);

      final snapshot = await loadField(lateEgo);

      expect(snapshot.requestsCapped, isTrue);
      expect(snapshot.requests.any((r) => r.id == 'Bego999'), isTrue);
      expect(snapshot.requests, hasLength(kConstellationRequestCap + 1));
    }, skip: skipReason);

    test('whole-call timing on small ad-hoc fixture', () async {
      for (var i = 0; i < 10; i++) {
        final peerId = 'Ucftiming${i.toString().padLeft(2, '0')}';
        await insertUser(peerId);
        await reciprocalTrust(egoId, peerId);
        await insertBeacon(id: 'Btime$i', authorId: peerId);
      }
      await insertBeacon(id: 'Btimeego', authorId: egoId);

      final sw = Stopwatch()..start();
      await loadField(egoId);
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(5000));
    }, skip: skipReason);
  });
}

final class _DisposablePgTarget {
  _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? 'localhost';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        'tentura_test_cf_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';

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

Future<bool> _canConnect(Env env) async {
  try {
    final conn = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await conn.close();
    return true;
  } on Object {
    return false;
  }
}

/// Avoids GetIt-backed presence mapping in pg tests.
final class _PgProfileLookup implements UserProfileBatchLookup {
  _PgProfileLookup(this._database);

  final TenturaDb _database;

  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(Iterable<String> ids) async {
    final idList = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (idList.isEmpty) {
      return {};
    }
    final users = await _database.managers.users
        .filter((u) => u.id.isIn(idList))
        .get();
    return {
      for (final user in users)
        user.id: UserEntity(id: user.id, displayName: user.displayName),
    };
  }

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async {
    final entities = await userEntitiesByIds(ids);
    return {
      for (final entry in entities.entries)
        entry.key: UserPublicRecord(
          id: entry.value.id,
          displayName: entry.value.displayName,
          description: entry.value.description,
          myVote: null,
          isMutualFriend: reciprocalPeerIds.contains(entry.key),
          subjectExplicitlyTrustsViewer: trustsViewerPeerIds.contains(entry.key),
          scores: const [],
          userAvailability: null,
        ),
    };
  }
}
