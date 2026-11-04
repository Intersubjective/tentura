import 'package:postgres/postgres.dart';

/// Persisted History receipts: an optional forward shell, a live obligation,
/// and an optional event that Read all can clear. No fake feed or count.
Future<void> seedCountedReceipts(
  Connection writer, {
  bool siblings = false,
}) async {
  for (final (id, key, requiresAction) in [
    if (siblings) ...[
      ('counted-plan', 'plan_step_due', true),
      ('counted-trust', 'trust_given_changed_up', false),
    ] else ...[
      ('counted-forward', 'relay_received', false),
      ('counted-offer', 'help_offer_submitted', true),
    ],
    ('counted-social', 'invite_accepted', false),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, source_event_key, beacon_id, destination_kind,
  presentation_key, presentation_payload, suppression_class, access_policy,
  requires_action, attention_thread_key, created_at
) VALUES (
  @id, 'Ua00000000001', 'coordination', 'newRelay', 'normal',
  'Алиса', @body, '/attention', @id, @id,
  @beacon, @destination, @key, CAST(@payload AS jsonb), 'standard',
  @access, @requiresAction, @threadKey, now()
)
'''),
      parameters: {
        'id': id,
        'key': key,
        'payload': key == 'plan_step_due'
            ? '{"eventType":"planStepDue","excerpt":"Подготовить лестницу"}'
            : '{}',
        'body': key == 'plan_step_due'
            ? 'Подготовить лестницу'
            : 'Новое событие',
        'beacon': key == 'invite_accepted' ? null : 'Bseenby000001',
        'destination': key == 'invite_accepted' ? 'profile' : 'beacon',
        'access': key == 'invite_accepted' ? 'profile' : 'beacon_content',
        'requiresAction': requiresAction,
        'threadKey': requiresAction ? 'v1|Bseenby000001|$key|viewer' : null,
      },
    );
  }
}
