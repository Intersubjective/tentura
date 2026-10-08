@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/discoverable_candidate_index_sql.dart';
import '../../support/pg_test_public_keys.dart';

const _legacyIndex = 'beacon_discoverable_author_idx';
Future<void> main() async {
  final migrations = migrationsForTesting;
  final additions = migrations
      .where(
        (migration) => migration.statements.any(
          (statement) => discoverableCandidateIndexNames(statement).isNotEmpty,
        ),
      )
      .toList();
  final candidatePosition = additions.isEmpty
      ? -1
      : migrations.indexOf(additions.first);
  // Before the index exists, the current head is the schema it must upgrade.
  // Once registered, use its actual predecessor even if later migrations land.
  final previousVersion =
      migrations[candidatePosition > 0
              ? candidatePosition - 1
              : migrations.length - 1]
          .version;
  final upgradeVersion = candidatePosition < 0
      ? migrations.last.version
      : migrations[candidatePosition].version;

  test('registers a new partial author and Request key index migration', () {
    expect(
      additions,
      hasLength(1),
      reason:
          'A new registered migration after $previousVersion must add '
          'the partial beacon (user_id, id) index; the shipped author-only '
          'index in m0193 must remain unchanged.',
    );
    expect(
      candidatePosition,
      greaterThan(0),
      reason: 'The candidate index must have a registered predecessor',
    );
    expect(
      additions.single.version.compareTo(previousVersion),
      greaterThan(0),
      reason:
          'The candidate index must follow its predecessor in registry order',
    );
  });

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_DISCOVERABLE_CANDIDATES_INDEX_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_discoverable_index',
  );
  final skipReason = await pgSkipReason(target);

  group('discoverable candidate index schema upgrade', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
        lastInclusiveVersion: previousVersion,
      );
      writer = session.writer;
      final initialVersion = await writer.execute(
        'SELECT max(version) FROM schema_version',
      );
      expect(
        initialVersion.single.single,
        previousVersion,
        reason:
            'The disposable database must start at the predecessor, not head',
      );
      final existingCandidateIndexes = await _candidateIndexes(writer);
      expect(
        existingCandidateIndexes,
        isEmpty,
        reason:
            'The predecessor must not already contain the new candidate index',
      );

      for (var slot = 1; slot <= 2; slot++) {
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
          parameters: {
            'id': 'Udiscoverableindex$slot',
            'key': pgTestPublicKey('discoverable_index', slot),
          },
        );
      }
      // Include every lifecycle state, unpublished Requests and
      // non-discoverable Requests. Both author and id affect index ordering.
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, status, is_discoverable, published_at)
SELECT 'Bindex' || author || status || discoverable || published,
       'Udiscoverableindex' || author, 'index fixture', '', 0, status,
       discoverable = 1,
       CASE WHEN published = 1 THEN '2026-01-01'::timestamptz END
FROM generate_series(1, 2) author
CROSS JOIN generate_series(0, 8) status
CROSS JOIN generate_series(0, 1) discoverable
CROSS JOIN generate_series(0, 1) published
WHERE status <> 4
''');
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, status, is_discoverable, published_at)
VALUES ('Bindexpost', 'Udiscoverableindex1', '', '', 1, 0, false,
        '2026-01-01'::timestamptz)
''');
      // Evaluate the catalog predicate independently of the Post shape guard.
      // Valid Posts are always non-discoverable; this truth table also proves
      // that kind itself is part of the predicate rather than incidental data.
      await writer.execute('''
CREATE TEMP TABLE candidate_predicate_fixture AS
SELECT 'Bpredicate' || author || kind || status || discoverable || published AS id,
       'Udiscoverableindex' || author AS user_id, kind, status,
       discoverable = 1 AS is_discoverable,
       CASE WHEN published = 1 THEN '2026-01-01'::timestamptz END AS published_at
FROM generate_series(1, 2) author
CROSS JOIN generate_series(0, 1) kind
CROSS JOIN generate_series(0, 8) status
CROSS JOIN generate_series(0, 1) discoverable
CROSS JOIN generate_series(0, 1) published
''');
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('upgrading preserves rows and the legacy author index and indexes '
        'exactly the published discoverable Request lifecycle union', () async {
      final before = await _beaconRows(writer);
      final oldIndexBefore = await writer.execute(
        Sql.named(
          'SELECT indexdef FROM pg_indexes '
          "WHERE schemaname = 'public' AND indexname = @name",
        ),
        parameters: {'name': _legacyIndex},
      );
      expect(oldIndexBefore, hasLength(1));

      await migrateDbSchemaThrough(writer, upgradeVersion);

      expect(await _beaconRows(writer), before);
      final oldIndexAfter = await writer.execute(
        Sql.named(
          'SELECT indexdef FROM pg_indexes '
          "WHERE schemaname = 'public' AND indexname = @name",
        ),
        parameters: {'name': _legacyIndex},
      );
      expect(
        oldIndexAfter,
        hasLength(1),
        reason: 'Preserve the shipped author-only benchmark index',
      );
      expect(
        oldIndexAfter.single.single,
        oldIndexBefore.single.single,
        reason:
            'The upgrade must leave the shipped author-only index definition unchanged',
      );
      final indexes = await _candidateIndexes(writer);
      expect(
        indexes,
        hasLength(1),
        reason:
            'Upgrade must add the partial '
            'ordered candidate index, not rely on the old author-only index.',
      );
      final index = indexes.single;
      expect(index[2], isTrue, reason: 'Index must be valid after upgrade');
      expect(index[3], isTrue, reason: 'Index must be ready after upgrade');
      final predicate = index[1]! as String;
      final indexedRows = await writer.execute(
        'SELECT id FROM candidate_predicate_fixture WHERE $predicate '
        'ORDER BY user_id, id',
      );
      final expectedRows = await writer.execute('''
SELECT id FROM candidate_predicate_fixture
WHERE kind = 0 AND is_discoverable AND published_at IS NOT NULL
  AND status IN (0, 4, 5, 6, 7, 8)
ORDER BY user_id, id
''');
      expect(expectedRows, hasLength(12));
      expect(
        indexedRows,
        expectedRows,
        reason:
            'The partial predicate must '
            'cover open and showClosed Requests, while excluding Posts, '
            'unpublished, undiscoverable and dormant lifecycle rows.',
      );

      // Verify both supported lifecycle variants imply the catalog predicate.
      for (final statuses in ['0,7,8', '0,4,5,6,7,8']) {
        final uncovered = await writer.execute('''
SELECT id FROM candidate_predicate_fixture
WHERE kind = 0 AND is_discoverable AND published_at IS NOT NULL
  AND status IN ($statuses) AND NOT ($predicate)
''');
        expect(
          uncovered,
          isEmpty,
          reason:
              'Query lifecycle $statuses must '
              'imply the partial-index predicate.',
        );
      }

      // Normal migration replay must neither duplicate the index nor alter data.
      await migrateDbSchemaThrough(writer, upgradeVersion);
      expect(await _beaconRows(writer), before);
      final version = await writer.execute(
        'SELECT max(version) FROM schema_version',
      );
      expect(version.single.single, upgradeVersion);
    });
  }, skip: skipReason ?? false);
}

Future<List<List<Object?>>> _beaconRows(Connection writer) async =>
    (await writer.execute(
      'SELECT * FROM public.beacon ORDER BY id',
    )).map((row) => row.toList()).toList();

Future<Result> _candidateIndexes(Connection writer) => writer.execute('''
SELECT c.relname, pg_get_expr(i.indpred, i.indrelid), i.indisvalid,
       i.indisready
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_am am ON am.oid = c.relam
JOIN pg_attribute author_key
  ON author_key.attrelid = i.indrelid AND author_key.attnum = i.indkey[0]
JOIN pg_attribute request_key
  ON request_key.attrelid = i.indrelid AND request_key.attnum = i.indkey[1]
WHERE i.indrelid = 'public.beacon'::regclass
  AND am.amname = 'btree' AND i.indpred IS NOT NULL
  AND i.indnkeyatts = 2
  AND author_key.attname = 'user_id' AND request_key.attname = 'id'
''');
