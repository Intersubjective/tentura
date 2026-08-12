@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/evaluation_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/port/attention_expiry_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
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

const _beaconId = 'Bcapc1bcn001';
const _evaluatorId = 'Ucapc1beval01';
const _subjectId = 'Ucapc1bsubj01';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('EvaluationCase.evaluationSubmit acknowledgement policy', () {
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
DELETE FROM public.beacon_evaluation_ack_tag
WHERE beacon_id = 'Bcapc1bcn001'
''');
      await writer.execute(r'''
DELETE FROM public.beacon_evaluation
WHERE beacon_id = 'Bcapc1bcn001'
''');
      await writer.execute(r'''
DELETE FROM public.beacon_help_offer
WHERE beacon_id = 'Bcapc1bcn001'
''');
      await writer.execute(r'''
DELETE FROM public.beacon_evaluation_visibility
WHERE beacon_id = 'Bcapc1bcn001'
''');
      await writer.execute(r'''
DELETE FROM public.beacon_evaluation_participant
WHERE beacon_id = 'Bcapc1bcn001'
''');
      await writer.execute(r'''
DELETE FROM public.beacon_review_status
WHERE beacon_id = 'Bcapc1bcn001'
''');
      await writer.execute(r'''
DELETE FROM public.beacon_review_window
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
      'writes ack tags to beacon_evaluation_ack_tag without ledger rows',
      () async {
        await evaluationCase.evaluationSubmit(
          beaconId: _beaconId,
          evaluatorId: _evaluatorId,
          evaluatedUserId: _subjectId,
          value: BeaconEvaluationValue.zero,
          reasonTags: const [],
          note: 'thanks',
          acknowledgedHelpTags: const ['transport', 'pets'],
        );

        final ackRows = await writer.execute(r'''
SELECT tag_slug
FROM public.beacon_evaluation_ack_tag
WHERE beacon_id = 'Bcapc1bcn001'
  AND evaluator_id = 'Ucapc1beval01'
  AND subject_id = 'Ucapc1bsubj01'
ORDER BY tag_slug
''');
        expect(ackRows.map((r) => r[0]), ['pets', 'transport']);

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

    test(
      'second submit replaces acknowledgement set end-to-end',
      () async {
        await evaluationCase.evaluationSubmit(
          beaconId: _beaconId,
          evaluatorId: _evaluatorId,
          evaluatedUserId: _subjectId,
          value: BeaconEvaluationValue.zero,
          reasonTags: const [],
          note: 'first',
          acknowledgedHelpTags: const ['transport', 'pets'],
        );
        await evaluationCase.evaluationSubmit(
          beaconId: _beaconId,
          evaluatorId: _evaluatorId,
          evaluatedUserId: _subjectId,
          value: BeaconEvaluationValue.zero,
          reasonTags: const [],
          note: 'second',
          acknowledgedHelpTags: const ['manual_labour'],
        );

        final ackRows = await writer.execute(r'''
SELECT tag_slug
FROM public.beacon_evaluation_ack_tag
WHERE beacon_id = 'Bcapc1bcn001'
  AND evaluator_id = 'Ucapc1beval01'
  AND subject_id = 'Ucapc1bsubj01'
ORDER BY tag_slug
''');
        expect(ackRows.map((r) => r[0]), ['manual_labour']);
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

  await writer.execute(r'''
INSERT INTO public.beacon (id, user_id, title, description, needs, primary_need_slug)
VALUES (
  'Bcapc1bcn001',
  'Ucapc1bauth01',
  'Ack policy beacon',
  'd',
  'transport,pets',
  'transport'
)
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon_help_offer (
  beacon_id, user_id, message, help_type, status, offer_kind, stake_state
) VALUES (
  'Bcapc1bcn001',
  'Ucapc1bsubj01',
  '',
  '["manual_labour"]',
  0,
  0,
  0
)
ON CONFLICT (beacon_id, user_id) DO UPDATE SET
  help_type = EXCLUDED.help_type,
  status = EXCLUDED.status
''');

  await writer.execute(r'''
INSERT INTO public.beacon_review_window (
  beacon_id, opened_at, closes_at, status
) VALUES (
  'Bcapc1bcn001',
  now() - interval '1 day',
  now() + interval '7 days',
  0
)
ON CONFLICT (beacon_id) DO UPDATE SET
  opened_at = EXCLUDED.opened_at,
  closes_at = EXCLUDED.closes_at,
  status = EXCLUDED.status
''');

  await writer.execute('''
INSERT INTO public.beacon_evaluation_participant (
  beacon_id, user_id, role, contribution_summary, causal_hint
) VALUES
  (
    'Bcapc1bcn001',
    'Ucapc1beval01',
    ${EvaluationParticipantRole.committer.dbValue},
    'helped',
    'hint'
  ),
  (
    'Bcapc1bcn001',
    'Ucapc1bsubj01',
    ${EvaluationParticipantRole.author.dbValue},
    'authored',
    'hint'
  )
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon_evaluation_visibility (
  beacon_id, evaluator_id, participant_id
) VALUES (
  'Bcapc1bcn001',
  'Ucapc1beval01',
  'Ucapc1bsubj01'
)
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon_review_status (beacon_id, user_id, status)
VALUES ('Bcapc1bcn001', 'Ucapc1beval01', 0)
ON CONFLICT DO NOTHING
''');
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
  }) async =>
      const ReviewFinalizationResult(didClose: false);
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
        Platform.environment['TENTURA_EVAL_ACK_POLICY_TEST_DB'] ??
        'tentura_test_eval_ack_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_EVAL_ACK_POLICY_TEST_DB',
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
