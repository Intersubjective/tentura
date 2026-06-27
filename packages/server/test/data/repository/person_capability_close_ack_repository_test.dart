@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/person_capability_event_repository.dart';
import 'package:tentura_server/domain/capability/capability_event_source.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

/// Postgres integration — skipped when DB or person_capability_event is unavailable.
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
WHERE beacon_id = 'Bcapacktest1'
  OR id LIKE 'CEcapacktest%'
''',
      );
      await db.customStatement(
        "DELETE FROM public.beacon WHERE id = 'Bcapacktest1'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id IN ('Ucapackobs1', 'Ucapacksub1')''',
      );
    });
  }

  Future<void> seedFixture() async {
    final observerKey = pgTestPublicKey('capack', 1);
    final subjectKey = pgTestPublicKey('capack', 2);
    await db.customStatement(
      r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('Ucapackobs1', 'Observer', $1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ucapacksub1', 'Subject', $2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  public_key = EXCLUDED.public_key
''',
      [observerKey, subjectKey],
    );
    await db.customStatement(
      '''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES ('Bcapacktest1', 'Ucapacksub1', 'Close ack dedup test', '', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
    );
  }

  Future<int> countCloseAckRows() async {
    final rows = await db.customSelect(
      '''
SELECT COUNT(*)::int AS c
FROM public.person_capability_event
WHERE observer_user_id = 'Ucapackobs1'
  AND subject_user_id = 'Ucapacksub1'
  AND beacon_id = 'Bcapacktest1'
  AND source_type = ${CapabilityEventSource.closeAcknowledgement.dbValue}
  AND deleted_at IS NULL
''',
    ).getSingle();
    return rows.read<int>('c');
  }

  test(
    'insertCloseAcknowledgements skips duplicate observer/subject/beacon/slug rows',
    () async {
      await seedFixture();
      const observerId = 'Ucapackobs1';
      const subjectId = 'Ucapacksub1';
      const beaconId = 'Bcapacktest1';

      await repo.insertCloseAcknowledgements(
        observerId: observerId,
        subjectId: subjectId,
        beaconId: beaconId,
        slugs: const ['helpful', 'kind'],
      );
      await repo.insertCloseAcknowledgements(
        observerId: observerId,
        subjectId: subjectId,
        beaconId: beaconId,
        slugs: const ['helpful', 'thoughtful'],
      );

      expect(await countCloseAckRows(), 3);
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
