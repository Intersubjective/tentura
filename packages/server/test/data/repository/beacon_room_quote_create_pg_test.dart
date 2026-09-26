@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// tentura-617.16 (issue #181 plan §8.5, §14.2): `insertRoomMessage` takes
/// `quotedFactCardId` + `quotedFactRevisionSeq`. The quoted insert is one
/// insert-select that only yields a row when the fact belongs to the same
/// beacon, is not removed, and the revision seq exists; zero rows surface as
/// [IdWrongException] and leave no `beacon_room_message` behind.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_QUOTE_CREATE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_quote_create',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group(
    'BeaconRoomRepository.insertRoomMessage quote — disposable Postgres',
    () {
      late DisposablePgWriterSession session;
      late Connection writer;
      late TenturaDb db;
      late BeaconRoomRepository room;
      late String activeFactId;
      late String foreignFactId;
      late String removedFactId;

      if (reachable) {
        setUpAll(() async {
          session = await setUpDisposablePgWriter(target: target);
          writer = session.writer;
          await _seed(writer);

          db = TenturaDb.forTest(
            database: PgDatabase.opened(
              Pool<dynamic>.withEndpoints(
                [target.databaseEnv.pgEndpoint],
                settings: target.databaseEnv.pgPoolSettings,
              ),
              enableMigrations: false,
            ),
          );
          room = BeaconRoomRepository(db);
          final facts = BeaconFactCardCase(
            BeaconFactCardRepository(db, room),
            room,
            BeaconHierarchyRepository(db),
            BeaconAccessRepository(db),
            env: Env(environment: Environment.test),
            logger: Logger('BeaconRoomQuoteCreatePgTest'),
          );

          Future<String> pin(String beaconId, String text) async =>
              (await facts.pin(
                    beaconId: beaconId,
                    factText: text,
                    visibility: BeaconFactCardVisibilityBits.public,
                    userId: _authorId,
                  ))['id']!
                  as String;

          activeFactId = await pin(_beaconId, 'Tap water is on');
          foreignFactId = await pin(_otherBeaconId, 'Other beacon fact');
          removedFactId = await pin(_beaconId, 'Soon removed fact');
          await writer.execute(
            Sql.named(
              'UPDATE public.beacon_fact_card SET status = @removed '
              'WHERE id = @id',
            ),
            parameters: {
              'removed': BeaconFactCardStatusBits.removed,
              'id': removedFactId,
            },
          );
        });

        tearDownAll(() async {
          await tearDownDisposablePgWriter(session: session, drift: db);
        });
      }

      Future<int> countOf(String sql, Map<String, Object?> parameters) async {
        final rows = await writer.execute(
          Sql.named(sql),
          parameters: parameters,
        );
        return rows.single.single! as int;
      }

      /// Runs a rejected quoted insert with a body unique to this attempt and
      /// asserts it throws [IdWrongException] and leaves no row for the
      /// attempted message: none with this (beacon, author, body) identity and
      /// none quoting this (fact, seq) pair created since the attempt began.
      Future<void> expectRejectedWithoutRow({
        required String label,
        required String quotedFactCardId,
        required int quotedFactRevisionSeq,
      }) async {
        final body =
            'rejected $label ${DateTime.timestamp().microsecondsSinceEpoch}';
        final startedAt = (await writer.execute(
          'SELECT clock_timestamp()',
        )).single.single!;
        await expectLater(
          room.insertRoomMessage(
            beaconId: _beaconId,
            authorId: _authorId,
            body: body,
            quotedFactCardId: quotedFactCardId,
            quotedFactRevisionSeq: quotedFactRevisionSeq,
          ),
          throwsA(isA<IdWrongException>()),
        );
        expect(
          await countOf(
            '''
SELECT count(*)::integer FROM public.beacon_room_message
WHERE beacon_id = @beacon AND author_id = @author AND body = @body
''',
            {'beacon': _beaconId, 'author': _authorId, 'body': body},
          ),
          0,
          reason: '$label: the attempted message must not be stored',
        );
        expect(
          await countOf(
            '''
SELECT count(*)::integer FROM public.beacon_room_message
WHERE quoted_fact_card_id = @fact
  AND quoted_fact_revision_seq = @seq::integer
  AND created_at >= @started::timestamptz
''',
            {
              'fact': quotedFactCardId,
              'seq': quotedFactRevisionSeq,
              'started': startedAt,
            },
          ),
          0,
          reason: '$label: no row quoting this pair from this attempt',
        );
      }

      test(
        'a valid quote stores quoted_fact_card_id and quoted_fact_revision_seq',
        () async {
          final record = await room.insertRoomMessage(
            beaconId: _beaconId,
            authorId: _authorId,
            body: 'see this fact',
            quotedFactCardId: activeFactId,
            quotedFactRevisionSeq: 1,
          );

          expect(record.quotedFactCardId, activeFactId);
          expect(record.quotedFactRevisionSeq, 1);

          final row = (await writer.execute(
            Sql.named('''
SELECT quoted_fact_card_id, quoted_fact_revision_seq, beacon_id, author_id,
       body, thread_item_id
FROM public.beacon_room_message
WHERE id = @id
'''),
            parameters: {'id': record.id},
          )).single;
          expect(row[0], activeFactId);
          expect(row[1], 1);
          expect(row[2], _beaconId);
          expect(row[3], _authorId);
          expect(row[4], 'see this fact');
          expect(row[5], isNull, reason: 'General-only: thread_item_id NULL');
        },
        skip: skipReason,
      );

      test(
        'a quote-only message (empty body) is stored with both columns',
        () async {
          final record = await room.insertRoomMessage(
            beaconId: _beaconId,
            authorId: _authorId,
            body: '',
            quotedFactCardId: activeFactId,
            quotedFactRevisionSeq: 1,
          );

          final row = (await writer.execute(
            Sql.named('''
SELECT quoted_fact_card_id, quoted_fact_revision_seq
FROM public.beacon_room_message
WHERE id = @id
'''),
            parameters: {'id': record.id},
          )).single;
          expect(row[0], activeFactId);
          expect(row[1], 1);
        },
        skip: skipReason,
      );

      test(
        'the no-quote path leaves both quote columns NULL',
        () async {
          final record = await room.insertRoomMessage(
            beaconId: _beaconId,
            authorId: _authorId,
            body: 'plain message',
          );

          expect(record.quotedFactCardId, isNull);
          expect(record.quotedFactRevisionSeq, isNull);
          final row = (await writer.execute(
            Sql.named('''
SELECT quoted_fact_card_id, quoted_fact_revision_seq
FROM public.beacon_room_message
WHERE id = @id
'''),
            parameters: {'id': record.id},
          )).single;
          expect(row[0], isNull);
          expect(row[1], isNull);
        },
        skip: skipReason,
      );

      test(
        'quoting a fact from another beacon → IdWrongException, no row',
        () => expectRejectedWithoutRow(
          label: 'foreign beacon',
          quotedFactCardId: foreignFactId,
          quotedFactRevisionSeq: 1,
        ),
        skip: skipReason,
      );

      test(
        'quoting a removed fact → IdWrongException, no row',
        () => expectRejectedWithoutRow(
          label: 'removed fact',
          quotedFactCardId: removedFactId,
          quotedFactRevisionSeq: 1,
        ),
        skip: skipReason,
      );

      test(
        'quoting a non-existent revision seq → IdWrongException, no row',
        () => expectRejectedWithoutRow(
          label: 'missing seq',
          quotedFactCardId: activeFactId,
          quotedFactRevisionSeq: 99,
        ),
        skip: skipReason,
      );

      test(
        'updateMessage rewrites body/mentions/edited_at and keeps both quote '
        'columns; readback still carries the quote',
        () async {
          final record = await room.insertRoomMessage(
            beaconId: _beaconId,
            authorId: _authorId,
            body: 'quoted before edit',
            quotedFactCardId: activeFactId,
            quotedFactRevisionSeq: 1,
          );

          await room.updateMessage(
            messageId: record.id,
            newBody: 'quoted after edit',
            mentions: const [],
            mentionSpans: const [],
          );

          final row = (await writer.execute(
            Sql.named('''
SELECT body, edited_at IS NOT NULL, quoted_fact_card_id,
       quoted_fact_revision_seq
FROM public.beacon_room_message
WHERE id = @id
'''),
            parameters: {'id': record.id},
          )).single;
          expect(row[0], 'quoted after edit');
          expect(row[1], isTrue, reason: 'edited_at set');
          expect(row[2], activeFactId, reason: 'quote card kept on edit');
          expect(row[3], 1, reason: 'quote seq kept on edit');

          final readback = await room.getRoomMessageById(record.id);
          expect(readback, isNotNull);
          expect(readback!.body, 'quoted after edit');
          expect(readback.quotedFactCardId, activeFactId);
          expect(readback.quotedFactRevisionSeq, 1);
        },
        skip: skipReason,
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Fixture: one author who owns two published beacons (so the author can use
// both rooms). Facts are pinned in setUpAll through BeaconFactCardCase.pin so
// every fact has a real seq-1 revision.

const _authorId = 'Urqauthor01';

const _beaconId = 'Brqbeacon01';
const _otherBeaconId = 'Brqbeacon02';

final _t0 = DateTime.utc(2026, 3, 1, 12);

Future<void> _seed(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, 'Quote Author', @key)
'''),
    parameters: {'id': _authorId, 'key': pgTestPublicKey('roomquote', 1)},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
VALUES
  (@beacon, @author, 't', 'd', 0, @t0, false),
  (@other, @author, 't2', 'd2', 0, @t0, false)
'''),
    parameters: {
      'beacon': _beaconId,
      'other': _otherBeaconId,
      'author': _authorId,
      't0': _t0,
    },
  );
}
