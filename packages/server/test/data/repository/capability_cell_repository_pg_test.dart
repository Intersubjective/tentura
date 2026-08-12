@Tags(['pg'])
library;

import 'dart:async';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/capability_cell_repository.dart';
import 'package:tentura_server/data/repository/witness_window_repository.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/use_case/capability_cell_expiry_sweep_case.dart';
import 'package:tentura_server/env.dart';
import 'package:logging/logging.dart';

const _obs = 'Um0147obs1';
const _sub = 'Um0147sub1';
const _tag = 'transport';
const _hlOut = 365.0 * 86400.0;
const _hlSeed = 90.0 * 86400.0;
const _windowMonths = 24;

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;
  late CapabilityCellRepository repo;
  late WitnessWindowRepository witnessRepo;
  late CapabilityCellExpirySweepCase sweepCase;

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      repo = CapabilityCellRepository(database);
      witnessRepo = WitnessWindowRepository(database);
      sweepCase = CapabilityCellExpirySweepCase(
        repo,
        env: target.databaseEnv,
        logger: Logger('CapabilityCellExpirySweepCaseTest'),
      );
      await _seedUsers(writer);
    });

    tearDown(() async {
      await writer.execute(
        "DELETE FROM public.person_capability_event "
        "WHERE observer_user_id LIKE 'Um0147%'",
      );
      await writer.execute(
        "DELETE FROM public.capability_evidence_edge "
        "WHERE observer_user_id LIKE 'Um0147%'",
      );
      await writer.execute(
        "DELETE FROM public.capability_evidence_generation "
        "WHERE observer_user_id LIKE 'Um0147%'",
      );
      await writer.execute(
        "DELETE FROM public.ego_witness_window "
        "WHERE ego_user_id LIKE 'Um0147%'",
      );
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });
  }

  group('CapabilityCellRepository', () {
    test(
      'fetchCells returns expected eOut eSeed and witness m from real Postgres',
      () async {
        await _insertEvent(writer, id: 'Um0147base', sourceType: 3);
        await _rebuild(writer);

        final rows = await repo.fetchCells(
          subjectIds: [_sub],
          tagSlugs: [_tag],
          admittedWitnesses: [
            const WitnessWeight(
              witnessUserId: _obs,
              m: 0.42,
              admitted: true,
            ),
          ],
        );

        expect(rows.length, 1);
        expect(rows.single.observerUserId, _obs);
        expect(rows.single.subjectUserId, _sub);
        expect(rows.single.tagSlug, _tag);
        expect(rows.single.m, 0.42);
        expect(rows.single.eOut, closeTo(1 / 3, 1e-4));
        expect(rows.single.eSeed, 0);
      },
      skip: skipReason,
    );

    test(
      'generation-stale cell is rebuilt on fetchCells before values are returned',
      () async {
        await _insertEvent(writer, id: 'Um0147stale', sourceType: 3);
        await _rebuild(writer);

        await writer.execute(
          "SELECT public.cap_generation_bump('$_obs', '$_sub', '$_tag')",
        );
        await writer.execute(r'''
UPDATE public.capability_evidence_edge
SET s_out = 999, s_seed = 888, built_from_gen = 0
WHERE observer_user_id = 'Um0147obs1'
  AND subject_user_id = 'Um0147sub1'
  AND tag_slug = 'transport'
''');

        final rows = await repo.fetchCells(
          subjectIds: [_sub],
          tagSlugs: [_tag],
          admittedWitnesses: [
            const WitnessWeight(
              witnessUserId: _obs,
              m: 1,
              admitted: true,
            ),
          ],
        );

        expect(rows.length, 1);
        expect(rows.single.eOut, closeTo(1 / 3, 1e-4));
        expect(rows.single.eSeed, 0);

        final genRow = await writer.execute(r'''
SELECT built_from_gen, generation
FROM public.capability_evidence_edge AS c
LEFT JOIN public.capability_evidence_generation AS g
  ON g.observer_user_id = c.observer_user_id
 AND g.subject_user_id = c.subject_user_id
 AND g.tag_slug = c.tag_slug
WHERE c.observer_user_id = 'Um0147obs1'
  AND c.subject_user_id = 'Um0147sub1'
  AND c.tag_slug = 'transport'
''');
        expect(genRow.single[0], genRow.single[1]);
      },
      skip: skipReason,
    );

    test(
      'rebuildCell deletes a cell whose only ledger row is beyond the window',
      () async {
        await writer.execute('BEGIN');
        await _insertEvent(
          writer,
          id: 'Um0147old',
          sourceType: 3,
          createdAt: '2020-01-01T00:00:00Z',
        );
        await _rebuild(writer);
        await writer.execute('COMMIT');

        final count = await writer.execute(r'''
SELECT count(*)::int
FROM public.capability_evidence_edge
WHERE observer_user_id = 'Um0147obs1'
  AND subject_user_id = 'Um0147sub1'
  AND tag_slug = 'transport'
''');
        expect(count.single.single, 0);
      },
      skip: skipReason,
    );

    test('claim sets lease columns and respects active lease', () async {
      await _insertEvent(writer, id: 'Um0147lease', sourceType: 3);
      await _rebuild(writer);
      await writer.execute(r'''
UPDATE public.capability_evidence_edge
SET next_expiry_at = now() - interval '1 minute'
WHERE observer_user_id = 'Um0147obs1'
  AND subject_user_id = 'Um0147sub1'
  AND tag_slug = 'transport'
''');

      final first = await repo.claimExpiredCells(
        limit: 10,
        leaseOwner: 'owner-a',
      );
      expect(first.length, 1);

      final leaseRow = await writer.execute(r'''
SELECT sweep_lease_owner, sweep_lease_until IS NOT NULL
FROM public.capability_evidence_edge
WHERE observer_user_id = 'Um0147obs1'
  AND subject_user_id = 'Um0147sub1'
  AND tag_slug = 'transport'
''');
      expect(leaseRow.single[0], 'owner-a');
      expect(leaseRow.single[1], isTrue);

      final second = await repo.claimExpiredCells(
        limit: 10,
        leaseOwner: 'owner-b',
      );
      expect(second, isEmpty);

      await writer.execute(r'''
UPDATE public.capability_evidence_edge
SET sweep_lease_until = now() - interval '1 minute'
WHERE observer_user_id = 'Um0147obs1'
  AND subject_user_id = 'Um0147sub1'
  AND tag_slug = 'transport'
''');

      final third = await repo.claimExpiredCells(
        limit: 10,
        leaseOwner: 'owner-c',
      );
      expect(third.length, 1);
    }, skip: skipReason);

    test(
      'two concurrent claimExpiredCells calls do not claim the same row',
      () async {
        await _insertEvent(writer, id: 'Um0147race', sourceType: 3);
        await _rebuild(writer);
        await writer.execute(r'''
UPDATE public.capability_evidence_edge
SET next_expiry_at = now() - interval '1 minute',
    sweep_lease_owner = NULL,
    sweep_lease_until = NULL
WHERE observer_user_id = 'Um0147obs1'
  AND subject_user_id = 'Um0147sub1'
  AND tag_slug = 'transport'
''');

        final dbA = TenturaDb(target.databaseEnv);
        final dbB = TenturaDb(target.databaseEnv);
        final repoA = CapabilityCellRepository(dbA);
        final repoB = CapabilityCellRepository(dbB);

        try {
          final results = await Future.wait([
            repoA.claimExpiredCells(limit: 1, leaseOwner: 'race-a'),
            repoB.claimExpiredCells(limit: 1, leaseOwner: 'race-b'),
          ]);

          final totalClaimed = results[0].length + results[1].length;
          expect(totalClaimed, 1);

          final leaseOwners = await writer.execute(r'''
SELECT sweep_lease_owner
FROM public.capability_evidence_edge
WHERE observer_user_id = 'Um0147obs1'
  AND subject_user_id = 'Um0147sub1'
  AND tag_slug = 'transport'
''');
          final owner = leaseOwners.single.single as String;
          expect(owner, anyOf('race-a', 'race-b'));
        } finally {
          await dbA.close();
          await dbB.close();
        }
      },
      skip: skipReason,
    );
  });

  group('CapabilityCellExpirySweepCase', () {
    test('sweep is idempotent across consecutive runs', () async {
      await _insertEvent(writer, id: 'Um0147sweep', sourceType: 3);
      await _rebuild(writer);
      await writer.execute(r'''
UPDATE public.capability_evidence_edge
SET next_expiry_at = now() - interval '1 minute',
    sweep_lease_owner = NULL,
    sweep_lease_until = NULL
WHERE observer_user_id = 'Um0147obs1'
  AND subject_user_id = 'Um0147sub1'
  AND tag_slug = 'transport'
''');

      final first = await sweepCase.runDue();
      expect(first, 1);

      final second = await sweepCase.runDue();
      expect(second, 0);
    }, skip: skipReason);
  });

  group('GC passes', () {
    test('gcStaleWindows deletes old rows and keeps fresh ones', () async {
      await writer.execute(r'''
INSERT INTO public.ego_witness_window (
  ego_user_id, context, witness_user_id, m, admitted, computed_at, mr_epoch
) VALUES
  ('Um0147ego1', '', 'Um0147obs1', 0.5, true, now() - interval '30 minutes', 0),
  ('Um0147ego1', '', 'Um0147sub1', 0.4, true, now(), 0)
''');

      final deleted = await witnessRepo.gcStaleWindows();
      expect(deleted, 1);

      final remaining = await writer.execute(r'''
SELECT witness_user_id
FROM public.ego_witness_window
WHERE ego_user_id = 'Um0147ego1'
ORDER BY witness_user_id
''');
      expect(remaining.length, 1);
      expect(remaining.single.single, _sub);
    }, skip: skipReason);

    test(
      'gcOrphanGenerations deletes rows with neither ledger nor cell',
      () async {
        await writer.execute(r'''
INSERT INTO public.capability_evidence_generation (
  observer_user_id, subject_user_id, tag_slug, generation
) VALUES ('Um0147obs1', 'Um0147sub1', 'orphan', 3)
''');

        final deleted = await repo.gcOrphanGenerations();
        expect(deleted, 1);

        final count = await writer.execute(r'''
SELECT count(*)::int
FROM public.capability_evidence_generation
WHERE tag_slug = 'orphan'
''');
        expect(count.single.single, 0);
      },
      skip: skipReason,
    );

    test(
      'gcOrphanGenerations keeps generation when ledger or cell exists',
      () async {
        await writer.execute(r'''
INSERT INTO public.capability_evidence_generation (
  observer_user_id, subject_user_id, tag_slug, generation
) VALUES ('Um0147obs1', 'Um0147sub1', 'keep-ledger', 1)
''');
        await _insertEvent(
          writer,
          id: 'Um0147keep',
          sourceType: 3,
          tagSlug: 'keep-ledger',
        );

        await writer.execute(r'''
INSERT INTO public.capability_evidence_generation (
  observer_user_id, subject_user_id, tag_slug, generation
) VALUES ('Um0147obs1', 'Um0147sub1', 'keep-cell', 2)
''');
        await _insertEvent(
          writer,
          id: 'Um0147cell',
          sourceType: 3,
          tagSlug: 'keep-cell',
        );
        await _rebuild(writer, tag: 'keep-cell');

        final deleted = await repo.gcOrphanGenerations(limit: 100);
        expect(deleted, 0);

        final count = await writer.execute(r'''
SELECT count(*)::int
FROM public.capability_evidence_generation
WHERE tag_slug IN ('keep-ledger', 'keep-cell')
''');
        expect(count.single.single, 2);
      },
      skip: skipReason,
    );
  });
}

Future<void> _seedUsers(Connection writer) async {
  await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Um0147obs1', 'Observer', 'pk-obs'),
  ('Um0147sub1', 'Subject', 'pk-sub'),
  ('Um0147ego1', 'Ego', 'pk-ego')
ON CONFLICT DO NOTHING
''');
}

Future<void> _insertEvent(
  Connection writer, {
  required String id,
  required int sourceType,
  String tagSlug = _tag,
  String? createdAt,
}) async {
  final createdClause = createdAt == null
      ? 'DEFAULT'
      : "'$createdAt'::timestamptz";
  await writer.execute(
    '''
INSERT INTO public.person_capability_event (
  id, subject_user_id, observer_user_id, tag_slug, source_type,
  visibility, note, is_negative, created_at
) VALUES (
  '$id', '$_sub', '$_obs', '$tagSlug', $sourceType,
  0, '', false, $createdClause
)
''',
  );
}

Future<void> _rebuild(Connection writer, {String tag = _tag}) async {
  await writer.execute(
    "SELECT public.cap_cell_rebuild("
    "'$_obs', '$_sub', '$tag', $_windowMonths, $_hlOut, $_hlSeed)",
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

class _DisposablePgTarget {
  const _DisposablePgTarget({
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
        Platform.environment['TENTURA_CAPABILITY_CELL_REPO_TEST_DB'] ??
        'tentura_test_capability_cell_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_CAPABILITY_CELL_REPO_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

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
