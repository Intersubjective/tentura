@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/notification_preference_repository.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

/// Regression: Drift plain [DateTime] binds as bigint against `timestamptz`.
///
/// Covers the bind styles used in Tentura custom SQL:
/// - `Variable(TypedValue(Type.timestampTz, ...))` (beacon countRecent)
/// - ISO-8601 string + `$N::timestamptz` (active mutes)
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasMuteTable(probe)) {
        skipReason = 'notification_beacon_mute table missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late BeaconRepository beaconRepo;
  late NotificationPreferenceRepository prefsRepo;

  const authorId = 'Utsbindauth01';
  const beaconId = 'Btsbindexpiry1';
  const muteBeaconId = 'Btsbindmute01';
  const accountId = 'Utsbindacct01';

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      beaconRepo = BeaconRepository(db);
      prefsRepo = NotificationPreferenceRepository(db);
    });

    tearDownAll(() async {
      await db.close();
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.notification_beacon_mute "
        "WHERE account_id LIKE 'Utsbind%'",
      );
      await db.customStatement(
        "DELETE FROM public.beacon WHERE id LIKE 'Btsbind%'",
      );
      await db.customStatement(
        "DELETE FROM public.\"user\" WHERE id LIKE 'Utsbind%'",
      );
    });
  }

  Future<void> seedUser(String id, int slot) async {
    await db.customStatement(
      r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ($1, $2, $3, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET public_key = EXCLUDED.public_key
''',
      [id, 'tsbind $id', pgTestPublicKey('tsbind', slot)],
    );
  }

  Future<void> seedBeacon(String id, {DateTime? createdAt}) async {
    final created = (createdAt ?? DateTime.utc(2026, 1, 1)).toIso8601String();
    await db.customStatement(
      r'''
INSERT INTO public.beacon (id, user_id, title, description, status, created_at, updated_at)
VALUES ($1, $2, 'tsbind', '', 0, $3::timestamptz, $3::timestamptz)
ON CONFLICT (id) DO UPDATE SET created_at = EXCLUDED.created_at
''',
      [id, authorId, created],
    );
  }

  test(
    'BeaconRepository.countRecentByAuthor binds TypedValue(Type.timestampTz)',
    () async {
      await seedUser(authorId, 1);
      await seedBeacon(
        beaconId,
        createdAt: DateTime.timestamp().subtract(const Duration(hours: 1)),
      );

      final count = await beaconRepo.countRecentByAuthor(
        userId: authorId,
        window: const Duration(days: 1),
      );

      expect(count, greaterThanOrEqualTo(1));
    },
    skip: skipReason,
  );

  test(
    'NotificationPreferenceRepository.getMutedBeaconIds '
    'binds muted_until via ISO + ::timestamptz',
    () async {
      await seedUser(accountId, 2);
      await seedUser(authorId, 1);
      await seedBeacon(muteBeaconId);
      final now = DateTime.timestamp();
      await db.customStatement(
        r'''
INSERT INTO public.notification_beacon_mute (account_id, beacon_id, muted_until)
VALUES ($1, $2, $3::timestamptz)
ON CONFLICT (account_id, beacon_id) DO UPDATE
  SET muted_until = EXCLUDED.muted_until
''',
        [
          accountId,
          muteBeaconId,
          now.add(const Duration(days: 1)).toIso8601String(),
        ],
      );

      final muted = await prefsRepo.getMutedBeaconIds(accountId, now);

      expect(muted, contains(muteBeaconId));
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

Future<bool> _canConnectPostgres() async {
  try {
    final db = TenturaDb(_testEnv());
    await db.customSelect('SELECT 1').get();
    await db.close();
    return true;
  } on Object {
    return false;
  }
}

Future<bool> _hasMuteTable(TenturaDb db) async {
  final row = await db
      .customSelect(
        r'''
SELECT EXISTS (
  SELECT 1 FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'notification_beacon_mute'
) AS ok
''',
      )
      .getSingle();
  return row.read<bool>('ok');
}
