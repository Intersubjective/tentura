import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';

import '../database/tentura_db.dart';
import 'attention_dismissible_sql.dart';

@Singleton(as: AttentionSystemSettlementPort)
class AttentionSystemSettlementRepository
    implements AttentionSystemSettlementPort {
  const AttentionSystemSettlementRepository(this._database);

  final TenturaDb _database;

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
