@Tags(['repo-files'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

const _release = '7.64.0';
const _previousRelease = '7.63.39';

int _compareVersions(String left, String right) {
  final leftParts = left.split('.').map(int.parse).toList();
  final rightParts = right.split('.').map(int.parse).toList();
  for (var index = 0; index < 3; index++) {
    final order = leftParts[index].compareTo(rightParts[index]);
    if (order != 0) return order;
  }
  return 0;
}

Future<String> _readMinimumVersion(String? override) async {
  final directory = await Directory.systemTemp.createTemp('client_floor_');
  addTearDown(() => directory.delete(recursive: true));
  final script = File('${directory.path}/read_client_floor.dart');
  await script.writeAsString('''
import 'package:tentura_server/env.dart';

void main() => print(Env().minClientVersion);
''');
  final packageConfig = (await Isolate.packageConfig)!.toFilePath();
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['--packages=$packageConfig', script.path],
    environment: {
      'ENVIRONMENT': 'test',
      'MIN_CLIENT_VERSION': ?override,
    },
    includeParentEnvironment: false,
  ).timeout(const Duration(minutes: 1));
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return (result.stdout as String).trim();
}

void main() {
  test('ships the next minor client and requires that release by default', () {
    final pubspec = File('../client/pubspec.yaml').readAsStringSync();
    final shippedVersion = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec)?.group(1);

    expect((shippedVersion, kDefaultMinClientVersion), (_release, _release));
  });

  for (final (setting, override) in [('unset', null), ('empty', '')]) {
    test(
      'requires the new client when MIN_CLIENT_VERSION is $setting',
      () async {
        final floor = await _readMinimumVersion(override);

        expect(
          (
            floor: floor,
            previousClientMeetsFloor:
                _compareVersions(_previousRelease, floor) >= 0,
            newClientMeetsFloor: _compareVersions(_release, floor) >= 0,
          ),
          (
            floor: _release,
            previousClientMeetsFloor: false,
            newClientMeetsFloor: true,
          ),
        );
      },
    );
  }

  test('documents the new minimum in both environment example entries', () {
    final example = File('../../.env.example').readAsStringSync();
    final describedFloor = RegExp(
      r'kDefaultMinClientVersion, currently ([0-9]+\.[0-9]+\.[0-9]+)\)',
    ).firstMatch(example)?.group(1);
    final exampleOverride = RegExp(
      r'^# MIN_CLIENT_VERSION=(\S+)$',
      multiLine: true,
    ).firstMatch(example)?.group(1);

    expect((describedFloor, exampleOverride), (_release, _release));
  });
}
