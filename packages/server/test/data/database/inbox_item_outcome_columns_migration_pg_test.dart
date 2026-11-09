@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// The last migration that had shipped before the forward-row outcome tick.
/// The outcome columns must come from a migration after it: a shipped
/// migration is never edited.
const _lastShippedVersion = 300;

const _viewer = 'Uoutcolsview';
const _author = 'Uoutcolsauth';
const _watchedRequest = 'Boutcolswatch';
const _pendingRequest = 'Boutcolspend';
const _closedRequest = 'Boutcolsclose';

const _outcomeColumns = [
  'outcome_changed_at',
  'outcome_changed_by',
  'outcome_seen_at',
];

Future<void> main() async {
  final adding = migrationsForTesting
      .where(
        (migration) => migration.statements.any(
          (statement) =>
              statement.contains('inbox_item') &&
              statement.contains('outcome_changed_at'),
        ),
      )
      .toList();

  test(
    'one new migration, after every shipped one, adds the forward outcome '
    'columns to inbox_item',
    () {
      expect(
        adding,
        hasLength(1),
        reason: 'exactly one registered migration adds outcome_changed_at',
      );
      expect(
        int.parse(adding.single.version),
        greaterThan(_lastShippedVersion),
        reason:
            'shipped migrations stay as shipped; the columns need a new one',
      );
    },
  );

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_INBOX_OUTCOME_COLUMNS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_inbox_outcome_cols',
  );
  final pgSkip = await pgSkipReason(target);

  // The schema the rows below are written on: everything before the
  // migration that adds the columns (head, while that migration is missing).
  final all = migrationsForTesting;
  final addingIndex = adding.length == 1 ? all.indexOf(adding.single) : -1;
  final previousVersion = addingIndex > 0
      ? all[addingIndex - 1].version
      : all.last.version;

  group(
    'inbox rows that existed before the outcome columns',
    () {
      late DisposablePgWriterSession session;
      late Connection writer;
      late List<List<Object?>> rowsBefore;

      setUpAll(() async {
        session = await setUpDisposablePgWriter(
          target: target,
          lastInclusiveVersion: previousVersion,
        );
        writer = session.writer;
        await _seed(writer);
        rowsBefore = await _inboxRows(writer);
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session);
      });

      test(
        'after migrating to head the three columns are nullable, typed, and '
        'NULL on every pre-existing row',
        () async {
          expect(
            {for (final r in rowsBefore) r[1]: r[2]},
            {_closedRequest: 3, _pendingRequest: 0, _watchedRequest: 1},
            reason:
                'closed-before-response (3, written by the beacon close '
                'trigger), pending (0) and watching (1) rows exist before '
                'the migration',
          );
          expect(
            adding,
            hasLength(1),
            reason: 'no migration adds the outcome columns yet',
          );

          await migrateDbSchemaThrough(writer, all.last.version);

          final columns = await writer.execute('''
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'inbox_item'
  AND column_name IN (
    'outcome_changed_at', 'outcome_changed_by', 'outcome_seen_at'
  )
ORDER BY column_name
''');
          expect(
            [
              for (final c in columns) [c[0], c[1], c[2]],
            ],
            [
              ['outcome_changed_at', 'timestamp with time zone', 'YES'],
              ['outcome_changed_by', 'text', 'YES'],
              ['outcome_seen_at', 'timestamp with time zone', 'YES'],
            ],
          );

          expect(
            await _inboxRows(writer),
            rowsBefore,
            reason: 'the migration leaves the existing rows as they were',
          );
          final outcomes = await writer.execute('''
SELECT beacon_id, ${_outcomeColumns.join(', ')}
FROM public.inbox_item
ORDER BY beacon_id
''');
          expect(outcomes, hasLength(rowsBefore.length));
          for (final row in outcomes) {
            expect(
              row.sublist(1),
              [null, null, null],
              reason:
                  'pre-existing row ${row[0]} is not backfilled: no relabel '
                  'is known for it, so it carries no tick',
            );
          }
        },
      );
    },
    skip: pgSkip,
  );
}

Future<List<List<Object?>>> _inboxRows(Connection writer) async => [
  for (final row in await writer.execute('''
SELECT user_id, beacon_id, status, latest_forward_at
FROM public.inbox_item
ORDER BY beacon_id
'''))
    row.toList(),
];

Future<void> _seed(Connection writer) async {
  for (final id in [_viewer, _author]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': '$id-key'},
    );
  }
  for (final id in [_watchedRequest, _pendingRequest, _closedRequest]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @author, @id, 'Request', 0)
'''),
      parameters: {'id': id, 'author': _author},
    );
  }
  for (final (beaconId, status) in [
    (_watchedRequest, 1),
    (_pendingRequest, 0),
    (_closedRequest, 0),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (
  @u, @b, @status, 1, CAST('2026-08-01T10:00:00Z' AS timestamptz), '', ''
)
'''),
      parameters: {'u': _viewer, 'b': beaconId, 'status': status},
    );
  }
  // The author closes one Request. The beacon trigger
  // (beacon_apply_inbox_before_response_tombstone, m0213) relabels the
  // viewer's pending row to 3 = closed-before-response, before the outcome
  // columns exist. inbox_item refuses a direct write of status 3.
  await writer.execute(
    Sql.named('UPDATE public.beacon SET status = 6 WHERE id = @id'),
    parameters: {'id': _closedRequest},
  );
}
