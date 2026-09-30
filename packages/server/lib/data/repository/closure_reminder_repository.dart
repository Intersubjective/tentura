import 'package:injectable/injectable.dart';
import 'package:tentura_root/consts.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/port/closure_reminder_sweep_port.dart';

import '../database/tentura_db.dart';

/// A17: raw-SQL audience selection and outbox writes of the two hourly
/// reminder sweeps (Arch §9). Keys make both idempotent.
@Singleton(as: ClosureReminderSweepPort, order: 1)
class ClosureReminderRepository implements ClosureReminderSweepPort {
  const ClosureReminderRepository(this._database);

  final TenturaDb _database;

  static const _insertColumns = '''
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, beacon_id, source_event_key, destination_kind, target_entity_id,
  presentation_key, presentation_payload, suppression_class, access_policy,
  requires_action, placement''';

  @override
  Future<int> writeDraftReminders({required DateTime now}) => _database
      .customUpdate(
        '''
INSERT INTO public.notification_outbox ($_insertColumns)
SELECT gen_random_uuid()::text, m.user_id, 'asksOfMe', 'staleRemind', 'high',
  'Finish your evaluation',
  'Your draft has not been committed. The window closes within a day.',
  \$2::text || c.beacon_id || '?is_deep_link=true',
  k.skey, c.beacon_id, k.skey, 'beacon', c.beacon_id,
  'closure_draft_reminder',
  jsonb_build_object(
    'eventType', 'closureDraftReminder', 'beaconId', c.beacon_id,
    'epoch', c.epoch),
  'standard', 'beacon_content', false, 'primary'
FROM public.beacon_closure c
JOIN public.beacon_closure_member m
  ON m.beacon_id = c.beacon_id AND m.epoch = c.epoch
 AND m.active_at_open AND m.departure IS DISTINCT FROM 2,
LATERAL (SELECT 'closure_draft_reminder:' || c.beacon_id || ':' || c.epoch
    || ':' || m.user_id AS skey) k,
LATERAL (
  SELECT
    coalesce(array_agg(s.target_id ORDER BY s.target_id)
      FILTER (WHERE s.version = 0), '{}') AS draft,
    coalesce(array_agg(s.target_id ORDER BY s.target_id)
      FILTER (WHERE s.version = 1), '{}') AS committed
  FROM public.beacon_closure_support s
  WHERE s.beacon_id = c.beacon_id AND s.voter_id = m.user_id
) sets
WHERE c.status = 0
  AND c.closes_at > \$1::timestamptz + interval '23 hours'
  AND c.closes_at <= \$1::timestamptz + interval '24 hours'
  AND (
    (cardinality(sets.draft) > 0 AND NOT EXISTS (
      SELECT 1 FROM public.beacon_closure_commit cm
      WHERE cm.beacon_id = c.beacon_id AND cm.voter_id = m.user_id))
    OR (EXISTS (
      SELECT 1 FROM public.beacon_closure_commit cm
      WHERE cm.beacon_id = c.beacon_id AND cm.voter_id = m.user_id)
      AND sets.draft IS DISTINCT FROM sets.committed)
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.notification_outbox o
    WHERE o.account_id = m.user_id AND o.source_event_key = k.skey)
''',
        variables: [
          Variable<String>(now.toUtc().toIso8601String()),
          const Variable<String>('/#$kPathBeaconView/'),
        ],
      );

  @override
  Future<int> writeStaleRequestReminders({
    required DateTime now,
    required String weekKey,
  }) => _database.customUpdate(
    '''
INSERT INTO public.notification_outbox ($_insertColumns)
SELECT gen_random_uuid()::text, b.user_id, 'asksOfMe', 'staleRemind', 'normal',
  'Your request has gone quiet',
  'Close it, extend it or post an update.',
  \$3::text || b.id || '?is_deep_link=true',
  k.skey, b.id, k.skey, 'beacon', b.id,
  'request_stale',
  jsonb_build_object('eventType', 'requestStale', 'beaconId', b.id),
  'standard', 'beacon_content', false, 'primary'
FROM public.beacon b,
LATERAL (SELECT 'stale_request:' || b.id || ':' || \$2::text AS skey) k
WHERE b.status IN (${BeaconStatus.openFamilyValues.join(', ')})
  AND (
    b.end_at < \$1::timestamptz
    OR greatest(
      b.created_at,
      b.status_changed_at,
      (SELECT max(x.created_at) FROM public.beacon_room_message x
        WHERE x.beacon_id = b.id),
      (SELECT max(x.created_at) FROM public.beacon_activity_event x
        WHERE x.beacon_id = b.id),
      (SELECT max(x.updated_at) FROM public.beacon_help_offer x
        WHERE x.beacon_id = b.id),
      (SELECT max(x.created_at) FROM public.beacon_commitment_event x
        WHERE x.beacon_id = b.id)
    ) < \$1::timestamptz - interval '14 days'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.notification_outbox o
    WHERE o.account_id = b.user_id AND o.source_event_key = k.skey)
''',
    variables: [
      Variable<String>(now.toUtc().toIso8601String()),
      Variable<String>(weekKey),
      const Variable<String>('/#$kPathBeaconView/'),
    ],
  );
}
