import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_policy.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';

import '../database/tentura_db.dart';

@Singleton(as: AttentionDispatchPort)
class AttentionDispatchRepository implements AttentionDispatchPort {
  AttentionDispatchRepository(this._database, this._logger);

  final TenturaDb _database;
  final Logger _logger;

  static const _policy = AttentionPolicy();

  @override
  Future<void> record(AttentionDispatchIntent intent) async {
    final immutablePayload = jsonEncode(_occurrencePayload(intent));
    final occurrence = await _database
        .customSelect(
          r'''INSERT INTO public.attention_occurrence (
  source_event_key, event_type, actor_user_id, immutable_payload
) VALUES ($1, $2, $3, $4::jsonb)
ON CONFLICT (source_event_key) DO NOTHING
RETURNING id, occurred_at''',
          variables: [
            Variable<String>(intent.sourceEventKey),
            Variable<String>(intent.eventType.name),
            Variable<String>(intent.actorUserId),
            Variable<String>(immutablePayload),
          ],
        )
        .get();
    // The unique source identity is the transaction-level idempotency guard.
    // A reused key with different source facts is a producer bug, not a no-op.
    // Idempotency equality = {source_event_key, event_type, actor_user_id,
    // immutable_payload} at the occurrence grain (CR-9): a replay must match
    // all four, not just the key and payload.
    if (occurrence.isEmpty) {
      final matching = await _database
          .customSelect(
            r'''SELECT id FROM public.attention_occurrence
WHERE source_event_key = $1 AND immutable_payload = $2::jsonb
  AND event_type = $3 AND actor_user_id IS NOT DISTINCT FROM $4''',
            variables: [
              Variable<String>(intent.sourceEventKey),
              Variable<String>(immutablePayload),
              Variable<String>(intent.eventType.name),
              Variable<String>(intent.actorUserId),
            ],
          )
          .get();
      if (matching.isEmpty) {
        throw StateError(
          'Attention source_event_key was reused with different immutable facts: '
          '${intent.sourceEventKey}',
        );
      }
      return;
    }
    final occurrenceRow = occurrence.single;
    final occurrenceId = occurrenceRow.read<String>('id');
    // `occurred_at` is a Postgres `timestamptz`; Drift's `read<DateTime>` would
    // decode it as epoch millis and throw. Parse the string, as the other
    // repositories do — see drift_postgres_timestamptz_bind_inventory_test.
    final occurrenceAt = DateTime.parse(
      occurrenceRow.read<String>('occurred_at'),
    ).toUtc();
    for (final recipient in intent.recipients) {
      final role = recipient.role.copyWith(
        beaconId: recipient.role.beaconId ?? intent.beaconId,
        coordinationItemId:
            recipient.role.coordinationItemId ?? intent.coordinationItemId,
        targetEntityId: recipient.role.targetEntityId ?? intent.targetEntityId,
        messageId: recipient.role.messageId ?? intent.messageId,
        actorUserId: recipient.role.actorUserId ?? intent.actorUserId,
      );
      final projection = _policy.project(
        eventType: intent.eventType,
        recipientId: recipient.recipientId,
        recipientReasons: recipient.reasons,
        role: role,
      );
      final collapseKey = recipient.collapseKey ?? intent.collapseKey;
      final dedupKey = '${recipient.recipientId}|attention-v1|$collapseKey';
      await _database.customStatement(
        r'''INSERT INTO public.attention_occurrence_recipient (
  occurrence_id, account_id, reasons, role_facts, collapse_key, channel_eligible
) VALUES ($1, $2, $3::jsonb, $4::jsonb, $5, $6)''',
        [
          occurrenceId,
          recipient.recipientId,
          jsonEncode(recipient.reasons.map((reason) => reason.name).toList()),
          jsonEncode(_rolePayload(role)),
          collapseKey,
          recipient.channelEligible,
        ],
      );
      // A receipt is inserted, never rewritten. Until U05a this was an
      // `ON CONFLICT (dedup_key) WHERE seen_at IS NULL DO UPDATE` that
      // repointed an existing unseen row at the newest occurrence and reset
      // its `created_at`, so two distinct occurrences in one collapse family
      // shared a single mutable row. Now each `(occurrence_id, account_id)`
      // pair is its own immutable receipt; `dedup_key` keeps its
      // collapse-derived value purely as a lookup key, and m0179 removed the
      // uniqueness that used to forbid a second unseen row per family.
      //
      // Replay of a `source_event_key` is still dedupped above, at the
      // occurrence grain, and never reaches this statement. The remaining
      // guard against a duplicate receipt is m0178's UNIQUE
      // `notification_outbox__occurrence_account`, which raises rather than
      // silently overwriting — that is deliberate: a duplicate here would be
      // a producer bug, not a replay.
      // U05c — obligation identity. An obligation receipt names the *task* it
      // is about (`logical_task_key`, stable across renewals) and which
      // generation of that task it is. Optional receipts leave both NULL;
      // m0178's `notification_outbox__logical_task_chk` enforces that pairing.
      final logicalTaskKey = _policy.logicalTaskKey(
        eventType: intent.eventType,
        recipientId: recipient.recipientId,
        recipientReasons: recipient.reasons,
        role: role,
      );
      final lifecycleGeneration = logicalTaskKey == null ? null : 1;
      final row = await _database
          .customSelect(
            r'''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key,
  beacon_id, coordination_item_id, actor_user_id,
  source_event_key, occurrence_id, destination_kind, target_entity_id,
  presentation_key, presentation_payload,
  in_app_preference_class, suppression_class, access_policy,
  requires_action, attention_thread_key,
  logical_task_key, lifecycle_generation
) VALUES (
  gen_random_uuid()::text, $1, $2, $3, $4,
  $5, $6, $7, $8,
  $9, $10, $11,
  $12, $13, $14, $15,
  $16, $17::jsonb,
  $18, $19, $20,
  $21, $22,
  $23, $24
)
RETURNING id
''',
            variables: [
              Variable<String>(recipient.recipientId),
              Variable<String>(projection.category.name),
              Variable<String>(intent.kind.name),
              Variable<String>(intent.priority.name),
              Variable<String>(intent.title),
              Variable<String>(intent.body),
              Variable<String>(intent.actionUrl),
              Variable<String>(dedupKey),
              Variable<String>(intent.beaconId),
              Variable<String>(intent.coordinationItemId),
              Variable<String>(intent.actorUserId),
              Variable<String>(intent.sourceEventKey),
              Variable<String>(occurrenceId),
              Variable<String>(projection.destination.kind.wireName),
              Variable<String>(projection.destination.targetEntityId),
              Variable<String>(projection.presentationKey),
              Variable<String>(jsonEncode(projection.presentationPayload)),
              Variable<String>(projection.inAppPreferenceClass?.wireName),
              Variable<String>(projection.suppressionClass.name),
              Variable<String>(projection.accessPolicy.wireName),
              Variable<bool>(projection.requiresAction),
              Variable<String>(projection.attentionThreadKey),
              Variable<String>(logicalTaskKey),
              Variable<int>(lifecycleGeneration),
            ],
          )
          .getSingle();

      if (!recipient.channelEligible) {
        continue;
      }
      final decision = AttentionChannelDecision(
        receiptId: row.read<String>('id'),
        recipientId: recipient.recipientId,
        kind: intent.kind,
        priority: intent.priority,
        title: intent.title,
        body: intent.body,
        actionUrl: intent.actionUrl,
        dedupKey: dedupKey,
        actorUserId: intent.actorUserId ?? '',
        reason: recipient.reasons.map((reason) => reason.name).join(','),
        beaconId: intent.beaconId,
        coordinationItemId: intent.coordinationItemId,
      );
      // U05b — collapsing lives here, at the channel layer, and nowhere else.
      //
      // In-app receipts are one per occurrence and immutable (U05a). Push and
      // email must not be: a family of events sharing a collapse key is one
      // notification, and sending it twice is the user-visible defect that a
      // receipt-row count cannot see. So a new job coalesces into the
      // account's existing **pending** job for the same collapse family
      // instead of queueing a second send.
      //
      // The key is `attention_occurrence_recipient.collapse_key` — the one
      // that already exists, at the same `(occurrence_id, account_id)` grain
      // a delivery job has. Nothing is denormalised onto the delivery table;
      // m0180 adds the index that makes the join cheap.
      //
      // The coalesced job is repointed at the newest receipt and carries the
      // newest copy, so the `receiptId` the notification hands back always
      // resolves to a receipt that exists and has just been written — an
      // older sibling may have been cleared or settled by the time the worker
      // runs.
      //
      // Only `pending` is collapsed into. A `leased` send is already on its
      // way out and a `delivered`/`dead` one has left, so absorbing a later
      // event into either would drop a notification outright.
      //
      // Not atomic against a concurrent dispatch in the same family: two
      // transactions that both see no pending job both insert one. That is
      // the pre-existing behaviour for simultaneous events and is bounded by
      // `claimDue`'s per-account throttle; it is not made worse here.
      await _database.customStatement(
        r'''WITH target AS (
  SELECT job.id
  FROM public.attention_channel_delivery job
  JOIN public.attention_occurrence_recipient recipient
    ON recipient.occurrence_id = job.occurrence_id
   AND recipient.account_id = job.account_id
  WHERE job.account_id = $3
    AND job.status = 'pending'
    AND recipient.collapse_key = $5
  ORDER BY job.created_at DESC, job.id DESC
  LIMIT 1
), collapsed AS (
  UPDATE public.attention_channel_delivery job
  SET occurrence_id = $1, receipt_id = $2, payload = $4::jsonb
  WHERE job.id = (SELECT id FROM target)
  RETURNING job.id
)
INSERT INTO public.attention_channel_delivery (
  occurrence_id, receipt_id, account_id, payload
)
SELECT $1, $2, $3, $4::jsonb
WHERE NOT EXISTS (SELECT 1 FROM collapsed)''',
        [
          occurrenceId,
          decision.receiptId,
          decision.recipientId,
          jsonEncode(_decisionPayload(decision)),
          collapseKey,
        ],
      );
    }
    logReceiptCreatedTelemetry(
      logger: _logger,
      eventType: intent.eventType,
      recipientCount: intent.recipients.length,
      occurrenceAt: occurrenceAt,
    );
  }

  @visibleForTesting
  static void logReceiptCreatedTelemetry({
    required Logger logger,
    required AttentionEventType eventType,
    required int recipientCount,
    required DateTime occurrenceAt,
  }) {
    logger.info(
      formatReceiptCreatedTelemetry(
        eventType: eventType,
        recipientCount: recipientCount,
        occurrenceAt: occurrenceAt,
      ),
    );
  }

  @visibleForTesting
  static String formatReceiptCreatedTelemetry({
    required AttentionEventType eventType,
    required int recipientCount,
    required DateTime occurrenceAt,
  }) =>
      '[AttentionDispatch] attention_event=receipt_created '
      'event_type=${eventType.name} recipients=$recipientCount '
      'occurrence_at=${occurrenceAt.toUtc().toIso8601String()}';

  Map<String, Object?> _occurrencePayload(AttentionDispatchIntent intent) => {
    'kind': intent.kind.name,
    'priority': intent.priority.name,
    'title': intent.title,
    'body': intent.body,
    'actionUrl': intent.actionUrl,
    'beaconId': intent.beaconId,
    'coordinationItemId': intent.coordinationItemId,
    'targetEntityId': intent.targetEntityId,
    'messageId': intent.messageId,
  };

  Map<String, Object?> _rolePayload(AttentionRecipientRoleFacts role) => {
    'canReadBeaconContent': role.canReadBeaconContent,
    'beaconId': role.beaconId,
    'coordinationItemId': role.coordinationItemId,
    'targetEntityId': role.targetEntityId,
    'messageId': role.messageId,
    'actorUserId': role.actorUserId,
    'beaconTitle': role.beaconTitle,
    'trustDirection': role.trustDirection,
    'inviteOrigin': role.inviteOrigin,
  };

  Map<String, Object?> _decisionPayload(AttentionChannelDecision decision) => {
    'receiptId': decision.receiptId,
    'recipientId': decision.recipientId,
    'kind': decision.kind.name,
    'priority': decision.priority.name,
    'title': decision.title,
    'body': decision.body,
    'actionUrl': decision.actionUrl,
    'dedupKey': decision.dedupKey,
    'actorUserId': decision.actorUserId,
    'reason': decision.reason,
    'beaconId': decision.beaconId,
    'coordinationItemId': decision.coordinationItemId,
  };
}
