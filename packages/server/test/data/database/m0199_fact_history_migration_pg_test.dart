@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// `m0199` adds fact history: `beacon_fact_card_revision`, provenance columns,
/// the quote FK behaviour, H1–H3 indexes, and a backfill of one imported or
/// created revision per existing fact.
///
/// Each fixture seeds a database at `0198` with facts in every status, then
/// runs the registry forward. The guard fixture is a separate database because
/// the migration must fail on it.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0199_FACT_HISTORY_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0199',
  );
  final guardTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0199_FACT_HISTORY_GUARD_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0199_guard',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('backfill', () {
    late DisposablePgWriterSession session;
    Connection writer() => session.writer;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(
          target: target,
          lastInclusiveVersion: '0198',
        );
        await _seedUsersAndBeacon(session.writer, _beaconId);
        await _seedBeacon(session.writer, _deleteBeaconId);
        for (final statement in _seedStatements) {
          await session.writer.execute(statement);
        }
        await migrateDbSchema(session.writer);
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session);
      });
    }

    test(
      'the registry now reaches 0201',
      () async {
        final rows = await writer().execute(
          'SELECT max(version COLLATE "C") FROM schema_version',
        );
        // m0199 seeds history; m0200 attachments_json; m0201 MR weight clamp is the tip.
        expect(rows.single.single, '0201');
      },
      skip: skipReason,
    );

    test(
      'backfills exactly one revision per fact',
      () async {
        final rows = await writer().execute('''
SELECT f.id, count(r.*)::int
FROM public.beacon_fact_card f
LEFT JOIN public.beacon_fact_card_revision r ON r.fact_card_id = f.id
GROUP BY f.id
ORDER BY f.id
''');
        final counts = {for (final r in rows) r[0]! as String: r[1]! as int};
        expect(counts, {
          _activeFactId: 1,
          _correctedFactId: 1,
          _removedFactId: 1,
          _quotedFactId: 1,
        });
      },
      skip: skipReason,
    );

    test(
      'an active fact gets a created revision by its pinner at its creation time',
      () async {
        final row = (await writer().execute(
          Sql.named('''
SELECT r.kind, r.actor_id, r.fact_text,
       r.created_at = f.created_at AS same_created_at
FROM public.beacon_fact_card_revision r
JOIN public.beacon_fact_card f ON f.id = r.fact_card_id
WHERE r.fact_card_id = @id
'''),
          parameters: {'id': _activeFactId},
        )).single;
        expect(row[0], BeaconFactCardRevisionKindBits.created);
        expect(row[1], _pinnerId);
        expect(row[2], 'Active fact text');
        expect(row[3], isTrue);
      },
      skip: skipReason,
    );

    test(
      'corrected and removed facts get an imported revision with no actor',
      () async {
        final rows = await writer().execute(
          Sql.named('''
SELECT fact_card_id, kind, actor_id
FROM public.beacon_fact_card_revision
WHERE fact_card_id IN (@corrected, @removed)
ORDER BY fact_card_id
'''),
          parameters: {
            'corrected': _correctedFactId,
            'removed': _removedFactId,
          },
        );
        expect(rows, hasLength(2));
        for (final row in rows) {
          expect(
            row[1],
            BeaconFactCardRevisionKindBits.imported,
            reason: '${row[0]} kind',
          );
          expect(row[2], isNull, reason: '${row[0]} actor');
        }
      },
      skip: skipReason,
    );

    test(
      'history_truncated is true exactly for corrected facts',
      () async {
        final truncated = await _historyTruncatedByFact(writer());
        expect(truncated, {
          _activeFactId: false,
          _correctedFactId: true,
          _removedFactId: false,
          _quotedFactId: false,
        });
      },
      skip: skipReason,
    );

    test(
      'fact pinned and visibility events get fact_card_id from diff.factCardId',
      () async {
        final rows = await writer().execute('''
SELECT id, fact_card_id
FROM public.beacon_activity_event
WHERE id IN ('$_pinnedEventId', '$_visibilityEventId', '$_danglingEventId')
ORDER BY id
''');
        final byId = {for (final r in rows) r[0]! as String: r[1] as String?};
        expect(byId, {
          _pinnedEventId: _activeFactId,
          _visibilityEventId: _correctedFactId,
          _danglingEventId: null,
        });
      },
      skip: skipReason,
    );

    test(
      'a revision whose fact_text is only whitespace violates the CHECK',
      () async {
        // Each insert targets a fresh fact with no revisions yet, so any
        // (fact_card_id, …) key is free; a standalone `id` column gets a
        // fresh value too. Every other required column is copied from a
        // backfilled row, so only fact_text differs between the valid
        // control insert and the whitespace one.
        Future<void> insertRevision(String factId, String text) async {
          await writer().execute(
            Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status)
VALUES (@fact, @beacon, 'Fresh fact', 0, @pinner, 0)
'''),
            parameters: {
              'fact': factId,
              'beacon': _beaconId,
              'pinner': _pinnerId,
            },
          );
          await writer().execute(
            Sql.named('''
INSERT INTO public.beacon_fact_card_revision
SELECT (jsonb_populate_record(
  NULL::public.beacon_fact_card_revision,
  to_jsonb(r) || jsonb_build_object(
    'id', 'X' || @fact,
    'fact_card_id', @fact,
    'fact_text', @text::text,
    'created_at', now()
  )
)).*
FROM public.beacon_fact_card_revision r
WHERE r.fact_card_id = @template
'''),
            parameters: {
              'fact': factId,
              'text': text,
              'template': _activeFactId,
            },
          );
        }

        await insertRevision('Ff199chk1', 'Fresh fact');
        final control = await writer().execute(
          'SELECT count(*)::int FROM public.beacon_fact_card_revision '
          "WHERE fact_card_id = 'Ff199chk1'",
        );
        expect(control.single.single, 1, reason: 'valid text is accepted');

        await expectLater(
          insertRevision('Ff199chk2', '  '),
          throwsA(
            isA<ServerException>().having(
              (e) => e.code,
              'code',
              '23514',
            ),
          ),
        );
      },
      skip: skipReason,
    );

    // Last: it deletes a beacon from the shared fixture.
    test(
      'deleting a beacon whose fact is quoted by a message succeeds',
      () async {
        final before = await writer().execute(
          Sql.named(
            'SELECT count(*)::int FROM public.beacon_fact_card_revision '
            'WHERE fact_card_id = @id',
          ),
          parameters: {'id': _quotedFactId},
        );
        expect(before.single.single, 1);

        // Quote revision 1 from a message on the surviving beacon (so the
        // beacon delete does not cascade it away) and from one on the deleted
        // beacon. Only the composite FK's SET NULL can clear the former.
        await writer().execute(
          Sql.named('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, quoted_fact_card_id, quoted_fact_revision_seq)
VALUES (@id, @beacon, @author, 'cross-beacon quote', @fact, 1)
'''),
          parameters: {
            'id': _crossBeaconQuoteMessageId,
            'beacon': _beaconId,
            'author': _otherId,
            'fact': _quotedFactId,
          },
        );
        await writer().execute(
          Sql.named('''
UPDATE public.beacon_room_message
SET quoted_fact_card_id = @fact, quoted_fact_revision_seq = 1
WHERE id = 'Rf199quote'
'''),
          parameters: {'fact': _quotedFactId},
        );
        final quotedBefore = await writer().execute(
          Sql.named(
            'SELECT count(*)::int FROM public.beacon_room_message '
            'WHERE quoted_fact_card_id = @id',
          ),
          parameters: {'id': _quotedFactId},
        );
        expect(quotedBefore.single.single, 2, reason: 'fixture quotes');

        await writer().execute(
          Sql.named('DELETE FROM public.beacon WHERE id = @id'),
          parameters: {'id': _deleteBeaconId},
        );

        final crossBeacon = await writer().execute(
          Sql.named(
            'SELECT quoted_fact_card_id, quoted_fact_revision_seq '
            'FROM public.beacon_room_message WHERE id = @id',
          ),
          parameters: {'id': _crossBeaconQuoteMessageId},
        );
        expect(crossBeacon, hasLength(1), reason: 'quoting message survives');
        expect(crossBeacon.single[0], isNull);
        expect(crossBeacon.single[1], isNull);
        final anyQuote = await writer().execute(
          'SELECT count(*)::int FROM public.beacon_room_message '
          'WHERE quoted_fact_card_id IS NOT NULL '
          'OR quoted_fact_revision_seq IS NOT NULL',
        );
        expect(anyQuote.single.single, 0);

        final quoting = await writer().execute(
          Sql.named(
            'SELECT count(*)::int FROM public.beacon_room_message m '
            "WHERE to_jsonb(m)::text LIKE '%' || @id || '%'",
          ),
          parameters: {'id': _quotedFactId},
        );
        expect(quoting.single.single, 0);
        final revisions = await writer().execute(
          Sql.named(
            'SELECT count(*)::int FROM public.beacon_fact_card_revision '
            'WHERE fact_card_id = @id',
          ),
          parameters: {'id': _quotedFactId},
        );
        expect(revisions.single.single, 0);
      },
      skip: skipReason,
    );
  });

  group('guard', () {
    late DisposablePgWriterSession session;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(
          target: guardTarget,
          lastInclusiveVersion: '0198',
        );
        final writer = session.writer;
        await _seedUsersAndBeacon(writer, _beaconId);
        await _insertMessage(writer, _dupSourceMessageId, _beaconId);
        // The partial unique index only covers status 0, so an active and a
        // corrected fact can share a source message at 0198.
        await writer.execute('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, source_message_id, status)
VALUES
  ('Ff199g0', '$_beaconId', 'Active', 0, '$_pinnerId', '$_dupSourceMessageId',
   ${BeaconFactCardStatusBits.active}),
  ('Ff199g1', '$_beaconId', 'Corrected', 0, '$_pinnerId', '$_dupSourceMessageId',
   ${BeaconFactCardStatusBits.corrected})
''');
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session);
      });
    }

    test(
      'an active and a corrected fact on one source message abort m0199',
      () async {
        Object? failure;
        try {
          await migrateDbSchema(session.writer);
        } on Object catch (error) {
          failure = error;
        }
        expect(failure, isNotNull, reason: 'the guard must fail the migration');
        final message = failure.toString();
        expect(
          message.contains(_dupSourceMessageId) ||
              RegExp(
                'active.*corrected|corrected.*active',
                caseSensitive: false,
              ).hasMatch(message),
          isTrue,
          reason: 'guard message should name the conflict, got: $message',
        );

        final version = await session.writer.execute(
          'SELECT max(version COLLATE "C") FROM schema_version',
        );
        expect(version.single.single, '0198');
        final table = await session.writer.execute(
          "SELECT to_regclass('public.beacon_fact_card_revision') IS NULL",
        );
        expect(table.single.single, isTrue);
      },
      skip: skipReason,
    );
  });
}

const _pinnerId = 'Uf199pin01';
const _otherId = 'Uf199oth01';
const _beaconId = 'Bf199main1';
const _deleteBeaconId = 'Bf199del01';

const _activeFactId = 'Ff199act0';
const _correctedFactId = 'Ff199cor1';
const _removedFactId = 'Ff199rem2';
const _quotedFactId = 'Ff199quo0';

const _dupSourceMessageId = 'Rf199dup01';
const _crossBeaconQuoteMessageId = 'Rf199xquot';

const _pinnedEventId = 'Vf199evt01';
const _visibilityEventId = 'Vf199evt02';
const _danglingEventId = 'Vf199evt03';

Future<void> _seedUsersAndBeacon(Connection writer, String beaconId) async {
  for (final (id, slot) in [(_pinnerId, 1), (_otherId, 2)]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('m0199', slot)},
    );
  }
  await _seedBeacon(writer, beaconId);
}

Future<void> _seedBeacon(Connection writer, String beaconId) => writer.execute(
  Sql.named(
    'INSERT INTO public.beacon (id, user_id, title, description) '
    "VALUES (@id, @user, 't', 'd')",
  ),
  parameters: {'id': beaconId, 'user': _pinnerId},
);

Future<void> _insertMessage(
  Connection writer,
  String id,
  String beaconId,
) => writer.execute(
  Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@id, @beacon, @author, 'msg')
'''),
  parameters: {'id': id, 'beacon': beaconId, 'author': _pinnerId},
);

/// Facts in every status plus a quoted one on a second beacon; room messages
/// as sources; activity events pointing at facts through `diff.factCardId`.
final _seedStatements = <String>[
  '''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES
  ('Rf199src01', '$_beaconId', '$_pinnerId', 'source 1'),
  ('Rf199src02', '$_beaconId', '$_otherId', 'source 2'),
  ('Rf199src03', '$_deleteBeaconId', '$_pinnerId', 'source 3')
''',
  '''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, source_message_id, status,
   created_at, updated_at)
VALUES
  ('$_activeFactId', '$_beaconId', 'Active fact text', 0, '$_pinnerId',
   'Rf199src01', ${BeaconFactCardStatusBits.active},
   '2026-01-02 03:04:05+00', '2026-02-01 00:00:00+00'),
  ('$_correctedFactId', '$_beaconId', 'Corrected fact text', 0, '$_otherId',
   'Rf199src02', ${BeaconFactCardStatusBits.corrected},
   '2026-01-03 00:00:00+00', '2026-02-02 00:00:00+00'),
  ('$_removedFactId', '$_beaconId', 'Removed fact text', 1, '$_pinnerId',
   NULL, ${BeaconFactCardStatusBits.removed},
   '2026-01-04 00:00:00+00', '2026-02-03 00:00:00+00'),
  ('$_quotedFactId', '$_deleteBeaconId', 'Quoted fact text', 0, '$_pinnerId',
   'Rf199src03', ${BeaconFactCardStatusBits.active},
   '2026-01-05 00:00:00+00', '2026-01-05 00:00:00+00')
''',
  '''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, linked_fact_card_id)
VALUES ('Rf199quote', '$_deleteBeaconId', '$_pinnerId', 'quoting', '$_quotedFactId')
''',
  '''
INSERT INTO public.beacon_activity_event (id, beacon_id, visibility, type, actor_id, diff)
VALUES
  ('$_pinnedEventId', '$_beaconId', 0, ${BeaconActivityEventTypeBits.factPinned},
   '$_pinnerId', '{"factCardId": "$_activeFactId"}'::jsonb),
  ('$_visibilityEventId', '$_beaconId', 0,
   ${BeaconActivityEventTypeBits.factVisibilityChanged},
   '$_otherId', '{"factCardId": "$_correctedFactId"}'::jsonb),
  ('$_danglingEventId', '$_beaconId', 0, ${BeaconActivityEventTypeBits.factPinned},
   '$_pinnerId', '{"factCardId": "Ff199gone"}'::jsonb)
''',
];

/// The plan may carry `history_truncated` on the fact or on its revision;
/// read it from whichever table has it (exactly one must).
Future<Map<String, bool>> _historyTruncatedByFact(Connection writer) async {
  final owners = await writer.execute('''
SELECT table_name::text FROM information_schema.columns
WHERE table_schema = 'public' AND column_name = 'history_truncated'
  AND table_name IN ('beacon_fact_card', 'beacon_fact_card_revision')
''');
  expect(owners, hasLength(1), reason: 'history_truncated column');
  final sql = owners.single.single == 'beacon_fact_card'
      ? 'SELECT id, history_truncated FROM public.beacon_fact_card'
      : 'SELECT fact_card_id, history_truncated '
            'FROM public.beacon_fact_card_revision';
  final rows = await writer.execute(sql);
  return {for (final r in rows) r[0]! as String: r[1]! as bool};
}
