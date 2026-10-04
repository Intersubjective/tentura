@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/pg_notification_recorder.dart';
import '../../support/pg_wait.dart';

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for notification recorder PG test';

  group('PgNotificationRecorder over real LISTEN/NOTIFY', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late Connection listener;
    late PgNotificationRecorder recorder;

    Future<void> notify(String entity, String id) => writer.execute(
          Sql.named("SELECT pg_notify('entity_changes', @payload)"),
          parameters: {
            'payload': jsonEncode({'entity': entity, 'id': id}),
          },
        );

    Future<void> barrier(String token) => notify('barrier', token);

    setUpAll(() async {
      if (skipReason != false) return;
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      recorder = PgNotificationRecorder(listener.channels['entity_changes']);
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await recorder.cancel();
      await listener.close();
      await writer.close();
      await target.drop();
    });

    test('drain drops a burst of notifications sent just before it', () async {
      for (var i = 0; i < 50; i++) {
        unawaited(notify('beacon_hierarchy', 'stale$i'));
      }

      await recorder.drain(sendBarrier: barrier);

      expect(recorder.messages, isEmpty);
    });

    test('notifications sent after a drain are recorded', () async {
      await recorder.drain(sendBarrier: barrier);
      await notify('beacon_hierarchy', 'fresh');
      final deadline = DateTime.now().add(kStableStateWait);
      while (recorder.messages.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(recorder.messages.map((m) => m['id']), ['fresh']);
    });
  }, skip: skipReason);
}
