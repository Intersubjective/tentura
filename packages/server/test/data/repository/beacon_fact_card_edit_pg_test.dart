@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_outcome.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/query_counter.dart';

/// tentura-617.10 (issue #181 plan §8.3 "Edit / restore", §14.3 editText /
/// restoreRevision, §14.9): both methods run the one canonical CTE through a
/// shared `_runEdit` inside `withMutatingUser`. It locks the card `FOR
/// UPDATE`, compares against the latest committed row, writes the revision,
/// the marker-10 room line and the type-19 event (the last two unless the
/// pinner re-edits a fresh pin inside the quiet window), and maps the
/// diagnostic columns to a [FactEditOutcome].
///
/// A repository call costs exactly 4 statements: BEGIN, the `set_config`
/// actor line, the CTE and COMMIT.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_EDIT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_edit',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('BeaconFactCardRepository.editText / restoreRevision — '
      'disposable Postgres', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late QueryCounter counter;
    late BeaconFactCardRepository repo;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        writer = session.writer;
        await _seedBase(writer);

        counter = QueryCounter();
        db = TenturaDb.forTest(
          database: PgDatabase.opened(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
            enableMigrations: false,
          ).interceptWith(counter),
        );
        repo = BeaconFactCardRepository(db, BeaconRoomRepository(db));
      });

      tearDown(() async {
        await writer.execute(
          Sql.named('''
DELETE FROM public.beacon_activity_event WHERE beacon_id = @beacon
'''),
          parameters: {'beacon': _beaconId},
        );
        await writer.execute(
          Sql.named('''
DELETE FROM public.beacon_room_message WHERE beacon_id = @beacon
'''),
          parameters: {'beacon': _beaconId},
        );
        await writer.execute(
          Sql.named('''
DELETE FROM public.beacon_fact_card_revision WHERE fact_card_id IN
  (SELECT id FROM public.beacon_fact_card WHERE beacon_id = @beacon)
'''),
          parameters: {'beacon': _beaconId},
        );
        await writer.execute(
          Sql.named('''
DELETE FROM public.beacon_fact_card WHERE beacon_id = @beacon
'''),
          parameters: {'beacon': _beaconId},
        );
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    Future<FactEditOutcome> edit(
      String factId,
      String actor,
      String text,
      int baseSeq, {
      BeaconFactCardRepository? via,
      int rateMax = 20,
      Duration quietWindow = kFactEditQuietWindow,
      String? attachmentsJson,
    }) => (via ?? repo).editText(
      factCardId: factId,
      beaconId: _beaconId,
      actorUserId: actor,
      newText: text,
      baseRevisionSeq: baseSeq,
      rateWindow: const Duration(seconds: 60),
      rateMax: rateMax,
      quietWindow: quietWindow,
      attachmentsJson: attachmentsJson,
    );

    Future<FactEditOutcome> restore(
      String factId,
      String actor,
      int fromSeq,
      int baseSeq,
    ) => repo.restoreRevision(
      factCardId: factId,
      beaconId: _beaconId,
      actorUserId: actor,
      fromSeq: fromSeq,
      baseRevisionSeq: baseSeq,
      rateWindow: const Duration(seconds: 60),
      rateMax: 20,
      quietWindow: kFactEditQuietWindow,
    );

    Future<int> countOf(String sql, Map<String, Object?> parameters) async {
      final rows = await writer.execute(Sql.named(sql), parameters: parameters);
      return rows.single.single! as int;
    }

    Future<int> revisionCount(String factId) => countOf(
      '''
SELECT count(*)::integer FROM public.beacon_fact_card_revision
WHERE fact_card_id = @id
''',
      {'id': factId},
    );

    Future<int> editLineCount(String factId) => countOf(
      '''
SELECT count(*)::integer FROM public.beacon_room_message
WHERE beacon_id = @beacon
  AND semantic_marker = ${BeaconRoomSemanticMarker.factEdited}
  AND system_payload->>'factCardId' = @id
''',
      {'beacon': _beaconId, 'id': factId},
    );

    Future<int> editEventCount(String factId) => countOf(
      '''
SELECT count(*)::integer FROM public.beacon_activity_event
WHERE beacon_id = @beacon
  AND type = ${BeaconActivityEventTypeBits.factEdited}
  AND fact_card_id = @id
''',
      {'beacon': _beaconId, 'id': factId},
    );

    Future<({int seq, String text, int otherEditors})> cardOf(
      String factId,
    ) async {
      final rows = await writer.execute(
        Sql.named('''
SELECT revision_seq, fact_text, other_editor_count::integer
FROM public.beacon_fact_card WHERE id = @id
'''),
        parameters: {'id': factId},
      );
      final r = rows.single;
      return (
        seq: r[0]! as int,
        text: r[1]! as String,
        otherEditors: r[2]! as int,
      );
    }

    test(
      'applied edit: new seq, revision kind 1, marker-10 line with exactly '
      'factCardId/revisionSeq/pinnedBy/factText, type-19 event with '
      'fact_card_id',
      () async {
        await _seedFact(writer, id: _factApplied, text: 'Tap on corner');

        final outcome = await edit(
          _factApplied,
          _editorAId,
          '  Tap moved to the square  ',
          1,
        );
        expect(
          outcome,
          isA<FactEditApplied>().having((o) => o.newSeq, 'newSeq', 2),
        );

        final card = await cardOf(_factApplied);
        expect(card.seq, 2);
        expect(card.text, 'Tap moved to the square');

        final revisions = await writer.execute(
          Sql.named('''
SELECT seq, kind, actor_id, fact_text, restored_from_seq
FROM public.beacon_fact_card_revision
WHERE fact_card_id = @id AND seq = 2
'''),
          parameters: {'id': _factApplied},
        );
        expect(revisions, hasLength(1));
        final rev = revisions.single;
        expect(rev[1], BeaconFactCardRevisionKindBits.edited);
        expect(rev[2], _editorAId);
        expect(rev[3], 'Tap moved to the square');
        expect(rev[4], isNull);

        final lines = await writer.execute(
          Sql.named('''
SELECT author_id, system_payload
FROM public.beacon_room_message
WHERE beacon_id = @beacon
  AND semantic_marker = ${BeaconRoomSemanticMarker.factEdited}
  AND system_payload->>'factCardId' = @id
'''),
          parameters: {'beacon': _beaconId, 'id': _factApplied},
        );
        expect(lines, hasLength(1), reason: 'one marker-10 line');
        expect(lines.single[0], _editorAId);
        final payload = lines.single[1]! as Map<String, dynamic>;
        expect(
          payload.keys.toSet(),
          {'factCardId', 'revisionSeq', 'pinnedBy', 'factText'},
          reason: 'system_payload keys must be exactly these four',
        );
        expect(payload['factCardId'], _factApplied);
        expect(payload['revisionSeq'], 2);
        expect(payload['pinnedBy'], _pinnerId);
        expect(payload['factText'], 'Tap moved to the square');

        final events = await writer.execute(
          Sql.named('''
SELECT actor_id, diff->>'factCardId', (diff->>'revisionSeq')::integer,
       (diff->>'kind')::integer
FROM public.beacon_activity_event
WHERE beacon_id = @beacon
  AND type = ${BeaconActivityEventTypeBits.factEdited}
  AND fact_card_id = @id
'''),
          parameters: {'beacon': _beaconId, 'id': _factApplied},
        );
        expect(events, hasLength(1), reason: 'one type-19 event');
        final event = events.single;
        expect(event[0], _editorAId);
        expect(event[1], _factApplied);
        expect(event[2], 2);
        expect(event[3], BeaconFactCardRevisionKindBits.edited);
      },
      skip: skipReason,
    );

    test(
      'the repository call alone costs exactly 4 statements for editText '
      'and restoreRevision',
      () async {
        await _seedFact(writer, id: _factCount, text: 'Counted');
        counter.reset();
        final outcome = await edit(_factCount, _editorAId, 'Counted v2', 1);
        expect(outcome, isA<FactEditApplied>());
        expect(
          counter.count,
          4,
          reason: 'BEGIN + set_config + one edit CTE + COMMIT',
        );

        counter.reset();
        final restored = await restore(_factCount, _editorAId, 1, 2);
        expect(restored, isA<FactEditApplied>());
        expect(
          counter.count,
          4,
          reason:
              'restore shares _runEdit: BEGIN + set_config + one CTE + '
              'COMMIT',
        );

        counter.reset();
        final missing = await restore(_factCount, _editorAId, 99, 3);
        expect(missing, isA<FactRestoreSourceMissing>());
        expect(
          counter.count,
          4,
          reason: 'a non-applied outcome costs no extra statement',
        );
      },
      skip: skipReason,
    );

    test(
      'stale base seq → FactEditConflict carrying the current seq',
      () async {
        await _seedFact(writer, id: _factStale, text: 'First');
        expect(
          await edit(_factStale, _editorAId, 'Second', 1),
          isA<FactEditApplied>(),
        );
        counter.reset();
        final outcome = await edit(_factStale, _editorBId, 'Third', 1);
        expect(counter.count, 4, reason: 'BEGIN + set_config + CTE + COMMIT');
        expect(
          outcome,
          isA<FactEditConflict>().having((o) => o.currentSeq, 'currentSeq', 2),
        );
        expect(await revisionCount(_factStale), 2);
        expect((await cardOf(_factStale)).text, 'Second');
      },
      skip: skipReason,
    );

    test(
      'identical (trimmed) text → FactEditNoOp(current), nothing written',
      () async {
        await _seedFact(writer, id: _factNoOp, text: 'Same text');
        counter.reset();
        final outcome = await edit(_factNoOp, _editorAId, '  Same text ', 1);
        expect(counter.count, 4, reason: 'BEGIN + set_config + CTE + COMMIT');
        expect(
          outcome,
          isA<FactEditNoOp>().having((o) => o.currentSeq, 'currentSeq', 1),
        );
        expect(await revisionCount(_factNoOp), 1);
        expect(await editLineCount(_factNoOp), 0);
        expect(await editEventCount(_factNoOp), 0);
      },
      skip: skipReason,
    );

    test(
      'removed fact → FactEditRemoved',
      () async {
        await _seedFact(
          writer,
          id: _factRemoved,
          text: 'Gone',
          status: BeaconFactCardStatusBits.removed,
        );
        counter.reset();
        final outcome = await edit(_factRemoved, _editorAId, 'Back', 1);
        expect(counter.count, 4, reason: 'BEGIN + set_config + CTE + COMMIT');
        expect(outcome, isA<FactEditRemoved>());
        expect(await revisionCount(_factRemoved), 1);
      },
      skip: skipReason,
    );

    test(
      'unknown id → FactEditNotFound',
      () async {
        counter.reset();
        final outcome = await edit('Fnosuchfact', _editorAId, 'Anything', 1);
        expect(counter.count, 4, reason: 'BEGIN + set_config + CTE + COMMIT');
        expect(outcome, isA<FactEditNotFound>());
      },
      skip: skipReason,
    );

    test(
      'rateMax 1 and a second edit → FactEditRateLimited',
      () async {
        await _seedFact(writer, id: _factRate, text: 'Rate v1');
        expect(
          await edit(_factRate, _editorRateId, 'Rate v2', 1, rateMax: 1),
          isA<FactEditApplied>(),
        );
        counter.reset();
        final outcome = await edit(
          _factRate,
          _editorRateId,
          'Rate v3',
          2,
          rateMax: 1,
        );
        expect(counter.count, 4, reason: 'BEGIN + set_config + CTE + COMMIT');
        expect(outcome, isA<FactEditRateLimited>());
        expect(await revisionCount(_factRate), 2);
        expect((await cardOf(_factRate)).text, 'Rate v2');
      },
      skip: skipReason,
    );

    test(
      'restore with a missing fromSeq → FactRestoreSourceMissing (no 23502)',
      () async {
        await _seedFact(writer, id: _factRestoreMissing, text: 'Only one');
        final outcome = await restore(_factRestoreMissing, _editorAId, 99, 1);
        expect(outcome, isA<FactRestoreSourceMissing>());
        expect(await revisionCount(_factRestoreMissing), 1);
      },
      skip: skipReason,
    );

    test(
      'restore → revision kind 2 with restored_from_seq and the source text',
      () async {
        await _seedFact(writer, id: _factRestore, text: 'Original wording');
        expect(
          await edit(_factRestore, _editorAId, 'Changed wording', 1),
          isA<FactEditApplied>(),
        );
        final outcome = await restore(_factRestore, _editorBId, 1, 2);
        expect(
          outcome,
          isA<FactEditApplied>().having((o) => o.newSeq, 'newSeq', 3),
        );

        final rows = await writer.execute(
          Sql.named('''
SELECT kind, restored_from_seq, fact_text, actor_id
FROM public.beacon_fact_card_revision
WHERE fact_card_id = @id AND seq = 3
'''),
          parameters: {'id': _factRestore},
        );
        expect(rows, hasLength(1));
        expect(rows.single[0], BeaconFactCardRevisionKindBits.restored);
        expect(rows.single[1], 1);
        expect(rows.single[2], 'Original wording');
        expect(rows.single[3], _editorBId);
        expect((await cardOf(_factRestore)).text, 'Original wording');

        final kinds = await writer.execute(
          Sql.named('''
SELECT (diff->>'kind')::integer FROM public.beacon_activity_event
WHERE fact_card_id = @id AND type = ${BeaconActivityEventTypeBits.factEdited}
  AND (diff->>'revisionSeq')::integer = 3
'''),
          parameters: {'id': _factRestore},
        );
        expect(kinds.single.single, BeaconFactCardRevisionKindBits.restored);
      },
      skip: skipReason,
    );

    test(
      'pinner edit inside the quiet window → revision written, no line, '
      'no event',
      () async {
        await _seedFact(
          writer,
          id: _factQuiet,
          text: 'Fresh pin',
          fresh: true,
        );
        final outcome = await edit(
          _factQuiet,
          _pinnerId,
          'Fresh pin, typo fixed',
          1,
        );
        expect(
          outcome,
          isA<FactEditApplied>().having((o) => o.newSeq, 'newSeq', 2),
        );
        final rows = await writer.execute(
          Sql.named('''
SELECT kind, actor_id FROM public.beacon_fact_card_revision
WHERE fact_card_id = @id AND seq = 2
'''),
          parameters: {'id': _factQuiet},
        );
        expect(rows, hasLength(1), reason: 'revision still written');
        expect(rows.single[0], BeaconFactCardRevisionKindBits.edited);
        expect(rows.single[1], _pinnerId);
        expect(await editLineCount(_factQuiet), 0, reason: 'no room line');
        expect(await editEventCount(_factQuiet), 0, reason: 'no event');
      },
      skip: skipReason,
    );

    test(
      "edit after the pinner's account is deleted → line and event written",
      () async {
        await _seedFact(
          writer,
          id: _factOrphan,
          text: 'Orphan fact',
          pinnedBy: _doomedPinnerId,
          fresh: true,
        );
        await writer.execute(
          Sql.named('DELETE FROM public."user" WHERE id = @id'),
          parameters: {'id': _doomedPinnerId},
        );
        final pinned = await writer.execute(
          Sql.named(
            'SELECT pinned_by FROM public.beacon_fact_card WHERE id = @id',
          ),
          parameters: {'id': _factOrphan},
        );
        expect(pinned.single.single, isNull, reason: 'fixture: SET NULL');

        final outcome = await edit(
          _factOrphan,
          _editorAId,
          'Orphan fact, updated',
          1,
        );
        expect(outcome, isA<FactEditApplied>());
        expect(await editLineCount(_factOrphan), 1);
        expect(await editEventCount(_factOrphan), 1);
      },
      skip: skipReason,
    );

    test(
      'other_editor_count rises once per distinct non-pinner editor',
      () async {
        await _seedFact(writer, id: _factEditors, text: 'Editors v1');
        expect(
          await edit(_factEditors, _editorAId, 'Editors v2', 1),
          isA<FactEditApplied>(),
        );
        expect((await cardOf(_factEditors)).otherEditors, 1);

        expect(
          await edit(_factEditors, _editorAId, 'Editors v3', 2),
          isA<FactEditApplied>(),
        );
        expect(
          (await cardOf(_factEditors)).otherEditors,
          1,
          reason: 'same editor again',
        );

        expect(
          await edit(_factEditors, _pinnerId, 'Editors v4', 3),
          isA<FactEditApplied>(),
        );
        expect(
          (await cardOf(_factEditors)).otherEditors,
          1,
          reason: 'the pinner is not an "other" editor',
        );

        expect(
          await edit(_factEditors, _editorBId, 'Editors v5', 4),
          isA<FactEditApplied>(),
        );
        expect((await cardOf(_factEditors)).otherEditors, 2);
      },
      skip: skipReason,
    );

    test(
      'two connections with the same base seq → one Applied, one Conflict',
      () async {
        await _seedFact(writer, id: _factRace, text: 'Race v1');
        final otherDb = openDisposablePgDatabase(target);
        try {
          final otherRepo = BeaconFactCardRepository(
            otherDb,
            BeaconRoomRepository(otherDb),
          );
          final outcomes = await Future.wait([
            edit(_factRace, _editorAId, 'Race A', 1),
            edit(_factRace, _editorBId, 'Race B', 1, via: otherRepo),
          ]);
          expect(
            outcomes.whereType<FactEditApplied>(),
            hasLength(1),
            reason: 'outcomes: $outcomes',
          );
          final conflicts = outcomes.whereType<FactEditConflict>().toList();
          expect(conflicts, hasLength(1), reason: 'outcomes: $outcomes');
          expect(conflicts.single.currentSeq, 2);
          expect(await revisionCount(_factRace), 2);
        } finally {
          await otherDb.close();
        }
      },
      skip: skipReason,
    );

    test(
      'resubmitting the old text after a concurrent edit committed → '
      'Conflict or NoOp carrying the NEW seq',
      () async {
        await _seedFact(writer, id: _factResubmit, text: 'Old text');
        // Mirror what a committed edit really leaves on the card: take the
        // status an applied editText writes on a probe fact instead of
        // assuming one.
        await _seedFact(writer, id: _factStatusProbe, text: 'Probe v1');
        expect(
          await edit(_factStatusProbe, _editorBId, 'Probe v2', 1),
          isA<FactEditApplied>(),
        );
        final probe = await writer.execute(
          Sql.named(
            'SELECT status FROM public.beacon_fact_card WHERE id = @id',
          ),
          parameters: {'id': _factStatusProbe},
        );
        final editedStatus = probe.single.single! as int;

        late Future<FactEditOutcome> pending;
        await writer.runTx((tx) async {
          await tx.execute(
            Sql.named('''
UPDATE public.beacon_fact_card
SET fact_text = 'Concurrent text', revision_seq = 2, status = @status,
    last_edited_by = @actor, last_edited_at = now(), updated_at = now()
WHERE id = @id
'''),
            parameters: {
              'id': _factResubmit,
              'status': editedStatus,
              'actor': _editorBId,
            },
          );
          await tx.execute(
            Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (id, fact_card_id, seq, fact_text, actor_id, kind)
VALUES ('FRresubmit2', @id, 2, 'Concurrent text', @actor, 1)
'''),
            parameters: {'id': _factResubmit, 'actor': _editorBId},
          );
          pending = edit(_factResubmit, _editorAId, 'Old text', 1);
          // Commit only once our edit is waiting on this transaction's row
          // lock. Scoped to backends blocked by this connection.
          final deadline = DateTime.timestamp().add(
            const Duration(seconds: 20),
          );
          while (true) {
            final waiting = await tx.execute('''
SELECT count(*)::integer FROM pg_stat_activity
WHERE pg_backend_pid() = ANY(pg_blocking_pids(pid))
''');
            if ((waiting.single.single! as int) > 0) break;
            if (DateTime.timestamp().isAfter(deadline)) {
              fail('the edit never waited on the locked fact row');
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });

        final outcome = await pending;
        expect(
          outcome,
          anyOf(
            isA<FactEditConflict>().having(
              (o) => o.currentSeq,
              'currentSeq',
              2,
            ),
            isA<FactEditNoOp>().having((o) => o.currentSeq, 'currentSeq', 2),
          ),
          reason: 'the decision must use the latest committed row',
        );
        expect(await revisionCount(_factResubmit), 2);
      },
      skip: skipReason,
    );

    test(
      'attach-only edit (same text, new attachments) → new revision + snapshot',
      () async {
        await _seedFact(
          writer,
          id: _factAttachOnly,
          text: 'Photo fact',
          attachmentsJson: '[{"id":"Aold","kind":1,"position":0,'
              '"mime":"image/jpeg","sizeBytes":10,"fileName":"old.jpg",'
              '"imageId":"Iold","imageAuthorId":"$_pinnerId",'
              '"blurHash":"","width":1,"height":1}]',
        );
        const next = '[{"id":"Anew","kind":1,"position":0,'
            '"mime":"image/jpeg","sizeBytes":20,"fileName":"new.jpg",'
            '"imageId":"Inew","imageAuthorId":"$_editorAId",'
            '"blurHash":"","width":2,"height":2}]';
        final outcome = await edit(
          _factAttachOnly,
          _editorAId,
          'Photo fact',
          1,
          attachmentsJson: next,
        );
        expect(
          outcome,
          isA<FactEditApplied>().having((o) => o.newSeq, 'newSeq', 2),
        );
        expect(await revisionCount(_factAttachOnly), 2);
        final snap = await writer.execute(
          Sql.named('''
SELECT attachments_json::text FROM public.beacon_fact_card_revision
WHERE fact_card_id = @id AND seq = 2
'''),
          parameters: {'id': _factAttachOnly},
        );
        expect(snap.single.single as String, contains('Anew'));
        expect(snap.single.single as String, isNot(contains('Aold')));
      },
      skip: skipReason,
    );

    test(
      'same text + same attachments → FactEditNoOp',
      () async {
        const snap = '[{"id":"Asame","kind":1,"position":0,'
            '"mime":"image/jpeg","sizeBytes":10,"fileName":"same.jpg",'
            '"imageId":"Isame","imageAuthorId":"$_pinnerId",'
            '"blurHash":"","width":1,"height":1}]';
        await _seedFact(
          writer,
          id: _factAttachNoOp,
          text: 'Unchanged',
          attachmentsJson: snap,
        );
        final outcome = await edit(
          _factAttachNoOp,
          _editorAId,
          'Unchanged',
          1,
          attachmentsJson: snap,
        );
        expect(
          outcome,
          isA<FactEditNoOp>().having((o) => o.currentSeq, 'currentSeq', 1),
        );
        expect(await revisionCount(_factAttachNoOp), 1);
      },
      skip: skipReason,
    );

    test(
      'restore restores attachments from the chosen seq',
      () async {
        await _seedFact(
          writer,
          id: _factAttachRestore,
          text: 'v1',
          attachmentsJson: '[{"id":"Av1","kind":1,"position":0,'
              '"mime":"image/jpeg","sizeBytes":1,"fileName":"v1.jpg",'
              '"imageId":"Iv1","imageAuthorId":"$_pinnerId",'
              '"blurHash":"","width":1,"height":1}]',
        );
        expect(
          await edit(
            _factAttachRestore,
            _editorAId,
            'v2',
            1,
            attachmentsJson: '[{"id":"Av2","kind":1,"position":0,'
                '"mime":"image/jpeg","sizeBytes":2,"fileName":"v2.jpg",'
                '"imageId":"Iv2","imageAuthorId":"$_editorAId",'
                '"blurHash":"","width":2,"height":2}]',
          ),
          isA<FactEditApplied>(),
        );
        expect(
          await restore(_factAttachRestore, _editorAId, 1, 2),
          isA<FactEditApplied>().having((o) => o.newSeq, 'newSeq', 3),
        );
        final snap = await writer.execute(
          Sql.named('''
SELECT fact_text, attachments_json::text
FROM public.beacon_fact_card_revision
WHERE fact_card_id = @id AND seq = 3
'''),
          parameters: {'id': _factAttachRestore},
        );
        expect(snap.single[0], 'v1');
        expect(snap.single[1] as String, contains('Av1'));
        expect(snap.single[1] as String, isNot(contains('Av2')));
      },
      skip: skipReason,
    );

    test(
      'null sourceMessageId fact can gain images via attachmentsJson',
      () async {
        await _seedFact(
          writer,
          id: _factNoSource,
          text: 'Manual pin',
        );
        const next = '[{"id":"Aadd","kind":1,"position":0,'
            '"mime":"image/jpeg","sizeBytes":5,"fileName":"add.jpg",'
            '"imageId":"Iadd","imageAuthorId":"$_editorAId",'
            '"blurHash":"","width":3,"height":3}]';
        expect(
          await edit(
            _factNoSource,
            _editorAId,
            'Manual pin',
            1,
            attachmentsJson: next,
          ),
          isA<FactEditApplied>(),
        );
        final source = await writer.execute(
          Sql.named('''
SELECT source_message_id FROM public.beacon_fact_card WHERE id = @id
'''),
          parameters: {'id': _factNoSource},
        );
        expect(source.single.single, isNull);
        final snap = await writer.execute(
          Sql.named('''
SELECT attachments_json::text FROM public.beacon_fact_card_revision
WHERE fact_card_id = @id AND seq = 2
'''),
          parameters: {'id': _factNoSource},
        );
        expect(snap.single.single as String, contains('Aadd'));
      },
      skip: skipReason,
    );
  });
}

// ---------------------------------------------------------------------------
// Fixture: a beacon authored by a separate author; the pinner, two editors, a
// rate-limited editor and a pinner whose account the orphan test deletes.
// Each test seeds its own fact (revision 1, kind created, by the pinner).

const _authorId = 'Ufeauthor01';
const _pinnerId = 'Ufepinner01';
const _editorAId = 'Ufeeditor0A';
const _editorBId = 'Ufeeditor0B';
const _editorRateId = 'Ufeeditrate';
const _doomedPinnerId = 'Ufepindoom1';

const _beaconId = 'Bfebeacon01';

const _factApplied = 'Ffeapplied1';
const _factCount = 'Ffecount001';
const _factStale = 'Ffestale001';
const _factNoOp = 'Ffenoop0001';
const _factRemoved = 'Fferemoved1';
const _factRate = 'Fferate0001';
const _factRestoreMissing = 'Fferestmiss';
const _factRestore = 'Fferestore1';
const _factQuiet = 'Ffequiet001';
const _factOrphan = 'Ffeorphan01';
const _factEditors = 'Ffeeditors1';
const _factRace = 'Fferace0001';
const _factResubmit = 'Fferesubmit';
const _factStatusProbe = 'Ffestatprob';
const _factAttachOnly = 'Ffeattach01';
const _factAttachNoOp = 'Ffeattnoop';
const _factAttachRestore = 'Ffeattrest';
const _factNoSource = 'Ffenosource';

final _t0 = DateTime.utc(2026, 3, 1, 12);

Future<void> _seedBase(Connection writer) async {
  var n = 0;
  for (final id in [
    _authorId,
    _pinnerId,
    _editorAId,
    _editorBId,
    _editorRateId,
    _doomedPinnerId,
  ]) {
    n++;
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('factedit', n)},
    );
  }
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
VALUES (@beacon, @author, 't', 'd', 0, @t0, false)
'''),
    parameters: {'beacon': _beaconId, 'author': _authorId, 't0': _t0},
  );
}

/// Seeds a fact at revision 1. [fresh] pins it now (inside the quiet
/// window); otherwise it and its revision date from [_t0].
Future<void> _seedFact(
  Connection writer, {
  required String id,
  required String text,
  String pinnedBy = _pinnerId,
  int status = BeaconFactCardStatusBits.active,
  bool fresh = false,
  String attachmentsJson = '[]',
}) async {
  final createdAt = fresh ? DateTime.timestamp() : _t0;
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, created_at,
   updated_at, revision_seq)
VALUES (@id, @beacon, @text, ${BeaconFactCardVisibilityBits.public}, @pinner,
        @status, @at, @at, 1)
'''),
    parameters: {
      'id': id,
      'beacon': _beaconId,
      'text': text,
      'pinner': pinnedBy,
      'status': status,
      'at': createdAt,
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at, attachments_json)
VALUES (@id, 1, @text, @pinner, ${BeaconFactCardRevisionKindBits.created}, @at,
        @att::jsonb)
'''),
    parameters: {
      'id': id,
      'text': text,
      'pinner': pinnedBy,
      'at': createdAt,
      'att': attachmentsJson,
    },
  );
}
