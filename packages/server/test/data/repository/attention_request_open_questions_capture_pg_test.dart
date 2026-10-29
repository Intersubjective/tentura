@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_clear_repository.dart';
import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/use_case/attention_clear_case.dart';

import '../../support/disposable_pg_target.dart';

/// Opening a Request absorbs its optional updates — except the Questions
/// messages the viewer has not seen. Those are cleared when Questions is
/// opened (by hand, one receipt at a time), so a viewer who goes to the
/// Request first still finds them waiting on the card.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_QUESTIONS_OPEN_CLEAR_TEST_DB',
    defaultNamePrefix: 'tentura_test_questions_open_clear',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('clearing on opening a Request leaves unseen Questions messages', () {
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

    test('opening the Request does not capture a Questions message', () async {
      await _insertReceipt(writer, id: 'Nqoc-status');
      await _insertReceipt(writer, id: 'Nqoc-question', questions: true);

      final snapshot = await clear.captureSnapshot(
        accountId: _viewerId,
        beaconId: _beaconId,
        kind: AttentionClearCaptureKind.requestOpen,
      );

      expect(snapshot.receiptIds, ['Nqoc-status']);
    });

    test('a Questions message survives the clear applied on open', () async {
      await _insertReceipt(writer, id: 'Nqoc-status');
      await _insertReceipt(writer, id: 'Nqoc-question', questions: true);

      final snapshot = await clear.captureSnapshot(
        accountId: _viewerId,
        beaconId: _beaconId,
        kind: AttentionClearCaptureKind.requestOpen,
      );
      await clear.clear(
        accountId: _viewerId,
        operationId: 'OPqoc-open',
        snapshotToken: snapshot.token,
      );

      expect(await _clearedAt(writer, 'Nqoc-status'), isNotNull);
      expect(
        await _clearedAt(writer, 'Nqoc-question'),
        isNull,
        reason: 'the viewer has not been to Questions yet',
      );
    });

    test('opening Questions clears its message by hand', () async {
      await _insertReceipt(writer, id: 'Nqoc-question', questions: true);

      final snapshot = await clear.captureSnapshot(
        accountId: _viewerId,
        receiptId: 'Nqoc-question',
        kind: AttentionClearCaptureKind.explicit,
      );
      final result = await clear.clear(
        accountId: _viewerId,
        operationId: 'OPqoc-questions',
        snapshotToken: snapshot.token,
      );

      expect(result.appliedReceiptIds, ['Nqoc-question']);
      expect(await _clearedAt(writer, 'Nqoc-question'), isNotNull);
    });
  }, skip: skipReason);
}

const _viewerId = 'Uqoc01';
const _beaconId = 'Bqocown';

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.attention_clear_operation,
  public.attention_request_state,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
    parameters: {'id': _viewerId, 'key': '$_viewerId-key'},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @viewerId, 'Owned', 'Owned request', 0)
'''),
    parameters: {'id': _beaconId, 'viewerId': _viewerId},
  );
}

/// An optional receipt on [_beaconId]. With [questions] it is what the server
/// writes for a message in Questions: a `roomActivityLowPriority` receipt for
/// a room message (`beacon_room_message`) tied to the Questions coordination
/// item. Without it, a plain Request status change.
Future<void> _insertReceipt(
  Connection writer, {
  required String id,
  bool questions = false,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, target_entity_id,
  presentation_key, presentation_payload,
  coordination_item_id,
  suppression_class, access_policy,
  requires_action
) VALUES (
  @id, @accountId, 'coordination', @kind, 'normal',
  'Title', 'Body', '/attention', @dedupKey,
  CAST('2026-10-29T10:00:00Z' AS timestamptz),
  @beaconId, @sourceEventKey,
  @destinationKind, @targetEntityId,
  @presentationKey, CAST(@payload AS jsonb),
  @coordinationItemId,
  'standard', 'beacon_content',
  false
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'dedupKey': 'dedup-$id',
    'beaconId': _beaconId,
    'sourceEventKey': 'source-$id',
    'kind': questions ? 'roomActivityLowPriority' : 'coordinationChanged',
    'destinationKind': questions ? 'beacon_room_message' : 'beacon',
    'targetEntityId': questions ? 'message-$id' : null,
    'presentationKey': questions
        ? 'room_message_posted'
        : 'request_status_changed',
    'payload': jsonEncode(
      questions
          ? {
              'eventType': 'roomMessagePosted',
              'beaconId': _beaconId,
              'coordinationItemId': 'questions-1',
            }
          : {'eventType': 'fixture'},
    ),
    'coordinationItemId': questions ? 'questions-1' : null,
  },
);

Future<Object?> _clearedAt(Connection writer, String id) async {
  final rows = await writer.execute(
    Sql.named('SELECT cleared_at FROM public.notification_outbox WHERE id = @id'),
    parameters: {'id': id},
  );
  return rows.first.first;
}
