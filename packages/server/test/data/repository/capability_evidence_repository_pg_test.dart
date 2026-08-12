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
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/env.dart';

const _obs1 = 'Ucapb2aobs01';
const _obs2 = 'Ucapb2aobs02';
const _sub = 'Ucapb2asub01';
const _auth = 'Ucapb2aauth1';
const _beaconId = 'Bcapb2abcn01';
const _edgeId = 'Fcapb2aedge1';
const _kOut = 2.0;
final _hlOut = kCapHalfLifeOutSeconds.toDouble();
final _hlSeed = kCapHalfLifeSeedSeconds.toDouble();

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('CapabilityEvidenceRepository', () {
    late Connection writer;
    late TenturaDb database;
    late CapabilityEvidenceRepository repo;
    late MutatingUnitOfWork unitOfWork;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      repo = CapabilityEvidenceRepository(database);
      unitOfWork = MutatingUnitOfWork(database);
    });

    setUp(() async {
      await writer.execute('''
DELETE FROM public.person_capability_event
WHERE observer_user_id LIKE 'Ucapb2a%'
   OR subject_user_id LIKE 'Ucapb2a%'
''');
      await writer.execute('''
DELETE FROM public.capability_evidence_edge
WHERE observer_user_id LIKE 'Ucapb2a%'
   OR subject_user_id LIKE 'Ucapb2a%'
''');
      await writer.execute('''
DELETE FROM public.capability_evidence_generation
WHERE observer_user_id LIKE 'Ucapb2a%'
   OR subject_user_id LIKE 'Ucapb2a%'
''');
      await _seedFixture(writer);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test(
      'reconcileForwardReasons writes ledger, bumps generation, rebuilds seed cell',
      () async {
        await repo.reconcileForwardReasons(
          forwardEdgeId: _edgeId,
          observerId: _obs1,
          subjectId: _sub,
          slugs: const ['transport', 'pets'],
        );

        final ledger = await _activeForwardSlugs(writer);
        expect(ledger, ['pets', 'transport']);

        final generation = await _generation(writer, _obs1, _sub, 'transport');
        expect(generation, 1);

        final cell = await _readCell(writer, _obs1, _sub, 'transport');
        expect(cell.sOut, 0);
        expect(cell.sSeed, closeTo(1.0, 1e-4));
        expect(
          await _effectiveSeedStrength(writer, _obs1, _sub, 'transport'),
          closeTo(0.5, 1e-4),
        );

        await repo.reconcileForwardReasons(
          forwardEdgeId: _edgeId,
          observerId: _obs1,
          subjectId: _sub,
          slugs: const ['pets'],
        );

        final after = await _activeForwardSlugs(writer);
        expect(after, ['pets']);
        expect(
          await _cellExists(writer, _obs1, _sub, 'transport'),
          isFalse,
        );
        expect(
          await _generation(writer, _obs1, _sub, 'transport'),
          2,
        );
      },
      skip: skipReason,
    );

    test(
      'upsertSeedAttestation writes source-4 ledger and rebuilds seed cell',
      () async {
        await repo.upsertSeedAttestation(
          observerId: _obs1,
          subjectId: _sub,
          slugs: const ['manual_labour'],
        );

        final rows = await writer.execute(r'''
SELECT tag_slug, source_type
FROM public.person_capability_event
WHERE observer_user_id = 'Ucapb2aobs01'
  AND subject_user_id = 'Ucapb2asub01'
  AND deleted_at IS NULL
ORDER BY tag_slug
''');
        expect(rows.map((r) => r[0]), ['manual_labour']);
        expect(rows.single[1], 4);

        expect(await _generation(writer, _obs1, _sub, 'manual_labour'), 1);
        expect(
          await _effectiveSeedStrength(
            writer,
            _obs1,
            _sub,
            'manual_labour',
          ),
          closeTo(0.5, 1e-4),
        );
      },
      skip: skipReason,
    );

    test(
      'emitOutcomeEvidenceBatch writes source-3 ledger and rebuilds outcome cell',
      () async {
        await unitOfWork.run(
          actorUserId: _auth,
          action: () => repo.emitOutcomeEvidenceBatch(
            beaconId: _beaconId,
            emissions: const [
              OutcomeEmission(
                observerUserId: _obs1,
                subjectUserId: _sub,
                tagSlug: 'transport',
              ),
            ],
          ),
        );

        final rows = await writer.execute(r'''
SELECT source_type, beacon_id
FROM public.person_capability_event
WHERE observer_user_id = 'Ucapb2aobs01'
  AND subject_user_id = 'Ucapb2asub01'
  AND tag_slug = 'transport'
  AND deleted_at IS NULL
''');
        expect(rows.single[0], 3);
        expect(rows.single[1], _beaconId);
        expect(await _generation(writer, _obs1, _sub, 'transport'), 1);
        expect(
          await _effectiveOutStrength(writer, _obs1, _sub, 'transport'),
          closeTo(1 / 3, 1e-4),
        );
      },
      skip: skipReason,
    );

    test(
      'revokeOutcomeEvidence soft-deletes source-3 row and clears rebuilt cell',
      () async {
        await unitOfWork.run(
          actorUserId: _auth,
          action: () => repo.emitOutcomeEvidenceBatch(
            beaconId: _beaconId,
            emissions: const [
              OutcomeEmission(
                observerUserId: _obs1,
                subjectUserId: _sub,
                tagSlug: 'transport',
              ),
            ],
          ),
        );

        await repo.revokeOutcomeEvidence(
          beaconId: _beaconId,
          observerId: _obs1,
          subjectId: _sub,
          slug: 'transport',
        );

        final active = await writer.execute(r'''
SELECT count(*)::int
FROM public.person_capability_event
WHERE observer_user_id = 'Ucapb2aobs01'
  AND subject_user_id = 'Ucapb2asub01'
  AND tag_slug = 'transport'
  AND source_type = 3
  AND deleted_at IS NULL
''');
        expect(active.single.single, 0);
        expect(
          await _cellExists(writer, _obs1, _sub, 'transport'),
          isFalse,
        );
        expect(await _generation(writer, _obs1, _sub, 'transport'), 2);
      },
      skip: skipReason,
    );

    test(
      'emitOutcomeEvidenceBatch is idempotent under repeated calls',
      () async {
        const emissions = [
          OutcomeEmission(
            observerUserId: _obs1,
            subjectUserId: _sub,
            tagSlug: 'transport',
          ),
          OutcomeEmission(
            observerUserId: _obs2,
            subjectUserId: _sub,
            tagSlug: 'transport',
          ),
        ];

        Future<void> emit() => unitOfWork.run(
          actorUserId: _auth,
          action: () => repo.emitOutcomeEvidenceBatch(
            beaconId: _beaconId,
            emissions: emissions,
          ),
        );

        await emit();
        final ledgerAfterFirst = await _activeOutcomeCount(writer);
        final strengthAfterFirst = await _effectiveOutStrength(
          writer,
          _obs1,
          _sub,
          'transport',
        );

        await emit();
        expect(await _activeOutcomeCount(writer), ledgerAfterFirst);
        expect(
          await _effectiveOutStrength(writer, _obs1, _sub, 'transport'),
          closeTo(strengthAfterFirst, 1e-9),
        );
        expect(await _generation(writer, _obs1, _sub, 'transport'), 2);
        expect(await _generation(writer, _obs2, _sub, 'transport'), 2);
      },
      skip: skipReason,
    );

    test(
      'emitOutcomeEvidenceBatch succeeds for multiple observers in one ambient UoW',
      () async {
        await unitOfWork.run(
          actorUserId: _auth,
          action: () => repo.emitOutcomeEvidenceBatch(
            beaconId: _beaconId,
            emissions: const [
              OutcomeEmission(
                observerUserId: _obs1,
                subjectUserId: _sub,
                tagSlug: 'transport',
              ),
              OutcomeEmission(
                observerUserId: _obs2,
                subjectUserId: _sub,
                tagSlug: 'pets',
              ),
            ],
          ),
        );

        expect(await _activeOutcomeCount(writer), 2);
        expect(
          await _effectiveOutStrength(writer, _obs1, _sub, 'transport'),
          closeTo(1 / 3, 1e-4),
        );
        expect(
          await _effectiveOutStrength(writer, _obs2, _sub, 'pets'),
          closeTo(1 / 3, 1e-4),
        );
      },
      skip: skipReason,
    );

    test(
      'opposite-input concurrent batches complete without deadlock',
      () async {
        final db1 = TenturaDb(target.databaseEnv);
        final db2 = TenturaDb(target.databaseEnv);
        final repo1 = CapabilityEvidenceRepository(db1);
        final repo2 = CapabilityEvidenceRepository(db2);
        final uow1 = MutatingUnitOfWork(db1);
        final uow2 = MutatingUnitOfWork(db2);

        const batchA = [
          OutcomeEmission(
            observerUserId: _obs1,
            subjectUserId: _sub,
            tagSlug: 'transport',
          ),
          OutcomeEmission(
            observerUserId: _obs2,
            subjectUserId: _sub,
            tagSlug: 'pets',
          ),
        ];
        const batchB = [
          OutcomeEmission(
            observerUserId: _obs2,
            subjectUserId: _sub,
            tagSlug: 'pets',
          ),
          OutcomeEmission(
            observerUserId: _obs1,
            subjectUserId: _sub,
            tagSlug: 'transport',
          ),
        ];

        try {
          await Future.wait([
            uow1.run(
              actorUserId: _auth,
              action: () => repo1.emitOutcomeEvidenceBatch(
                beaconId: _beaconId,
                emissions: batchA,
              ),
            ),
            uow2.run(
              actorUserId: _auth,
              action: () => repo2.emitOutcomeEvidenceBatch(
                beaconId: _beaconId,
                emissions: batchB,
              ),
            ),
          ]);
        } finally {
          await db1.close();
          await db2.close();
        }

        expect(await _activeOutcomeCount(writer), 2);
        expect(
          await _effectiveOutStrength(writer, _obs1, _sub, 'transport'),
          closeTo(1 / 3, 1e-4),
        );
        expect(
          await _effectiveOutStrength(writer, _obs2, _sub, 'pets'),
          closeTo(1 / 3, 1e-4),
        );
      },
      skip: skipReason,
    );
  });
}

Future<void> _seedFixture(Connection writer) async {
  await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Ucapb2aobs01', 'Observer 1', 'pk-obs1'),
  ('Ucapb2aobs02', 'Observer 2', 'pk-obs2'),
  ('Ucapb2asub01', 'Subject', 'pk-sub'),
  ('Ucapb2aauth1', 'Author', 'pk-auth')
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon (id, user_id, title, description)
VALUES
  ('Bcapb2abcn01', 'Ucapb2aauth1', 'Beacon 1', 'd'),
  ('Bcapb2abcn02', 'Ucapb2aauth1', 'Beacon 2', 'd')
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (
  'Fcapb2aedge1', 'Bcapb2abcn01', 'Ucapb2aobs01', 'Ucapb2asub01', now()
)
ON CONFLICT DO NOTHING
''');
}

Future<List<String>> _activeForwardSlugs(Connection writer) async {
  final rows = await writer.execute(r'''
SELECT tag_slug
FROM public.person_capability_event
WHERE forward_edge_id = 'Fcapb2aedge1'
  AND source_type = 1
  AND deleted_at IS NULL
ORDER BY tag_slug
''');
  return rows.map((r) => r[0]! as String).toList();
}

Future<int> _activeOutcomeCount(Connection writer) async {
  final rows = await writer.execute(r'''
SELECT count(*)::int
FROM public.person_capability_event
WHERE observer_user_id LIKE 'Ucapb2a%'
  AND source_type = 3
  AND deleted_at IS NULL
''');
  return rows.single.single! as int;
}

Future<int> _generation(
  Connection writer,
  String observer,
  String subject,
  String tag,
) async {
  final rows = await writer.execute(
    "SELECT generation FROM public.capability_evidence_generation "
    "WHERE observer_user_id = '$observer' "
    "AND subject_user_id = '$subject' "
    "AND tag_slug = '$tag'",
  );
  if (rows.isEmpty) {
    return 0;
  }
  return rows.single.single! as int;
}

Future<bool> _cellExists(
  Connection writer,
  String observer,
  String subject,
  String tag,
) async {
  final rows = await writer.execute(
    "SELECT 1 FROM public.capability_evidence_edge "
    "WHERE observer_user_id = '$observer' "
    "AND subject_user_id = '$subject' "
    "AND tag_slug = '$tag'",
  );
  return rows.isNotEmpty;
}

Future<_CellRow> _readCell(
  Connection writer,
  String observer,
  String subject,
  String tag,
) async {
  final row = await writer.execute(
    "SELECT s_out, s_seed FROM public.capability_evidence_edge "
    "WHERE observer_user_id = '$observer' "
    "AND subject_user_id = '$subject' "
    "AND tag_slug = '$tag'",
  );
  return _CellRow(
    sOut: (row.single[0] as num).toDouble(),
    sSeed: (row.single[1] as num).toDouble(),
  );
}

Future<double> _effectiveOutStrength(
  Connection writer,
  String observer,
  String subject,
  String tag,
) async {
  final row = await writer.execute(
    "SELECT public.cap_strength(s_out, $_kOut, anchor_at, $_hlOut) "
    "FROM public.capability_evidence_edge "
    "WHERE observer_user_id = '$observer' "
    "AND subject_user_id = '$subject' "
    "AND tag_slug = '$tag'",
  );
  return (row.single.single as num).toDouble();
}

Future<double> _effectiveSeedStrength(
  Connection writer,
  String observer,
  String subject,
  String tag,
) async {
  final row = await writer.execute(
    "SELECT public.cap_strength(s_seed, 1.0, anchor_at, $_hlSeed) "
    "FROM public.capability_evidence_edge "
    "WHERE observer_user_id = '$observer' "
    "AND subject_user_id = '$subject' "
    "AND tag_slug = '$tag'",
  );
  return (row.single.single as num).toDouble();
}

class _CellRow {
  const _CellRow({required this.sOut, required this.sSeed});

  final double sOut;
  final double sSeed;
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
        Platform.environment['TENTURA_CAP_EVIDENCE_REPO_TEST_DB'] ??
        'tentura_test_cap_evidence_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_CAP_EVIDENCE_REPO_TEST_DB',
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
