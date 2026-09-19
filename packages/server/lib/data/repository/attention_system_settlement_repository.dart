import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';

import '../database/tentura_db.dart';

@Singleton(as: AttentionSystemSettlementPort)
class AttentionSystemSettlementRepository
    implements AttentionSystemSettlementPort {
  const AttentionSystemSettlementRepository(this._database);

  final TenturaDb _database;

  static const _reviewOpenedEventType = 'reviewOpened';
  static const _helpOfferSubmittedEventType = 'helpOfferSubmitted';

  @override
  Future<int> settleReviewObligationsAfterWindowClose(String beaconId) =>
      _database.customUpdate(
        r'''
UPDATE public.notification_outbox AS outbox
SET
  settlement_kind = CASE
    WHEN COALESCE(
      (
        SELECT brs.status
        FROM public.beacon_review_status AS brs
        WHERE brs.beacon_id = outbox.beacon_id
          AND brs.user_id = outbox.account_id
      ),
      -1
    ) = 2 THEN 'resolved'
    ELSE 'expired'
  END,
  settled_at = now(),
  settled_by_user_id = NULL,
  settled_by_occurrence_id = NULL
FROM public.attention_occurrence AS occ
WHERE outbox.occurrence_id = occ.id
  AND occ.event_type = $2
  AND outbox.beacon_id = $1
  AND outbox.requires_action
  AND outbox.settlement_kind IS NULL
''',
        variables: [
          Variable<String>(beaconId),
          Variable<String>(_reviewOpenedEventType),
        ],
        updateKind: UpdateKind.update,
      );

  @override
  Future<int> settleReviewerObligationOnPackageSend({
    required String beaconId,
    required String reviewerAccountId,
  }) =>
      _database.customUpdate(
        r'''
UPDATE public.notification_outbox AS outbox
SET
  settlement_kind = 'resolved',
  settled_at = now(),
  settled_by_user_id = NULL,
  settled_by_occurrence_id = NULL
FROM public.attention_occurrence AS occ
WHERE outbox.occurrence_id = occ.id
  AND occ.event_type = $3
  AND outbox.beacon_id = $1
  AND outbox.account_id = $2
  AND outbox.requires_action
  AND outbox.settlement_kind IS NULL
''',
        variables: [
          Variable<String>(beaconId),
          Variable<String>(reviewerAccountId),
          Variable<String>(_reviewOpenedEventType),
        ],
        updateKind: UpdateKind.update,
      );

  @override
  Future<int> settleAuthorHelpOfferSubmitted({
    required String beaconId,
    required String authorAccountId,
    required String helpOffererUserId,
  }) =>
      _database.customUpdate(
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
  }) =>
      _database.customUpdate(
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
  ) =>
      _database.customUpdate(
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

  @override
  Future<int> supersedeReviewObligationsOnReopen(String beaconId) =>
      _database.customUpdate(
        r'''
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
''',
        variables: [
          Variable<String>(beaconId),
          Variable<String>(_reviewOpenedEventType),
        ],
        updateKind: UpdateKind.update,
      );

  @override
  Future<List<String>> listBeaconIdsWithClosedReviewWindows() async {
    final rows = await _database.customSelect(
      r'''
SELECT beacon_id
FROM public.beacon_review_window
WHERE status = 1
ORDER BY beacon_id
''',
    ).get();
    return rows.map((row) => row.read<String>('beacon_id')).toList();
  }
}
