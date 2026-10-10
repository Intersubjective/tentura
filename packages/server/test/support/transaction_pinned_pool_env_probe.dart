import 'dart:convert';
import 'dart:io';

import 'transaction_pinned_pool_env.dart';

void main(List<String> arguments) {
  final env = transactionPinnedPoolEnv(
    enabled: arguments.isEmpty ? null : arguments.single == 'true',
    maxConnectionCount: 3,
  );
  stdout.writeln(
    jsonEncode({
      'enabled': transactionPinnedPoolEnabled(env),
      'configuredCapacity': env.pgMaxConnectionCount,
      'poolCapacity': env.pgPoolSettings.maxConnectionCount,
    }),
  );
}
