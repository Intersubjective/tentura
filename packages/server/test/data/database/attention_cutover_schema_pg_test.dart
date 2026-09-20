@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

/// U18a — `m0192`, the cutover singleton.
///
/// Three properties, each proven by a write the database must refuse rather
/// than by reading the catalogue: the row is a singleton, `cutover_at` is
/// immutable, and the progress columns beside it are not.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U18A_SCHEMA_TEST_DB',
    defaultNamePrefix: 'tentura_test_u18a_schema',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('attention_cutover', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public.attention_cutover');
    });

    test('takes one row and refuses a second', () async {
      await writer.execute(
        "INSERT INTO public.attention_cutover (cutover_at) "
        "VALUES ('2026-09-20T12:00:00Z')",
      );

      // The singleton is enforced by the primary key on a `true`-only boolean,
      // which is what makes `ON CONFLICT (id) DO NOTHING` the whole of
      // "write it once" for two isolates booting at the same moment.
      await expectLater(
        writer.execute(
          "INSERT INTO public.attention_cutover (cutover_at) "
          "VALUES ('2026-09-20T13:00:00Z')",
        ),
        throwsA(
          isA<ServerException>().having(
            (error) => error.constraintName,
            'constraintName',
            'attention_cutover_pkey',
          ),
        ),
      );

      final rows = await writer.execute(
        'SELECT cutover_at FROM public.attention_cutover',
      );
      expect(rows, hasLength(1));
      expect(
        (rows.first.first! as DateTime).toUtc(),
        DateTime.utc(2026, 9, 20, 12),
      );
    });

    test('refuses to move cutover_at', () async {
      await writer.execute(
        "INSERT INTO public.attention_cutover (cutover_at) "
        "VALUES ('2026-09-20T12:00:00Z')",
      );

      // The mutation this exists to catch: a restart that re-stamps the
      // boundary instead of resuming against it. A re-stamped boundary
      // silently redefines which receipts are legacy.
      await expectLater(
        writer.execute(
          'UPDATE public.attention_cutover SET cutover_at = now()',
        ),
        throwsA(
          isA<ServerException>().having(
            (error) => error.message,
            'message',
            contains('cutover_at is immutable'),
          ),
        ),
      );

      final rows = await writer.execute(
        'SELECT cutover_at FROM public.attention_cutover',
      );
      expect(
        (rows.first.first! as DateTime).toUtc(),
        DateTime.utc(2026, 9, 20, 12),
      );
    });

    test('lets the progress columns beside it move', () async {
      // The immutability guard must be narrow: every restart updates this very
      // row to advance the cursor. A trigger that refused all updates would
      // pass the test above and break the backfill.
      await writer.execute(
        "INSERT INTO public.attention_cutover (cutover_at) "
        "VALUES ('2026-09-20T12:00:00Z')",
      );

      await writer.execute(
        "UPDATE public.attention_cutover "
        "SET legacy_seen_cursor = 'Nu18a007', "
        "    legacy_seen_completed_at = '2026-09-20T12:05:00Z'",
      );

      final rows = await writer.execute(
        'SELECT cutover_at, legacy_seen_cursor, legacy_seen_completed_at '
        'FROM public.attention_cutover',
      );
      expect(
        (rows.first[0]! as DateTime).toUtc(),
        DateTime.utc(2026, 9, 20, 12),
      );
      expect(rows.first[1], 'Nu18a007');
      expect(rows.first[2], isNotNull);
    });

    // U18b — m0193. Each deferred gate advances on its own, because either can
    // be interrupted while the other has not started, and neither may drag the
    // boundary with it.
    test('carries an independent cursor for each deferred gate', () async {
      await writer.execute(
        "INSERT INTO public.attention_cutover (cutover_at) "
        "VALUES ('2026-09-20T12:00:00Z')",
      );

      await writer.execute(
        "UPDATE public.attention_cutover "
        "SET obligation_key_cursor = 'Nu18b007', "
        "    obligation_key_completed_at = '2026-09-20T12:06:00Z'",
      );
      await writer.execute(
        "UPDATE public.attention_cutover "
        "SET placement_cursor = 'Nu18b009'",
      );

      final rows = await writer.execute(
        'SELECT cutover_at, obligation_key_cursor, '
        '       obligation_key_completed_at, placement_cursor, '
        '       placement_completed_at '
        'FROM public.attention_cutover',
      );
      expect(
        (rows.first[0]! as DateTime).toUtc(),
        DateTime.utc(2026, 9, 20, 12),
        reason: 'the gates advance against the boundary, never move it',
      );
      expect(rows.first[1], 'Nu18b007');
      expect(rows.first[2], isNotNull);
      expect(rows.first[3], 'Nu18b009');
      expect(
        rows.first[4],
        isNull,
        reason: 'one gate finishing says nothing about the other',
      );
    });
  }, skip: skipReason);
}
