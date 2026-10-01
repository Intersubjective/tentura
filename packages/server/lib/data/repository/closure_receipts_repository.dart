import 'package:injectable/injectable.dart';
import 'package:tentura_root/consts.dart';

import 'package:tentura_server/domain/port/closure_receipts_port.dart';

import '../database/tentura_db.dart';

/// A17: writes the closure receipts (Arch §9) straight into
/// `notification_outbox`, one row per recipient, inside the caller's
/// transaction. The payload carries codes only (no title or excerpt), so a
/// single statement per receipt kind is enough; a repeated call finds the
/// `(account, source_event_key)` row and writes nothing.
@Singleton(as: ClosureReceiptsPort, order: 1)
class ClosureReceiptsRepository implements ClosureReceiptsPort {
  const ClosureReceiptsRepository(this._database);

  final TenturaDb _database;

  @override
  Future<void> opened(String beaconId, int epoch) => _write(
    beaconId,
    epoch,
    type: 'closure_opened',
    eventType: 'closureOpened',
    kind: 'reviewReady',
    category: 'asksOfMe',
    priority: 'high',
    title: 'Time to sum up',
    body: 'The closing window is open.',
    safeKey: 'closure_opened_bookmark_only',
    includeAuthor: true,
  );

  @override
  Future<void> finalized(String beaconId, int epoch) => _write(
    beaconId,
    epoch,
    type: 'closure_finalized',
    eventType: 'closureFinalized',
    kind: 'reviewReady',
    category: 'unblocksMe',
    priority: 'normal',
    title: 'Request closed',
    body: 'The results are in.',
    safeKey: 'closure_finalized',
    includeAuthor: true,
  );

  @override
  Future<void> cancelled(String beaconId, int epoch) => _write(
    beaconId,
    epoch,
    type: 'closure_cancelled',
    eventType: 'closureCancelled',
    kind: 'reviewReady',
    category: 'unblocksMe',
    priority: 'normal',
    title: 'Evaluation cancelled',
    body: 'The closing was cancelled.',
    safeKey: 'closure_cancelled',
    includeAuthor: false,
  );

  Future<void> _write(
    String beaconId,
    int epoch, {
    required String type,
    required String eventType,
    required String kind,
    required String category,
    required String priority,
    required String title,
    required String body,
    required String safeKey,
    required bool includeAuthor,
  }) => _database.customStatement(
    r'''
WITH request AS (
  SELECT id, user_id AS author_id FROM public.beacon WHERE id = $1::text
), people AS (
  SELECT r.author_id AS uid, false AS gone FROM request r WHERE $9::boolean
  UNION
  SELECT m.user_id, m.departure IS NOT NULL
  FROM public.beacon_closure_member m
  WHERE m.beacon_id = $1::text AND m.epoch = $2::int
), audience AS (
  SELECT p.uid,
    p.gone OR EXISTS (
      SELECT 1 FROM public.user_block ub, request r
      WHERE (ub.blocker_id = r.author_id AND ub.blocked_id = p.uid)
         OR (ub.blocker_id = p.uid AND ub.blocked_id = r.author_id)
    ) AS safe
  FROM people p
), keyed AS (
  SELECT a.uid, a.safe,
    $3::text || ':' || $1::text || ':' || $2::text || ':' || a.uid AS skey
  FROM audience a
)
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, beacon_id, source_event_key, destination_kind, target_entity_id,
  presentation_key, presentation_payload, suppression_class, access_policy,
  requires_action, placement
)
SELECT gen_random_uuid()::text, k.uid, $5::text, $6::text, $7::text,
  $8::text, $10::text, $11::text || $1::text || '?is_deep_link=true',
  k.skey, $1::text, k.skey,
  CASE WHEN k.safe THEN 'safe_terminal' ELSE 'beacon' END,
  $1::text,
  CASE WHEN k.safe THEN $12::text ELSE $3::text END,
  jsonb_strip_nulls(jsonb_build_object(
    'eventType', $4::text, 'beaconId', $1::text, 'epoch', $2::int,
    'outcome', res.outcome, 'band', res.band, 'draftFlag', res.draft_flag
  )),
  'standard',
  CASE WHEN k.safe THEN 'recipient_safe' ELSE 'beacon_content' END,
  false, 'primary'
FROM keyed k
LEFT JOIN public.beacon_closure_result res
  ON $4::text = 'closureFinalized'
 AND res.beacon_id = $1::text AND res.epoch = $2::int AND res.user_id = k.uid
WHERE NOT EXISTS (
  SELECT 1 FROM public.notification_outbox o
  WHERE o.account_id = k.uid AND o.source_event_key = k.skey
)
''',
    [
      beaconId,
      epoch,
      type,
      eventType,
      category,
      kind,
      priority,
      title,
      includeAuthor,
      body,
      '/#$kPathBeaconView/',
      safeKey,
    ],
  );
}
