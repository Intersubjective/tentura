@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/domain/capability/capability_event_source.dart';
import 'package:tentura_server/domain/port/person_capability_event_repository_port.dart';
import 'package:tentura_server/env.dart';

/// Postgres integration — fetchDeduplicatedCapabilities source-type and dedup SQL.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final env = _testEnv();
    final probe = TenturaDb(env);
    try {
      if (!await _hasPersonCapabilityEventTable(probe)) {
        skipReason = 'person_capability_event table missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late PersonCapabilityEventRepository repo;

  const viewerId = 'Ucapdedview1';
  const subjectId = 'Ucapdedsub1';
  const otherId = 'Ucapdedoth1';
  const beaconId = 'Bcapdedtest1';

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      repo = PersonCapabilityEventRepository(db);
    });

    tearDownAll(() async {
      await db.close();
    });

    tearDown(() async {
      await db.customStatement(
        '''
DELETE FROM public.person_capability_event
WHERE beacon_id = '$beaconId'
  OR id LIKE 'CEcapdedtest%'
''',
      );
      await db.customStatement(
        "DELETE FROM public.beacon WHERE id = '$beaconId'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id IN ('$viewerId', '$subjectId', '$otherId')''',
      );
    });
  }

  Future<void> seedFixture() async {
    final viewerKey = '${'e' * 43}1';
    final subjectKey = '${'f' * 43}2';
    final otherKey = '${'g' * 43}3';
    await db.customStatement(
      '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('$viewerId', 'Viewer', \$1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$subjectId', 'Subject', \$2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$otherId', 'Other', \$3, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  public_key = EXCLUDED.public_key
''',
      [viewerKey, subjectKey, otherKey],
    );
    await db.customStatement(
      '''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES ('$beaconId', '$subjectId', 'Dedup fetch test', '', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
    );
  }

  Future<List<ViewerVisibleCapabilityRow>> fetch({
    required String viewer,
    required String subject,
  }) => repo.fetchDeduplicatedCapabilities(
    viewerId: viewer,
    subjectId: subject,
  );

  test(
    'returns empty when viewer has no capability signals for subject',
    () async {
      await seedFixture();
      expect(await fetch(viewer: viewerId, subject: subjectId), isEmpty);
    },
    skip: skipReason,
  );

  test(
    'includes private labels (source 0) with hasManualLabel true',
    () async {
      await seedFixture();
      await repo.upsertPrivateLabels(
        observerId: viewerId,
        subjectId: subjectId,
        slugs: const ['helpful'],
      );

      final rows = await fetch(viewer: viewerId, subject: subjectId);

      expect(rows, [
        isA<ViewerVisibleCapabilityRow>()
            .having((r) => r.slug, 'slug', 'helpful')
            .having((r) => r.hasManualLabel, 'hasManualLabel', isTrue),
      ]);
    },
    skip: skipReason,
  );

  test(
    'includes forward reasons (source 1) with hasManualLabel false',
    () async {
      await seedFixture();
      await repo.insertForwardReasons(
        observerId: viewerId,
        subjectId: subjectId,
        beaconId: beaconId,
        slugs: const ['kind'],
      );

      final rows = await fetch(viewer: viewerId, subject: subjectId);

      expect(rows, [
        isA<ViewerVisibleCapabilityRow>()
            .having((r) => r.slug, 'slug', 'kind')
            .having((r) => r.hasManualLabel, 'hasManualLabel', isFalse),
      ]);
    },
    skip: skipReason,
  );

  test(
    'includes commit roles (source 2) for any viewer observing subject',
    () async {
      await seedFixture();
      await repo.insertCommitRole(
        observerId: otherId,
        subjectId: subjectId,
        beaconId: beaconId,
        slug: 'reliable',
      );

      final rows = await fetch(viewer: viewerId, subject: subjectId);

      expect(rows, [
        isA<ViewerVisibleCapabilityRow>()
            .having((r) => r.slug, 'slug', 'reliable')
            .having((r) => r.hasManualLabel, 'hasManualLabel', isFalse),
      ]);
    },
    skip: skipReason,
  );

  test(
    'includes viewer close-acks (source 3) with hasManualLabel false',
    () async {
      await seedFixture();
      await repo.insertCloseAcknowledgements(
        observerId: viewerId,
        subjectId: subjectId,
        beaconId: beaconId,
        slugs: const ['thoughtful'],
      );

      final rows = await fetch(viewer: viewerId, subject: subjectId);

      expect(rows, [
        isA<ViewerVisibleCapabilityRow>()
            .having((r) => r.slug, 'slug', 'thoughtful')
            .having((r) => r.hasManualLabel, 'hasManualLabel', isFalse),
      ]);
    },
    skip: skipReason,
  );

  test(
    'deduplicates slug across sources and ORs hasManualLabel',
    () async {
      await seedFixture();
      await repo.insertForwardReasons(
        observerId: viewerId,
        subjectId: subjectId,
        beaconId: beaconId,
        slugs: const ['helpful'],
      );
      await repo.upsertPrivateLabels(
        observerId: viewerId,
        subjectId: subjectId,
        slugs: const ['helpful'],
      );

      final rows = await fetch(viewer: viewerId, subject: subjectId);

      expect(rows, hasLength(1));
      expect(rows.single.slug, 'helpful');
      expect(rows.single.hasManualLabel, isTrue);
    },
    skip: skipReason,
  );

  test(
    'excludes tombstoned slugs for the viewer',
    () async {
      await seedFixture();
      await repo.upsertPrivateLabels(
        observerId: viewerId,
        subjectId: subjectId,
        slugs: const ['helpful', 'kind'],
      );
      await repo.insertTombstone(
        observerId: viewerId,
        subjectId: subjectId,
        slug: 'helpful',
      );

      final rows = await fetch(viewer: viewerId, subject: subjectId);

      expect(rows.map((r) => r.slug), ['kind']);
    },
    skip: skipReason,
  );

  test(
    'excludes soft-deleted positive events',
    () async {
      await seedFixture();
      await repo.upsertPrivateLabels(
        observerId: viewerId,
        subjectId: subjectId,
        slugs: const ['helpful'],
      );
      await db.customStatement(
        '''
UPDATE public.person_capability_event
SET deleted_at = now()
WHERE observer_user_id = '$viewerId'
  AND subject_user_id = '$subjectId'
  AND tag_slug = 'helpful'
  AND source_type = ${CapabilityEventSource.privateLabel.dbValue}
''',
      );

      expect(await fetch(viewer: viewerId, subject: subjectId), isEmpty);
    },
    skip: skipReason,
  );

  test(
    'does not include another observer private labels',
    () async {
      await seedFixture();
      await repo.upsertPrivateLabels(
        observerId: otherId,
        subjectId: subjectId,
        slugs: const ['helpful'],
      );

      expect(await fetch(viewer: viewerId, subject: subjectId), isEmpty);
    },
    skip: skipReason,
  );

  test(
    'self-view includes close-acks about subject from any observer',
    () async {
      await seedFixture();
      await repo.insertCloseAcknowledgements(
        observerId: otherId,
        subjectId: subjectId,
        beaconId: beaconId,
        slugs: const ['helpful'],
      );

      final rows = await fetch(viewer: subjectId, subject: subjectId);

      expect(rows, [
        isA<ViewerVisibleCapabilityRow>()
            .having((r) => r.slug, 'slug', 'helpful')
            .having((r) => r.hasManualLabel, 'hasManualLabel', isFalse),
      ]);
    },
    skip: skipReason,
  );

  test(
    'non-self-view excludes close-acks about subject from other observers',
    () async {
      await seedFixture();
      await repo.insertCloseAcknowledgements(
        observerId: otherId,
        subjectId: subjectId,
        beaconId: beaconId,
        slugs: const ['helpful'],
      );

      expect(await fetch(viewer: viewerId, subject: subjectId), isEmpty);
    },
    skip: skipReason,
  );
}

Env _testEnv() => Env(
      environment: Environment.test,
      pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
      pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
      pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
      printEnv: false,
      isDebugModeOn: false,
    );

Future<bool> _hasPersonCapabilityEventTable(TenturaDb db) async {
  final rows = await db.customSelect(
    '''
SELECT 1 FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'person_capability_event'
LIMIT 1
''',
  ).get();
  return rows.isNotEmpty;
}

Future<bool> _canConnectPostgres() async {
  try {
    final db = TenturaDb(_testEnv());
    await db.customSelect('SELECT 1').getSingle();
    await db.close();
    return true;
  } on Object {
    return false;
  }
}
