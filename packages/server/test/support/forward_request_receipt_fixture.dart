import 'package:postgres/postgres.dart';

/// The viewer of the forwarded-Request History fixture. Socket authentication
/// uses production-valid user ids.
const forwardRequestViewerId = 'Ua00000000005';
const forwardRequestAuthorId = 'Ua00000000001';
const forwardRequestBeaconId = 'Bfwdreq000001';
const forwardRequestReceiptId = 'Nfwdrelay00001';
const forwardRequestPlainReceiptId = 'Nfwdplain00001';

/// A Request forwarded to [forwardRequestViewerId] by its author, with the
/// forward shell receipt (`relay_received`) and one ordinary optional receipt,
/// both unread. The viewer has not answered the forward.
Future<void> seedForwardRequestHistory(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@b, @a, 'Forwarded Request', 'Forwarded to the viewer', 0)
'''),
    parameters: {'b': forwardRequestBeaconId, 'a': forwardRequestAuthorId},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES ('FEfwdreq000001', @b, @a, @v, now(), NULL)
'''),
    parameters: {
      'b': forwardRequestBeaconId,
      'a': forwardRequestAuthorId,
      'v': forwardRequestViewerId,
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (@v, @b, 0, 1, now() - interval '2 hours', '', '')
ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = 0
'''),
    parameters: {'b': forwardRequestBeaconId, 'v': forwardRequestViewerId},
  );
  for (final (id, kind, category, key, payload) in [
    (
      forwardRequestReceiptId,
      'newRelay',
      'requestProgress',
      'relay_received',
      '{"eventType":"relayReceived","personal":true,'
          '"actorUserId":"$forwardRequestAuthorId",'
          '"beaconId":"$forwardRequestBeaconId",'
          '"beaconTitle":"Forwarded Request"}',
    ),
    (
      forwardRequestPlainReceiptId,
      'coordinationChanged',
      'coordination',
      'request_status_changed',
      '{"eventType":"fixture"}',
    ),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, actor_user_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy
) VALUES (
  @id, @v, @category, @kind, 'low',
  'Author', 'Forwarded Request', '/#/view?id=' || @b, @dedup,
  now() - interval '1 hour',
  @b, @a, @source,
  'beacon', @key, CAST(@payload AS jsonb),
  'standard', 'beacon_content'
)
'''),
      parameters: {
        'id': id,
        'v': forwardRequestViewerId,
        'category': category,
        'kind': kind,
        'b': forwardRequestBeaconId,
        'a': forwardRequestAuthorId,
        'dedup': 'dedup-$id',
        'source': 'source-$id',
        'key': key,
        'payload': payload,
      },
    );
  }
}

/// What an older «Read all» left behind: the viewer follows (`status = 1`) a
/// forwarded Request they never opened, its forward shell receipt is old and
/// seen-but-uncleared, and 59 newer unread optional receipts push it past the
/// first 50-item History page.
Future<void> seedLeftoverForwardRequestHistory(Connection writer) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@b, @a, 'Forwarded Request', 'Forwarded to the viewer', 0)
'''),
    parameters: {'b': forwardRequestBeaconId, 'a': forwardRequestAuthorId},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES ('FEfwdreq000001', @b, @a, @v, now() - interval '5 days', NULL)
'''),
    parameters: {
      'b': forwardRequestBeaconId,
      'a': forwardRequestAuthorId,
      'v': forwardRequestViewerId,
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (@v, @b, 1, 1, now() - interval '5 days', '', '')
ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = 1
'''),
    parameters: {'b': forwardRequestBeaconId, 'v': forwardRequestViewerId},
  );
  for (var i = -1; i < 59; i++) {
    final old = i < 0;
    final id = old
        ? forwardRequestReceiptId
        : 'Nfwdbulk${i.toString().padLeft(5, '0')}';
    await writer.execute(
      Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at,
  beacon_id, actor_user_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy
) VALUES (
  @id, @v, @category, @kind, 'low',
  'Author', 'Forwarded Request', '/#/view?id=' || @b, @dedup,
  CASE WHEN @old THEN now() - interval '4 days'
       ELSE now() - make_interval(mins => @i + 1) END,
  CASE WHEN @old THEN now() - interval '4 days' END,
  @b, @a, @source,
  'beacon', @key, CAST(@payload AS jsonb),
  'standard', 'beacon_content'
)
'''),
      parameters: {
        'id': id,
        'v': forwardRequestViewerId,
        'category': old ? 'requestProgress' : 'coordination',
        'kind': old ? 'newRelay' : 'coordinationChanged',
        'b': forwardRequestBeaconId,
        'a': forwardRequestAuthorId,
        'dedup': 'dedup-$id',
        'source': 'source-$id',
        'old': old,
        'i': i < 0 ? 0 : i,
        'key': old ? 'relay_received' : 'request_status_changed',
        'payload': old
            ? '{"eventType":"relayReceived","personal":true,'
                  '"actorUserId":"$forwardRequestAuthorId",'
                  '"beaconId":"$forwardRequestBeaconId",'
                  '"beaconTitle":"Forwarded Request"}'
            : '{"eventType":"fixture"}',
      },
    );
  }
}

const activityTombstoneBeaconId = 'Bfwdtomb00001';
const activityTombstoneRowId = 'inbox:$activityTombstoneBeaconId';

/// [seedForwardRequestHistory] plus a second forwarded Request that closed
/// before the viewer answered (inbox status 3), whose outcome row is unread.
Future<void> seedActivityTombstoneAndPendingForward(Connection writer) async {
  await seedForwardRequestHistory(writer);
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@b, @a, 'Closed forwarded Request', 'Closed before the viewer answered', 0)
'''),
    parameters: {'b': activityTombstoneBeaconId, 'a': forwardRequestAuthorId},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES ('FEfwdtomb00001', @b, @a, @v, now() - interval '3 hours', NULL)
'''),
    parameters: {
      'b': activityTombstoneBeaconId,
      'a': forwardRequestAuthorId,
      'v': forwardRequestViewerId,
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (@v, @b, 0, 1, now() - interval '3 hours', '', '')
ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = 0
'''),
    parameters: {'b': activityTombstoneBeaconId, 'v': forwardRequestViewerId},
  );
  // Closing the Request is what moves an unanswered inbox row to a tombstone
  // (the guard trigger refuses a direct write).
  await writer.execute(
    Sql.named('UPDATE public.beacon SET status = 1 WHERE id = @b'),
    parameters: {'b': activityTombstoneBeaconId},
  );
}
