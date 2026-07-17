import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_policy.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';

import '../database/tentura_db.dart';

@Singleton(as: AttentionDispatchPort)
class AttentionDispatchRepository implements AttentionDispatchPort {
  const AttentionDispatchRepository(this._database);

  final TenturaDb _database;

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
RETURNING id''',
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
    if (occurrence.isEmpty) {
      final matching = await _database
          .customSelect(
            r'''SELECT id FROM public.attention_occurrence
WHERE source_event_key = $1 AND immutable_payload = $2::jsonb''',
            variables: [
              Variable<String>(intent.sourceEventKey),
              Variable<String>(immutablePayload),
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
    final occurrenceId = occurrence.single.read<String>('id');
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
  requires_action, attention_thread_key
) VALUES (
  gen_random_uuid()::text, $1, $2, $3, $4,
  $5, $6, $7, $8,
  $9, $10, $11,
  $12, $13, $14, $15,
  $16, $17::jsonb,
  $18, $19, $20,
  $21, $22
)
ON CONFLICT (dedup_key) WHERE seen_at IS NULL
DO UPDATE SET
  category                = EXCLUDED.category,
  kind                    = EXCLUDED.kind,
  priority                = EXCLUDED.priority,
  title                   = EXCLUDED.title,
  body                    = EXCLUDED.body,
  action_url              = EXCLUDED.action_url,
  beacon_id               = EXCLUDED.beacon_id,
  coordination_item_id    = EXCLUDED.coordination_item_id,
  actor_user_id           = EXCLUDED.actor_user_id,
  source_event_key        = EXCLUDED.source_event_key,
  occurrence_id           = EXCLUDED.occurrence_id,
  destination_kind        = EXCLUDED.destination_kind,
  target_entity_id        = EXCLUDED.target_entity_id,
  presentation_key        = EXCLUDED.presentation_key,
  presentation_payload    = EXCLUDED.presentation_payload,
  in_app_preference_class = EXCLUDED.in_app_preference_class,
  suppression_class       = EXCLUDED.suppression_class,
  access_policy           = EXCLUDED.access_policy,
  requires_action         = EXCLUDED.requires_action,
  attention_thread_key    = EXCLUDED.attention_thread_key,
  created_at              = now(),
  collapsed_count         = notification_outbox.collapsed_count + 1
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
      await _database.customStatement(
        r'''INSERT INTO public.attention_channel_delivery (
  occurrence_id, receipt_id, account_id, payload
) VALUES ($1, $2, $3, $4::jsonb)''',
        [
          occurrenceId,
          decision.receiptId,
          decision.recipientId,
          jsonEncode(_decisionPayload(decision)),
        ],
      );
    }
  }

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
