@Tags(['pg'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/evaluation_repository.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';
import 'package:tentura_server/domain/entity/evaluation/beacon_evaluation_record.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';

import '../../support/disposable_pg_target.dart';

const _beacon1 = 'Bcapc1abcn01';
const _beacon2 = 'Bcapc1abcn02';
const _eval1 = 'Ucapc1aeval01';
const _eval2 = 'Ucapc1aeval02';
const _subject = 'Ucapc1asubj01';
const _author = 'Ucapc1aauth01';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_EVAL_ATOMIC_TEST_DB',
    defaultNamePrefix: 'tentura_test_eval_atomic',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('EvaluationRepository.submitEvaluationAtomic', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late EvaluationRepository repo;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      final proof = await writer.execute('SELECT current_database()');
      print('PG_DISPOSABLE_DATABASE=${proof.single.single}');

      final tableRows = await writer.execute(r'''
SELECT 1
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name = 'beacon_evaluation_ack_tag'
''');
      expect(tableRows, isNotEmpty);

      database = openDisposablePgDatabase(target);
      repo = EvaluationRepository(database);
    });

    setUp(() async {
      await writer.execute(r'''
DELETE FROM public.beacon_evaluation_ack_tag
WHERE beacon_id LIKE 'Bcapc1a%'
''');
      await writer.execute(r'''
DELETE FROM public.beacon_evaluation
WHERE beacon_id LIKE 'Bcapc1a%'
''');
      await _seedFixture(writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    test(
      'writes evaluation content and ack tags on first submit',
      () async {
        await repo.submitEvaluationAtomic(
          beaconId: _beacon1,
          evaluatorId: _eval1,
          evaluatedUserId: _subject,
          value: 4,
          reasonTags: const ['quality', 'speed'],
          note: 'solid help',
          ackTags: const ['transport', 'pets'],
        );

        final evalRow = await writer.execute(r'''
SELECT value, reason_tags, note, status
FROM public.beacon_evaluation
WHERE beacon_id = 'Bcapc1abcn01'
  AND evaluator_id = 'Ucapc1aeval01'
  AND evaluated_user_id = 'Ucapc1asubj01'
''');
        expect(evalRow.single[0], 4);
        expect(evalRow.single[1], 'quality,speed');
        expect(evalRow.single[2], 'solid help');
        expect(
          evalRow.single[3],
          BeaconEvaluationRowStatus.draft,
        );

        final ackRows = await _ackTagsForTriple(
          writer,
          _beacon1,
          _eval1,
          _subject,
        );
        expect(ackRows, ['pets', 'transport']);

        final viaRepo = await repo.getEvaluation(
          beaconId: _beacon1,
          evaluatorId: _eval1,
          evaluatedUserId: _subject,
        );
        expect(viaRepo, isNotNull);
        expect(viaRepo!.status, BeaconEvaluationRowStatus.draft);
        expect(viaRepo.ackTags, ackRows);
        expect(await _ackTagCount(writer, _beacon1, _eval1, _subject), 2);
      },
      skip: skipReason,
    );

    test(
      'replaces ack tag set on second submit for same triple',
      () async {
        await repo.submitEvaluationAtomic(
          beaconId: _beacon1,
          evaluatorId: _eval1,
          evaluatedUserId: _subject,
          value: 3,
          reasonTags: const ['first'],
          note: 'n1',
          ackTags: const ['transport', 'pets'],
        );

        await repo.submitEvaluationAtomic(
          beaconId: _beacon1,
          evaluatorId: _eval1,
          evaluatedUserId: _subject,
          value: 5,
          reasonTags: const ['second'],
          note: 'n2',
          ackTags: const ['manual_labour'],
        );

        final ackRows = await _ackTagsForTriple(
          writer,
          _beacon1,
          _eval1,
          _subject,
        );
        expect(ackRows, ['manual_labour']);

        final evalRow = await writer.execute(r'''
SELECT value, reason_tags, note
FROM public.beacon_evaluation
WHERE beacon_id = 'Bcapc1abcn01'
  AND evaluator_id = 'Ucapc1aeval01'
  AND evaluated_user_id = 'Ucapc1asubj01'
''');
        expect(evalRow.single[0], 5);
        expect(evalRow.single[1], 'second');
        expect(evalRow.single[2], 'n2');
      },
      skip: skipReason,
    );

    test(
      'ack tags round-trip through every evaluation read projection',
      () async {
        await repo.submitEvaluationAtomic(
          beaconId: _beacon1,
          evaluatorId: _eval1,
          evaluatedUserId: _subject,
          value: 4,
          reasonTags: const ['first'],
          note: 'first',
          ackTags: const ['zeta', 'alpha'],
        );
        await repo.submitEvaluationAtomic(
          beaconId: _beacon1,
          evaluatorId: _eval2,
          evaluatedUserId: _subject,
          value: 5,
          reasonTags: const ['second'],
          note: 'second',
          ackTags: const ['beta'],
        );
        await repo.submitEvaluationAtomic(
          beaconId: _beacon2,
          evaluatorId: _eval1,
          evaluatedUserId: _subject,
          value: 3,
          reasonTags: const [],
          note: 'cross-beacon',
          ackTags: const ['gamma'],
        );
        await writer.execute(
          "UPDATE public.beacon_evaluation SET status = ${BeaconEvaluationRowStatus.final_}, "
          "updated_at = CASE WHEN beacon_id = '$_beacon2' THEN '2026-01-03'::timestamptz "
          "ELSE CASE WHEN evaluator_id = '$_eval2' THEN '2026-01-02'::timestamptz "
          "ELSE '2026-01-01'::timestamptz END END "
          "WHERE beacon_id IN ('$_beacon1', '$_beacon2')",
        );
        await writer.execute(
          "UPDATE public.beacon SET status = 6 WHERE id IN ('$_beacon1', '$_beacon2')",
        );
        final direct = await repo.getEvaluation(
          beaconId: _beacon1,
          evaluatorId: _eval1,
          evaluatedUserId: _subject,
        );
        expect(direct!.ackTags, ['alpha', 'zeta']);
        final byEvaluator = await repo.listEvaluationsForEvaluator(
          beaconId: _beacon1,
          evaluatorId: _eval1,
        );
        expect(byEvaluator.single.ackTags, ['alpha', 'zeta']);
        expect(byEvaluator.single.status, BeaconEvaluationRowStatus.final_);
        final byEvaluated = await repo.listEvaluationsForEvaluatedUser(
          beaconId: _beacon1,
          evaluatedUserId: _subject,
        );
        final byEvaluatorId = {
          for (final row in byEvaluated) row.evaluatorId: row,
        };
        expect(byEvaluatorId[_eval1]!.ackTags, ['alpha', 'zeta']);
        expect(byEvaluatorId[_eval1]!.status, BeaconEvaluationRowStatus.final_);
        expect(byEvaluatorId[_eval2]!.ackTags, ['beta']);
        expect(byEvaluatorId[_eval2]!.status, BeaconEvaluationRowStatus.final_);
        final cross = await repo.listFinalizedEvaluationsBetween(
          evaluatorId: _eval1,
          evaluatedUserId: _subject,
        );
        expect(cross.map((row) => row.beaconId), [_beacon2, _beacon1]);
        expect(cross.map((row) => row.ackTags), [
          ['gamma'],
          ['alpha', 'zeta'],
        ]);
        await writer.execute(
          "UPDATE public.beacon SET status = 0 WHERE id IN ('$_beacon1', '$_beacon2')",
        );
      },
      skip: skipReason,
    );

    test(
      'empty ack tags succeeds and leaves zero ack rows',
      () async {
        await repo.submitEvaluationAtomic(
          beaconId: _beacon1,
          evaluatorId: _eval1,
          evaluatedUserId: _subject,
          value: 4,
          reasonTags: const ['ok'],
          note: 'forwarder path',
          ackTags: const ['transport'],
        );

        await repo.submitEvaluationAtomic(
          beaconId: _beacon1,
          evaluatorId: _eval1,
          evaluatedUserId: _subject,
          value: 4,
          reasonTags: const ['ok'],
          note: 'forwarder path',
          ackTags: const [],
        );

        final count = await _ackTagCount(writer, _beacon1, _eval1, _subject);
        expect(count, 0);
      },
      skip: skipReason,
    );

    test(
      'serializes concurrent submits for the same beacon across evaluators',
      () async {
        final db1 = TenturaDb(target.databaseEnv);
        final db2 = TenturaDb(target.databaseEnv);
        final repo1 = EvaluationRepository(db1);
        final repo2 = EvaluationRepository(db2);

        try {
          await Future.wait([
            repo1.submitEvaluationAtomic(
              beaconId: _beacon1,
              evaluatorId: _eval1,
              evaluatedUserId: _subject,
              value: 4,
              reasonTags: const ['a'],
              note: 'e1',
              ackTags: const ['transport'],
            ),
            repo2.submitEvaluationAtomic(
              beaconId: _beacon1,
              evaluatorId: _eval2,
              evaluatedUserId: _subject,
              value: 5,
              reasonTags: const ['b'],
              note: 'e2',
              ackTags: const ['pets'],
            ),
          ]);

          expect(
            await _ackTagsForTriple(writer, _beacon1, _eval1, _subject),
            ['transport'],
          );
          expect(
            await _ackTagsForTriple(writer, _beacon1, _eval2, _subject),
            ['pets'],
          );
        } finally {
          await db1.close();
          await db2.close();
        }
      },
      skip: skipReason,
    );

    test(
      'rejects more than three ack tags inside the advisory lock',
      () async {
        expect(
          () => repo.submitEvaluationAtomic(
            beaconId: _beacon1,
            evaluatorId: _eval1,
            evaluatedUserId: _subject,
            value: 4,
            reasonTags: const ['ok'],
            note: 'cap',
            ackTags: const [
              'transport',
              'pets',
              'manual_labour',
              'overflow',
            ],
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Ack tag cap exceeded',
            ),
          ),
        );
        expect(
          await _ackTagCount(writer, _beacon1, _eval1, _subject),
          0,
        );
      },
      skip: skipReason,
    );

    test(
      'allows different evaluators each to submit three ack tags for same subject',
      () async {
        await repo.submitEvaluationAtomic(
          beaconId: _beacon1,
          evaluatorId: _eval1,
          evaluatedUserId: _subject,
          value: 4,
          reasonTags: const ['e1'],
          note: 'n1',
          ackTags: const ['transport', 'pets', 'manual_labour'],
        );
        await repo.submitEvaluationAtomic(
          beaconId: _beacon1,
          evaluatorId: _eval2,
          evaluatedUserId: _subject,
          value: 5,
          reasonTags: const ['e2'],
          note: 'n2',
          ackTags: const ['transport', 'pets', 'manual_labour'],
        );

        expect(
          await _ackTagCount(writer, _beacon1, _eval1, _subject),
          3,
        );
        expect(
          await _ackTagCount(writer, _beacon1, _eval2, _subject),
          3,
        );
      },
      skip: skipReason,
    );

    test(
      'resolver reads clear state after a competing submit waits on the lock',
      () async {
        await repo.submitEvaluationAtomic(
          beaconId: _beacon1,
          evaluatorId: _eval1,
          evaluatedUserId: _subject,
          value: 4,
          reasonTags: const ['clear_request'],
          note: 'before clear',
          ackTags: const ['transport'],
        );

        final blockerDb = TenturaDb(target.databaseEnv);
        final competingDb = TenturaDb(target.databaseEnv);
        final competingRepo = EvaluationRepository(competingDb);
        final blockerReady = Completer<void>();
        final releaseBlocker = Completer<void>();
        final competingResolverCalled = Completer<void>();
        final releaseCompeting = Completer<void>();
        final resolverCalled = Completer<BeaconEvaluationRecord?>();
        try {
          unawaited(
            blockerDb.transaction(() async {
              await blockerDb.customStatement(
                r'SELECT pg_advisory_xact_lock(hashtextextended($1, 4242))',
                [_beacon1],
              );
              blockerReady.complete();
              await releaseBlocker.future;
            }),
          );
          await blockerReady.future;

          final competingClear = competingRepo.submitEvaluationAtomic(
            beaconId: _beacon1,
            evaluatorId: _eval1,
            evaluatedUserId: _subject,
            value: 5,
            reasonTags: const [],
            note: 'explicit clear',
            ackTags: const [],
            resolve: (existing) async {
              expect(existing?.reasonTags, 'clear_request');
              expect(existing?.ackTags, ['transport']);
              competingResolverCalled.complete();
              await releaseCompeting.future;
              return const EvaluationWriteCommand(
                value: 5,
                reasonTags: [],
                note: 'explicit clear',
                ackTags: [],
              );
            },
          );
          releaseBlocker.complete();
          await competingResolverCalled.future;

          final pending = repo.submitEvaluationAtomic(
            beaconId: _beacon1,
            evaluatorId: _eval1,
            evaluatedUserId: _subject,
            value: 5,
            reasonTags: const [],
            note: 'after clear',
            ackTags: const [],
            resolve: (existing) {
              resolverCalled.complete(existing);
              return EvaluationWriteCommand(
                value: 5,
                reasonTags: existing == null
                    ? const []
                    : existing.reasonTags.isEmpty
                    ? const []
                    : existing.reasonTags.split(','),
                note: 'after clear',
                ackTags: existing?.ackTags ?? const [],
              );
            },
          );

          await Future<void>.delayed(const Duration(milliseconds: 25));
          expect(resolverCalled.isCompleted, isFalse);
          releaseCompeting.complete();
          await competingClear;
          final resolved = await resolverCalled.future;
          expect(resolved?.reasonTags, isEmpty);
          expect(resolved?.ackTags, isEmpty);
          await pending;

          final finalRow = await repo.getEvaluation(
            beaconId: _beacon1,
            evaluatorId: _eval1,
            evaluatedUserId: _subject,
          );
          expect(finalRow!.reasonTags, isEmpty);
          expect(finalRow.ackTags, isEmpty);
        } finally {
          if (!releaseBlocker.isCompleted) releaseBlocker.complete();
          if (!releaseCompeting.isCompleted) releaseCompeting.complete();
          await competingDb.close();
          await blockerDb.close();
        }
      },
      skip: skipReason,
    );

    test(
      'beacon advisory lock does not block concurrent submits on different beacons',
      () async {
        final blockerDb = TenturaDb(target.databaseEnv);
        final releaseBlocker = Completer<void>();
        final blockerReady = Completer<void>();

        try {
          unawaited(
            blockerDb.transaction(() async {
              await blockerDb.customStatement(
                r'SELECT pg_advisory_xact_lock(hashtextextended($1, 4242))',
                [_beacon1],
              );
              blockerReady.complete();
              await releaseBlocker.future;
            }),
          );
          await blockerReady.future;

          await repo.submitEvaluationAtomic(
            beaconId: _beacon2,
            evaluatorId: _eval1,
            evaluatedUserId: _subject,
            value: 4,
            reasonTags: const ['other'],
            note: 'other beacon',
            ackTags: const ['pets'],
          );

          expect(
            await _ackTagsForTriple(writer, _beacon2, _eval1, _subject),
            ['pets'],
          );
        } finally {
          if (!releaseBlocker.isCompleted) {
            releaseBlocker.complete();
          }
          await blockerDb.close();
        }
      },
      skip: skipReason,
    );
  });
}

Future<List<String>> _ackTagsForTriple(
  Connection writer,
  String beaconId,
  String evaluatorId,
  String subjectId,
) async {
  final rows = await writer.execute(
    "SELECT tag_slug FROM public.beacon_evaluation_ack_tag "
    "WHERE beacon_id = '$beaconId' "
    "AND evaluator_id = '$evaluatorId' "
    "AND subject_id = '$subjectId' "
    "ORDER BY tag_slug",
  );
  return rows.map((r) => r[0]! as String).toList();
}

Future<int> _ackTagCount(
  Connection writer,
  String beaconId,
  String evaluatorId,
  String subjectId,
) async {
  final rows = await writer.execute(
    "SELECT count(*)::int FROM public.beacon_evaluation_ack_tag "
    "WHERE beacon_id = '$beaconId' "
    "AND evaluator_id = '$evaluatorId' "
    "AND subject_id = '$subjectId'",
  );
  return rows.single.single! as int;
}

Future<void> _seedFixture(Connection writer) async {
  await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Ucapc1aeval01', 'Evaluator 1', 'pk-e1'),
  ('Ucapc1aeval02', 'Evaluator 2', 'pk-e2'),
  ('Ucapc1asubj01', 'Subject', 'pk-sub'),
  ('Ucapc1aauth01', 'Author', 'pk-auth')
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon (id, user_id, title, description)
VALUES
  ('Bcapc1abcn01', 'Ucapc1aauth01', 'Beacon 1', 'd'),
  ('Bcapc1abcn02', 'Ucapc1aauth01', 'Beacon 2', 'd')
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon_review_window (
  beacon_id, opened_at, closes_at, status
) VALUES
  (
    'Bcapc1abcn01',
    now() - interval '1 day',
    now() + interval '7 days',
    0
  ),
  (
    'Bcapc1abcn02',
    now() - interval '1 day',
    now() + interval '7 days',
    0
  )
ON CONFLICT (beacon_id) DO UPDATE SET
  opened_at = EXCLUDED.opened_at,
  closes_at = EXCLUDED.closes_at,
  status = EXCLUDED.status
''');
}
