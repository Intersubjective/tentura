import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';

import '../database/tentura_db.dart';
import 'attention_dismissible_sql.dart';

@Singleton(as: AttentionSystemSettlementPort)
class AttentionSystemSettlementRepository
    implements AttentionSystemSettlementPort {
  const AttentionSystemSettlementRepository(this._database);

  final TenturaDb _database;

  @override
  Future<int> completeForwardHelped({
    required String beaconId,
    required int epoch,
  }) => _database.customUpdate(
    r'''
UPDATE public.notification_outbox outbox
SET title = CASE WHEN outbox.presentation_payload->>'done' = 'true'
                THEN outbox.title ELSE outbox.title || ' · Done ✓' END,
    presentation_payload = outbox.presentation_payload ||
      jsonb_build_object('done', true, 'doneEpoch', $2::int::text),
    seen_at = NULL
WHERE outbox.beacon_id = $1
  AND outbox.presentation_key = 'forward_helped'
  AND outbox.presentation_payload->>'doneEpoch' IS DISTINCT FROM $2::int::text
  AND EXISTS (
    SELECT 1
    FROM public.attention_occurrence_recipient recipient
    JOIN public.attention_occurrence occurrence ON occurrence.id = recipient.occurrence_id
    JOIN public.beacon_closure_member member
      ON member.beacon_id = $1 AND member.epoch = $2
     AND member.user_id = occurrence.immutable_payload->>'targetEntityId'
     AND member.departure IS NULL
    WHERE recipient.account_id = outbox.account_id
      AND occurrence.event_type = 'forwardHelped'
      AND occurrence.immutable_payload->>'beaconId' = $1
  )
''',
    variables: [Variable<String>(beaconId), Variable<int>(epoch)],
    updateKind: UpdateKind.update,
  );

  static const _helpOfferSubmittedEventType = 'helpOfferSubmitted';

  static const _authorInviteReceivedEventType = 'authorInviteReceived';

  @override
  Future<int> settleAuthorHelpOfferSubmitted({
    required String beaconId,
    required String authorAccountId,
    required String helpOffererUserId,
  }) => _database.customUpdate(
    r'''
UPDATE public.notification_outbox AS outbox
SET
  settlement_kind = COALESCE(outbox.settlement_kind, 'resolved'),
  settled_at = COALESCE(outbox.settled_at, now()),
  settled_by_user_id = NULL,
  settled_by_occurrence_id = NULL,
  seen_at = COALESCE(outbox.seen_at, now())
FROM public.attention_occurrence AS occ
WHERE outbox.occurrence_id = occ.id
  AND occ.event_type = $4
  AND outbox.beacon_id = $1
  AND outbox.account_id = $2
  AND outbox.target_entity_id = $3
  AND outbox.requires_action
  AND (outbox.settlement_kind IS NULL OR outbox.seen_at IS NULL)
''',
    variables: [
      Variable<String>(beaconId),
      Variable<String>(authorAccountId),
      Variable<String>(helpOffererUserId),
      Variable<String>(_helpOfferSubmittedEventType),
    ],
    updateKind: UpdateKind.update,
  );

  @override
  Future<int> supersedeAuthorHelpOfferSubmitted({
    required String beaconId,
    required String authorAccountId,
    required String helpOffererUserId,
  }) => _database.customUpdate(
    r"""
UPDATE public.notification_outbox AS outbox
SET
  settlement_kind = 'superseded',
  settled_at = now(),
  settled_by_user_id = NULL,
  settled_by_occurrence_id = NULL
FROM public.attention_occurrence AS occ
WHERE outbox.occurrence_id = occ.id
  AND occ.event_type = $4
  AND outbox.beacon_id = $1
  AND outbox.account_id = $2
  AND outbox.target_entity_id = $3
  AND outbox.requires_action
  AND outbox.settlement_kind IS NULL
""",
    variables: [
      Variable<String>(beaconId),
      Variable<String>(authorAccountId),
      Variable<String>(helpOffererUserId),
      Variable<String>(_helpOfferSubmittedEventType),
    ],
    updateKind: UpdateKind.update,
  );

  @override
  Future<int> supersedeAuthorHelpOfferObligationsOnBeaconClose(
    String beaconId,
  ) => _database.customUpdate(
    r"""
UPDATE public.notification_outbox AS outbox
SET
  settlement_kind = 'superseded',
  settled_at = now(),
  settled_by_user_id = NULL,
  settled_by_occurrence_id = NULL
FROM public.attention_occurrence AS occ
WHERE outbox.occurrence_id = occ.id
  AND occ.event_type = $2
  AND outbox.beacon_id = $1
  AND outbox.requires_action
  AND outbox.settlement_kind IS NULL
""",
    variables: [
      Variable<String>(beaconId),
      Variable<String>(_helpOfferSubmittedEventType),
    ],
    updateKind: UpdateKind.update,
  );

  /// `clear_reason` has a frozen vocabulary (m0193
  /// `notification_outbox__clear_reason_chk`); a system clear without an
  /// operation is recorded as `sweep` with no `cleared_by_operation_id`, so
  /// no sweep undo can bring it back.
  @override
  Future<int> clearAuthorInviteReceived({
    required String beaconId,
    required String inviteeId,
  }) => _database.customUpdate(
    '''
UPDATE public.notification_outbox AS outbox
SET
  cleared_at = now(),
  clear_reason = 'sweep',
  seen_at = COALESCE(outbox.seen_at, now())
FROM public.attention_occurrence AS occ
WHERE outbox.occurrence_id = occ.id
  AND occ.event_type = \$3
  AND outbox.beacon_id = \$1
  AND outbox.account_id = \$2
  AND ${AttentionDismissibleSql.activeOptional('outbox')}
''',
    variables: [
      Variable<String>(beaconId),
      Variable<String>(inviteeId),
      const Variable<String>(_authorInviteReceivedEventType),
    ],
    updateKind: UpdateKind.update,
  );

  @override
  Future<void> reverseAuthorInviteDeclineReceipts({
    required String inviteId,
    required String beaconId,
    required String inviterId,
    required String inviteeId,
  }) async {
    // Undo exactly the decline's own system clear (`sweep`, no operation).
    await _database.customUpdate(
      r'''
UPDATE public.notification_outbox
SET cleared_at = NULL, clear_reason = NULL, seen_at = NULL
WHERE source_event_key = $1
  AND beacon_id = $2
  AND account_id = $3
  AND NOT requires_action
  AND clear_reason = 'sweep'
  AND cleared_by_operation_id IS NULL
''',
      variables: [
        Variable<String>('author_invite:$inviteId'),
        Variable<String>(beaconId),
        Variable<String>(inviteeId),
      ],
      updateKind: UpdateKind.update,
    );
    await _database.customUpdate(
      '''
UPDATE public.notification_outbox AS outbox
SET
  cleared_at = now(),
  clear_reason = 'sweep',
  seen_at = COALESCE(outbox.seen_at, now())
WHERE outbox.source_event_key = \$1
  AND outbox.beacon_id = \$2
  AND outbox.account_id = \$3
  AND ${AttentionDismissibleSql.activeOptional('outbox')}
''',
      variables: [
        Variable<String>('author_invite_declined:$inviteId'),
        Variable<String>(beaconId),
        Variable<String>(inviterId),
      ],
      updateKind: UpdateKind.update,
    );
  }
}
