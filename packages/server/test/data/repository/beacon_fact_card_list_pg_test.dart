@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:sentry/sentry.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/query_counter.dart';

/// tentura-617.5 (issue #181 plan §8.2, §8.4 "Fact list", §14.3): the fact
/// list reads through one fused preflight and one list query.
///
/// Contract under test:
///
/// ```dart
/// Future<BeaconFactRoomAccess> loadRoomAccess({
///   required String beaconId,
///   required String userId,
/// });
///
/// Future<List<BeaconFactCardEntity>> listForBeacon({
///   required String beaconId,
///   required bool includeRoomOnly,
/// });
/// ```
///
/// `loadRoomAccess` is one SELECT returning the beacon status, `can_use_room`
/// (author, steward or `room_access = 3`) and `beacon_can_read_content`.
/// `listForBeacon` filters removed rows in SQL, joins the pinner and last
/// editor titles, and drops room-only facts unless `includeRoomOnly`.
/// `BeaconFactCardCase.list` costs at most 4 statements: preflight, list and
/// the attachment batch.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_LIST_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_list',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('BeaconFactCardRepository fact list', () {
    late DisposablePgWriterSession session;
    late TenturaDb db;
    late _RecordingCounter counter;
    late BeaconFactCardRepository repository;
    late BeaconFactCardCase useCase;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        await _seed(session.writer);
        await session.writer.execute('ANALYZE public.beacon_fact_card');
        await session.writer.execute(
          'ANALYZE public.beacon_room_message_attachment',
        );

        counter = _RecordingCounter();
        db = TenturaDb.forTest(
          database: PgDatabase.opened(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
            enableMigrations: false,
          ).interceptWith(counter),
        );
        final room = BeaconRoomRepository(db);
        repository = BeaconFactCardRepository(db, room);
        useCase = BeaconFactCardCase(
          repository,
          room,
          _UnusedImage(),
          _UnusedTasks(),
          BeaconHierarchyRepository(db),
          BeaconAccessRepository(db),
          env: Env(environment: Environment.test),
          logger: Logger('BeaconFactCardListPgTest'),
        );
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    group('loadRoomAccess', () {
      for (final (label, userId) in [
        ('author', _authorId),
        ('steward', _stewardId),
        ('room_access = 3 participant', _admittedId),
      ]) {
        test(
          'canUseRoom is true for the $label',
          () async {
            final access = await repository.loadRoomAccess(
              beaconId: _beaconId,
              userId: userId,
            );

            expect(access.exists, isTrue);
            expect(access.canUseRoom, isTrue);
            expect(access.canReadContent, isTrue);
            expect(access.beaconStatus, 0);
          },
          skip: skipReason,
        );
      }

      test(
        'canUseRoom is false for a stranger and a requested participant',
        () async {
          final stranger = await repository.loadRoomAccess(
            beaconId: _beaconId,
            userId: _strangerId,
          );
          expect(stranger.exists, isTrue);
          expect(stranger.canUseRoom, isFalse);
          expect(stranger.canReadContent, isFalse);

          final requested = await repository.loadRoomAccess(
            beaconId: _beaconId,
            userId: _requestedId,
          );
          expect(requested.exists, isTrue);
          expect(requested.canUseRoom, isFalse);
        },
        skip: skipReason,
      );

      test(
        'exists is false for an unknown beacon id',
        () async {
          final access = await repository.loadRoomAccess(
            beaconId: 'Bflunknown01',
            userId: _authorId,
          );

          expect(access.exists, isFalse);
          expect(access.canUseRoom, isFalse);
          expect(access.canReadContent, isFalse);
        },
        skip: skipReason,
      );

      test(
        'is a single statement',
        () async {
          counter.reset();
          await repository.loadRoomAccess(
            beaconId: _beaconId,
            userId: _admittedId,
          );
          expect(counter.count, 1);
        },
        skip: skipReason,
      );
    });

    group('listForBeacon', () {
      test(
        'includeRoomOnly: false omits room-only facts',
        () async {
          final rows = await repository.listForBeacon(
            beaconId: _beaconId,
            includeRoomOnly: false,
          );

          expect(
            rows.map((e) => e.id).toSet(),
            {_publicFactId, _correctedFactId},
          );
          expect(
            rows.map((e) => e.visibility),
            everyElement(BeaconFactCardVisibilityBits.public),
          );
        },
        skip: skipReason,
      );

      test(
        'includeRoomOnly: true adds live room-only facts',
        () async {
          final rows = await repository.listForBeacon(
            beaconId: _beaconId,
            includeRoomOnly: true,
          );

          expect(
            rows.map((e) => e.id).toSet(),
            {_publicFactId, _roomFactId, _correctedFactId},
          );
        },
        skip: skipReason,
      );

      test(
        'removed facts are never returned',
        () async {
          for (final includeRoomOnly in [false, true]) {
            final rows = await repository.listForBeacon(
              beaconId: _beaconId,
              includeRoomOnly: includeRoomOnly,
            );
            final ids = rows.map((e) => e.id).toSet();
            expect(ids, isNot(contains(_removedPublicFactId)));
            expect(ids, isNot(contains(_removedRoomFactId)));
            expect(
              rows.map((e) => e.status),
              everyElement(isNot(BeaconFactCardStatusBits.removed)),
            );
            expect(ids, isNot(contains(_otherBeaconFactId)));
          }
        },
        skip: skipReason,
      );

      test(
        'pinned_by_title and last_edited_by_title are joined, with provenance',
        () async {
          counter.reset();
          final rows = await repository.listForBeacon(
            beaconId: _beaconId,
            includeRoomOnly: true,
          );
          expect(counter.count, 1, reason: 'titles joined, not a 2nd query');
          final byId = {for (final r in rows) r.id: r};

          final edited = byId[_publicFactId]!;
          expect(edited.pinnedByTitle, _authorTitle);
          expect(edited.lastEditedBy, _editorId);
          expect(edited.lastEditedByTitle, _editorTitle);
          expect(edited.lastEditedAt?.toUtc(), _editedAt);
          expect(edited.revisionSeq, 3);
          expect(edited.otherEditorCount, 1);
          expect(edited.historyTruncated, isTrue);
          expect(edited.sourceMessageId, _publicSourceId);

          final room = byId[_roomFactId]!;
          expect(room.pinnedByTitle, _admittedTitle);
          expect(room.lastEditedBy, isNull);
          expect(room.lastEditedByTitle, isNull);
          expect(room.lastEditedAt, isNull);
          expect(room.revisionSeq, 1);
          expect(room.otherEditorCount, 0);
          expect(room.historyTruncated, isFalse);

          expect(byId[_correctedFactId]!.pinnedByTitle, _stewardTitle);
        },
        skip: skipReason,
      );
    });

    group('BeaconFactCardCase.list', () {
      test(
        'costs at most 4 statements for an admitted participant',
        () async {
          counter.reset();
          final rows = await useCase.list(
            beaconId: _beaconId,
            userId: _admittedId,
          );

          expect(
            counter.count,
            lessThanOrEqualTo(4),
            reason: counter.selects.map((s) => s.statement).join('\n---\n'),
          );
          expect(
            rows.map((r) => r['id']).toSet(),
            {_publicFactId, _roomFactId, _correctedFactId},
          );
        },
        skip: skipReason,
      );

      test(
        'costs at most 4 statements for the author',
        () async {
          counter.reset();
          await useCase.list(beaconId: _beaconId, userId: _authorId);

          expect(
            counter.count,
            lessThanOrEqualTo(4),
            reason: counter.selects.map((s) => s.statement).join('\n---\n'),
          );
        },
        skip: skipReason,
      );

      test(
        'maps provenance fields and joined titles into the row',
        () async {
          final rows = await useCase.list(
            beaconId: _beaconId,
            userId: _admittedId,
          );
          final byId = {for (final r in rows) r['id']: r};

          final edited = byId[_publicFactId]!;
          expect(edited['pinnedByTitle'], _authorTitle);
          expect(edited['revisionSeq'], 3);
          expect(edited['lastEditedBy'], _editorId);
          expect(edited['lastEditedByTitle'], _editorTitle);
          expect(edited['lastEditedAt'], isNotNull);
          expect(
            DateTime.parse(edited['lastEditedAt']! as String).toUtc(),
            _editedAt,
          );
          expect(edited['otherEditorCount'], 1);
          expect(edited['historyTruncated'], isTrue);
          expect(edited['attachmentsJson'], contains(_publicAttachmentId));

          final room = byId[_roomFactId]!;
          expect(room['pinnedByTitle'], _admittedTitle);
          expect(room['revisionSeq'], 1);
          expect(room['lastEditedBy'], isNull);
          expect(room['lastEditedByTitle'], isNull);
          expect(room['lastEditedAt'], isNull);
          expect(room['otherEditorCount'], 0);
          expect(room['historyTruncated'], isFalse);
          expect(room['attachmentsJson'], contains(_roomAttachmentId));
        },
        skip: skipReason,
      );

      test(
        'a reader who cannot use the room sees only public facts',
        () async {
          // The requested participant can read content through a help offer
          // but is not admitted to the room.
          final rows = await useCase.list(
            beaconId: _beaconId,
            userId: _requestedId,
          );
          expect(
            rows.map((r) => r['id']).toSet(),
            {_publicFactId, _correctedFactId},
          );
        },
        skip: skipReason,
      );

      test(
        'a stranger who cannot read content is refused',
        () async {
          await expectLater(
            useCase.list(beaconId: _beaconId, userId: _strangerId),
            throwsA(isA<UnauthorizedException>()),
          );
        },
        skip: skipReason,
      );

      test(
        'EXPLAIN (enable_seqscan off) of the attachment batch uses '
        'beacon_fact_card_revision_seq_uq',
        () async {
          counter.reset();
          await useCase.list(beaconId: _beaconId, userId: _admittedId);
          final selects = counter.selects
              .where(
                (s) =>
                    s.statement.contains('beacon_fact_card_revision') &&
                    s.statement.contains('attachments_json'),
              )
              .toList();
          expect(selects, hasLength(1), reason: 'one attachment batch');
          final select = selects.single;

          final executor = select.executor;
          await executor.runCustom('SET enable_seqscan = off');
          try {
            final shown = await executor.runSelect('SHOW enable_seqscan', []);
            expect(shown.single.values.single, 'off');
            final rows = await executor.runSelect(
              'EXPLAIN (COSTS OFF) ${select.statement}',
              select.args,
            );
            final plan = rows.map((r) => r.values.single).join('\n');
            expect(
              plan,
              contains('beacon_fact_card_revision_seq_uq'),
              reason: 'plan:\n$plan',
            );
            expect(
              plan,
              isNot(
                matches(
                  RegExp(
                    r'Seq Scan on (?:public\.)?'
                    r'beacon_fact_card_revision\b',
                  ),
                ),
              ),
              reason: 'plan:\n$plan',
            );
          } finally {
            await executor.runCustom('RESET enable_seqscan');
          }
        },
        skip: skipReason,
      );
    });

    group('listForBeacon Sentry span (tentura-617.20)', () {
      SentryTransaction? capturedTransaction;

      setUp(() async {
        await Sentry.close();
        capturedTransaction = null;
        await Sentry.init((options) {
          options
            ..dsn = 'https://public@o123.ingest.sentry.io/1'
            // Deliberate: rethrow exceptions in user closures during tests.
            // ignore: invalid_use_of_internal_member
            ..automatedTestMode = true
            ..tracesSampleRate = 1.0
            ..beforeSendTransaction = (transaction, hint) {
              capturedTransaction = transaction;
              return transaction;
            };
        });
      });

      tearDown(() async {
        await Sentry.close();
      });

      test(
        'records the actual returned row count on a db span',
        () async {
          final transaction = Sentry.startTransaction(
            'test-tx',
            'test',
            bindToScope: true,
          );

          final rows = await repository.listForBeacon(
            beaconId: _beaconId,
            includeRoomOnly: true,
          );

          await transaction.finish();

          expect(rows, hasLength(3));
          expect(capturedTransaction, isNotNull);

          final listSpans = capturedTransaction!.spans
              .where((span) => span.context.operation == 'db.fact.list')
              .toList();
          expect(
            listSpans,
            hasLength(1),
            reason:
                'expected exactly one db.fact.list child span for '
                'listForBeacon; captured spans: '
                '${capturedTransaction!.spans.map((s) => s.context.operation).toList()}',
          );
          expect(
            listSpans.single.data['db.rows'],
            rows.length,
            reason: 'the db.fact.list span must carry the actual row count',
          );
        },
        skip: skipReason,
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Fixture: one published, non-discoverable beacon with an author, a steward,
// an admitted participant, a requested participant (reads content through an
// active help offer) and a stranger. Facts: one public edited fact, one
// room-only fact, one corrected public fact, a removed public and a removed
// room-only fact, and a fact on another beacon. The two live sourced facts
// each carry one file attachment.

const _authorId = 'Uflauthor01';
const _authorTitle = 'Fact Author';
const _stewardId = 'Uflsteward1';
const _stewardTitle = 'Fact Steward';
const _admittedId = 'Ufladmitted';
const _admittedTitle = 'Fact Admitted';
const _requestedId = 'Uflrequest1';
const _strangerId = 'Uflstranger';
const _editorId = 'Ufleditor01';
const _editorTitle = 'Fact Editor';

const _beaconId = 'Bflbeacon01';
const _otherBeaconId = 'Bflbeacon02';

const _publicFactId = 'Fflpublic01';
const _roomFactId = 'Fflroom0001';
const _correctedFactId = 'Fflcorrect1';
const _removedPublicFactId = 'Fflremoved1';
const _removedRoomFactId = 'Fflremoved2';
const _otherBeaconFactId = 'Fflother001';

const _publicSourceId = 'Rflsource01';
const _roomSourceId = 'Rflsource02';
const _publicAttachmentId = 'Aflattach01';
const _roomAttachmentId = 'Aflattach02';

final _t0 = DateTime.utc(2026, 3, 1, 12);
final _editedAt = _t0.add(const Duration(hours: 2));

Future<void> _seed(Connection writer) async {
  var slot = 1;
  for (final (id, title) in [
    (_authorId, _authorTitle),
    (_stewardId, _stewardTitle),
    (_admittedId, _admittedTitle),
    (_requestedId, 'Fact Requested'),
    (_strangerId, 'Fact Stranger'),
    (_editorId, _editorTitle),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @title, @key)
'''),
      parameters: {
        'id': id,
        'title': title,
        'key': pgTestPublicKey('factlist', slot++),
      },
    );
  }
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
  await writer.execute(
    Sql.named(
      'INSERT INTO public.beacon_steward (beacon_id, user_id) '
      'VALUES (@beacon, @steward)',
    ),
    parameters: {'beacon': _beaconId, 'steward': _stewardId},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES
  (@beacon, @admitted, 2, ${RoomAccessBits.admitted}),
  (@beacon, @requested, 2, ${RoomAccessBits.requested})
'''),
    parameters: {
      'beacon': _beaconId,
      'admitted': _admittedId,
      'requested': _requestedId,
    },
  );
  await writer.execute(
    Sql.named(
      'INSERT INTO public.beacon_help_offer (beacon_id, user_id, status) '
      'VALUES (@beacon, @requested, 0)',
    ),
    parameters: {'beacon': _beaconId, 'requested': _requestedId},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES
  (@public, @beacon, @author, 'public source'),
  (@room, @beacon, @admitted, 'room source')
'''),
    parameters: {
      'public': _publicSourceId,
      'room': _roomSourceId,
      'beacon': _beaconId,
      'author': _authorId,
      'admitted': _admittedId,
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_room_message_attachment
  (id, message_id, kind, file_url, mime, size_bytes, "position", file_name)
VALUES
  (@a1, @m1, ${BeaconRoomMessageAttachmentKind.file}, 'https://x/a1',
   'text/plain', 1, 0, 'a1.txt'),
  (@a2, @m2, ${BeaconRoomMessageAttachmentKind.file}, 'https://x/a2',
   'text/plain', 2, 0, 'a2.txt')
'''),
    parameters: {
      'a1': _publicAttachmentId,
      'a2': _roomAttachmentId,
      'm1': _publicSourceId,
      'm2': _roomSourceId,
    },
  );

  const public = BeaconFactCardVisibilityBits.public;
  const room = BeaconFactCardVisibilityBits.room;
  const active = BeaconFactCardStatusBits.active;
  const corrected = BeaconFactCardStatusBits.corrected;
  const removed = BeaconFactCardStatusBits.removed;
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, source_message_id, status,
   revision_seq, last_edited_by, last_edited_at, other_editor_count,
   history_truncated, created_at, updated_at)
VALUES
  (@f1, @beacon, 'public fact', $public, @author, @m1, $active,
   3, @editor, @editedAt, 1, true, @t1, @editedAt),
  (@f2, @beacon, 'room fact', $room, @admitted, @m2, $active,
   1, NULL, NULL, 0, false, @t2, @t2),
  (@f3, @beacon, 'corrected fact', $public, @steward, NULL, $corrected,
   1, NULL, NULL, 0, false, @t3, @t3),
  (@f4, @beacon, 'removed public', $public, @author, NULL, $removed,
   1, NULL, NULL, 0, false, @t4, @t4),
  (@f5, @beacon, 'removed room', $room, @author, NULL, $removed,
   1, NULL, NULL, 0, false, @t5, @t5),
  (@f6, @other, 'other beacon fact', $public, @author, NULL, $active,
   1, NULL, NULL, 0, false, @t1, @t1)
'''),
    parameters: {
      'f1': _publicFactId,
      'f2': _roomFactId,
      'f3': _correctedFactId,
      'f4': _removedPublicFactId,
      'f5': _removedRoomFactId,
      'f6': _otherBeaconFactId,
      'beacon': _beaconId,
      'other': _otherBeaconId,
      'author': _authorId,
      'admitted': _admittedId,
      'steward': _stewardId,
      'editor': _editorId,
      'm1': _publicSourceId,
      'm2': _roomSourceId,
      'editedAt': _editedAt,
      't1': _t0,
      't2': _t0.add(const Duration(minutes: 1)),
      't3': _t0.add(const Duration(minutes: 2)),
      't4': _t0.add(const Duration(minutes: 3)),
      't5': _t0.add(const Duration(minutes: 4)),
    },
  );
  // List reads attachment snapshots from the head revision (m0200), not from
  // the source message's attachment rows.
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (id, fact_card_id, seq, fact_text, actor_id, kind, created_at, attachments_json)
VALUES
  ('FRlpublic01', @f1, 3, 'public fact', @editor,
   ${BeaconFactCardRevisionKindBits.edited}, @editedAt,
   '[{"id":"$_publicAttachmentId","kind":1,"position":0}]'::jsonb),
  ('FRlroom0001', @f2, 1, 'room fact', @admitted,
   ${BeaconFactCardRevisionKindBits.created}, @t2,
   '[{"id":"$_roomAttachmentId","kind":1,"position":0}]'::jsonb),
  ('FRlcorrect1', @f3, 1, 'corrected fact', @steward,
   ${BeaconFactCardRevisionKindBits.created}, @t3, '[]'::jsonb),
  ('FRlremoved1', @f4, 1, 'removed public', @author,
   ${BeaconFactCardRevisionKindBits.created}, @t4, '[]'::jsonb),
  ('FRlremoved2', @f5, 1, 'removed room', @author,
   ${BeaconFactCardRevisionKindBits.created}, @t5, '[]'::jsonb),
  ('FRlother001', @f6, 1, 'other beacon fact', @author,
   ${BeaconFactCardRevisionKindBits.created}, @t1, '[]'::jsonb)
'''),
    parameters: {
      'f1': _publicFactId,
      'f2': _roomFactId,
      'f3': _correctedFactId,
      'f4': _removedPublicFactId,
      'f5': _removedRoomFactId,
      'f6': _otherBeaconFactId,
      'author': _authorId,
      'admitted': _admittedId,
      'steward': _stewardId,
      'editor': _editorId,
      'editedAt': _editedAt,
      't1': _t0,
      't2': _t0.add(const Duration(minutes: 1)),
      't3': _t0.add(const Duration(minutes: 2)),
      't4': _t0.add(const Duration(minutes: 3)),
      't5': _t0.add(const Duration(minutes: 4)),
    },
  );
}

/// Counts every statement (see [QueryCounter]) and records each select so a
/// test can EXPLAIN what the list path actually issued, on the same session.
class _RecordingCounter extends QueryCounter {
  final selects =
      <({String statement, List<Object?> args, QueryExecutor executor})>[];

  @override
  void reset() {
    super.reset();
    selects.clear();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects.add((
      statement: statement,
      args: List.of(args),
      executor: executor,
    ));
    return super.runSelect(executor, statement, args);
  }
}

class _UnusedImage extends Fake implements ImageRepositoryPort {}

class _UnusedTasks extends Fake implements TaskRepositoryPort {}

