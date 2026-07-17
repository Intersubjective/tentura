import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/port/attention_channel_delivery_port.dart';

import '../database/tentura_db.dart';

@Singleton(as: AttentionChannelDeliveryPort)
class AttentionChannelDeliveryRepository
    implements AttentionChannelDeliveryPort {
  const AttentionChannelDeliveryRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<AttentionChannelDelivery>> claimDue({
    required String workerId,
    required DateTime now,
    required int limit,
  }) async {
    final rows = await _database
        .customSelect(
          r'''WITH due AS (
  SELECT id FROM public.attention_channel_delivery
  WHERE (status = 'pending' AND available_at <= $1::timestamptz)
     OR (status = 'leased' AND lease_until <= $1::timestamptz)
  ORDER BY available_at, created_at, id
  FOR UPDATE SKIP LOCKED
  LIMIT $2
), reserved AS (
  INSERT INTO public.attention_channel_throttle (
    account_id, channel, lease_until
  )
  SELECT job.account_id, 'immediate', $1::timestamptz + interval '1 minute'
  FROM public.attention_channel_delivery job
  JOIN due ON due.id = job.id
  ON CONFLICT (account_id, channel) DO UPDATE
    SET lease_until = EXCLUDED.lease_until
    WHERE attention_channel_throttle.lease_until <= $1::timestamptz
  RETURNING account_id
)
UPDATE public.attention_channel_delivery job
SET status = 'leased', attempts = attempts + 1, lease_owner = $3,
    lease_until = $1::timestamptz + interval '2 minutes'
FROM due, reserved
WHERE job.id = due.id AND reserved.account_id = job.account_id
RETURNING job.id, job.payload::text AS payload''',
          variables: [
            Variable<String>(now.toUtc().toIso8601String()),
            Variable<int>(limit),
            Variable<String>(workerId),
          ],
        )
        .get();
    return [
      for (final row in rows)
        AttentionChannelDelivery(
          id: row.read<String>('id'),
          decision: _decision(jsonDecode(row.read<String>('payload')) as Map),
        ),
    ];
  }

  @override
  Future<void> markDelivered({required String id, required String workerId}) =>
      _database.customStatement(
        r'''UPDATE public.attention_channel_delivery
SET status = 'delivered', delivered_at = now(), lease_owner = NULL, lease_until = NULL
WHERE id = $1 AND status = 'leased' AND lease_owner = $2''',
        [id, workerId],
      );

  @override
  Future<void> retryOrDeadLetter({
    required String id,
    required String workerId,
    required DateTime now,
    required Object error,
  }) => _database.customStatement(
    r'''UPDATE public.attention_channel_delivery
SET status = CASE WHEN attempts >= 5 THEN 'dead' ELSE 'pending' END,
    available_at = CASE WHEN attempts >= 5 THEN available_at ELSE $3::timestamptz + (attempts * interval '30 seconds') END,
    dead_lettered_at = CASE WHEN attempts >= 5 THEN now() ELSE NULL END,
    last_error = left($4, 1000), lease_owner = NULL, lease_until = NULL
WHERE id = $1 AND status = 'leased' AND lease_owner = $2''',
    [id, workerId, now.toUtc().toIso8601String(), error.toString()],
  );

  AttentionChannelDecision _decision(Map value) => AttentionChannelDecision(
    receiptId: value['receiptId']! as String,
    recipientId: value['recipientId']! as String,
    kind: NotificationKind.values.byName(value['kind']! as String),
    priority: NotificationPriority.values.byName(value['priority']! as String),
    title: value['title']! as String,
    body: value['body']! as String,
    actionUrl: value['actionUrl']! as String,
    dedupKey: value['dedupKey']! as String,
    actorUserId: value['actorUserId']! as String,
    reason: value['reason']! as String,
    beaconId: value['beaconId'] as String?,
    coordinationItemId: value['coordinationItemId'] as String?,
  );
}
