import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Future<Map<String, dynamic>> _probe(Map<String, String> overrides) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['test/support/disposable_pg_target_env_probe.dart'],
    workingDirectory: Directory.current.path,
    environment: {...Platform.environment, ...overrides},
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode((result.stdout as String).trim().split('\n').last)
      as Map<String, dynamic>;
}

void main() {
  group('disposable PG target isolation from ambient pool settings', () {
    test(
      'all Envs use the configured pool capacity from POSTGRES_MAXCONN',
      () async {
        final snapshot = await _probe({'POSTGRES_MAXCONN': '4'});
        expect(snapshot.values, everyElement(4));
      },
    );
  });
}
