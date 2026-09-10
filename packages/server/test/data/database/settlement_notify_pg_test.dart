@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('notify_notification_outbox_update settlement detection', () {
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> notificationSubscription;
    final notifications = <Map<String, dynamic>>[];

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

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
      await notificationSubscription.cancel();
      await listener.close();
      await writer.close();
      await target.drop();
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

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    ).timeout(const Duration(seconds: 2));
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_SETTLEMENT_NOTIFY_TEST_DB'] ??
        'tentura_test_settle_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_SETTLEMENT_NOTIFY_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}
