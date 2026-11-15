import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Reads the search rate limit in a fresh process: Env reads
/// `Platform.environment`, which cannot be changed inside this process.
Future<ProcessResult> _readSearchRateMaxWith(
  Map<String, String> vars, {
  String ctorArg = '',
}) async {
  final dir = await Directory.systemTemp.createTemp('fact_search_rate_env_');
  addTearDown(() => dir.delete(recursive: true));
  final script = File('${dir.path}/read_search_rate_max.dart')
    ..writeAsStringSync('''
import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/env.dart';

void main() {
  print(Env(environment: Environment.test$ctorArg).factSearchRateMax);
}
''');
  final packageConfig = await Isolate.packageConfig;
  final environment = Map.of(Platform.environment)
    ..remove('FACT_SEARCH_RATE_MAX')
    ..addAll(vars);
  return Process.run(
    Platform.resolvedExecutable,
    ['--packages=${packageConfig!.toFilePath()}', script.path],
    environment: environment,
    includeParentEnvironment: false,
  ).timeout(const Duration(minutes: 2));
}

void main() {
  group('FACT_SEARCH_RATE_MAX', () {
    test('defaults to 30 searches per edit window when unset', () async {
      final result = await _readSearchRateMaxWith(const {});
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}'.trim(), '30');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('is read from the environment', () async {
      final result = await _readSearchRateMaxWith({
        'FACT_SEARCH_RATE_MAX': '5',
      });
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}'.trim(), '5');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('the constructor argument overrides the environment', () async {
      final result = await _readSearchRateMaxWith(
        {'FACT_SEARCH_RATE_MAX': '5'},
        ctorArg: ', factSearchRateMax: 7',
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}'.trim(), '7');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
