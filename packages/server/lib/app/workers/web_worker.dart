import 'dart:async';
import 'dart:isolate';
import 'package:shelf_plus/shelf_plus.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/api/root_router.dart';

import '../di.dart';
import '../sentry/sentry_init.dart';

Future<void> serveWeb(({SendPort sendPort, Env env}) params) async {
  await initSentry(
    env: params.env,
    appRunner: () async {
      final receivePort = ReceivePort();
      params.sendPort.send(receivePort.sendPort);

      final getIt = await configureDependencies(params.env);
      await getIt.allReady();

      final rootRouter = await getIt.getAsync<RootRouter>();

      final webServer = await shelfRun(
        rootRouter.routeHandler,
        onStarted: (address, port) => print(
          '${Isolate.current.debugName} web server listen [$address:$port]',
        ),
        defaultEnableHotReload: params.env.isDebugModeOn,
        defaultBindAddress: params.env.bindAddress,
        defaultBindPort: params.env.listenWebPort,
        defaultShared: true,
      );
      print(
        '${Isolate.current.debugName} server started at ${DateTime.timestamp()} ',
      );

      // First message means stop command
      await receivePort.first;

      receivePort.close();
      await webServer.close();
      await getIt.reset();
      params.sendPort.send(null);
      print('${Isolate.current.debugName} stoped at ${DateTime.timestamp()}');
    },
  );
}
