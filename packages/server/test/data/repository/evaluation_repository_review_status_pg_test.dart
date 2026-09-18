@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/port/attention_expiry_repository_port.dart';
import 'package:tentura_server/domain/port/review_finalization_port.dart';
import 'package:tentura_server/domain/use_case/attention_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_draft_purger.dart';
import 'package:tentura_server/domain/use_case/evaluation/evaluation_participant_graph_builder.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/use_case/evaluation_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import '../../domain/evaluation/evaluation_graph_test_repos.dart';
import '../../support/beacon_lifecycle_effects_test_support.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/test_attention_harness.dart';
import '../../support/recording_commitment_repository.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/evaluation_repository.dart';

import '../../support/disposable_pg_target.dart';

const _beacon = 'Bcrvst1abcn01';
const _author = 'Ucrvst1aauth01';
const _reviewer = 'Ucrvst1arevw01';
const _subject = 'Ucrvst1asubj01';
const _former = 'Ucrvst1aform01';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_EVAL_REVIEW_STATUS_TEST_DB',
    defaultNamePrefix: 'tentura_test_eval_review_status',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('EvaluationRepository review package sent_at', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late EvaluationRepository repo;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      final proof = await writer.execute('SELECT current_database()');
      print('PG_DISPOSABLE_DATABASE=${proof.single.single}');

      // m0176 must have run on the disposable target.
      final columns = await writer.execute(r'''
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'beacon_review_status'
  AND column_name = 'sent_at'
''');
      expect(columns, isNotEmpty);

      database = openDisposablePgDatabase(target);
      repo = EvaluationRepository(database);
    });

    setUp(() async {
      await _clean(writer);
      await _seedFixture(writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    test('two simultaneous last sends emit one notification', () async {
      await _seedRequiredPackages(writer);
      final evaluationCase = _buildEvaluationCase(database, repo, target);
      final window = (await repo.getReviewWindow(_beacon))!;
      final sourceEventKey =
          'review_all_in:$_beacon:${window.openedAt.toUtc().toIso8601String()}';

      // Both actions are launched together. The shared Drift connection
      // serializes their real mutating transactions, as in the server.
      expect(
        await Future.wait([
          evaluationCase.evaluationFinalize(beaconId: _beacon, userId: _author),
          evaluationCase.evaluationFinalize(
            beaconId: _beacon,
            userId: _reviewer,
          ),
        ]),
        [true, true],
      );
      expect(await _nudgeCount(writer, sourceEventKey), 1);
      final receipts = await writer.execute(
        r'''SELECT r.account_id, r.requires_action, o.actor_user_id
              FROM public.notification_outbox r
              JOIN public.attention_occurrence o ON o.id = r.occurrence_id
              WHERE o.source_event_key = $1''',
        parameters: [sourceEventKey],
      );
      expect(receipts, hasLength(1));
      expect(receipts.single, [_author, false, _author]);

      // A different last sender after an edit must replay the same stable
      // source facts and must neither add a receipt nor reject the key.
      await repo.submitEvaluationAtomic(
        beaconId: _beacon,
        evaluatorId: _author,
        evaluatedUserId: _reviewer,
        value: 4,
        reasonTags: const [],
        note: 'edited',
        ackTags: const [],
      );
      expect(await repo.getReviewUserStatus(_beacon, _author), 1);
      await evaluationCase.evaluationFinalize(
        beaconId: _beacon,
        userId: _author,
      );
      expect(await _nudgeCount(writer, sourceEventKey), 1);
      final status = await evaluationCase.reviewWindowStatus(
        beaconId: _beacon,
        userId: _author,
      );
      expect(status.canCloseNow, isTrue);
      expect((await repo.getReviewWindow(_beacon))!.status, 0);
    });

    test('dispatch failure rolls back the last package send', () async {
      await _seedRequiredPackages(writer);
      await repo.setReviewUserStatus(
        beaconId: _beacon,
        userId: _author,
        status: 2,
        markSent: true,
      );
      final evaluationCase = _buildEvaluationCase(database, repo, target);
      final window = (await repo.getReviewWindow(_beacon))!;
      final sourceEventKey =
          'review_all_in:$_beacon:${window.openedAt.toUtc().toIso8601String()}';
      // NOT VALID leaves historical occurrences alone but rejects the new one.
      await writer.execute('''
        ALTER TABLE public.attention_occurrence
        ADD CONSTRAINT unit05_reject_nudge
        CHECK (event_type <> 'reviewAllPackagesIn') NOT VALID
      ''');
      try {
        await expectLater(
          evaluationCase.evaluationFinalize(
            beaconId: _beacon,
            userId: _reviewer,
          ),
          throwsA(
            predicate<Object>(
              (error) => error.toString().contains('unit05_reject_nudge'),
            ),
          ),
        );
        expect(await _status(writer), 1);
        expect(await _sentAt(writer), isNull);
        expect(await _nudgeCount(writer, sourceEventKey), 0);
      } finally {
        await writer.execute(
          'ALTER TABLE public.attention_occurrence DROP CONSTRAINT unit05_reject_nudge',
        );
      }
    });

    test(
      'finalize stamps sent_at',
      () async {
        expect(await _sentAt(writer), isNull);

        // A plain status write must never stamp the package as sent.
        await repo.setReviewUserStatus(
          beaconId: _beacon,
          userId: _reviewer,
          status: 1,
        );
        expect(await _sentAt(writer), isNull);

        await repo.setReviewUserStatus(
          beaconId: _beacon,
          userId: _reviewer,
          status: 2,
          markSent: true,
        );

        expect(await _status(writer), 2);
        expect(await _sentAt(writer), isNotNull);
      },
      skip: skipReason,
    );

    test(
      'editing a card after send demotes status to 1 and keeps sent_at',
      () async {
        await repo.setReviewUserStatus(
          beaconId: _beacon,
          userId: _reviewer,
          status: 2,
          markSent: true,
        );
        final sentAtAfterSend = await _sentAt(writer);
        expect(sentAtAfterSend, isNotNull);

        await repo.submitEvaluationAtomic(
          beaconId: _beacon,
          evaluatorId: _reviewer,
          evaluatedUserId: _subject,
          value: 4,
          reasonTags: const ['quality'],
          note: 'edited after send',
          ackTags: const [],
        );

        expect(await _status(writer), 1);
        expect(await _sentAt(writer), sentAtAfterSend);
      },
      skip: skipReason,
    );

    test(
      'reopen deletes the review status row entirely',
      () async {
        await repo.setReviewUserStatus(
          beaconId: _beacon,
          userId: _reviewer,
          status: 2,
          markSent: true,
        );
        expect(await _statusRowCount(writer), 1);

        await repo.deleteReviewScaffoldingForBeacon(_beacon);

        expect(await _statusRowCount(writer), 0);
      },
      skip: skipReason,
    );

    test(
      'optional unsent package is discarded at close without becoming trust input',
      () async {
        await _seedRequiredPackages(writer);
        await _seedOptionalUnsentPackage(writer);
        await repo.setReviewUserStatus(
          beaconId: _beacon,
          userId: _author,
          status: 2,
          markSent: true,
        );
        await repo.setReviewUserStatus(
          beaconId: _beacon,
          userId: _reviewer,
          status: 2,
          markSent: true,
        );

        final snapshot = await repo.closeReviewWindow(
          _beacon,
          reason: BeaconLifecycleChangeReason.authorCloseNow,
          actorUserId: _author,
          requireAllRequiredPackagesSent: true,
        );

        expect(snapshot, isNotNull);
        expect(
          snapshot!.finalizedEvaluations.map((e) => e.evaluatorId),
          isNot(contains(_former)),
        );
        expect(await _evalCount(writer, _former), 0);
        expect(await _ackCount(writer, _former), 0);
        expect(await _evalCount(writer, _author), 1);
        expect(
          await _evalStatus(writer, _author),
          BeaconEvaluationRowStatus.final_,
        );
      },
      skip: skipReason,
    );

    test(
      'author close racing an edit yields one serial outcome',
      () async {
        await _seedRequiredPackages(writer);
        await repo.setReviewUserStatus(
          beaconId: _beacon,
          userId: _author,
          status: 2,
          markSent: true,
        );
        await repo.setReviewUserStatus(
          beaconId: _beacon,
          userId: _reviewer,
          status: 2,
          markSent: true,
        );

        Object? closed;
        Object? editError;
        await Future.wait<void>([
          repo
              .closeReviewWindow(
                _beacon,
                reason: BeaconLifecycleChangeReason.authorCloseNow,
                actorUserId: _author,
                requireAllRequiredPackagesSent: true,
              )
              .then((value) => closed = value),
          () async {
            try {
              await repo.submitEvaluationAtomic(
                beaconId: _beacon,
                evaluatorId: _author,
                evaluatedUserId: _reviewer,
                value: 3,
                reasonTags: const [],
                note: 'race edit',
                ackTags: const [],
              );
            } catch (error) {
              editError = error;
            }
          }(),
        ]);

        final window = await repo.getReviewWindow(_beacon);
        expect(window, isNotNull);
        if (closed != null) {
          expect(window!.status, 1);
          if (editError != null) {
            expect('$editError', contains('Review window not open'));
          }
        } else {
          expect(window!.status, 0);
          expect(editError, isNull);
          expect(await repo.getReviewUserStatus(_beacon, _author), 1);
        }
      },
      skip: skipReason,
    );
  });
}

Future<int?> _status(Connection writer) async {
  final rows = await writer.execute(
    r'''
SELECT status FROM public.beacon_review_status
WHERE beacon_id = $1 AND user_id = $2
''',
    parameters: [_beacon, _reviewer],
  );
  return rows.isEmpty ? null : rows.single[0] as int?;
}

Future<DateTime?> _sentAt(Connection writer) async {
  final rows = await writer.execute(
    r'''
SELECT sent_at FROM public.beacon_review_status
WHERE beacon_id = $1 AND user_id = $2
''',
    parameters: [_beacon, _reviewer],
  );
  return rows.isEmpty ? null : rows.single[0] as DateTime?;
}

Future<int> _statusRowCount(Connection writer) async {
  final rows = await writer.execute(
    r'''
SELECT count(*) FROM public.beacon_review_status WHERE beacon_id = $1
''',
    parameters: [_beacon],
  );
  return rows.single[0]! as int;
}

Future<int> _evalCount(Connection writer, String evaluatorId) async {
  final rows = await writer.execute(
    r'''
SELECT count(*) FROM public.beacon_evaluation
WHERE beacon_id = $1 AND evaluator_id = $2
''',
    parameters: [_beacon, evaluatorId],
  );
  return rows.single[0]! as int;
}

Future<int?> _evalStatus(Connection writer, String evaluatorId) async {
  final rows = await writer.execute(
    r'''
SELECT status FROM public.beacon_evaluation
WHERE beacon_id = $1 AND evaluator_id = $2
''',
    parameters: [_beacon, evaluatorId],
  );
  return rows.isEmpty ? null : rows.single[0] as int?;
}

Future<int> _ackCount(Connection writer, String evaluatorId) async {
  final rows = await writer.execute(
    r'''
SELECT count(*) FROM public.beacon_evaluation_ack_tag
WHERE beacon_id = $1 AND evaluator_id = $2
''',
    parameters: [_beacon, evaluatorId],
  );
  return rows.single[0]! as int;
}

Future<void> _seedOptionalUnsentPackage(Connection writer) async {
  await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('Ucrvst1aform01', 'Former', 'pk-rvst-form')
ON CONFLICT DO NOTHING
''');
  await writer.execute(r'''
INSERT INTO public.beacon_evaluation_participant
  (beacon_id, user_id, role, contribution_summary, causal_hint)
VALUES ('Bcrvst1abcn01', 'Ucrvst1aform01', 3, 'former', 'h')
''');
  await writer.execute(r'''
INSERT INTO public.beacon_evaluation_visibility
  (beacon_id, evaluator_id, participant_id)
VALUES ('Bcrvst1abcn01', 'Ucrvst1aform01', 'Ucrvst1aauth01')
''');
  await writer.execute(r'''
INSERT INTO public.beacon_review_status (beacon_id, user_id, status)
VALUES ('Bcrvst1abcn01', 'Ucrvst1aform01', 1)
ON CONFLICT (beacon_id, user_id) DO UPDATE SET status = EXCLUDED.status
''');
  await writer.execute(r'''
INSERT INTO public.beacon_evaluation
  (beacon_id, evaluator_id, evaluated_user_id, value, reason_tags, note, status)
VALUES ('Bcrvst1abcn01', 'Ucrvst1aform01', 'Ucrvst1aauth01', 4, '', '', 0)
''');
  await writer.execute(r'''
INSERT INTO public.beacon_evaluation_ack_tag
  (beacon_id, evaluator_id, subject_id, tag_slug)
VALUES ('Bcrvst1abcn01', 'Ucrvst1aform01', 'Ucrvst1aauth01', 'quality')
''');
}

Future<void> _clean(Connection writer) async {
  for (final table in const [
    'beacon_evaluation_ack_tag',
    'beacon_evaluation',
    'beacon_evaluation_visibility',
    'beacon_evaluation_participant',
    'beacon_review_status',
    'beacon_review_window',
  ]) {
    await writer.execute(
      'DELETE FROM public.$table WHERE beacon_id LIKE \'Bcrvst1a%\'',
    );
  }
}

Future<void> _seedFixture(Connection writer) async {
  await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Ucrvst1aauth01', 'Author', 'pk-rvst-auth'),
  ('Ucrvst1arevw01', 'Reviewer', 'pk-rvst-revw'),
  ('Ucrvst1asubj01', 'Subject', 'pk-rvst-subj')
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon (id, user_id, title, description)
VALUES ('Bcrvst1abcn01', 'Ucrvst1aauth01', 'Review status beacon', 'd')
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon_review_window (
  beacon_id, opened_at, closes_at, status
) VALUES (
  'Bcrvst1abcn01',
  now() - interval '1 day',
  now() + interval '7 days',
  0
)
ON CONFLICT (beacon_id) DO UPDATE SET
  opened_at = EXCLUDED.opened_at,
  closes_at = EXCLUDED.closes_at,
  status = EXCLUDED.status
''');

  await writer.execute(r'''
INSERT INTO public.beacon_review_status (beacon_id, user_id, status)
VALUES ('Bcrvst1abcn01', 'Ucrvst1arevw01', 0)
ON CONFLICT (beacon_id, user_id) DO UPDATE SET status = EXCLUDED.status
''');
}

class _NoDueWindows extends Fake implements AttentionExpiryRepositoryPort {
  @override
  Future<List<String>> lockExpiredReviewWindowBeaconIds(DateTime now) async =>
      [];
}

class _UnusedFinalization extends Fake implements ReviewFinalizationPort {}

EvaluationCase _buildEvaluationCase(
  TenturaDb database,
  EvaluationRepository repo,
  DisposablePgTarget target,
) {
  final logger = Logger('ReviewAllPackagesInPgTest');
  final attention = TestAttentionHarness();
  final transactional = TransactionalAttentionCase(
    MutatingUnitOfWork(database),
    AttentionDispatchRepository(database, logger),
  );
  final offers = EmptyGraphHelpOfferRepository();
  final forwards = EmptyGraphForwardEdgeRepository();
  final commitments = NoOpCommitmentRepository();
  final finalization = _UnusedFinalization();
  return EvaluationCase(
    BeaconRepository(database),
    forwards,
    repo,
    StubUserProfileBatchLookup('User'),
    EvaluationParticipantGraphBuilder(
      commitments,
      offers,
      forwards,
      StubUserRepository('User'),
    ),
    EvaluationDraftPurger(repo),
    CommitmentQueryCase(
      commitments,
      offers,
      env: target.databaseEnv,
      logger: logger,
    ),
    commitments,
    offers,
    FakeBeaconHierarchyRepository(),
    buildLifecycleEffectsCase(),
    attentionIntents: attention.intents,
    attention: transactional,
    attentionExpirySweep: AttentionExpirySweepCase(
      _NoDueWindows(),
      finalization,
      attention.intents,
      transactional,
    ),
    reviewFinalization: finalization,
    env: target.databaseEnv,
    logger: logger,
  );
}

Future<int> _nudgeCount(Connection writer, String sourceEventKey) async {
  final rows = await writer.execute(
    r'''SELECT count(*) FROM public.attention_occurrence
        WHERE source_event_key = $1 AND event_type = 'reviewAllPackagesIn'
        ''',
    parameters: [sourceEventKey],
  );
  return rows.single.single! as int;
}

Future<void> _seedRequiredPackages(Connection writer) async {
  await writer.execute(
    r'UPDATE public.beacon SET status = $1 WHERE id = $2',
    parameters: [BeaconStatus.reviewOpen.smallintValue, _beacon],
  );
  await writer.execute(r'''
    INSERT INTO public.beacon_evaluation_participant
      (beacon_id, user_id, role, contribution_summary, causal_hint)
    VALUES ('Bcrvst1abcn01', 'Ucrvst1aauth01', 0, 'author', 'h'),
           ('Bcrvst1abcn01', 'Ucrvst1arevw01', 1, 'reviewer', 'h')
  ''');
  await writer.execute(r'''
    INSERT INTO public.beacon_evaluation_visibility
      (beacon_id, evaluator_id, participant_id)
    VALUES ('Bcrvst1abcn01', 'Ucrvst1aauth01', 'Ucrvst1arevw01'),
           ('Bcrvst1abcn01', 'Ucrvst1arevw01', 'Ucrvst1aauth01')
  ''');
  await writer.execute(r'''
    INSERT INTO public.beacon_review_status (beacon_id, user_id, status)
    VALUES ('Bcrvst1abcn01', 'Ucrvst1aauth01', 1),
           ('Bcrvst1abcn01', 'Ucrvst1arevw01', 1)
    ON CONFLICT (beacon_id, user_id) DO UPDATE SET status = EXCLUDED.status
  ''');
  await writer.execute(r'''
    INSERT INTO public.beacon_evaluation
      (beacon_id, evaluator_id, evaluated_user_id, value, reason_tags, note, status)
    VALUES ('Bcrvst1abcn01', 'Ucrvst1aauth01', 'Ucrvst1arevw01', 4, '', '', 0),
           ('Bcrvst1abcn01', 'Ucrvst1arevw01', 'Ucrvst1aauth01', 4, '', '', 0)
  ''');
}
