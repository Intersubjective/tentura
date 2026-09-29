@Tags(['pg'])
library;


import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/beacon_lifecycle_effects_test_support.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/evaluation_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/port/attention_expiry_repository_port.dart';
import 'package:tentura_server/domain/entity/review_finalization_result.dart';
import 'package:tentura_server/domain/port/review_finalization_port.dart';
import 'package:tentura_server/domain/use_case/attention_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_draft_purger.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_participant_graph_builder.dart';
import 'package:tentura_server/domain/use_case/evaluation_case.dart';
import 'package:tentura_server/env.dart';

import '../evaluation/evaluation_graph_test_repos.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';

import '../../support/disposable_pg_target.dart';

const _beaconId = 'Bcapc1bcn001';
const _evaluatorId = 'Ucapc1beval01';
const _subjectId = 'Ucapc1bsubj01';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_EVAL_ACK_POLICY_TEST_DB',
    defaultNamePrefix: 'tentura_test_eval_ack',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('EvaluationCase.evaluationSubmit acknowledgement policy (A18 stub)',
      () {
    late Connection writer;
    late TenturaDb database;
    late EvaluationCase evaluationCase;

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
      final helpOfferRepo = HelpOfferRepository(database);
      final beaconRepo = BeaconRepository(database);
      final attention = TestAttentionHarness();
      final reviewFinalization = _NoopReviewFinalization();
      final expirySweep = AttentionExpirySweepCase(
        _NoopAttentionExpiryRepository(),
        reviewFinalization,
        attention.intents,
        attention.transactional,
      );
      final graphBuilder = EvaluationParticipantGraphBuilder(
        NoOpCommitmentRepository(),
        helpOfferRepo,
        EmptyGraphForwardEdgeRepository(),
        StubUserRepository('User'),
      );

      evaluationCase = EvaluationCase(
        beaconRepo,
        EmptyGraphForwardEdgeRepository(),
        evalRepo,
        StubUserProfileBatchLookup('User'),
        graphBuilder,
        EvaluationDraftPurger(evalRepo),
        CommitmentQueryCase(
          NoOpCommitmentRepository(),
          helpOfferRepo,
          env: Env(environment: Environment.test),
          logger: Logger('EvaluationSubmitAckPolicyPgTest'),
        ),
        NoOpCommitmentRepository(),
        helpOfferRepo,
        FakeBeaconHierarchyRepository(),
        buildLifecycleEffectsCase(),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        attentionExpirySweep: expirySweep,
        reviewFinalization: reviewFinalization,
        env: Env(environment: Environment.test),
        logger: Logger('EvaluationSubmitAckPolicyPgTest'),
      );
    });

    setUp(() async {
      await writer.execute(r'''
DELETE FROM public.person_capability_event
WHERE beacon_id = 'Bcapc1bcn001'
''');
      await writer.execute(r'''
DELETE FROM public.beacon_help_offer
WHERE beacon_id = 'Bcapc1bcn001'
''');
      await writer.execute(r'''
DELETE FROM public.beacon
WHERE id = 'Bcapc1bcn001'
''');
      await _seedFixture(writer);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    test(
      'submit fails loudly on the stubbed review write path and mints nothing',
      () async {
        // m0203 (A6) dropped the review-era tables and stubbed the
        // EvaluationRepository write path; A18 deletes these call paths.
        // Until then a submit against a review-era Request must raise the
        // stub instead of touching the dropped schema, and no acknowledgement
        // may leak into the capability ledger.
        await expectLater(
          () => evaluationCase.evaluationSubmit(
            beaconId: _beaconId,
            evaluatorId: _evaluatorId,
            evaluatedUserId: _subjectId,
            value: BeaconEvaluationValue.zero,
            reasonTags: const [],
            note: 'thanks',
            acknowledgedHelpTags: const ['transport', 'pets'],
          ),
          throwsA(isA<UnimplementedError>()),
        );

        final ledgerRows = await writer.execute(r'''
SELECT 1
FROM public.person_capability_event
WHERE beacon_id = 'Bcapc1bcn001'
  AND observer_user_id = 'Ucapc1beval01'
  AND subject_user_id = 'Ucapc1bsubj01'
  AND source_type = 3
''');
        expect(ledgerRows, isEmpty);
      },
      skip: skipReason,
    );
  });
}

Future<void> _seedFixture(Connection writer) async {
  await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Ucapc1beval01', 'Evaluator', 'pk-eval'),
  ('Ucapc1bsubj01', 'Subject', 'pk-sub'),
  ('Ucapc1bauth01', 'Author', 'pk-auth')
ON CONFLICT DO NOTHING
''');

  await writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, needs, primary_need_slug, status
)
VALUES (
  'Bcapc1bcn001',
  'Ucapc1bauth01',
  'Ack policy beacon',
  'd',
  'transport,pets',
  'transport',
  ${BeaconStatus.reviewOpen.smallintValue}
)
ON CONFLICT (id) DO UPDATE SET
  status = EXCLUDED.status
''');
}

class _NoopAttentionExpiryRepository implements AttentionExpiryRepositoryPort {
  @override
  Future<List<String>> lockExpiredReviewWindowBeaconIds(DateTime now) async =>
      const [];
}

class _NoopReviewFinalization implements ReviewFinalizationPort {
  @override
  Future<ReviewFinalizationResult> closeAndFinalize(
    String beaconId, {
    required String reason,
    String? actorUserId,
    bool requireAllRequiredPackagesSent = false,
  }) async =>
      const ReviewFinalizationResult(didClose: false);
}
