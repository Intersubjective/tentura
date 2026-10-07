@Tags(['pg', 'mr'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_AGE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_cfage',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for constellation PG test';

  const egoId = 'Ucfage00001';

  group('ConstellationFieldRepository.readSnapshot when the pool connection '
      'ages out', () {
    late TenturaDb db;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      await target.recreate();
      final base = target.databaseEnv;
      db = TenturaDb(
        Env(
          environment: Environment.test,
          pgHost: base.pgHost,
          pgPort: base.pgPort,
          pgDatabase: base.pgDatabase,
          pgUsername: base.pgUsername,
          pgPassword: base.pgPassword,
          maxConnectionAge: 1,
          printEnv: false,
          isDebugModeOn: false,
        ),
      );
      await db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$egoId', '$egoId', 'pk-$egoId',
        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await db.close();
      await target.drop();
    });

    test(
      'constellation snapshot transaction keeps its session when the connection '
      'age elapses mid-read',
      () async {
        late ({int pid, int startedAtMicros}) afterStall;
        late ({int pid, int startedAtMicros}) beforeStall;
        final repository = ConstellationFieldRepository(
          db,
          _EmptyProfileLookup(),
          snapshotOpenProbe: (probeDb) async {
            Future<({int pid, int startedAtMicros})> sample() async {
              final row = await probeDb
                  .customSelect('SELECT pg_backend_pid() AS pid, (extract(epoch FROM now()) * 1000000)::bigint AS t')
                  .getSingle();
              return (
                pid: row.read<int>('pid'),
                startedAtMicros: row.read<int>('t'),
              );
            }

            beforeStall = await sample();
            await Future<void>.delayed(const Duration(milliseconds: 2500));
            afterStall = await sample();
          },
        );

        await repository.readSnapshot(
          viewerId: egoId,
          context: '',
          params: (
            filters: ConstellationFieldMembershipFilters.defaults,
            projection: ConstellationProjection.full,
          ),
        );

        expect(afterStall.pid, beforeStall.pid);
        expect(afterStall.startedAtMicros, beforeStall.startedAtMicros);
      },
      skip: skipReason,
    );
  });
}

final class _EmptyProfileLookup implements UserProfileBatchLookup {
  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(Iterable<String> ids) async =>
      {};

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async => {};
}
