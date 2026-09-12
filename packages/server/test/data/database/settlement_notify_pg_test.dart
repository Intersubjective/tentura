@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_SETTLEMENT_NOTIFY_TEST_DB',
    defaultNamePrefix: 'tentura_test_settle',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('notify_notification_outbox_update settlement detection', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> notificationSubscription;
    final notifications = <Map<String, dynamic>>[];

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;

      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      notificationSubscription = listener.channels['entity_changes'].listen(
        (payload) => notifications.add(
          jsonDecode(payload) as Map<String, dynamic>,
        ),
      );
      await _settle();
      notifications.clear();
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE public.notification_outbox, public."user" CASCADE
''');
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('Usettle03', 'Settlement notify', 'settle-notify-public-key')
''');
      notifications.clear();
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await notificationSubscription.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session);
    });

    test('settlement-only update emits a notification', () async {
      await writer.execute('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key
) VALUES (
  'Nsettle03', 'Usettle03', 'asksOfMe', 'needsMe', 'normal',
  'Obligation', 'Obligation body', '/attention', 'dedup-settle03',
  '2026-07-16T12:00:00Z'::timestamptz,
  '2026-07-17T12:00:00Z'::timestamptz,
  'Bsettle03', 'source-settle03',
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  true, 'v1|needsMe|Nsettle03|Usettle03'
)
''');
      await _settle();
      notifications.clear();

      await writer.execute('''
UPDATE public.notification_outbox
SET
  settlement_kind = 'resolved',
  settled_at = '2026-07-18T12:00:00Z'::timestamptz,
  settled_by_user_id = 'Usettle03'
WHERE id = 'Nsettle03'
''');

      await _waitUntil(
        () => _notificationUpdates(notifications).isNotEmpty,
      );
      expect(_notificationUpdates(notifications), [
        {
          'event': 'update',
          'entity': 'notification',
          'id': 'Usettle03',
          'user_ids': ['Usettle03'],
        },
      ]);
    });

    test('update outside the change-detection tuple emits nothing', () async {
      await writer.execute('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  source_event_key, destination_kind, presentation_key, access_policy
) VALUES (
  'Nnoop03', 'Usettle03', 'asksOfMe', 'needsMe', 'normal',
  'No-op', 'Body', '/noop', 'dedup-noop03',
  '2026-07-16T12:00:00Z'::timestamptz,
  'source-noop03', 'profile', 'needs_me', 'profile'
)
''');
      await _settle();
      notifications.clear();

      await writer.execute('''
UPDATE public.notification_outbox
SET emailed_at = now()
WHERE id = 'Nnoop03'
''');
      await _settle();

      expect(_notificationUpdates(notifications), isEmpty);
    });
  }, skip: skipReason);
}

List<Map<String, dynamic>> _notificationUpdates(
  List<Map<String, dynamic>> notifications,
) => notifications
    .where(
      (message) =>
          message['entity'] == 'notification' && message['event'] == 'update',
    )
    .toList();

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.timestamp().add(timeout);
  while (!condition()) {
    if (DateTime.timestamp().isAfter(deadline)) {
      fail('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 100));
