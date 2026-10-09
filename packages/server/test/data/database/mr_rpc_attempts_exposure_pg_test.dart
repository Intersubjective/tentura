@Tags(['pg', 'mr'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart' show Connection;
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:test/test.dart';

import '../../support/constellation_profiles_from_public_records.dart';
import '../../support/disposable_pg_target.dart';

/// `TenturaDb.mrRpcAttempts()` reads the connector's per-backend
/// `mr_rpc_attempts()` counter on the connection the database runs on (inside
/// an open transaction too), so the RPC-count gate of `applyBatch` can take
/// deltas around a transaction without a second, unrelated backend. The last
/// group is that gate's own measurement: the delta around a real `applyBatch`
/// read through this API equals the connector RPCs the backend counted for
/// that batch when asked directly on its connection.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_MR_RPC_ATTEMPTS_EXPOSURE_TEST_DB',
    defaultNamePrefix: 'tentura_test_mr_rpc_exposure',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession fixture;
  late Connection backend;
  late TenturaDb db;

  setUpAll(() async {
    fixture = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    backend = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    db = TenturaDb.forTest(
      database: PgDatabase.opened(backend, enableMigrations: false),
    );
  });

  tearDownAll(() async {
    await db.close();
    if (backend.isOpen) await backend.close();
    await tearDownDisposablePgWriter(session: fixture);
  });

  Future<void> oneConnectorRpc(TenturaDb database) =>
      database.customSelect('SELECT count(*) FROM mr_edgelist()').get();

  group('connector RPC attempts of the database connection', () {
    test('a read without MeritRank calls reports an unchanged count', () async {
      final before = await db.mrRpcAttempts();
      await db.customSelect('SELECT 1').get();
      expect(await db.mrRpcAttempts() - before, 0);
    });

    test(
      'each MeritRank call on the connection adds exactly one attempt',
      () async {
        final before = await db.mrRpcAttempts();
        await oneConnectorRpc(db);
        await oneConnectorRpc(db);
        expect(await db.mrRpcAttempts() - before, 2);
      },
    );

    test('is readable inside a transaction and counts its own RPCs', () async {
      final delta = await db.transaction(() async {
        final before = await db.mrRpcAttempts();
        await oneConnectorRpc(db);
        return await db.mrRpcAttempts() - before;
      });
      expect(delta, 1);
    });

    test('does not move for RPCs made by another connection', () async {
      final before = await db.mrRpcAttempts();
      await fixture.writer.execute('SELECT count(*) FROM mr_edgelist()');
      await fixture.writer.execute('SELECT count(*) FROM mr_edgelist()');
      expect(await db.mrRpcAttempts() - before, 0);
    });
  });

  group('RPC-count gate around applyBatch', () {
    const viewer = 'Urpcgateviewer001';
    const peer = 'Urpcgatepeer00001';
    const params = AnchorApplyParams(
      context: kConstellationContext,
      filters: ConstellationFieldMembershipFilters.defaults,
    );

    setUp(() async {
      final writer = fixture.writer;
      await writer.execute('DELETE FROM public.constellation_anchor_op_log');
      await writer.execute('DELETE FROM public.constellation_anchor');
      await writer.execute(
        'DELETE FROM public.constellation_anchor_target_watermark',
      );
      await writer.execute('DELETE FROM public.constellation_anchor_cursor');
      await writer.execute('DELETE FROM public.user_block');
      await writer.execute('DELETE FROM public.vote_user');
      await writer.execute('DELETE FROM public."user"');
      for (final id in [viewer, peer]) {
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
      }
      await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$viewer', '$peer', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
       ('$peer', '$viewer', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
      await writer.execute('SELECT public.mr_reset()');
      for (final (src, dst) in [(viewer, peer), (peer, viewer)]) {
        await writer.execute('''
SELECT public.mr_put_edge('$src', '$dst', 0.75::double precision, '${params.context}', 0)
''');
      }
      await writer.execute('''
INSERT INTO public.constellation_anchor_cursor (viewer_id) VALUES ('$viewer')
''');
    });

    test(
      'the delta read through the database API around an apply equals the '
      'connector RPCs the backend counted for that batch',
      () async {
        // The independent reading: the same backend's counter asked directly
        // on its connection, outside Drift, before and after the batch.
        Future<int> backendAttempts() async =>
            ((await backend.execute(
                      'SELECT public.mr_rpc_attempts()',
                    )).single.single!
                    as num)
                .toInt();

        final repository = ConstellationAnchorRepository(db, _Profiles(db));
        final apiBefore = await db.mrRpcAttempts();
        final backendBefore = await backendAttempts();
        final result = await repository.applyBatch(
          viewerId: viewer,
          ops: [
            AnchorApplyOp(
              clientOpId: 'pin-for-gate',
              kind: AnchorOpKind.upsert,
              target: ConstellationAnchorTarget.person(peer),
              position: const ConstellationAnchorPosition(
                xUnits: 2,
                yUnits: -3,
                coordinateSpaceVersion: 1,
              ),
              ifRevision: ConstellationAnchorRevision.zero,
            ),
          ],
          params: params,
        );
        final apiDelta = await db.mrRpcAttempts() - apiBefore;
        final backendDelta = await backendAttempts() - backendBefore;

        expect(result.results.single.status, AnchorOpStatus.ok);
        expect(
          backendDelta,
          greaterThanOrEqualTo(1),
          reason: 'An apply on a fresh transaction must reach MeritRank.',
        );
        expect(
          apiDelta,
          backendDelta,
          reason:
              'The gate must see every connector RPC of the batch '
              'through TenturaDb.mrRpcAttempts().',
        );
      },
    );
  });
}

final class _Profiles implements UserProfileBatchLookup {
  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
    Iterable<String> ids,
  ) => constellationProfilesFromRecords(this, ids);

  _Profiles(this.db);

  final TenturaDb db;

  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async {
    final users = await db.managers.users
        .filter((u) => u.id.isIn(ids.toSet()))
        .get();
    return {
      for (final u in users)
        u.id: UserEntity(id: u.id, displayName: u.displayName),
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
    final users = await userEntitiesByIds(ids);
    return {
      for (final u in users.values)
        u.id: UserPublicRecord(
          id: u.id,
          displayName: u.displayName,
          description: u.description,
          isMutualFriend: reciprocalPeerIds.contains(u.id),
          subjectExplicitlyTrustsViewer: trustsViewerPeerIds.contains(u.id),
          userAvailability: null,
        ),
    };
  }
}
