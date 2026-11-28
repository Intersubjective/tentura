@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

const _release = '7.76.0';
const _previousRelease = '7.75.0';

void main() {
  test('the client declares the new minor release without a build suffix', () {
    final pubspec = File('../client/pubspec.yaml').readAsLinesSync();
    expect(
      pubspec.where((line) => line.startsWith('version:')),
      ['version: $_release'],
    );
  });

  test('the server defaults to the new client release with no override', () {
    expect(Platform.environment.containsKey('MIN_CLIENT_VERSION'), isFalse);
    expect(
      (compiled: kDefaultMinClientVersion, resolved: Env().minClientVersion),
      (compiled: _release, resolved: _release),
    );
  });

  test(
    'the sample environment documents a single override for the new floor',
    () {
      final lines = File('../../.env.example').readAsLinesSync();
      expect(
        {
          'floor comments': lines.where(
            (line) =>
                line.startsWith('#') &&
                line.contains('kDefaultMinClientVersion, currently '),
          ),
          'overrides': lines.where(
            (line) => line.startsWith('# MIN_CLIENT_VERSION='),
          ),
          'previous release': lines.where(
            (line) => line.contains(_previousRelease),
          ),
        },
        {
          'floor comments': [
            contains('kDefaultMinClientVersion, currently $_release)'),
          ],
          'overrides': ['# MIN_CLIENT_VERSION=$_release'],
          'previous release': isEmpty,
        },
      );
    },
  );
}
