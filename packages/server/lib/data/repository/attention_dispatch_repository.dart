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

  /// The recipient's role facts, with the intent's facts filling what the
  /// recipient left empty.
  static AttentionRecipientRoleFacts _effectiveRole(
    AttentionDispatchIntent intent,
    AttentionRecipientSnapshot recipient,
  ) => recipient.role.copyWith(
    beaconId: recipient.role.beaconId ?? intent.beaconId,
    coordinationItemId:
        recipient.role.coordinationItemId ?? intent.coordinationItemId,
    targetEntityId: recipient.role.targetEntityId ?? intent.targetEntityId,
    messageId: recipient.role.messageId ?? intent.messageId,
    actorUserId: recipient.role.actorUserId ?? intent.actorUserId,
  );

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
    // One statement for the whole recipient snapshot set: the cost of a
    // forward may not grow with the number of people it reaches.
    if (intent.recipients.isNotEmpty) {
      await _database.customStatement(
        r'''
INSERT INTO public.attention_occurrence_recipient (
  occurrence_id, account_id, reasons, role_facts, collapse_key, channel_eligible
)
SELECT $1, r.account_id, r.reasons, r.role_facts, r.collapse_key,
       r.channel_eligible
FROM jsonb_to_recordset($2::jsonb) AS r(
  account_id text, reasons jsonb, role_facts jsonb, collapse_key text,
  channel_eligible boolean
)''',
        [
          occurrenceId,
          jsonEncode([
            for (final recipient in intent.recipients)
              {
                'account_id': recipient.recipientId,
                'reasons': recipient.reasons
                    .map((reason) => reason.name)
                    .toList(),
                'role_facts': _rolePayload(_effectiveRole(intent, recipient)),
                'collapse_key': recipient.collapseKey ?? intent.collapseKey,
                'channel_eligible': recipient.channelEligible,
              },
          ]),
        ],
      );
    }
    if (intent.recipients.isNotEmpty) {
      await _writeReceipts(intent, occurrenceId);
    }
    logReceiptCreatedTelemetry(
      logger: _logger,
      eventType: intent.eventType,
      recipientCount: intent.recipients.length,
      occurrenceAt: occurrenceAt,
    );
  }

  /// Writes every recipient's receipt and channel delivery job in a fixed
  /// number of statements.
  Future<void> _writeReceipts(
    AttentionDispatchIntent intent,
    String occurrenceId,
  ) async {
    final receipts = [
      for (final recipient in intent.recipients) _receiptFor(intent, recipient),
    ];
    // Every statement below covers the whole recipient set: the cost of a
    // dispatch may not grow with the number of people it reaches.
    //
    // U05c — obligation identity. An obligation receipt names the *task* it
    // is about (`logical_task_key`, stable across renewals) and which
    // generation of that task it is. Optional receipts leave both NULL;
    // m0178's `notification_outbox__logical_task_chk` enforces that pairing.
    //
    // A *semantic renewal* — the same unresolved task asked again — must
    // supersede its predecessor here, in the caller's transaction, so the
    // two generations never coexist as live obligations and a rollback of
    // the source mutation takes the supersede with it. The database holds
    // the line either way: m0178's partial UNIQUE
    // `notification_outbox__live_logical_task` rejects a second live row
    // for one task, so a writer that forgets to supersede fails loudly.
    //
    // A *delivery retry* reaches neither statement: a replayed
    // `source_event_key` returns at the occurrence dedup above, and a
    // channel retry only touches `attention_channel_delivery`. Neither
    // bumps a generation.
    //
    // Legacy obligations written before U05c carry a NULL
    // `logical_task_key`; the partial index ignores NULL keys, so they
    // neither block nor get superseded by this. They gain keys at U18's
    // cutover, not here — backfilling them now would have to guess which
    // generation a row belonged to.
    final previousGenerations = <(String, String), int>{};
    final taskReceipts = receipts.where((r) => r.logicalTaskKey != null);
    if (taskReceipts.isNotEmpty) {
      final superseded = await _database
          .customSelect(
            r'''
UPDATE public.notification_outbox o
SET settlement_kind = 'superseded', settled_at = now()
FROM jsonb_to_recordset($1::jsonb) AS t(account_id text, logical_task_key text)
WHERE o.account_id = t.account_id
  AND o.logical_task_key = t.logical_task_key
  AND o.requires_action
  AND o.settlement_kind IS NULL
RETURNING o.account_id, o.logical_task_key, o.lifecycle_generation
''',
            variables: [
              Variable<String>(
                jsonEncode([
                  for (final receipt in taskReceipts)
                    {
                      'account_id': receipt.recipientId,
                      'logical_task_key': receipt.logicalTaskKey,
                    },
                ]),
              ),
            ],
          )
          .get();
      for (final row in superseded) {
        final key = (
          row.read<String>('account_id'),
          row.read<String>('logical_task_key'),
        );
        final generation = row.readNullable<int>('lifecycle_generation') ?? 0;
        final known = previousGenerations[key] ?? 0;
        previousGenerations[key] = generation > known ? generation : known;
      }
    }
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
    final inserted = await _database
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
  logical_task_key, lifecycle_generation,
  placement
)
SELECT
  gen_random_uuid()::text, r.account_id, r.category, $1, $2,
  $3, $4, $5, r.dedup_key,
  $6, $7, $8,
  $9, $10, r.destination_kind, r.target_entity_id,
  r.presentation_key, r.presentation_payload,
  r.in_app_preference_class, r.suppression_class, r.access_policy,
  r.requires_action, r.attention_thread_key,
  r.logical_task_key, r.lifecycle_generation,
  $11
FROM jsonb_to_recordset($12::jsonb) AS r(
  account_id text, category text, dedup_key text, destination_kind text,
  target_entity_id text, presentation_key text, presentation_payload jsonb,
  in_app_preference_class text, suppression_class text, access_policy text,
  requires_action boolean, attention_thread_key text, logical_task_key text,
  lifecycle_generation integer
)
RETURNING id, account_id
''',
          variables: [
            Variable<String>(intent.kind.name),
            Variable<String>(intent.priority.name),
            Variable<String>(intent.title),
            Variable<String>(intent.body),
            Variable<String>(intent.actionUrl),
            Variable<String>(intent.beaconId),
            Variable<String>(intent.coordinationItemId),
            Variable<String>(intent.actorUserId),
            Variable<String>(intent.sourceEventKey),
            Variable<String>(occurrenceId),
            // U11/D16: producer-time placement. `timeline_only` keeps the
            // receipt in the destination Request's log while excluding it
            // from that Request's dot, count and position.
            Variable<String>(_policy.placement(intent.eventType).wireName),
            Variable<String>(
              jsonEncode([
                for (final receipt in receipts)
                  {
                    'account_id': receipt.recipientId,
                    'category': receipt.projection.category.name,
                    'dedup_key': receipt.dedupKey,
                    'destination_kind':
                        receipt.projection.destination.kind.wireName,
                    'target_entity_id':
                        receipt.projection.destination.targetEntityId,
                    'presentation_key': receipt.projection.presentationKey,
                    'presentation_payload':
                        receipt.projection.presentationPayload,
                    'in_app_preference_class':
                        receipt.projection.inAppPreferenceClass?.wireName,
                    'suppression_class':
                        receipt.projection.suppressionClass.name,
                    'access_policy': receipt.projection.accessPolicy.wireName,
                    'requires_action': receipt.projection.requiresAction,
                    'attention_thread_key':
                        receipt.projection.attentionThreadKey,
                    'logical_task_key': receipt.logicalTaskKey,
                    'lifecycle_generation': receipt.logicalTaskKey == null
                        ? null
                        : (previousGenerations[(
                                    receipt.recipientId,
                                    receipt.logicalTaskKey!,
                                  )] ??
                                  0) +
                              1,
                  },
              ]),
            ),
          ],
        )
        .get();
    final receiptIds = {
      for (final row in inserted)
        row.read<String>('account_id'): row.read<String>('id'),
    };

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
    final deliveries = [
      for (var i = 0; i < intent.recipients.length; i++)
        if (intent.recipients[i].channelEligible)
          {
            'account_id': receipts[i].recipientId,
            'receipt_id': receiptIds[receipts[i].recipientId],
            'collapse_key': receipts[i].collapseKey,
            'payload': _decisionPayload(
              AttentionChannelDecision(
                receiptId: receiptIds[receipts[i].recipientId]!,
                recipientId: receipts[i].recipientId,
                kind: intent.kind,
                priority: intent.priority,
                title: intent.title,
                body: intent.body,
                actionUrl: intent.actionUrl,
                dedupKey: receipts[i].dedupKey,
                actorUserId: intent.actorUserId ?? '',
                reason: intent.recipients[i].reasons
                    .map((reason) => reason.name)
                    .join(','),
                beaconId: intent.beaconId,
                coordinationItemId: intent.coordinationItemId,
                beaconKind: intent.beaconKind,
                actorDisplayName: intent.actorDisplayName,
              ),
            ),
          },
    ];
    if (deliveries.isNotEmpty) {
      await _database.customStatement(
        r'''WITH incoming AS (
  SELECT d.account_id, d.receipt_id, d.collapse_key, d.payload
  FROM jsonb_to_recordset($2::jsonb) AS d(
    account_id text, receipt_id text, collapse_key text, payload jsonb
  )
), target AS (
  SELECT incoming.*, pending.id AS job_id
  FROM incoming
  LEFT JOIN LATERAL (
    SELECT job.id
    FROM public.attention_channel_delivery job
    JOIN public.attention_occurrence_recipient recipient
      ON recipient.occurrence_id = job.occurrence_id
     AND recipient.account_id = job.account_id
    WHERE job.account_id = incoming.account_id
      AND job.status = 'pending'
      AND recipient.collapse_key = incoming.collapse_key
    ORDER BY job.created_at DESC, job.id DESC
    LIMIT 1
  ) pending ON true
), collapsed AS (
  UPDATE public.attention_channel_delivery job
  SET occurrence_id = $1, receipt_id = target.receipt_id,
      payload = target.payload
  FROM target
  WHERE job.id = target.job_id
  RETURNING job.id
)
INSERT INTO public.attention_channel_delivery (
  occurrence_id, receipt_id, account_id, payload
)
SELECT $1, target.receipt_id, target.account_id, target.payload
FROM target
WHERE target.job_id IS NULL''',
        [occurrenceId, jsonEncode(deliveries)],
      );
    }
  }

  /// What one recipient's receipt is made of: the projection, the dedup key
  /// and the obligation's logical task key.
  ({
    String recipientId,
    AttentionReceiptProjection projection,
    String collapseKey,
    String dedupKey,
    String? logicalTaskKey,
  })
  _receiptFor(
    AttentionDispatchIntent intent,
    AttentionRecipientSnapshot recipient,
  ) {
    final role = _effectiveRole(intent, recipient);
    final projection = _policy.project(
      eventType: intent.eventType,
      recipientId: recipient.recipientId,
      recipientReasons: recipient.reasons,
      role: role,
      actorDisplayName: intent.actorDisplayName,
    );
    final collapseKey = recipient.collapseKey ?? intent.collapseKey;
    return (
      recipientId: recipient.recipientId,
      projection: projection,
      collapseKey: collapseKey,
      dedupKey: '${recipient.recipientId}|attention-v1|$collapseKey',
      logicalTaskKey: _policy.logicalTaskKey(
        eventType: intent.eventType,
        recipientId: recipient.recipientId,
        recipientReasons: recipient.reasons,
        role: role,
      ),
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
    'excerpt': role.excerpt,
    'toStatus': role.toStatus,
    'withdrawReason': role.withdrawReason,
    'leftDiscussion': role.leftDiscussion,
    'nextStepMentionsActor': role.nextStepMentionsActor,
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
    'beaconKind': decision.beaconKind.name,
    'actorDisplayName': decision.actorDisplayName,
  };
}
