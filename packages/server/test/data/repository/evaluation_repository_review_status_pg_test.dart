@Tags(['pg'])
library;

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
