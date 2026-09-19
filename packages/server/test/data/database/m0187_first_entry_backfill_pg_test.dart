@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// U10d — the m0187 backfill path U10c's verify found untested.
///
/// m0187's second backfill statement is the clock correction the migration
/// exists for:
///
/// ```sql
/// SET first_entry_at = LEAST(state.first_entry_at, ii.latest_forward_at)
/// ```
///
/// It only fires when the forward **predates** the instant the state row was
/// written — exactly the shape m0184's writer produced, since that writer
/// stamped `now()` rather than the forward time. Nothing exercised it, so the
/// tests below stage a pre-m0187 schema, write the two histories m0187's
/// doc-comment names as holes 1 and 2, then apply m0187's own statements and
/// read the anchor back.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0187_BACKFILL_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0187',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late Connection writer;

  if (reachable) {
    setUp(() async {
      // The schema one step before m0187, so the migration under test is the
      // only thing that has touched `first_entry_at`.
      session = await setUpDisposablePgWriter(
        target: target,
        lastInclusiveVersion: '0186',
      );
      writer = session.writer;
      await _seedPeopleAndBeacon(writer);
    });

    tearDown(() async {
      await tearDownDisposablePgWriter(session: session);
    });
  }

  test(
    'hole 2 — a state row anchored at its write instant is pulled back to the '
    'forward that predates it',
    () async {
      // m0184's writer: the inbox row arrives, the trigger stamps `now()`.
      await _insertInbox(writer, latestForwardAt: _forwardAt);
      final before = await _anchor(writer);
      expect(
        before,
        isNotNull,
        reason: 'the pre-m0187 trigger must have written a row to correct',
      );
      expect(
        before!.isAfter(DateTime.parse(_forwardAt)),
        isTrue,
        reason:
            'the fixture is only meaningful while the write instant is later '
            'than the forward — otherwise LEAST has nothing to do',
      );

      await _applyM0187(writer);

      expect(
        await _anchor(writer),
        DateTime.parse(_forwardAt),
        reason:
            'the anchor is when the Request arrived, not when the database '
            'noticed it (D08)',
      );
    },
    skip: skipReason,
  );

  test(
    'hole 2 never walks an anchor forward, so the backfill is re-runnable',
    () async {
      await _insertInbox(writer, latestForwardAt: _forwardAt);
      await _applyM0187(writer);
      final first = await _anchor(writer);

      // A re-forward bumps `latest_forward_at` into the future of the anchor;
      // re-running the backfill must leave the anchor where it is.
      await writer.execute(
        Sql.named(
          'UPDATE public.inbox_item SET latest_forward_at = @at '
          'WHERE user_id = @user AND beacon_id = @beacon',
        ),
        parameters: {
          'at': DateTime.parse(_laterForwardAt),
          'user': _viewerId,
          'beacon': _beaconId,
        },
      );
      await _applyBackfillOnly(writer);

      expect(
        await _anchor(writer),
        first,
        reason: 'LEAST only ever moves the anchor downwards',
      );
    },
    skip: skipReason,
  );

  test(
    'hole 1 — an inbox row with no state row at all gets one at its forward',
    () async {
      await _insertInbox(writer, latestForwardAt: _forwardAt);
      // The pre-m0184 shape: an inbox row that never had a state row.
      await writer.execute('DELETE FROM public.attention_request_state');
      expect(await _anchor(writer), isNull);

      await _applyM0187(writer);

      expect(await _anchor(writer), DateTime.parse(_forwardAt));
    },
    skip: skipReason,
  );
}

const _viewerId = 'Um0187bf01';
const _authorId = 'Um0187bf02';
const _beaconId = 'Bm0187bf01';

/// Comfortably before any `now()` this test can observe.
const _forwardAt = '2025-01-02T03:04:05Z';
const _laterForwardAt = '2030-01-02T03:04:05Z';

Future<void> _applyM0187(Connection writer) async {
  for (final statement in m0187.statements) {
    await writer.execute(statement);
  }
}

/// Just the hole-2 `UPDATE`, for the re-run assertion.
Future<void> _applyBackfillOnly(Connection writer) async {
  await writer.execute(
    m0187.statements.firstWhere(
      (statement) => statement.contains('SET first_entry_at = LEAST('),
    ),
  );
}

Future<DateTime?> _anchor(Connection writer) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT first_entry_at FROM public.attention_request_state '
      'WHERE account_id = @user AND beacon_id = @beacon',
    ),
    parameters: {'user': _viewerId, 'beacon': _beaconId},
  );
  if (rows.isEmpty) return null;
  return (rows.first.first as DateTime?)?.toUtc();
}

Future<void> _insertInbox(
  Connection writer, {
  required String latestForwardAt,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (@user, @beacon, 0, 1, @at, '', '')
'''),
  parameters: {
    'user': _viewerId,
    'beacon': _beaconId,
    'at': DateTime.parse(latestForwardAt),
  },
);

Future<void> _seedPeopleAndBeacon(Connection writer) async {
  for (final id in [_viewerId, _authorId]) {
    await writer.execute(
      Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @id, @key)',
      ),
      parameters: {'id': id, 'key': '$id-key'},
    );
  }
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@beacon, @author, 'Backfill', 'Backfill request', 0)
'''),
    parameters: {'beacon': _beaconId, 'author': _authorId},
  );
}
