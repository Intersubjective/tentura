import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

/// Keeps the acceptance tests runnable before the opt-in constructor argument
/// exists. Missing configuration must fail an assertion, not test compilation.
Env transactionPinnedPoolEnv({
  bool? enabled,
  int maxConnectionCount = 2,
  Env? postgres,
}) {
  try {
    return Function.apply(Env.new, const <Object?>[], <Symbol, Object?>{
          #environment: Environment.test,
          #printEnv: false,
          #isDebugModeOn: false,
          #maxConnectionCount: maxConnectionCount,
          if (postgres != null) ...{
            #pgHost: postgres.pgHost,
            #pgPort: postgres.pgPort,
            #pgDatabase: postgres.pgDatabase,
            #pgUsername: postgres.pgUsername,
            #pgPassword: postgres.pgPassword,
          },
          if (enabled != null) #driftTransactionPinnedPoolEnabled: enabled,
        })
        as Env;
    // This is the expected red-phase outcome until the flag is implemented.
    // ignore: avoid_catching_errors
  } on NoSuchMethodError {
    fail(
      'Env must accept the default-off driftTransactionPinnedPoolEnabled '
      'opt-in flag.',
    );
  }
}

bool transactionPinnedPoolEnabled(Env env) {
  try {
    return (env as dynamic).driftTransactionPinnedPoolEnabled as bool;
    // A missing flag getter is an acceptance failure before implementation.
    // ignore: avoid_catching_errors
  } on NoSuchMethodError {
    fail('Env must expose the driftTransactionPinnedPoolEnabled flag.');
  }
}

Directory transactionPinnedPoolServerDirectory() {
  var directory = Directory.current.absolute;
  while (!File('${directory.path}/AGENTS.md').existsSync()) {
    final parent = directory.parent;
    if (parent.path == directory.path) {
      fail('Tentura repository root not found');
    }
    directory = parent;
  }
  return Directory('${directory.path}/packages/server');
}

/// Env caches Platform.environment, so each runtime configuration needs a
/// fresh process. No constructor opt-in is supplied unless the caller is
/// testing constructor precedence.
Future<({bool enabled, int configuredCapacity, int poolCapacity})>
probeTransactionPinnedPoolRuntimeEnv({
  String? flag,
  bool? constructorOverride,
}) async {
  final environment = Map<String, String>.of(Platform.environment)
    ..remove('DRIFT_TRANSACTION_PINNED_POOL_ENABLED');
  if (flag != null) {
    environment['DRIFT_TRANSACTION_PINNED_POOL_ENABLED'] = flag;
  }
  final result = await Process.run(
    Platform.resolvedExecutable,
    [
      'test/support/transaction_pinned_pool_env_probe.dart',
      if (constructorOverride != null) '$constructorOverride',
    ],
    workingDirectory: transactionPinnedPoolServerDirectory().path,
    environment: environment,
    includeParentEnvironment: false,
  );
  expect(
    result.exitCode,
    0,
    reason:
        'A fresh Env must read DRIFT_TRANSACTION_PINNED_POOL_ENABLED='
        '${flag ?? "<unset>"}:\n${result.stdout}\n${result.stderr}',
  );
  final snapshot = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  return (
    enabled: snapshot['enabled'] as bool,
    configuredCapacity: snapshot['configuredCapacity'] as int,
    poolCapacity: snapshot['poolCapacity'] as int,
  );
}
