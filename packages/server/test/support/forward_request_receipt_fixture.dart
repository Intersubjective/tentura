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
