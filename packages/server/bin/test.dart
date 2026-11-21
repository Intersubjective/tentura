import 'dart:io';

import 'package:tentura_server/app/app.dart';
import 'package:tentura_server/app/workers/web_worker.dart';

import '../test/support/test_di.dart';

Future<void> main(List<String> args) async {
  await runTestServer();
  exit(0);
}

Future<void> runTestServer() => App().runWithTestEnv(
  worker: (params) =>
      serveWeb(params, configureGraph: configureTestDependencies),
);
