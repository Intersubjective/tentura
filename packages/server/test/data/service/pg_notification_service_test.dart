import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/service/pg_notification_connection.dart';
import 'package:tentura_server/data/service/pg_notification_service.dart';
import 'package:tentura_server/env.dart';

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.timestamp().add(timeout);
  while (!condition()) {
    if (DateTime.timestamp().isAfter(deadline)) {
      fail('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  group('PgNotificationService', () {
    test('forwards LISTEN payloads and emits no recovery at startup', () async {
      final connector = _FakePgNotificationConnector();
      final service = await PgNotificationService.createForTesting(
        Env.test(),
        connector,
      );
      addTearDown(service.dispose);

      final recoveries = <PgNotificationRecovery>[];
      final recoverySub = service.recoveryNotifications.listen(recoveries.add);
      addTearDown(recoverySub.cancel);
      final notification = service.entityChangeNotifications.first;
      connector.connections.single.add('payload-1');

      expect(await notification, 'payload-1');
      expect(recoveries, isEmpty);
      expect(connector.connections.single.listenedChannels, ['entity_changes']);
    });

    test(
      'emits one recovery after error and onDone from the same gap',
      () async {
        final connector = _FakePgNotificationConnector();
        final service = await PgNotificationService.createForTesting(
          Env.test(),
          connector,
        );
        addTearDown(service.dispose);

        final recoveries = <PgNotificationRecovery>[];
        final recoverySub = service.recoveryNotifications.listen(
          recoveries.add,
        );
        addTearDown(recoverySub.cancel);
        final first = connector.connections.single;
        await first.failAndClose();

        await _waitUntil(() => connector.connections.length == 2);
        await _waitUntil(() => recoveries.length == 1);
        expect(recoveries.single.sequence, 1);
        expect(first.closed, isTrue);

        final notification = service.entityChangeNotifications.first;
        connector.connections.last.add('payload-after-recovery');
        expect(await notification, 'payload-after-recovery');
      },
    );

    test(
      'notify delegates only to the active replacement connection',
      () async {
        final connector = _FakePgNotificationConnector();
        final service = await PgNotificationService.createForTesting(
          Env.test(),
          connector,
        );
        addTearDown(service.dispose);

        await connector.connections.single.failAndClose();
        await _waitUntil(() => connector.connections.length == 2);
        await service.notify('entity_changes', 'outgoing');

        expect(connector.connections.first.notifications, isEmpty);
        expect(
          connector.connections.last.notifications,
          [(channel: 'entity_changes', payload: 'outgoing')],
        );
      },
    );
  });
}

final class _FakePgNotificationConnector implements PgNotificationConnector {
  final connections = <_FakePgNotificationConnection>[];

  @override
  Future<PgNotificationConnection> open(
    Endpoint endpoint, {
    required ConnectionSettings settings,
  }) async {
    final connection = _FakePgNotificationConnection();
    connections.add(connection);
    return connection;
  }
}

final class _FakePgNotificationConnection implements PgNotificationConnection {
  final _channels = <String, StreamController<String>>{};
  final listenedChannels = <String>[];
  final notifications = <({String channel, String payload})>[];
  bool closed = false;

  @override
  Stream<String> channel(String name) =>
      (_channels[name] ??= StreamController<String>.broadcast()).stream;

  void add(String payload) => _channels['entity_changes']!.add(payload);

  Future<void> failAndClose() async {
    final controller = _channels['entity_changes']!;
    await (controller..addError(StateError('connection lost'))).close();
  }

  @override
  Future<void> listen(String channel) async {
    listenedChannels.add(channel);
    _channels[channel] ??= StreamController<String>.broadcast();
  }

  @override
  Future<void> notify(String channel, String payload) async {
    notifications.add((channel: channel, payload: payload));
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
