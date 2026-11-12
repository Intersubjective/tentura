import 'dart:async';
import 'dart:io';

import 'package:shelf_plus/shelf_plus.dart';
import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/app.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/service/pg_notification_service.dart';

import '../../bin/test.dart' as entrypoint;

late int _listenPort;
late String _listenAddress;

Future<void> main(List<String> args) => runZoned(
  () => _run(args),
  zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) {
      final match = RegExp(
        r'web server listen \[([^:\]]+):(\d+)\]',
      ).firstMatch(line);
      if (match != null) {
        _listenAddress = match.group(1)!;
        _listenPort = int.parse(match.group(2)!);
      }
      parent.print(zone, line);
    },
  ),
);

Future<void> _run(List<String> args) async {
  // Lifecycle tests do not exercise authentication or database subscriptions.
  // In particular, Env.test currently lacks SessionRepositoryPort, so using
  // the full authentication graph would fail before reaching serveWeb.
  // The server, socket, stop handshake and DI reset remain the real ones.
  getIt
    ..skipDoubleRegistration = true
    ..registerSingletonAsync<RootRouter>(
      () async => _LifecycleRouter(),
      dispose: (_) async {
        if (args.single == 'barrier') {
          print('DISPOSAL_STARTED');
          await stdin.first;
          print('DISPOSAL_FINISHED');
        }
      },
    )
    ..registerSingletonAsync<PgNotificationService>(
      () async => _UnusedNotifications(),
    );
  await getIt.getAsync<RootRouter>();
  await getIt.getAsync<PgNotificationService>();
  if (args.single == 'entrypoint') {
    await entrypoint.main([]);
    return;
  }
  await App().runWithTestEnv();
  // Probe before process exit can close the socket for us.
  try {
    final socket = await Socket.connect(
      _listenAddress,
      _listenPort,
      timeout: const Duration(seconds: 1),
    );
    socket.destroy();
    print('APP_RETURNED:port-open');
  } on SocketException catch (error) {
    // These lifecycle tests run on Linux. A timeout, unreachable address or
    // other networking error must not masquerade as an acknowledged close.
    if (error.osError?.errorCode != 111) rethrow; // ECONNREFUSED
    print('APP_RETURNED:port-closed');
  }
  // No exit(): remaining ReceivePorts must be observable to the parent.
}

final class _LifecycleRouter implements RootRouter {
  @override
  Handler routeHandler() =>
      (_) => Response.ok('shutdown probe');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _UnusedNotifications implements PgNotificationService {
  @override
  Stream<String> get entityChangeNotifications => const Stream.empty();

  @override
  Stream<String> get presenceNotifications => const Stream.empty();

  @override
  Stream<String> get roomTypingNotifications => const Stream.empty();

  @override
  Stream<PgNotificationRecovery> get recoveryNotifications =>
      const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
