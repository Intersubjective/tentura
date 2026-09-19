@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_clear_repository.dart';
import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/use_case/attention_clear_case.dart';

import '../../support/disposable_pg_target.dart';

/// U08 — the clear command's storage guarantees.
///
/// This group holds the two refusals the schema itself owes us. They are
/// asserted *by constraint name*, because a test that merely observes "the
/// write failed" would keep passing if the failure moved to some unrelated
/// constraint.
///
/// The FK case is carried in from U04's verify: U08 is the first writer of
/// `cleared_by_operation_id`, and until now nothing proved the FK refuses an
/// operation id that does not exist.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U08_CLEAR_TEST_DB',
    defaultNamePrefix: 'tentura_test_u08_clear',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('clear-state constraints', () {
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
      await _resetFixtures(writer);
    });

    test(
      'notification_outbox__cleared_by_operation_fkey rejects an unknown '
      'operation id',
      () async {
        await _insertReceipt(writer, id: 'Nu08fkey', beaconId: _beaconId);

        await expectLater(
          writer.execute(
            Sql.named('''
UPDATE public.notification_outbox
   SET cleared_at = now(),
       clear_reason = 'explicit',
       cleared_by_operation_id = @operationId
 WHERE id = 'Nu08fkey'
'''),
            parameters: {'operationId': 'OPu08doesnotexist'},
          ),
          throwsA(
            isA<ServerException>().having(
              (error) => error.constraintName,
              'constraintName',
              'notification_outbox__cleared_by_operation_fkey',
            ),
          ),
        );

        final after = await writer.execute(
          "SELECT cleared_at FROM public.notification_outbox WHERE id = 'Nu08fkey'",
        );
        expect(after.first.first, isNull);
      },
    );

    test(
      'an obligation cannot be cleared: '
      'notification_outbox__clear_optional_only_chk is the catcher',
      () async {
        // The eligible predicate (`NOT requires_action AND cleared_at IS NULL`)
        // is what keeps obligations out of every token this unit issues. This
        // test is the second line: if that predicate ever regresses, the write
        // still has to be refused, and by this constraint specifically.
        await _insertReceipt(
          writer,
          id: 'Nu08oblig',
          beaconId: _beaconId,
          requiresAction: true,
        );
        await _insertOperation(writer, id: 'OPu08oblig');

        await expectLater(
          writer.execute('''
UPDATE public.notification_outbox
   SET cleared_at = now(),
       clear_reason = 'explicit',
       cleared_by_operation_id = 'OPu08oblig'
 WHERE id = 'Nu08oblig'
'''),
          throwsA(
            isA<ServerException>().having(
              (error) => error.constraintName,
              'constraintName',
              'notification_outbox__clear_optional_only_chk',
            ),
          ),
        );
      },
    );
  }, skip: skipReason);

  group('attentionClear', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionClearCase clear;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      clear = AttentionClearCase(AttentionClearRepository(database));
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    setUp(() async {
      await _resetFixtures(writer);
    });

    test('captures the active optional receipts of one Request', () async {
      await _insertReceipt(writer, id: 'Nu08capa', beaconId: _beaconId);
      await _insertReceipt(writer, id: 'Nu08capb', beaconId: _beaconId);
      // Neither of these may ever enter a token.
      await _insertReceipt(
        writer,
        id: 'Nu08capoblig',
        beaconId: _beaconId,
        requiresAction: true,
      );
      await _insertReceipt(
        writer,
        id: 'Nu08capother',
        beaconId: _forwardedBeaconId,
      );

      final snapshot = await clear.captureSnapshot(
        accountId: _viewerId,
        beaconId: _beaconId,
        kind: AttentionClearCaptureKind.requestOpen,
      );

      expect(snapshot.receiptIds.toSet(), {'Nu08capa', 'Nu08capb'});
      // `attention_request_state` has no writer until U09/U10, so the outcome
      // identity binds as 0/0 today — honest, and already carried through to
      // the operation members.
      expect(snapshot.outcomeGeneration, 0);
      expect(snapshot.decisionRevision, 0);
    });

    test('an event committed after the capture survives the clear', () async {
      await _insertReceipt(writer, id: 'Nu08racea', beaconId: _beaconId);

      final snapshot = await clear.captureSnapshot(
        accountId: _viewerId,
        beaconId: _beaconId,
        kind: AttentionClearCaptureKind.requestOpen,
      );

      // Between capture and apply. The boundary is membership, never a
      // wall-clock instant, so this row is simply not a member.
      await _insertReceipt(
        writer,
        id: 'Nu08raceb',
        beaconId: _beaconId,
        createdAt: '2026-09-16T09:00:00Z',
      );

      final result = await clear.clear(
        accountId: _viewerId,
        operationId: 'OPu08race',
        snapshotToken: snapshot.token,
      );

      expect(result.appliedReceiptIds, ['Nu08racea']);
      expect(result.status, AttentionClearStatus.complete);
      expect(await _clearedAt(writer, 'Nu08racea'), isNotNull);
      expect(
        await _clearedAt(writer, 'Nu08raceb'),
        isNull,
        reason: 'an event that arrived after the capture is not a member',
      );
    });

    test('records the clear facts and the operation membership', () async {
      await _insertReceipt(writer, id: 'Nu08facts', beaconId: _beaconId);

      final snapshot = await clear.captureSnapshot(
        accountId: _viewerId,
        beaconId: _beaconId,
        kind: AttentionClearCaptureKind.explicit,
      );
      await clear.clear(
        accountId: _viewerId,
        operationId: 'OPu08facts',
        snapshotToken: snapshot.token,
      );

      final row = await writer.execute(
        'SELECT clear_reason, cleared_by_operation_id '
        "FROM public.notification_outbox WHERE id = 'Nu08facts'",
      );
      expect(row.first[0], 'explicit');
      // Every clear this unit performs is operation-backed: the operation row
      // is what makes replay idempotent and U09's undo possible at all.
      expect(row.first[1], 'OPu08facts');

      final member = await writer.execute(
        'SELECT beacon_id, outcome_generation, state '
        'FROM public.attention_clear_operation_member '
        "WHERE operation_id = 'OPu08facts'",
      );
      expect(member.first[0], _beaconId);
      expect(member.first[1], 0);
      expect(member.first[2], 'applied');
    });

    test('a replayed operation id has exactly one effect', () async {
      await _insertReceipt(writer, id: 'Nu08replaya', beaconId: _beaconId);

      final snapshot = await clear.captureSnapshot(
        accountId: _viewerId,
        beaconId: _beaconId,
        kind: AttentionClearCaptureKind.explicit,
      );
      final first = await clear.clear(
        accountId: _viewerId,
        operationId: 'OPu08replay',
        snapshotToken: snapshot.token,
      );
      final clearedAt = await _clearedAt(writer, 'Nu08replaya');

      // A receipt that arrived after the first apply must not be swept up by
      // the replay: a replay returns the first result, it does not re-capture.
      await _insertReceipt(writer, id: 'Nu08replayb', beaconId: _beaconId);

      final second = await clear.clear(
        accountId: _viewerId,
        operationId: 'OPu08replay',
        snapshotToken: snapshot.token,
      );

      expect(second.appliedReceiptIds, first.appliedReceiptIds);
      expect(second.skippedReceiptIds, first.skippedReceiptIds);
      expect(second.deniedReceiptIds, first.deniedReceiptIds);
      expect(second.status, first.status);
      expect(
        await _clearedAt(writer, 'Nu08replaya'),
        clearedAt,
        reason: 'the second apply must not re-stamp cleared_at',
      );
      expect(await _clearedAt(writer, 'Nu08replayb'), isNull);
      expect(await _countOperations(writer, 'OPu08replay'), 1);
      expect(await _countMembers(writer, 'OPu08replay'), 1);
    });

    test(
      'a concurrently replayed operation id has exactly one effect',
      () async {
        await _insertReceipt(writer, id: 'Nu08conc', beaconId: _beaconId);

        final snapshot = await clear.captureSnapshot(
          accountId: _viewerId,
          beaconId: _beaconId,
          kind: AttentionClearCaptureKind.explicit,
        );
        // A second connection, so the two applies really do race in Postgres
        // rather than being serialized by one drift executor.
        final rival = openDisposablePgDatabase(target);
        addTearDown(rival.close);
        final rivalClear = AttentionClearCase(AttentionClearRepository(rival));

        final results = await Future.wait([
          clear.clear(
            accountId: _viewerId,
            operationId: 'OPu08conc',
            snapshotToken: snapshot.token,
          ),
          rivalClear.clear(
            accountId: _viewerId,
            operationId: 'OPu08conc',
            snapshotToken: snapshot.token,
          ),
        ]);

        expect(results.first.appliedReceiptIds, ['Nu08conc']);
        expect(results.last.appliedReceiptIds, ['Nu08conc']);
        expect(results.first.status, results.last.status);
        expect(await _countOperations(writer, 'OPu08conc'), 1);
        expect(await _countMembers(writer, 'OPu08conc'), 1);
        final applied = await writer.execute(
          'SELECT applied FROM public.attention_clear_operation '
          "WHERE id = 'OPu08conc'",
        );
        expect(applied.first.first, 1);
      },
    );

    test(
      'a Request that left the viewer scope between capture and apply is '
      'skipped, not cleared',
      () async {
        await _insertReceipt(
          writer,
          id: 'Nu08scope',
          beaconId: _forwardedBeaconId,
        );

        final snapshot = await clear.captureSnapshot(
          accountId: _viewerId,
          beaconId: _forwardedBeaconId,
          kind: AttentionClearCaptureKind.requestOpen,
        );
        expect(snapshot.receiptIds, ['Nu08scope']);

        // Authorization is lost mid-operation: the author blocks the viewer,
        // so `visible_attention_receipts` stops returning the row.
        await writer.execute(
          Sql.named(
            'INSERT INTO public.user_block '
            '(blocker_id, blocked_id, origin_id) '
            'VALUES (@authorId, @viewerId, @authorId)',
          ),
          parameters: {'authorId': _authorId, 'viewerId': _viewerId},
        );

        final result = await clear.clear(
          accountId: _viewerId,
          operationId: 'OPu08scope',
          snapshotToken: snapshot.token,
        );

        expect(result.appliedReceiptIds, isEmpty);
        expect(result.skippedReceiptIds, ['Nu08scope']);
        expect(result.status, AttentionClearStatus.stale);
        expect(await _clearedAt(writer, 'Nu08scope'), isNull);
        final member = await writer.execute(
          'SELECT state FROM public.attention_clear_operation_member '
          "WHERE operation_id = 'OPu08scope'",
        );
        expect(member.first.first, 'skipped');
      },
    );

    test(
      'a foreign receipt is denied exactly as a receipt that does not exist',
      () async {
        await _insertReceipt(writer, id: 'Nu08mine', beaconId: _beaconId);
        await _insertReceipt(
          writer,
          id: 'Nu08theirs',
          beaconId: _forwardedBeaconId,
          accountId: _authorId,
        );

        final tampered = const AttentionClearSnapshotToken(
          accountId: _viewerId,
          beaconId: null,
          kind: AttentionClearCaptureKind.explicit,
          outcomeGeneration: 0,
          decisionRevision: 0,
          receiptIds: ['Nu08mine', 'Nu08theirs', 'Nu08ghost'],
        ).encode();

        final result = await clear.clear(
          accountId: _viewerId,
          operationId: 'OPu08foreign',
          snapshotToken: tampered,
        );

        expect(result.appliedReceiptIds, ['Nu08mine']);
        expect(
          result.deniedReceiptIds,
          ['Nu08ghost', 'Nu08theirs'],
          reason:
              'an existing foreign receipt and a receipt that never existed '
              'are reported identically, so the answer discloses neither',
        );
        expect(result.status, AttentionClearStatus.partial);
        expect(await _clearedAt(writer, 'Nu08theirs'), isNull);
      },
    );

    test('a token issued for another account clears nothing', () async {
      await _insertReceipt(writer, id: 'Nu08cross', beaconId: _beaconId);

      final snapshot = await clear.captureSnapshot(
        accountId: _viewerId,
        beaconId: _beaconId,
        kind: AttentionClearCaptureKind.explicit,
      );

      final result = await clear.clear(
        accountId: _strangerId,
        operationId: 'OPu08cross',
        snapshotToken: snapshot.token,
      );

      expect(result.status, AttentionClearStatus.denied);
      expect(result.appliedReceiptIds, isEmpty);
      expect(await _clearedAt(writer, 'Nu08cross'), isNull);
      expect(
        await _countOperations(writer, 'OPu08cross'),
        0,
        reason: 'a denied token must not even leave an operation row',
      );
    });

    test(
      'an obligation forced into a token is skipped, never cleared',
      () async {
        await _insertReceipt(
          writer,
          id: 'Nu08tokenoblig',
          beaconId: _beaconId,
          requiresAction: true,
        );

        final tampered = const AttentionClearSnapshotToken(
          accountId: _viewerId,
          beaconId: _beaconId,
          kind: AttentionClearCaptureKind.explicit,
          outcomeGeneration: 0,
          decisionRevision: 0,
          receiptIds: ['Nu08tokenoblig'],
        ).encode();

        final result = await clear.clear(
          accountId: _viewerId,
          operationId: 'OPu08tokenoblig',
          snapshotToken: tampered,
        );

        expect(result.appliedReceiptIds, isEmpty);
        expect(result.skippedReceiptIds, ['Nu08tokenoblig']);
        expect(await _clearedAt(writer, 'Nu08tokenoblig'), isNull);
      },
    );

    test(
      'clearing does not change the read axis yet (U10 owns the indicators)',
      () async {
        // Deliberate: `attentionFeed` and `surfaceSummary` still read
        // `seen_at`. A cleared-but-unseen receipt keeps its dot until U10
        // switches the indicators to the optional axis. This is not a bug.
        await _insertReceipt(writer, id: 'Nu08feed', beaconId: _beaconId);

        final snapshot = await clear.captureSnapshot(
          accountId: _viewerId,
          beaconId: _beaconId,
          kind: AttentionClearCaptureKind.explicit,
        );
        await clear.clear(
          accountId: _viewerId,
          operationId: 'OPu08feed',
          snapshotToken: snapshot.token,
        );

        final row = await writer.execute(
          'SELECT seen_at FROM public.notification_outbox '
          "WHERE id = 'Nu08feed'",
        );
        expect(row.first.first, isNull);
      },
    );
  }, skip: skipReason);
}

Future<DateTime?> _clearedAt(Connection writer, String id) async {
  final row = await writer.execute(
    Sql.named(
      'SELECT cleared_at FROM public.notification_outbox WHERE id = @id',
    ),
    parameters: {'id': id},
  );
  return row.first.first as DateTime?;
}

Future<int> _countOperations(Connection writer, String operationId) async {
  final row = await writer.execute(
    Sql.named(
      'SELECT count(*)::int FROM public.attention_clear_operation '
      'WHERE id = @id',
    ),
    parameters: {'id': operationId},
  );
  return row.first.first! as int;
}

Future<int> _countMembers(Connection writer, String operationId) async {
  final row = await writer.execute(
    Sql.named(
      'SELECT count(*)::int FROM public.attention_clear_operation_member '
      'WHERE operation_id = @id',
    ),
    parameters: {'id': operationId},
  );
  return row.first.first! as int;
}

const _viewerId = 'Uu08clear01';
const _authorId = 'Uu08clear02';
const _strangerId = 'Uu08clear03';
const _beaconId = 'Bu08clearown';
const _forwardedBeaconId = 'Bu08clearfwd';

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.user_block,
  public.beacon_forward_edge,
  public.attention_clear_operation,
  public.attention_request_state,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_viewerId, _authorId, _strangerId]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': '$id-key'},
    );
  }
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES
  (@ownedId, @viewerId, 'Owned', 'Owned request', 0),
  (@forwardedId, @authorId, 'Forwarded', 'Forwarded request', 0)
'''),
    parameters: {
      'ownedId': _beaconId,
      'forwardedId': _forwardedBeaconId,
      'viewerId': _viewerId,
      'authorId': _authorId,
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fu08clear01', @beaconId, @senderId, @recipientId)
'''),
    parameters: {
      'beaconId': _forwardedBeaconId,
      'senderId': _authorId,
      'recipientId': _viewerId,
    },
  );
}

Future<void> _insertOperation(
  Connection writer, {
  required String id,
  String accountId = _viewerId,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.attention_clear_operation (id, account_id, surface, status)
VALUES (@id, @accountId, 'explicit', 'complete')
'''),
  parameters: {'id': id, 'accountId': accountId},
);

Future<void> _insertReceipt(
  Connection writer, {
  required String id,
  required String beaconId,
  String accountId = _viewerId,
  String createdAt = '2026-09-16T10:00:00Z',
  bool requiresAction = false,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Title', 'Body', '/attention', @dedupKey,
  CAST(@createdAt AS timestamptz),
  @beaconId, @sourceEventKey,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  @requiresAction, @threadKey
)
'''),
  parameters: {
    'id': id,
    'accountId': accountId,
    'dedupKey': 'dedup-$id',
    'createdAt': createdAt,
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
    'requiresAction': requiresAction,
    'threadKey': requiresAction ? 'v1|needsMe|$id|$accountId' : null,
  },
);
