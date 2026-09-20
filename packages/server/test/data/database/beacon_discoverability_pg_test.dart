@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/beacon_lifecycle_effects_test_support.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/noop_commitment_query_case.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/test_attention_harness.dart';

Future<void> main() async {
  final target = BeaconHierarchyDisposablePgTarget.fromEnvironment(
    databaseNameOverride:
        'tentura_test_disc_${DateTime.timestamp().microsecondsSinceEpoch}',
  );
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for discoverability PG test';

  group('beacon.is_discoverable — disposable Postgres', () {
    late Connection writer;
    late TenturaDb database;
    late BeaconRepository beaconRepo;
    late BeaconCase beaconCase;

    const authorId = 'Udiscov00001';
    const forkSourceUserId = 'Udiscov00002';

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      beaconRepo = BeaconRepository(database);

      await _seedUser(writer, authorId, slot: 1);
      await _seedUser(writer, forkSourceUserId, slot: 2);

      final attention = TestAttentionHarness();
      beaconCase = BeaconCase(
        beaconRepo,
        _NoopImageRepo(),
        _NoopImageObjectGc(),
        _NoopTaskRepo(),
        noopCommitmentQueryCase(),
        FakeBeaconAccessGuard(),
        FakeBeaconHierarchyRepository(),
        FakeBeaconChildCreatePort(),
        buildLifecycleEffectsCase(),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: Env(environment: Environment.test),
        logger: Logger('BeaconDiscoverabilityPgTest'),
      );
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await database.close();
      await writer.close();
      await target.drop();
    });

    Future<bool> readDiscoverable(String beaconId) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT is_discoverable FROM public.beacon WHERE id = @id',
        ),
        parameters: {'id': beaconId},
      );
      return rows.single.first! as bool;
    }

    test('m0160 adds is_discoverable column and partial index', () async {
      final column = await writer.execute(
        r'''
SELECT column_name, column_default, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'beacon'
  AND column_name = 'is_discoverable'
''',
      );
      expect(column, hasLength(1));
      expect(column.single[1], contains('true'));
      expect(column.single[2], 'NO');

      final index = await writer.execute(
        r'''
SELECT indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'beacon'
  AND indexname = 'beacon_discoverable_author_idx'
''',
      );
      expect(index, hasLength(1));
    }, skip: skipReason);

    test('insert without explicit value defaults to true', () async {
      const beaconId = 'Bdiscdef001';
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon
  (id, user_id, title, description, status, created_at, updated_at)
VALUES (@id, @user, 't', 'd', 0, now(), now())
'''),
        parameters: {'id': beaconId, 'user': authorId},
      );
      expect(await readDiscoverable(beaconId), isTrue);
    }, skip: skipReason);


    test('create and update round-trip true and false', () async {
      final created = await beaconRepo.createBeacon(
        authorId: authorId,
        title: 'Discoverable request',
        description: 'Enough description text here.',
      );
      expect(await readDiscoverable(created.id), isTrue);
      expect(created.isDiscoverable, isTrue);

      final hidden = await beaconRepo.createBeacon(
        authorId: authorId,
        title: 'Hidden request',
        description: 'Enough description text here.',
        isDiscoverable: false,
      );
      expect(await readDiscoverable(hidden.id), isFalse);
      expect(hidden.isDiscoverable, isFalse);

      final updatedVisible = await beaconRepo.updateBeacon(
        beaconId: hidden.id,
        userId: authorId,
        title: 'Now visible',
        description: 'Enough description text here.',
        isDiscoverable: true,
        isDiscoverableProvided: true,
      );
      expect(await readDiscoverable(hidden.id), isTrue);
      expect(updatedVisible.isDiscoverable, isTrue);

      final updatedHidden = await beaconRepo.updateBeacon(
        beaconId: created.id,
        userId: authorId,
        title: 'Now hidden',
        description: 'Enough description text here.',
        isDiscoverable: false,
        isDiscoverableProvided: true,
      );
      expect(await readDiscoverable(created.id), isFalse);
      expect(updatedHidden.isDiscoverable, isFalse);

      final unchanged = await beaconRepo.updateBeacon(
        beaconId: created.id,
        userId: authorId,
        title: 'Still hidden',
        description: 'Enough description text here.',
      );
      expect(await readDiscoverable(created.id), isFalse);
      expect(unchanged.isDiscoverable, isFalse);
    }, skip: skipReason);

    test('child beacon create uses column default true', () async {
      const parentId = 'Bdiscpar001';
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon
  (id, user_id, title, description, status, created_at, updated_at, published_at)
VALUES (@id, @user, 'parent', 'd', 0, now(), now(), now())
'''),
        parameters: {'id': parentId, 'user': authorId},
      );

      final child = await beaconRepo.createChildBeacon(
        authorId: authorId,
        parentBeaconId: parentId,
        title: 'Nested child',
        description: 'Child description text.',
        draft: false,
      );
      expect(await readDiscoverable(child.id), isTrue);
      expect(child.isDiscoverable, isTrue);
    }, skip: skipReason);

    test('beaconFork copies source is_discoverable', () async {
      final source = await beaconRepo.createBeacon(
        authorId: forkSourceUserId,
        title: 'Fork source hidden',
        description: 'Enough description text here.',
        isDiscoverable: false,
      );

      final forked = await beaconCase.fork(
        sourceId: source.id,
        userId: authorId,
      );

      expect(await readDiscoverable(forked.id), isFalse);
      expect(forked.isDiscoverable, isFalse);
    }, skip: skipReason);
  });
}

Future<bool> _readDiscoverableOn(Connection connection, String beaconId) async {
  final rows = await connection.execute(
    Sql.named(
      'SELECT is_discoverable FROM public.beacon WHERE id = @id',
    ),
    parameters: {'id': beaconId},
  );
  return rows.single.first! as bool;
}

Future<void> _seedUser(
  Connection writer,
  String userId, {
  required int slot,
}) => writer.execute(
  Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @key, now(), now())
ON CONFLICT (id) DO NOTHING
'''),
  parameters: {'id': userId, 'key': pgTestPublicKey('discov', slot)},
);

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on SocketException {
    return false;
  } on ServerException {
    return false;
  }
}

class _NoopImageRepo extends Fake implements ImageRepositoryPort {}

class _NoopImageObjectGc extends Fake implements ImageObjectGcPort {}

class _NoopTaskRepo extends Fake implements TaskRepositoryPort {}
