import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Reads the copy rate limit in a fresh process: Env reads
/// `Platform.environment`, which cannot be changed inside this process.
Future<ProcessResult> _readCopyRateMaxWith(Map<String, String> vars) async {
  final dir = await Directory.systemTemp.createTemp('fact_copy_rate_env_');
  addTearDown(() => dir.delete(recursive: true));
  final script = File('${dir.path}/read_copy_rate_max.dart')
    ..writeAsStringSync('''
import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/env.dart';

void main() {
  print(Env(environment: Environment.test).factCopyRateMax);
}
''');
  final packageConfig = await Isolate.packageConfig;
  // Start from this process's variables without FACT_COPY_RATE_MAX, so a
  // shell that exports it cannot change the result.
  final environment = Map.of(Platform.environment)
    ..remove('FACT_COPY_RATE_MAX')
    ..addAll(vars);
  return Process.run(
    Platform.resolvedExecutable,
    ['--packages=${packageConfig!.toFilePath()}', script.path],
    environment: environment,
    includeParentEnvironment: false,
  ).timeout(const Duration(minutes: 2));
}

void main() {
  group('FACT_COPY_RATE_MAX', () {
    test('defaults to 60 copies per edit window when unset', () async {
      final result = await _readCopyRateMaxWith(const {});
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}'.trim(), '60');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('is read from the environment', () async {
      final result = await _readCopyRateMaxWith({'FACT_COPY_RATE_MAX': '5'});
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}'.trim(), '5');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
