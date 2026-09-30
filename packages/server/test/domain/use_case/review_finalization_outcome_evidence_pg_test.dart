@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/evaluation_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/use_case/evaluation/review_finalization_case.dart';

import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/beacon_lifecycle_effects_test_support.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/review_finalization_test_support.dart'
    show NoopAttentionSystemSettlement;

const _beaconId = 'Bcapc2bcn001';
const _author = 'Ucapc2author1';
const _subject = 'Ucapc2subj001';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REVIEW_OUTCOME_TEST_DB',
    defaultNamePrefix: 'tentura_test_review_outcome',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('ReviewFinalizationCase outcome evidence (post-m0203 contract)', () {
    late Connection writer;
    late TenturaDb database;
    late ReviewFinalizationCase finalizationCase;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      database = TenturaDb(target.databaseEnv);
      final evalRepo = EvaluationRepository(database);
      finalizationCase = ReviewFinalizationCase(
        MutatingUnitOfWork(database),
        evalRepo,
        CapabilityEvidenceRepository(database),
        FakeBeaconHierarchyRepository(),
        buildLifecycleEffectsCase(),
        NoopAttentionSystemSettlement(),
        env: target.databaseEnv,
        logger: Logger('ReviewFinalizationOutcomeEvidencePgTest'),
      );
    });

    setUp(() async {
      await writer.execute(r'''
DELETE FROM public.person_capability_event
WHERE observer_user_id LIKE 'Ucapc2%'
   OR subject_user_id LIKE 'Ucapc2%'
''');
      await writer.execute(r'''
DELETE FROM public.capability_evidence_edge
WHERE observer_user_id LIKE 'Ucapc2%'
   OR subject_user_id LIKE 'Ucapc2%'
''');
      await writer.execute(r'''
DELETE FROM public.capability_evidence_generation
WHERE observer_user_id LIKE 'Ucapc2%'
   OR subject_user_id LIKE 'Ucapc2%'
''');
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test(
      'closeAndFinalize fails loudly on the stubbed review close path and '
      'mints no outcome evidence',
      () async {
        // m0203 (A6) dropped the review-era tables and stubbed
        // EvaluationRepository.closeReviewWindow; A18 deletes these call
        // paths. Until then finalization must raise the stub, and no
        // ack-derived outcome evidence may reach the capability ledger.
        await expectLater(
          () => finalizationCase.closeAndFinalize(
            _beaconId,
            reason: 'test',
            actorUserId: _author,
          ),
          throwsA(isA<UnimplementedError>()),
        );

        expect(await _outcomeLedgerCount(writer, _subject), 0);
        expect(await _cellCountForSubject(writer, _subject), 0);
      },
      skip: skipReason,
    );
  });
}

Future<int> _outcomeLedgerCount(Connection writer, String subjectId) async {
  final rows = await writer.execute(
    "SELECT count(*)::int FROM public.person_capability_event "
    "WHERE subject_user_id = '$subjectId' "
    "AND source_type = 3 "
    "AND deleted_at IS NULL",
  );
  return rows.single.single! as int;
}

Future<int> _cellCountForSubject(Connection writer, String subjectId) async {
  final rows = await writer.execute(
    "SELECT count(*)::int FROM public.capability_evidence_edge "
    "WHERE subject_user_id = '$subjectId'",
  );
  return rows.single.single! as int;
}
