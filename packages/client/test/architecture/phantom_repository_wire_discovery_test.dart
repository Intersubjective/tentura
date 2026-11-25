@Tags(['repo-files'])
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _thisTest =
    'test/architecture/phantom_repository_wire_discovery_test.dart';
const _oldContract =
    'test/features/phantoms/phantom_repository_wire_contract.dart';

final _wireCases = [
  'create forwards the name, emoji and position and returns the id',
  'update sends the selected id and the edited name and emoji',
  'delete sends the id of the selected phantom',
  'ensure invite sends the phantom id and returns the existing link',
  'rotate invite sends the phantom id and returns the replacement link',
  'link sends the selected phantom and account ids',
  'unmerge sends the id of the merged phantom',
  'dismiss hint sends both ids of the link suggestion',
  'create accepts a name alone and returns the server id',
  for (final operation in [
    'PhantomCreate',
    'PhantomUpdate',
    'PhantomDelete',
    'PhantomInviteEnsure',
    'PhantomInviteRotate',
    'PhantomLink',
    'PhantomUnmerge',
    'PhantomHintDismiss',
  ])
    '$operation fails when GraphQL rejects it',
  for (final operation in [
    'PhantomUpdate',
    'PhantomDelete',
    'PhantomLink',
    'PhantomUnmerge',
    'PhantomHintDismiss',
  ])
    '$operation fails when the server returns false',
];

void main() {
  test(
    'Flutter runs every phantom repository wire case from CI-discovered suites',
    () async {
      final suites = await _wireSuitesFromCi();
      expect(
        suites,
        isNotEmpty,
        reason: 'CI has no *_test.dart entry point for the phantom wire cases.',
      );

      final scratch = Directory.systemTemp.createTempSync('phantom-wire-');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final report = File.fromUri(scratch.uri.resolve('results.jsonl'));
      final caseNames = _wireCases.map(RegExp.escape).join('|');
      final run = await Process.run('timeout', [
        '--kill-after=5s',
        '120s',
        'flutter',
        'test',
        '--no-pub',
        '--no-test-assets',
        '--dart-define=ENV=test',
        '--dart-define-from-file=env/test.env',
        '--reporter=failures-only',
        '--file-reporter=json:${report.path}',
        '--name=(^| )(?:$caseNames)\$',
        ...suites,
      ]);
      final output = '${run.stdout}\n${run.stderr}';
      expect(
        run.exitCode,
        0,
        reason:
            'Flutter did not run the phantom wire selection successfully.\n$output',
      );

      final passed = _passingTestNames(report);
      expect(
        _wireCases.where(
          (name) => !passed.any(
            (registered) => registered == name || registered.endsWith(' $name'),
          ),
        ),
        isEmpty,
        reason: 'Every original wire case must run successfully without skips.',
      );
      expect(File(_oldContract).existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<List<String>> _wireSuitesFromCi() async {
  final result = await Process.run('python3', [
    '../../scripts/ci_select_tests.py',
    'test',
  ]);
  expect(result.exitCode, 0, reason: result.stderr.toString());

  return [
    for (final path in (result.stdout as String).trim().split('\n'))
      if (path.isNotEmpty && path != _thisTest && _mayRegisterWireCases(path))
        path,
  ];
}

// Source markers only narrow the CI list. Only the Flutter report proves
// that the selected entry points registered and ran the cases.
bool _mayRegisterWireCases(String path) {
  if (path ==
      'test/features/phantoms/phantom_repository_wire_contract_test.dart') {
    return true;
  }
  final source = File(path).readAsStringSync();
  return source.contains('registerPhantomRepositoryWireTests(') ||
      _wireCases.any(source.contains);
}

List<String> _passingTestNames(File report) {
  final started = <int, String>{};
  final passed = <String>[];
  for (final line in report.readAsLinesSync()) {
    final event = jsonDecode(line) as Map<String, Object?>;
    switch (event) {
      case {
        'type': 'testStart',
        'test': {'id': final int id, 'name': final String name},
      }:
        started[id] = name;
      case {
        'type': 'testDone',
        'testID': final int id,
        'result': 'success',
        'hidden': false,
        'skipped': false,
      }:
        passed.add(started[id]!);
    }
  }
  return passed;
}
