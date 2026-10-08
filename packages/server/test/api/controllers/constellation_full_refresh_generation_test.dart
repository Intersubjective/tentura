import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show WebSocketSession;
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/auth_request_intent.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field.dart';
import 'package:tentura_server/api/controllers/websocket_controller.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/service/pg_notification_connection.dart';
import 'package:tentura_server/data/service/pg_notification_service.dart';
import 'package:tentura_server/data/service/task_worker.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/constellation_field_repository_port.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/gated_constellation_field_repository.dart';
import 'websocket/websocket_realtime_protocol_test.mocks.dart';

const _viewer = 'Uaaaaaaaaaaaa';
const _otherViewer = 'Ubbbbbbbbbbbb';
const _marker = {
  'entity': 'constellation_field',
  'id': 'global',
  'event': 'update',
  'user_ids': <String>[],
};

void main() {
  group('FULL refresh after a newer global field marker', () {
    late GatedConstellationFieldRepository repository;
    late _NotificationConnector connector;
    late PgNotificationService notifications;
    late WebSocketController sockets;
    late QueryConstellationField query;
    late _HintSession first;
    late _HintSession second;

    setUp(() async {
      await getIt.reset();
      final env = Env(
        environment: Environment.test,
        constellationFieldBroadcastWindow: const Duration(milliseconds: 40),
      );
      repository = GatedConstellationFieldRepository();
      connector = _NotificationConnector();
      // Override external I/O before initializing the production graph. In
      // particular, do not construct a detached read case or socket router:
      // their real registrations must wire any generation bridge themselves.
      getIt
        ..skipDoubleRegistration = true
        ..registerSingleton<ConstellationFieldRepositoryPort>(repository)
        ..registerSingleton<UserPresenceRepositoryPort>(
          MockUserPresenceRepositoryPort(),
        )
        ..registerLazySingletonAsync<TaskWorker>(
          () async => _UnusedTaskWorker(),
        )
        ..registerSingletonAsync<PgNotificationService>(
          () => PgNotificationService.createForTesting(env, connector),
          dispose: (service) => service.dispose(),
        );
      await getIt.getAsync<TaskWorker>();
      notifications = await getIt.getAsync<PgNotificationService>();
      await configureDependencies(env);
      await getIt.allReady(ignorePendingAsyncCreation: true);
      sockets = await getIt.getAsync<WebSocketController>();
      query = QueryConstellationField();
      first = _HintSession();
      second = _HintSession();
      for (final entry in [(first, _viewer), (second, _otherViewer)]) {
        final token = sockets.authCase.issueAccessToken(entry.$2).rawToken;
        await sockets.onAuth(entry.$1, {
          'intent': AuthRequestIntent.cnameSignIn,
          'token': token,
        });
      }
    });

    tearDown(() async {
      if (getIt.isRegistered<WebSocketController>()) {
        sockets.authenticatedSessions.forEach(sockets.removeSession);
      }
      await getIt.reset();
      getIt.skipDoubleRegistration = false;
    });

    Future<void> publishMarker() async {
      final received = notifications.entityChangeNotifications.first;
      connector.connection.publish(jsonEncode(_marker));
      await received;
      await Future<void>.delayed(Duration.zero);
    }

    Future<Object?> full({
      String viewerId = _viewer,
      bool showClosed = false,
    }) => Future<Object?>.value(
      query.constellationField.resolve!(null, {
        kGlobalInputQueryJwt: JwtEntity(sub: viewerId),
        'showClosed': showClosed,
        'participatedOnly': false,
        'projection': 'FULL',
      }),
    );

    for (final target in [
      'the same key',
      'another viewer',
      'another context',
      'another filter set',
    ]) {
      test(
        'completing an older FULL leaves a refresh available for $target',
        () async {
          // Establish generation g through the real isolate-local fan-out, and
          // wait for its hint before starting the generation-g database read.
          final initialHints = Future.wait([
            first.nextHint(),
            second.nextHint(),
          ]);
          await publishMarker();
          await initialHints;

          final leader = full();
          await repository.firstReadStarted.future;
          final overlapping = Future.wait([leader, full()]);
          await Future<void>.delayed(Duration.zero);
          final computationsAtG = repository.readSnapshotCalls;
          expect(repository.activeReads, greaterThanOrEqualTo(1));

          // Both FULLs remain open while g+1 arrives at the production service.
          // Their completion must not consume that newer refresh hint, including
          // the other viewer's hint. No case/private generation accessor is used.
          final newerHints = Future.wait([first.nextHint(), second.nextHint()]);
          await publishMarker();
          // A caller arriving after g+1 still joins the pending same-key FULL;
          // that older flight must leave a subsequent refresh available.
          final lateFollower = full();
          await Future<void>.delayed(Duration.zero);
          repository.completePendingReads();
          await overlapping;
          await lateFollower;
          final computationsThroughCompletion = repository.readSnapshotCalls;
          await newerHints;
          expect(first.hints, 2);
          expect(second.hints, 2);

          final callsBeforeRefresh = repository.readSnapshotCalls;
          final Future<Object?> refresh;
          switch (target) {
            case 'another viewer':
              refresh = full(viewerId: _otherViewer);
            case 'another context':
              refresh = getIt<ConstellationFieldCase>().load(
                viewerId: _viewer,
                context: 'other-context',
              );
            case 'another filter set':
              refresh = full(showClosed: true);
            default:
              refresh = full();
          }
          await Future<void>.delayed(Duration.zero);
          expect(repository.readSnapshotCalls, callsBeforeRefresh + 1);
          final read = repository.reads.last;
          expect(
            read.viewerId,
            target == 'another viewer' ? _otherViewer : _viewer,
          );
          expect(
            read.context,
            target == 'another context'
                ? 'other-context'
                : kConstellationContext,
          );
          expect(
            read.params.filters.showClosed,
            target == 'another filter set',
          );
          repository.completePendingReads();
          await refresh;
          expect(
            computationsAtG,
            1,
            reason: 'The generation-g leader and follower share one FULL read',
          );
          expect(
            computationsThroughCompletion,
            1,
            reason:
                'The post-marker follower must join the older same-key flight',
          );
        },
      );
    }
  });
}

final class _HintSession extends WebSocketSession {
  int hints = 0;
  Completer<void>? _next;

  Future<void> nextHint() {
    final next = Completer<void>();
    _next = next;
    return next.future.timeout(const Duration(seconds: 2));
  }

  @override
  void send(Object? data) {
    if (data is! String) return;
    final frame = jsonDecode(data) as Map;
    if (frame['path'] != 'entity_changes') return;
    final payload = frame['payload'] as Map;
    if (payload['entity'] != 'constellation_field') return;
    expect(payload['id'], 'global');
    hints++;
    _next?.complete();
    _next = null;
  }
}

final class _UnusedTaskWorker implements TaskWorker {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _NotificationConnector implements PgNotificationConnector {
  final connection = _NotificationConnection();

  @override
  Future<PgNotificationConnection> open(
    Endpoint endpoint, {
    required ConnectionSettings settings,
  }) async => connection;
}

final class _NotificationConnection implements PgNotificationConnection {
  final _events = StreamController<String>.broadcast();

  void publish(String payload) => _events.add(payload);

  @override
  Stream<String> channel(String name) => _events.stream;

  @override
  Future<void> listen(String channel) async {}

  @override
  Future<void> notify(String channel, String payload) async => publish(payload);

  @override
  Future<void> close() async => _events.close();
}
