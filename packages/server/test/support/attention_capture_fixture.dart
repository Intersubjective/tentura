import 'dart:convert';

import 'package:postgres/postgres.dart';

import 'package:tentura_server/data/repository/attention_sweep_repository.dart';

/// Fixtures for tests that drive an Activity clear *while its capture is
/// half-done*.
///
/// A capture is persisted as a frozen snapshot on the operation header and
/// committed into member rows one bounded chunk at a time, advancing
/// `capture_cursor` as it goes. These helpers reproduce the committed state of
/// such a capture by hand, so a test can hold it at an exact point instead of
/// hoping a race lands there.
const captureViewerId = 'Ucapture0001';
const captureAuthorId = 'Ucapture0002';
const captureBeaconId = 'Bcapture01';

/// One forwarded Request and [receiptCount] clearable receipts for the viewer.
Future<List<String>> resetCaptureFixtures(
  Connection writer, {
  int receiptCount = 0,
}) async {
  await writer.execute('''
TRUNCATE TABLE
  public.inbox_item,
  public.beacon_forward_edge,
  public.attention_clear_operation,
  public.attention_request_state,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [captureViewerId, captureAuthorId]) {
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
VALUES (@id, @authorId, 'Forwarded', 'Forwarded request', 0)
'''),
    parameters: {'id': captureBeaconId, 'authorId': captureAuthorId},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES (@id, @beaconId, @senderId, @recipientId)
'''),
    parameters: {
      'id': 'Fcapture01',
      'beaconId': captureBeaconId,
      'senderId': captureAuthorId,
      'recipientId': captureViewerId,
    },
  );
  final receiptIds = [
    for (var index = 0; index < receiptCount; index++) 'Ncapture$index',
  ];
  for (final id in receiptIds) {
    await writer.execute(
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
  'Title', 'Body', '/attention', @dedupKey, now(),
  @beaconId, @sourceEventKey,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  false, NULL
)
'''),
      parameters: {
        'id': id,
        'accountId': captureViewerId,
        'dedupKey': 'dedup-$id',
        'beaconId': captureBeaconId,
        'sourceEventKey': 'source-$id',
      },
    );
  }
  return receiptIds;
}

/// The viewer's whole dismissible surface, in the shape the operation header
/// stores it: the repository's own capture statement, not a paraphrase.
Future<List<Map<String, Object?>>> readCaptureSurface(Session session) async {
  final rows = await session.execute(
    AttentionSweepRepository.captureSql,
    parameters: [captureViewerId],
  );
  return [
    for (final row in rows)
      {
        'kind': row[0],
        'member_id': row[1],
        'beacon_id': row[2],
        'outcome_generation': row[3],
        'decision_revision': row[4],
      },
  ];
}

/// An operation header exactly as the first capture transaction leaves it:
/// `pending`, snapshot frozen, nothing committed into members yet.
Future<void> seedPendingCapture(
  Session session, {
  required String operationId,
  required List<Map<String, Object?>> snapshot,
  Duration age = Duration.zero,
}) => session.execute(
  Sql.named('''
INSERT INTO public.attention_clear_operation
  (id, account_id, surface, status, applied, skipped, failed,
   capture_snapshot, capture_cursor, captured_at)
VALUES
  (@id, @accountId, 'activity', 'pending', 0, 0, 0,
   @snapshot::jsonb, 0, now() - (@ageSeconds::int * interval '1 second'))
'''),
  parameters: {
    'id': operationId,
    'accountId': captureViewerId,
    'snapshot': jsonEncode(snapshot),
    'ageSeconds': age.inSeconds,
  },
);

/// One capture chunk, committed the way the repository commits it: the cursor
/// compare-and-set and the member rows in the same transaction. Returns false
/// when somebody else already moved the cursor past [start].
Future<bool> commitCaptureChunk(
  Session session, {
  required String operationId,
  required List<Map<String, Object?>> snapshot,
  required int start,
  required int next,
}) async {
  final claimed = await session.execute(
    Sql.named('''
UPDATE public.attention_clear_operation
   SET capture_cursor = @next,
       capture_snapshot = CASE WHEN @last THEN NULL ELSE capture_snapshot END
 WHERE id = @id AND capture_cursor = @start
'''),
    parameters: {
      'id': operationId,
      'start': start,
      'next': next,
      'last': next == snapshot.length,
    },
  );
  if (claimed.affectedRows == 0) return false;
  await session.execute(
    Sql.named('''
INSERT INTO public.attention_clear_operation_member
  (operation_id, receipt_id, outcome_beacon_id, beacon_id,
   outcome_generation, decision_revision, state)
SELECT @id,
  CASE WHEN m.kind = 'receipt' THEN m.member_id END,
  CASE WHEN m.kind = 'outcome' THEN m.member_id END,
  m.beacon_id, m.outcome_generation, m.decision_revision, 'pending'
FROM jsonb_to_recordset(@chunk::jsonb) AS m(kind text, member_id text,
  beacon_id text, outcome_generation integer, decision_revision integer)
ON CONFLICT DO NOTHING
'''),
    parameters: {
      'id': operationId,
      'chunk': jsonEncode(snapshot.sublist(start, next)),
    },
  );
  return true;
}

/// Moves an operation's `captured_at` back, as if its capture had been last
/// touched [age] ago, without touching the capture itself.
Future<void> ageCapture(
  Session session, {
  required String operationId,
  required Duration age,
}) => session.execute(
  Sql.named('''
UPDATE public.attention_clear_operation
   SET captured_at = now() - (@ageSeconds::int * interval '1 second')
 WHERE id = @id
'''),
  parameters: {'id': operationId, 'ageSeconds': age.inSeconds},
);
